#!/bin/bash
# SPDX-License-Identifier: MIT
#
# power-cap.sh - reduce sustained heat under a capped fan.
#
# The EC fan curve of the Thunderobot ZERO is aggressive (it spins the fans
# near max even at ~50C).  When combined with fan-cap.py (which caps the fans
# at MAX_DUTY), the machine stays quieter but also carries less heat away, so
# it makes sense to reduce how much heat the CPU/GPU generate in the first
# place.  This script does that with two safe, reversible knobs:
#
#   1. RAPL (Intel power limits): cap CPU long-term (PL1) and short-term
#      (PL2) power draw.  The factory BIOS on this machine sets PL1 to a very
#      high value (observed 200W); 45W/65W are the stock Intel spec values
#      for the i9-12900HK and keep temperatures under control.
#
#   2. NVIDIA GPU clock lock: nvidia-smi -pl is locked by the VBIOS on this
#      machine, so instead we clamp the GPU boost clock, which cuts GPU power
#      and heat almost proportionally.
#
# All values below are tunable.  Raise them if you want more performance,
# lower them if you want even less heat.

# --- CPU RAPL limits in microwatts ---
# /sys/class/powercap/intel-rapl:0 is "package-0" on Intel Alder Lake.
RAPL="/sys/class/powercap/intel-rapl:0"
PL1=45000000   # long_term  (45 W)
PL2=65000000   # short_term (65 W)

# --- NVIDIA GPU max clock in MHz (0 = leave untouched) ---
GPU_MAX_CLOCK=1400   # stock boost is 2100 MHz on the RTX 3060 Laptop

set -e

echo "[power-cap] setting CPU RAPL PL1=${PL1}uW PL2=${PL2}uW"
[ -w "$RAPL/constraint_0_power_limit_uw" ] && \
    echo "$PL1" > "$RAPL/constraint_0_power_limit_uw"
[ -w "$RAPL/constraint_1_power_limit_uw" ] && \
    echo "$PL2" > "$RAPL/constraint_1_power_limit_uw"

if [ "$GPU_MAX_CLOCK" -gt 0 ] && command -v nvidia-smi >/dev/null; then
    echo "[power-cap] locking GPU max clock to ${GPU_MAX_CLOCK} MHz"
    nvidia-smi -lgc "0,$GPU_MAX_CLOCK" >/dev/null || true
fi

echo "[power-cap] done"
exit 0
