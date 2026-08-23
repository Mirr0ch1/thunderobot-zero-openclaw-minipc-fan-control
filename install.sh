#!/bin/bash
# SPDX-License-Identifier: MIT
#
# install.sh - one-shot installer for the Thunderobot ZERO fan control.
#
# What it does:
#   1. Builds and installs the ec_rw kernel module via DKMS
#      (auto-rebuilt on every kernel upgrade).
#   2. Installs the fan-cap daemon + systemd service (capped fans).
#   3. Installs the power-cap service (RAPL + GPU clock cap).
#   4. Configures module auto-loading at boot.
#   5. Configures DKMS to sign modules with the enrolled MOK key if a key is
#      found (required on Secure Boot; harmless otherwise).
#
# Usage:  sudo ./install.sh
#
# Uninstall with ./uninstall.sh.

set -euo pipefail

if [[ $EUID -ne 0 ]]; then
    echo "error: run as root (sudo ./install.sh)" >&2
    exit 1
fi

SRC="$(cd "$(dirname "$0")" && pwd)"
KVER="$(uname -r)"

# --- sanity checks ----------------------------------------------------------
for c in dkms make gcc python3 systemctl; do
    command -v "$c" >/dev/null || { echo "error: missing required tool: $c" >&2; exit 1; }
done
if ! ls /lib/modules/"$KVER"/build >/dev/null 2>&1; then
    echo "error: kernel headers for $KVER not found" >&2
    echo "       install them with: sudo apt install linux-headers-$(uname -r)" >&2
    exit 1
fi

# --- 1. DKMS module ---------------------------------------------------------
echo "==> installing ec_rw kernel module via DKMS"
rm -rf /usr/src/ec_rw-1.0
cp -r "$SRC/dkms" /usr/src/ec_rw-1.0
chmod -R a+rX /usr/src/ec_rw-1.0

# DKMS signing: use the enrolled MOK key if present (Secure Boot).
if [[ -f /var/lib/shim-signed/mok/MOK.priv && -f /var/lib/shim-signed/mok/MOK.der ]]; then
    mkdir -p /etc/dkms/framework.conf.d
    cp -f "$SRC/config/sign_with_mok.conf" /etc/dkms/framework.conf.d/sign_with_mok.conf
    echo "   DKMS will sign modules with the enrolled MOK key"
fi

rmmod ec_rw 2>/dev/null || true
dkms remove -m ec_rw -v 1.0 --all 2>/dev/null || true
dkms add /usr/src/ec_rw-1.0
dkms build -m ec_rw -v 1.0
dkms install -m ec_rw -v 1.0
rm -f /lib/modules/"$KVER"/extra/ec_rw.ko   # remove any legacy manual copy
depmod -a

# --- 2. module auto-load at boot --------------------------------------------
echo "==> enabling ec_rw at boot"
cp -f "$SRC/config/ec_rw.conf" /etc/modules-load.d/ec_rw.conf

modprobe ec_rw
if [[ ! -e /dev/ec_rw ]]; then
    echo "error: ec_rw loaded but /dev/ec_rw is missing" >&2
    exit 1
fi
echo "   /dev/ec_rw ready"

# --- 3. fan-cap daemon ------------------------------------------------------
echo "==> installing fan-cap daemon"
install -m 755 "$SRC/daemon/fan-cap.py" /usr/local/sbin/fan-cap.py
install -m 644 "$SRC/daemon/fan-cap.service" /etc/systemd/system/fan-cap.service
if [[ ! -e /etc/thunderobot-fan-control.conf ]]; then
    install -m 644 "$SRC/config/fan-control.conf" /etc/thunderobot-fan-control.conf
    echo "   wrote default config /etc/thunderobot-fan-control.conf"
fi

# --- 4. power-cap service ---------------------------------------------------
echo "==> installing power-cap service"
install -m 755 "$SRC/power/power-cap.sh" /usr/local/sbin/power-cap.sh
install -m 644 "$SRC/power/power-cap.service" /etc/systemd/system/power-cap.service

# --- 5. enable everything ---------------------------------------------------
systemctl daemon-reload
systemctl enable fan-cap.service power-cap.service
systemctl restart fan-cap.service power-cap.service

echo
echo "==> done."
echo "    fan-cap.service   $(systemctl is-active fan-cap.service)"
echo "    power-cap.service $(systemctl is-active power-cap.service)"
echo "    ec_rw module      $(modinfo -F version ec_rw 2>/dev/null || echo installed)"
echo
echo "Tune the cap in /etc/thunderobot-fan-control.conf (then restart fan-cap.service)."
echo "To revert everything: sudo ./uninstall.sh"
