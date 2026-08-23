#!/bin/bash
# SPDX-License-Identifier: MIT
#
# uninstall.sh - remove everything installed by install.sh.
#
# Note: the fan-control config file /etc/thunderobot-fan-control.conf and the
# DKMS signing config are left in place (they are harmless and the config may
# hold user tuning).  Remove them manually if you want a clean slate.
#
# Usage:  sudo ./uninstall.sh

set -euo pipefail

if [[ $EUID -ne 0 ]]; then
    echo "error: run as root (sudo ./uninstall.sh)" >&2
    exit 1
fi

echo "==> stopping services"
systemctl stop fan-cap.service power-cap.service 2>/dev/null || true
systemctl disable fan-cap.service power-cap.service 2>/dev/null || true

echo "==> removing service units"
rm -f /etc/systemd/system/fan-cap.service /etc/systemd/system/power-cap.service
systemctl daemon-reload

echo "==> removing scripts and config"
rm -f /usr/local/sbin/fan-cap.py /usr/local/sbin/power-cap.sh
rm -f /etc/modules-load.d/ec_rw.conf

echo "==> unloading and removing DKMS module"
rmmod ec_rw 2>/dev/null || true
dkms remove -m ec_rw -v 1.0 --all 2>/dev/null || true
rm -rf /usr/src/ec_rw-1.0
depmod -a

echo "==> done. /dev/ec_rw and all services removed."
echo "    EC fans will return to firmware auto mode after reboot."
