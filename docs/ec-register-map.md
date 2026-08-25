# EC register map (Thunderobot ZERO)

Verified on a Thunderobot ZERO laptop (BIOS `TP141`, board `NLZC`, Quanta
barebone, i9-12900HK + RTX 3060) running kernel 7.0.  All offsets are in the
ACPI Embedded Controller RAM (256 bytes, ports `0x62`/`0x66`).

## Verified / actively used registers

| Offset | DSDT name | Type | Description |
|--------|-----------|------|-------------|
| `0x2C` | —         | RW   | **Fan1 (CPU) duty.** `0xFF` = EC auto mode; `0`–`100` = manual duty % |
| `0x2D` | —         | RW   | **Fan2 (GPU) duty.** same encoding as 0x2C |
| `0x2E` | —         | RO   | Fan1 current speed indicator (see caveat below) |
| `0x2F` | —         | RO   | Fan2 current speed indicator (see caveat below) |
| `0x58` | `RTMP`    | RO   | CPU temperature, °C |
| `0x59` | `TRTM`    | RO   | GPU temperature, °C |
| `0x95` | `APMD`    | RW   | **Power mode:** `0`=High(狂暴), `1`=Gaming, `2`=Office |

### Fan duty behaviour

* Writing any value `0`–`100` to `0x2C`/`0x2D` switches that fan to **manual
  mode**; the EC holds the fan at that duty regardless of temperature.
* Writing `0xFF` to both restores EC **auto mode**.
* Verified: with duty fixed at 50%, a sustained CPU load that previously ran
  the fans at 92–100% (auto mode) keeps them at ~50% while CPU climbs to
  ~70 °C.  The EC does **not** override manual duty.
* The EC resets to auto mode on reboot, so the daemon re-asserts the duty on
  every boot and periodically.

### Stall threshold (important!)

* Below roughly **40% duty** the fan motors cannot sustain rotation: the EC
  pulses them on/off in a repeating start–stop cycle that is clearly audible
  ("fan spins up, abruptly stops, restarts").  Measured on this unit:
  * duty 10–30%: speed indicator oscillates (std ≈ 15–18, frequent drops to 0)
    for the whole time → motor never settles.
  * duty 35%: partly stable, Fan1 still drops out occasionally.
  * duty 40%: rock stable (indicator std < 2, no dropouts), both cold start
    (from duty 0) and sustained.
  * duty 0%: fans spin down and stop completely (useful if you want them off).
* Consequence: never configure a fan curve / minimum duty below ~40%.  The
  stock `fan-cap.py` therefore defaults to `MIN_DUTY = 40` with a maximum of
  `MAX_DUTY = 75` and a curve of `55:40, 70:55, 85:75`.

### Caveat on `0x2E`/`0x2F`

At low duty values the speed indicator reads higher than expected (it reports
~48–50 when the fan is driven at 20–30% duty).  Treat `0x2E`/`0x2F` as a
*coarse* speed trend, not a reliable percentage.  The duty registers
`0x2C`/`0x2D` are the authoritative control path.

## Other fields from the DSDT (for reference / further RE)

The EC0 device in the DSDT (`\_SB.PC00.LPCB.EC0`) declares an
`OperationRegion (ERAM, EmbeddedControl, 0, 0xFF)`.  Selected named fields:

| Offset | Name | Notes |
|--------|------|-------|
| `0x30` | `BTPL`, `PTPH`, `BCLC` | battery/backlight related |
| `0x38` | `RGBK` (1 bit) | RGB keyboard flag |
| `0x41` | `WIN7` … `RFLG` | misc flags |
| `0x44` | `FASO` (1 bit) | fan something flag (name only, unused by us) |
| `0x47` | `TNT2`, `LKCL`, `TNT4`, `IRSN`, `TNT5`, `STOE` | |
| `0x58` | `RTMP`, `TRTM` | temps (see above) |
| `0x62` | `OMCC` (1 bit) | |
| `0x6B` | `DCBR`, `GWKR` | |
| `0x70` | `BADC`, `BFCC`, `BVLB`, `BVHB`, `BDVO` | battery ADC etc. |
| `0x78` | `SBRM` … `LKBB` | battery/charging |
| `0x90` | `NVDO`, `ECDO` | |
| `0x95` | `APMD` | power mode (see above) |
| `0xB0` | `RPM1`, `RPM2`, `RPM3`, `RPM4` | 8-bit values; not raw fan RPM |
| `0xC3` | `FANM` (bit 0) | fan-max flag, mirrored to WMI `WMIA.FMAX` |
| `0xD6` | `FANE` (bit 2), `FAND` (bit 3) | fan enable/disable flags, set via WMI cmd `0xFB00/0x0200` |

### Fan RPM

Fan RPM is **not** in EC RAM.  The DSDT reads it from a system-memory
operation region `H2RA` (`SystemMemory 0xFE400000`):
`FS1H:FS1L` = Fan1 RPM, `FS2H:FS2L` = Fan2 RPM (16-bit big-endian).  On
Windows this is what ControlCenter reports; from Linux the region is not
directly readable without an ACPI helper.

## Differences from the community RE project

[InkeyP/thunderobot-zero-fan-control](https://github.com/InkeyP/thunderobot-zero-fan-control)
reports the same duty registers (`0x2C`/`0x2D`, `0xFF` = auto) and temps
(`0x58`/`0x59`) — those match this unit.  It also lists `0x2E`/`0x2F` as
"current speed %", which we found to be unreliable at low duty.  Its WMI
`SetFanSpeed` command (`0xFB00/0x0205`) does **not** exist in this unit's
DSDT (only `0x0200`, `0x0201`, `0x0202`, `0x0300` are handled), so a direct
WMI fan-speed path may not work here — the EC duty registers are the way.
