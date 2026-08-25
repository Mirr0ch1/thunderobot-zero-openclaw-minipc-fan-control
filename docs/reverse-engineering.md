# Reverse engineering notes

This document records *how* the EC fan control for the Thunderobot ZERO was
worked out, including dead ends, so that owners of sibling machines (other
Quanta-barebone laptops) can adapt it.

## The problem

* Under load the fans spin at ~100% and the laptop is loud.
* There is **no hwmon PWM interface**: `/sys/class/hwmon` has no `pwm*` or
  `fan*` entries, and `fancontrol`/`lm-sensors` have nothing to bind to.
* The ACPI "Fan" cooling devices (`cooling_device5..9`) only expose a binary
  `max_state=1` (on/off), not speed control.

Conclusion: fans are owned entirely by the **EC firmware**.

## Finding the registers

1. A community project
   ([InkeyP/thunderobot-zero-fan-control](https://github.com/InkeyP/thunderobot-zero-fan-control))
   reverse-engineered a *Quanta* ZERO and published EC registers
   `0x2C`/`0x2D` = fan duty (`0xFF` = auto, 0–100 = manual) and
   `0x58`/`0x59` = CPU/GPU temp.

2. On this unit (BIOS `TP141`), reading `/sys/kernel/debug/ec/ec0/io` (via
   `ec_sys`, read-only) confirmed `0x2C`/`0x2D` = `0xFF` (auto) and the temps
   matched `coretemp`/`nvidia-smi`.

3. First write tests *appeared* to fail: `dd ... of=/dev/ec_rw` changed
   nothing and the registers kept reading back ~92.  This turned out to be a
   **`dd` quirk** with the misc device (seek/write behaviour), **not** a
   read-only register.  Writing with Python
   (`os.lseek(fd, off, 0); os.write(fd, bytes([val]))`) works perfectly and
   the fans respond immediately.  (Lesson: when probing a custom device,
   verify with several tools before concluding a register is read-only.)

## Verification that duty control works

| Duty written (0x2C/0x2D) | Fan speed indicator (0x2E/0x2F) |
|---|---|
| auto (0xFF), idle | 92 / 92 |
| 50 | 50 / 49 |
| 30 | 63 / 31 (Fan1 still spinning down) |
| **50 under sustained 45 W CPU load** | **50 / 50 held for 35 s, CPU 37→68 °C** |

The EC does not override manual duty.  In contrast, in auto mode the same
load ran the fans at 92–100%.

## Stall threshold measurement

Duty below ~40% is **unstable**: the fan motors stall and the EC restarts
them repeatedly, producing an audible "spin up → stop → restart" cycle.
Measured on this unit (idle, ~43 °C, each duty held 12 s, speed indicator
sampled every 0.2 s):

| Duty | Fan1 indicator (std) | Fan2 indicator (std) | Result |
|---|---|---|---|
| 10% | 52.5 (18.4), 2×zero | 45.0 (16.1), 3×zero | stalls |
| 20% | 44.9 (17.0), 4×zero | 43.9 (17.0), 4×zero | stalls |
| 30% | 45.6 (17.3), 4×zero | 44.6 (15.8), 3×zero | stalls |
| 35% | 40.2 (13.6), 2×zero | 40.0 (9.9), no zero | Fan1 still drops out |
| 40% | 39.1 (1.7), no zero | 39.0 (1.6), no zero | stable |
| 50% | ~50 (stable) | ~50 (stable) | stable |

* Cold start from duty 0 → 40%: fans spin up in ~5 s then hold steady.
* Duty 0%: fans spin down and stop completely.
* Conclusion: use `MIN_DUTY = 40` (or higher); the stock curve is
  `55:40, 70:45, 85:50`.

## Why the fans are aggressive: power mode

The DSDT shows the machine defaults to `APMD = 0` (**High / 狂暴** mode) at
`EC 0x95`:

* `0` = High — highest firmware power limits, most aggressive fan curve
* `1` = Gaming
* `2` = Office — lowest firmware power limits

The WMI `SetPowerMode` command (`0xFB00/0x0300`) writes `APMD` and re-applies
NVIDIA platform power limits (`NPCF.ATPP/AMAT/AMIT`).  We observed the fans
near max even at ~42 °C in High mode; switching to Office mode and capping
the duty directly gives the quiet behaviour users want.

## What the DSDT says about fans

Decompiled with `iasl -d dsdt.dat` (install `acpica-tools`).

* EC device: `\_SB.PC00.LPCB.EC0`, `OperationRegion ERAM (EmbeddedControl,
  0, 0xFF)` — full field map in `docs/ec-register-map.md`.
* `FANM` (bit 0 of `0xC3`) is a fan-max flag mirrored to WMI `WMIA.FMAX`.
* `FANE`/`FAND` (bits 2/3 of `0xD6`) are fan enable/disable flags, set from
  WMI command `0xFB00/0x0200` (`DAT2=1` → `FAND`, else `FANE`).  They are
  single bits — **not** duty control.
* Fan RPM is **not** in EC RAM.  It lives in a system-memory region
  `H2RA` at `0xFE400000`: `FS1H:FS1L` (Fan1), `FS2H:FS2L` (Fan2), 16-bit
  big-endian.  The WMI `GetHardwareInfo` (`0xFA00/0x0200`) returns
  `DAT2=RTMP`, `DAT3=VGAT`, `DAT4=FS1 RPM`, `DAT5=FS2 RPM`.

## WMI command table (this unit)

Handler `WSAA` in `\_SB.GWMI`, dispatch on `GWF0`/`GWF1`:

| GWF0 | GWF1 | Function |
|------|------|----------|
| `0xFA00` | `0x0200` | GetHardwareInfo (temps, fan RPM, kb-light level) |
| `0xFA00` | `0x0201` | RGB status |
| `0xFA00` | `0x0300` | GetPowerMode (→ `DAT2 = APMD`) |
| `0xFB00` | `0x0100` | Set keyboard backlight |
| `0xFB00` | `0x0200` | Set `DWNK` / `FAND` / `FANE` flags |
| `0xFB00` | `0x0202` | Touchpad on/off |
| `0xFB00` | `0x0300` | SetPowerMode (writes `APMD`, re-applies GPU limits) |

Note: the community project's `SetFanSpeed` (`0xFB00/0x0205`) is **not**
present in this DSDT.  Duty control goes through the EC registers directly.

## Practical levers on Linux

1. **Fan duty cap** — write `0x2C`/`0x2D` every few seconds (fan-cap.py).
2. **Power mode** — write `APMD` (`0x95`) = 2 (Office) to lower firmware
   power limits and heat.
3. **RAPL** — cap CPU PL1/PL2 via `/sys/class/powercap/intel-rapl:0`
   (the factory set PL1 to 200 W; 45/65 W is the stock spec and plenty).
4. **GPU** — `nvidia-smi -pl` is locked by the VBIOS; clamp the boost clock
   instead with `nvidia-smi -lgc 0,1400`.

## Security / safety

* Only `0x2C`, `0x2D`, `0x58`, `0x59`, `0x95` are known-safe on this EC.
  The community RE project reports that writing unknown EC registers caused a
  forced reboot during their research — **never poke unknown registers**.
* With the fan capped at 50% and a sustained full load, CPU temperature
  plateaus around 70–80 °C (at 45 W PL1).  Watch temperatures when gaming;
  lower `MAX_DUTY` cap means hotter silicon.
* The daemon restores `0xFF` (auto) on exit, and the EC resets on reboot.
