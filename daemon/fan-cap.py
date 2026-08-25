#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""
fan-cap.py - cap the Thunderobot ZERO fans at a configurable duty limit.

The fans on this laptop are driven purely by the EC firmware.  By writing a
duty value (0-100) to the EC fan registers 0x2C/0x2D the EC switches to
"manual" mode and holds the fans at that duty regardless of temperature.
Writing 0xFF restores EC auto mode.  This daemon re-asserts the duty every
few seconds so the cap survives anything that momentarily resets the EC
registers, and restores auto mode when it is stopped.

Behaviour:
  * reads CPU temp (EC 0x58) and GPU temp (EC 0x59)
  * picks a duty from a piecewise-linear temperature curve
  * clamps the duty to [MIN_DUTY, MAX_DUTY]  (default MAX_DUTY = 75)
  * writes the duty to both fans (0x2C / 0x2D)
  * on exit, restores 0xFF (auto) to both fans
  * optionally switches the power mode to Office (EC 0x95 = 2) which lowers
    the firmware power limits and helps keep temperatures in check while the
    fans are capped

Tuning: edit /etc/thunderobot-fan-control.conf (copied from config/fan-
control.conf) or the defaults at the top of this file.

Requires the ec_rw kernel module (see dkms/) which exposes /dev/ec_rw.
"""

import configparser
import os
import signal
import sys
import time

EC_DEV = "/dev/ec_rw"

# EC register map (Thunderobot ZERO / Quanta barebone, verified 2026-08)
REG_DUTY1 = 0x2C       # Fan1 (CPU) duty, 0-100, 0xFF = auto
REG_DUTY2 = 0x2D       # Fan2 (GPU) duty, 0-100, 0xFF = auto
REG_CPU_TEMP = 0x58    # CPU temperature in Celsius
REG_GPU_TEMP = 0x59    # GPU temperature in Celsius
REG_POWER_MODE = 0x95  # APMD: 0=High, 1=Gaming, 2=Office
AUTO = 0xFF

# ---- defaults (overridden by /etc/thunderobot-fan-control.conf) ----
MAX_DUTY = 75          # hard cap: never exceed this duty (%)
MIN_DUTY = 40          # measured stable floor; <40% the fans stall/restart
INTERVAL = 3           # seconds between updates
POWER_MODE = 2         # EC power mode: 0=High 1=Gaming 2=Office, -1 = leave
# Temperature curve: sorted (temp_C, duty) breakpoints, linearly interpolated.
# Between the lowest point and 0C the duty is MIN_DUTY; above the highest
# point the duty is MAX_DUTY.  Do NOT set the curve below MIN_DUTY - below
# ~40% duty the fans on this unit stall and get restarted by the EC in an
# audible start/stop cycle.
CURVE_POINTS = [(55, 40), (70, 55), (85, 75)]
CONF_PATH = "/etc/thunderobot-fan-control.conf"

_fd = None


def ec_write(off, val):
    os.lseek(_fd, off, os.SEEK_SET)
    os.write(_fd, bytes([val]))


def ec_read(off):
    os.lseek(_fd, off, os.SEEK_SET)
    return os.read(_fd, 1)[0]


def curve(temp):
    """temp (C) -> duty (%), piecewise linear through CURVE_POINTS."""
    pts = sorted(CURVE_POINTS)
    if temp <= pts[0][0]:
        return MIN_DUTY
    if temp >= pts[-1][0]:
        return MAX_DUTY
    for i in range(1, len(pts)):
        t_lo, d_lo = pts[i - 1]
        t_hi, d_hi = pts[i]
        if temp <= t_hi:
            duty = int(d_lo + (d_hi - d_lo) * (temp - t_lo) / (t_hi - t_lo))
            return max(MIN_DUTY, min(MAX_DUTY, duty))
    return MAX_DUTY


def restore_auto():
    try:
        ec_write(REG_DUTY1, AUTO)
        ec_write(REG_DUTY2, AUTO)
        print("fan-cap: restored EC auto mode (0xFF)", flush=True)
    except Exception:
        pass


def _handle_exit(signum, frame):
    restore_auto()
    sys.exit(0)


def load_config():
    global MAX_DUTY, MIN_DUTY, INTERVAL, POWER_MODE, CURVE_POINTS
    if not os.path.exists(CONF_PATH):
        return
    cfg = configparser.ConfigParser()
    cfg.read(CONF_PATH)
    try:
        if cfg.has_section("duty"):
            if cfg.has_option("duty", "max"):
                MAX_DUTY = cfg.getint("duty", "max")
            if cfg.has_option("duty", "min"):
                MIN_DUTY = cfg.getint("duty", "min")
        if cfg.has_section("general") and cfg.has_option("general", "interval"):
            INTERVAL = cfg.getint("general", "interval")
        if cfg.has_section("power_mode") and cfg.has_option("power_mode", "value"):
            POWER_MODE = cfg.getint("power_mode", "value")
        if cfg.has_section("fan_curve") and cfg.has_option("fan_curve", "points"):
            raw = cfg.get("fan_curve", "points").strip()
            if raw:
                CURVE_POINTS = [tuple(int(x) for x in p.split(":"))
                                for p in raw.split(",")]
    except (ValueError, configparser.Error) as e:
        print("fan-cap: ignoring invalid config: %s" % e, file=sys.stderr)
    # sanitize
    if MIN_DUTY < 0:
        MIN_DUTY = 0
    if MAX_DUTY > 100:
        MAX_DUTY = 100
    if MIN_DUTY > MAX_DUTY:
        MAX_DUTY = MIN_DUTY


def main():
    global _fd
    load_config()
    try:
        _fd = os.open(EC_DEV, os.O_RDWR)
    except OSError as e:
        print("fan-cap: cannot open %s: %s" % (EC_DEV, e), file=sys.stderr)
        sys.exit(1)

    signal.signal(signal.SIGTERM, _handle_exit)
    signal.signal(signal.SIGINT, _handle_exit)

    if POWER_MODE >= 0:
        try:
            ec_write(REG_POWER_MODE, POWER_MODE)
            print("fan-cap: EC power mode set to %d (0=High 1=Gaming 2=Office)"
                  % POWER_MODE, flush=True)
        except OSError:
            pass

    print("fan-cap: started (max duty %d%%, min duty %d%%, interval %ds)"
          % (MAX_DUTY, MIN_DUTY, INTERVAL), flush=True)
    try:
        while True:
            try:
                t_cpu = ec_read(REG_CPU_TEMP)
                t_gpu = ec_read(REG_GPU_TEMP)
                duty = curve(max(t_cpu, t_gpu))
                ec_write(REG_DUTY1, duty)
                ec_write(REG_DUTY2, duty)
                print("fan-cap: cpu=%dC gpu=%dC duty=%d%%"
                      % (t_cpu, t_gpu, duty), flush=True)
            except OSError as e:
                print("fan-cap: EC error: %s" % e, file=sys.stderr)
            time.sleep(INTERVAL)
    finally:
        restore_auto()


if __name__ == "__main__":
    main()
