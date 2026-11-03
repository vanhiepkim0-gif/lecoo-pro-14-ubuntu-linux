#!/usr/bin/env bash
# install.sh — One-step installer for Lenovo Lecoo Pro 14 (N155A) Ubuntu/Linux ACPI & Poweroff/Sleep fix
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
    echo "Please run as root: sudo ./install.sh"
    exit 1
fi

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "[1/5] Installing /boot/acpi_override.cpio (SSDT-WLAN, SSDT-INTGPP01, SSDT-CPMGPIO0 v2)..."
if [ -f /boot/acpi_override.cpio ]; then
    cp -a /boot/acpi_override.cpio /boot/acpi_override.cpio.bak
fi
install -m 644 "$REPO_DIR/acpi/acpi_override.cpio" /boot/acpi_override.cpio

echo "[2/5] Installing wakeup & S5 poweroff scripts..."
install -m 755 "$REPO_DIR/scripts/disable-wakeup.sh" /usr/local/bin/disable-wakeup.sh
install -m 755 "$REPO_DIR/scripts/lecoo-poweroff-fix.shutdown" /usr/lib/systemd/system-shutdown/lecoo-poweroff-fix.shutdown

echo "[3/5] Installing and enabling systemd services..."
install -m 644 "$REPO_DIR/systemd/disable-wakeup.service" /etc/systemd/system/disable-wakeup.service
install -m 644 "$REPO_DIR/systemd/lecoo-nic-unbind.service" /etc/systemd/system/lecoo-nic-unbind.service
systemctl daemon-reload
systemctl enable --now disable-wakeup.service lecoo-nic-unbind.service

echo "[4/5] Configuring GRUB (/etc/default/grub)..."
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

echo "[5/5] Updating GRUB..."
update-grub

echo ""
echo "=== Installation complete! ==="
echo "Reboot once for the initrd ACPI table upgrades to load, or Shutdown directly."
