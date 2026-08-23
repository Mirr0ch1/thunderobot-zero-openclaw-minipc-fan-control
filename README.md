# Thunderobot ZERO Linux Fan Control

Cap the fans of the **Thunderobot ZERO** (雷神 ZERO) gaming laptop at 50% of
their max speed on Linux, so it stops sounding like a hairdryer under load —
**without disabling Secure Boot**.

Works on the stock kernel, survives kernel upgrades (DKMS), and auto-restores
EC auto-mode when stopped.

[English](#english) · [中文](#中文)

---

## English

### What it does

The ZERO's fans are driven purely by its **Embedded Controller (EC)** — there
is no hwmon/PWM interface, so `fancontrol`/`lm-sensors` can't help. Worse, the
EC defaults to the most aggressive power mode ("High") whose fan curve runs
the fans near max even at ~50 °C.

This project:

1. Ships a tiny, **MOK-signed kernel module** (`ec_rw`) that exposes the EC
   RAM as `/dev/ec_rw` — the only way to write EC fan registers while Secure
   Boot is on (the stock `ec_sys` write path is blocked by kernel lockdown).
2. Runs a **daemon** (`fan-cap.py`) that drives the fans from a temperature
   curve **capped at 50% duty**, and optionally switches the EC to **Office**
   power mode to reduce heat.
3. Optionally caps CPU RAPL power and GPU boost clock to further cut heat.

Measured effect (same sustained CPU load):

| | before | after |
|---|---|---|
| fan speed | 92–100% | **~35% (max 50%)** |
| CPU temperature | ~95–100 °C | **~70 °C** |

### Hardware

* **Laptop:** Thunderobot ZERO (雷神 ZERO, 911 series), BIOS `TP141`,
  board `NLZC`, Quanta barebone
* **Verified CPU/GPU:** i9-12900HK + RTX 3060 Laptop GPU
* **OS:** Ubuntu 26.04 / kernel 7.0 (should work on any distro with DKMS)
* Likely compatible with sibling Quanta-barebone machines (e.g. Eluktronics
  Prometheus XVI, MaiBenBen x658) — please test and report!

### How it works

* EC register `0x2C` = Fan1 (CPU) duty, `0x2D` = Fan2 (GPU) duty.
  `0xFF` = auto, `0`–`100` = manual duty %. Verified: in manual mode the EC
  holds the duty even under load.
* `0x58`/`0x59` = CPU/GPU temperature. `0x95` = power mode
  (0=High, 1=Gaming, 2=Office).
* Full register map & reverse engineering notes:
  [`docs/ec-register-map.md`](docs/ec-register-map.md),
  [`docs/reverse-engineering.md`](docs/reverse-engineering.md).

### Requirements

* Root access, `dkms`, `gcc`, `make`, `python3`, kernel headers
  (`linux-headers-$(uname -r)`).
* **Secure Boot:** you need an enrolled MOK key. If you already installed the
  NVIDIA driver on this machine you have one. See
  [`docs/secure-boot.md`](docs/secure-boot.md) for how to enroll a new one.

### Install

```bash
git clone https://github.com/<you>/thunderobot-zero-fan-control.git
cd thunderobot-zero-fan-control
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
max = 50          # fan duty cap in % of max speed
min = 20

[power_mode]
value = 2         # 0=High 1=Gaming 2=Office, -1 = leave as-is

[fan_curve]
points = 55:20, 70:35, 85:50
```

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

### 这是什么

把**雷神 ZERO** 游戏本在 Linux 下的风扇最大转速封顶到 50%，满载时不再像吹风机一样吵——**无需关闭 Secure Boot**。

### 解决的问题

ZERO 的风扇完全由 **EC（嵌入式控制器）** 固件控制，Linux 下没有 hwmon/PWM 接口，`fancontrol`/`lm-sensors` 都无能为力；而且 EC 默认处于最激进的「狂暴」性能模式，~50°C 就把风扇拉到接近满速。

本项目：

1. 提供一个 **MOK 签名的小内核模块** `ec_rw`，把 EC 内存暴露为 `/dev/ec_rw` —— 这是 Secure Boot 开启时唯一能写 EC 风扇寄存器的途径（内核 lockdown 会拦截标准 `ec_sys` 写入路径）。
2. 运行一个**守护进程** `fan-cap.py`，按温度曲线驱动风扇、**占空比封顶 50%**，并可把 EC 切成 **Office 模式** 降低发热。
3. 可选地限制 CPU RAPL 功耗和 GPU 频率，进一步降温。

实测（同样持续 CPU 负载）：

| | 之前 | 之后 |
|---|---|---|
| 风扇转速 | 92–100% | **~35%（上限 50%）** |
| CPU 温度 | ~95–100 °C | **~70 °C** |

### 硬件适配

* 雷神 ZERO（911 系列），BIOS `TP141`，板号 `NLZC`，广达（Quanta）公模
* 已实测：i9-12900HK + RTX 3060 Laptop
* 系统：Ubuntu 26.04 / kernel 7.0（任意带 DKMS 的发行版应该都行）
* 同模具机型（Eluktronics Prometheus XVI、麦本本 x658 等）大概率兼容，欢迎测试反馈

### 原理简述

* EC 寄存器 `0x2C`=Fan1(CPU) 占空比、`0x2D`=Fan2(GPU) 占空比；`0xFF`=自动，`0`–`100`=手动 %。已验证手动模式下满载不会被 EC 覆盖。
* `0x58`/`0x59`=CPU/GPU 温度；`0x95`=性能模式（0=狂暴 1=游戏 2=办公）。
* 完整寄存器映射与逆向笔记：[`docs/ec-register-map.md`](docs/ec-register-map.md)、[`docs/reverse-engineering.md`](docs/reverse-engineering.md)。

### 安装

```bash
git clone https://github.com/<you>/thunderobot-zero-fan-control.git
cd thunderobot-zero-fan-control
sudo ./install.sh
```

安装脚本会：用 DKMS 编译并安装 MOK 签名的 `ec_rw`（内核升级自动重建）、安装 `fan-cap`/`power-cap` 两个开机自启服务、配置 `/dev/ec_rw` 开机加载、写入默认配置。

**Secure Boot**：需要已注册的 MOK 密钥（装过 NVIDIA 驱动就有）；没有的话见
[`docs/secure-boot.md`](docs/secure-boot.md)。

### 调参

改 `/etc/thunderobot-fan-control.conf` 后 `sudo systemctl restart fan-cap.service`：

```ini
[duty]
max = 50          # 风扇占空比上限（%）
min = 20

[power_mode]
value = 2         # 0=狂暴 1=游戏 2=办公，-1=不动

[fan_curve]
points = 55:20, 70:35, 85:50
```

功耗上限在 `/usr/local/sbin/power-cap.sh`（CPU `PL1`/`PL2` 微瓦、GPU 频率 MHz）。

### 卸载

```bash
sudo ./uninstall.sh
```

重启后 EC 风扇恢复固件自动模式。

### 安全提醒

* 本机仅 `0x2C`/`0x2D`/`0x58`/`0x59`/`0x95` 确认安全。**切勿乱写未知寄存器**（社区 RE 项目反馈：写过会导致强制重启）。
* 风扇封顶后重负载（如游戏）会偏热，注意观察温度，必要时调高 `max` 或调低功耗。
* 守护进程退出时恢复 EC 自动模式，重启后 EC 也会自动复位。

### 致谢

* [InkeyP/thunderobot-zero-fan-control](https://github.com/InkeyP/thunderobot-zero-fan-control) —— 最初的广达 ZERO EC 寄存器逆向
* [NBFC](https://github.com/hirschmann/nbfc) —— EC 探测生态

### 许可证

MIT —— 见 [LICENSE](LICENSE)。
