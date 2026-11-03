#!/usr/bin/env bash
# install.sh — One-step installer for Lenovo Lecoo Pro 14 (N155A) Ubuntu/Linux ACPI & Poweroff/Sleep fix
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
    echo "Please run as root: sudo ./install.sh"
    exit 1
fi

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "[1/6] Building machine-native ACPI override CPIO (DSDT _PTS fix + uncorrupted SSDT-CPMGPIO0 v2)..."
python3 "$REPO_DIR/acpi/build_acpi_override.py" "$REPO_DIR/acpi"
(cd "$REPO_DIR/acpi" && find kernel -type f | sort | cpio -o -H newc > "$REPO_DIR/acpi/acpi_override.cpio" 2>/dev/null)
cpio -itv < "$REPO_DIR/acpi/acpi_override.cpio"

if [ -f /boot/acpi_override.cpio ]; then
    cp -a /boot/acpi_override.cpio /boot/acpi_override.cpio.bak
fi
install -m 644 "$REPO_DIR/acpi/acpi_override.cpio" /boot/acpi_override.cpio

echo "[2/6] Installing wakeup & S5 poweroff scripts..."
install -m 755 "$REPO_DIR/scripts/disable-wakeup.sh" /usr/local/bin/disable-wakeup.sh
install -m 755 "$REPO_DIR/scripts/lecoo-poweroff-fix.shutdown" /usr/lib/systemd/system-shutdown/lecoo-poweroff-fix.shutdown

echo "[3/6] Installing udev rule for hot-plugged USB receivers/hubs..."
install -m 644 "$REPO_DIR/udev/99-lecoo-disable-wakeup.rules" /etc/udev/rules.d/99-lecoo-disable-wakeup.rules
udevadm control --reload-rules && udevadm trigger --subsystem-match=usb || true

echo "[4/6] Installing and enabling systemd services..."
install -m 644 "$REPO_DIR/systemd/disable-wakeup.service" /etc/systemd/system/disable-wakeup.service
install -m 644 "$REPO_DIR/systemd/lecoo-nic-unbind.service" /etc/systemd/system/lecoo-nic-unbind.service
systemctl daemon-reload
systemctl enable --now disable-wakeup.service lecoo-nic-unbind.service
/usr/local/bin/disable-wakeup.sh

echo "[5/6] Configuring GRUB (/etc/default/grub)..."
if ! grep -q 'GRUB_EARLY_INITRD_LINUX_CUSTOM="acpi_override.cpio"' /etc/default/grub; then
    echo 'GRUB_EARLY_INITRD_LINUX_CUSTOM="acpi_override.cpio"' >> /etc/default/grub
fi

for param in "acpi.ec_no_wakeup=1" "acpi=force" "i8042.nomux"; do
    if ! grep "^GRUB_CMDLINE_LINUX_DEFAULT=" /etc/default/grub | grep -q "$param"; then
        sed -i "s/^GRUB_CMDLINE_LINUX_DEFAULT=\"/GRUB_CMDLINE_LINUX_DEFAULT=\"$param /" /etc/default/grub
    fi
done

if ! grep "^GRUB_CMDLINE_LINUX_DEFAULT=" /etc/default/grub | grep -q "Windows 2020"; then
    sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT="/GRUB_CMDLINE_LINUX_DEFAULT="acpi_osi=\\"!Windows 2020\\" /' /etc/default/grub
fi

echo "[6/6] Updating GRUB..."
update-grub

echo ""
echo "=== Installation complete! ==="
