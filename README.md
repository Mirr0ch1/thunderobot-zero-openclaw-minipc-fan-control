# Thunderobot ZERO — Quiet MiniPC Server & OpenClaw Gateway

Turn a **Thunderobot ZERO** (雷神 ZERO) gaming laptop — i9-12900HK + RTX 3060,
Quanta barebone — into a **quiet, low-power hosted Linux server / OpenClaw
gateway miniPC**. The EC firmware, CPU power limits and GPU clocks are tuned
to a "sweet spot": quiet enough to sleep next to, cool enough for 24/7
hosting, still powerful enough to be an always-on LLM gateway node.

Works on the stock kernel, survives kernel upgrades (DKMS), needs **no
disabling of Secure Boot**.

[English](#english) · [中文](#中文)

---

## English

### Why this project

Out of the box a gaming laptop makes a terrible server:

- The fans are driven purely by the **Embedded Controller (EC)** — there is no
  hwmon/PWM interface, so `fancontrol`/`lm-sensors` can't help. The EC
  defaults to the most aggressive power mode ("High") and runs the fans near
  max even at ~50 °C.
- The BIOS sets CPU PL1 to a ludicrous **200 W** and the GPU boosts to
  2100 MHz — great for gaming, wrong for a machine that sits next to your bed
  routing messages for [OpenClaw](https://openclaw.ai) all night.

This project re-tunes three levers to a measured sweet spot: fan curve,
CPU/GPU power, and EC power mode.

### The sweet-spot recipe

| Knob | Value | Why |
|---|---|---|
| Fan cap | **75% max, 40% min** | below ~40% duty the fans **stall** (EC restarts them in an audible start/stop cycle); 75% was the loudest the author tolerates next to a bed |
| EC power mode | **Office** (`0x95` = 2) | lowers the firmware power limits & fan aggressiveness |
| CPU RAPL | **PL1 50 W / PL2 80 W** | factory PL1 was 200 W; 50 W keeps CPU ~75 °C on full load with fans only ~45–55% |
| GPU clock lock | **1700 MHz** | stock boost is 2100 MHz; 1700 measures ~60 °C under load |

Measured on this unit:

| Scenario | Fans | Temperatures |
|---|---|---|
| Idle | 40% duty, steady | CPU/GPU ~40–45 °C, machine draws ~8–10 W |
| Sustained full CPU load (20 threads) | ~45–55% (curve 40→55) | CPU ~69–75 °C at 50 W PL1 |
| GPU at 1700 MHz | ~44% | GPU ~59–62 °C |

### How it works

1. **`ec_rw`** — a tiny, **MOK-signed DKMS kernel module** that exposes the EC
   RAM as `/dev/ec_rw`. This is the only way to write EC fan registers while
   Secure Boot / kernel lockdown is active (the stock `ec_sys` write path is
   blocked). Auto-rebuilds on every kernel upgrade.
2. **`fan-cap`** — a daemon that reads CPU/GPU temperature (EC `0x58`/`0x59`)
   and drives the fans from a temperature curve (EC `0x2C`/`0x2D`) capped at
   75%, and switches the EC to Office power mode (`0x95`). Restores EC auto
   mode when stopped.
3. **`power-cap`** — a one-shot service that applies CPU RAPL (PL1/PL2) and
   the GPU clock lock at boot.

Register details & the reverse-engineering journey:
[`docs/ec-register-map.md`](docs/ec-register-map.md),
[`docs/reverse-engineering.md`](docs/reverse-engineering.md).

### Hardware

* **Laptop:** Thunderobot ZERO (911 series), BIOS `TP141`, board `NLZC`,
  Quanta barebone
* **Verified CPU/GPU:** i9-12900HK + RTX 3060 Laptop GPU
* **OS:** Ubuntu 26.04 / kernel 7.0 (any DKMS-capable distro should work)
* Likely compatible with sibling Quanta-barebone machines (Eluktronics
  Prometheus XVI, MaiBenBen x658, …) — please test and report!

### Requirements

* Root access, `dkms`, `gcc`, `make`, `python3`, kernel headers
  (`linux-headers-$(uname -r)`).
* **Secure Boot:** you need an enrolled MOK key. If you already installed the
  NVIDIA driver on this machine you have one. See
  [`docs/secure-boot.md`](docs/secure-boot.md) to enroll a new one.

### Install

```bash
git clone https://github.com/Mirr0ch1/thunderobot-zero-openclaw-minipc-fan-control.git
cd thunderobot-zero-openclaw-minipc-fan-control
sudo ./install.sh
```

The installer:
1. builds & installs `ec_rw` via **DKMS** (auto-rebuilds on kernel upgrades),
   signed with your MOK key,
2. installs the `fan-cap` daemon + `power-cap` service (both enabled at boot),
3. configures `/dev/ec_rw` to load at boot,
4. writes a default config to `/etc/thunderobot-fan-control.conf`.

### Tuning

Edit `/etc/thunderobot-fan-control.conf` and restart the service:

```ini
[duty]
max = 75          # fan duty cap in % of max speed
min = 40          # stable floor: below ~40% the fans stall (start/stop)

[power_mode]
value = 2         # 0=High 1=Gaming 2=Office, -1 = leave as-is

[fan_curve]
points = 55:40, 70:55, 85:75
```

> **Do not set `min` (or any curve point) below 40.**  On this unit, duties
> below ~40% make the fan motors stall; the EC then restarts them over and
> over in an audible "spin up → stop → restart" cycle.  40% is the lowest
> stable duty (verified for both cold start and sustained running).

```bash
sudo systemctl restart fan-cap.service
```

Power limits are in `/usr/local/sbin/power-cap.sh`
(CPU `PL1`/`PL2` in microwatts, GPU max clock in MHz).

### Verify it works

```bash
journalctl -u fan-cap.service -n 5          # should show duty %
ls -l /dev/ec_rw                            # the EC access device
systemctl is-active fan-cap.service power-cap.service
```

### Uninstall

```bash
sudo ./uninstall.sh
```

EC fans return to firmware auto-mode after reboot.

### Safety

* Only the fan-duty (`0x2C/0x2D`), temp (`0x58/0x59`) and power-mode (`0x95`)
  registers are known-safe on this EC. **Never write unknown registers** —
  the community RE project reports that doing so caused a forced reboot.
* With the fans capped, sustained heavy load (e.g. gaming) runs hotter.
  Watch temperatures; raise `max` or lower the power caps if needed.
* The daemon restores EC auto mode on exit; the EC also resets on reboot.

### Acknowledgements

* [InkeyP/thunderobot-zero-fan-control](https://github.com/InkeyP/thunderobot-zero-fan-control)
  — original EC register RE for the Quanta ZERO.
* [NBFC](https://github.com/hirschmann/nbfc) — the EC-probing ecosystem.

### License

MIT — see [LICENSE](LICENSE).

---

## 中文

### 这个项目是干什么的

把一台**雷神 ZERO** 游戏本（i9-12900HK + RTX 3060，广达公模）改造成**安静、
低功耗的托管 Linux 服务器 / OpenClaw 网关 miniPC**。通过调教 EC 固件、
CPU 功耗上限和 GPU 频率，把它放进一个"甜点区间"：安静到可以放在床边，
凉爽到能 7×24 小时托管服务，性能又足够当一个常驻的 LLM 网关节点。

内核原样可用、内核升级自动重建（DKMS），**无需关闭 Secure Boot**。

### 为什么需要这个项目

游戏本开箱即用不适合当服务器：

- 风扇完全由 **EC（嵌入式控制器）** 固件控制，Linux 下没有 hwmon/PWM 接口，
  `fancontrol`/`lm-sensors` 都无能为力；EC 默认「狂暴」模式，~50°C 就把
  风扇拉到接近满速。
- BIOS 把 CPU PL1 设成离谱的 **200W**，GPU 也能 boost 到 2100MHz——打游戏
  是好事，但对一台要躺在你床边、整夜为 [OpenClaw](https://openclaw.ai)
  转发消息的机器来说就完全跑偏了。

本项目把三个旋钮调到实测出来的甜点：风扇曲线、CPU/GPU 功耗、EC 性能模式。

### 甜点配方

| 旋钮 | 取值 | 为什么 |
|---|---|---|
| 风扇上限 | **上限 75%，下限 40%** | 低于 ~40% 占空比风扇会**失速**（EC 反复重启风扇，形成可听见的启停循环）；75% 是作者能接受的音量上限 |
| EC 性能模式 | **Office**（`0x95`=2） | 降低固件功耗上限和风扇激进程度 |
| CPU RAPL | **PL1 50W / PL2 80W** | 出厂 PL1 是 200W；50W 下满载 CPU 约 75°C，风扇只需 ~45–55% |
| GPU 频率锁定 | **1700MHz** | 默认 boost 2100MHz；1700MHz 实测满载约 60°C |

本机实测：

| 场景 | 风扇 | 温度 |
|---|---|---|
| 空闲 | 40% 稳定运转 | CPU/GPU ~40–45°C，整机功耗 ~8–10W |
| CPU 全核持续满载（20 线程） | ~45–55%（曲线 40→55） | CPU ~69–75°C（50W PL1） |
| GPU @1700MHz | ~44% | GPU ~59–62°C |

### 实现原理

1. **`ec_rw`** —— 一个 **MOK 签名的小内核模块**（DKMS 管理），把 EC 内存
   暴露为 `/dev/ec_rw`。这是 Secure Boot/内核 lockdown 下唯一能写 EC 风扇
   寄存器的途径（标准 `ec_sys` 写入路径被拦截）。内核升级自动重建。
2. **`fan-cap`** —— 守护进程，读 CPU/GPU 温度（EC `0x58`/`0x59`），按温度
   曲线驱动风扇（EC `0x2C`/`0x2D`），上限 75%，并把 EC 切成 Office 模式
   （`0x95`）。退出时恢复 EC 自动模式。
3. **`power-cap`** —— 一次性服务，开机应用 CPU RAPL（PL1/PL2）和 GPU 频率锁定。

寄存器细节与逆向笔记：[`docs/ec-register-map.md`](docs/ec-register-map.md)、
[`docs/reverse-engineering.md`](docs/reverse-engineering.md)。

### 硬件适配

* 雷神 ZERO（911 系列），BIOS `TP141`，板号 `NLZC`，广达（Quanta）公模
* 已实测：i9-12900HK + RTX 3060 Laptop
* 系统：Ubuntu 26.04 / kernel 7.0（任意带 DKMS 的发行版应该都行）
* 同模具机型（Eluktronics Prometheus XVI、麦本本 x658 等）大概率兼容，欢迎测试反馈

### 安装

```bash
git clone https://github.com/Mirr0ch1/thunderobot-zero-openclaw-minipc-fan-control.git
cd thunderobot-zero-openclaw-minipc-fan-control
sudo ./install.sh
```

安装脚本会：用 DKMS 编译并安装 MOK 签名的 `ec_rw`（内核升级自动重建）、
安装 `fan-cap`/`power-cap` 两个开机自启服务、配置 `/dev/ec_rw` 开机加载、
写入默认配置。

**Secure Boot**：需要已注册的 MOK 密钥（装过 NVIDIA 驱动就有）；没有的话见
[`docs/secure-boot.md`](docs/secure-boot.md)。

### 调参

改 `/etc/thunderobot-fan-control.conf` 后 `sudo systemctl restart fan-cap.service`：

```ini
[duty]
max = 75          # 风扇占空比上限（%）
min = 40          # 稳定下限：低于约 40% 风扇会失速（反复启停）

[power_mode]
value = 2         # 0=狂暴 1=游戏 2=办公，-1=不动

[fan_curve]
points = 55:40, 70:55, 85:75
```

> **不要把 `min`（或曲线任一拐点）设到 40 以下。** 实测本机在低于约 40%
> 占空比时风扇电机会失速，EC 会不停重启风扇，形成可听见的"转起来→急停→
> 再启动"循环。40% 是能稳定运转的最低值（冷启动与持续运行均已验证）。

功耗上限在 `/usr/local/sbin/power-cap.sh`（CPU `PL1`/`PL2` 微瓦、GPU 频率 MHz）。

### 验证

```bash
journalctl -u fan-cap.service -n 5          # 应显示占空比 %
ls -l /dev/ec_rw                            # EC 访问设备
systemctl is-active fan-cap.service power-cap.service
```

### 卸载

```bash
sudo ./uninstall.sh
```

重启后 EC 风扇恢复固件自动模式。

### 安全提醒

* 本机仅 `0x2C`/`0x2D`/`0x58`/`0x59`/`0x95` 确认安全。**切勿乱写未知寄存器**
  （社区 RE 项目反馈：写过会导致强制重启）。
* 风扇封顶后重负载（如游戏）会偏热，注意观察温度，必要时调高 `max` 或调低功耗。
* 守护进程退出时恢复 EC 自动模式，重启后 EC 也会自动复位。

### 致谢

* [InkeyP/thunderobot-zero-fan-control](https://github.com/InkeyP/thunderobot-zero-fan-control)
  —— 最初的广达 ZERO EC 寄存器逆向
* [NBFC](https://github.com/hirschmann/nbfc) —— EC 探测生态

### 许可证

MIT —— 见 [LICENSE](LICENSE)。
