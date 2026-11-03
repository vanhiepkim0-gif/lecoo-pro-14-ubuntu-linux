#!/usr/bin/env bash
# uninstall.sh — Cleanly remove Lecoo Pro 14 (N155A) ACPI & Poweroff/Sleep fix
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
    echo "Please run as root: sudo ./uninstall.sh"
    exit 1
fi

systemctl disable --now disable-wakeup.service lecoo-nic-unbind.service 2>/dev/null || true
rm -f /etc/systemd/system/disable-wakeup.service \
      /etc/systemd/system/lecoo-nic-unbind.service \
      /usr/local/bin/disable-wakeup.sh \
      /usr/lib/systemd/system-shutdown/lecoo-poweroff-fix.shutdown \
      /boot/acpi_override.cpio
systemctl daemon-reload

sed -i '/GRUB_EARLY_INITRD_LINUX_CUSTOM="acpi_override.cpio"/d' /etc/default/grub
update-grub

echo "Uninstalled Lecoo Pro 14 (N155A) fixes."
