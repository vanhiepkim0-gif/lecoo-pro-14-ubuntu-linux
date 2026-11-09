#!/bin/bash
# Revert the hibernate experiment and keep only the Sleep/Shutdown fixes.
# Usage: sudo bash cleanup-hibernate.sh
set -e
[ "$(id -u)" = 0 ] || { echo "Run with sudo"; exit 1; }

# 1. GRUB: restore original cmdline (the hibernate edit mangled acpi_osi quoting)
if [ -f /etc/default/grub.bak-hibernate ]; then
    cp /etc/default/grub.bak-hibernate /etc/default/grub
    rm -f /etc/default/grub.bak-hibernate
fi

# 2. Disable hibernation (resume is not configured, so hibernating would lose open work)
rm -f /etc/initramfs-tools/conf.d/resume
rm -f /usr/lib/systemd/system-sleep/lecoo-hibernate-fix
mkdir -p /etc/systemd/sleep.conf.d
cat > /etc/systemd/sleep.conf.d/lecoo-hibernate.conf <<'EOF'
# Lecoo N155A: S4/S5 auto power-on bug -> only use s2idle Sleep
[Sleep]
AllowHibernation=no
AllowSuspendThenHibernate=no
AllowHybridSleep=no
EOF

# 3. Shrink /swap.img back to 8G
if [ "$(stat -c %s /swap.img)" -gt $((9*1024*1024*1024)) ]; then
    swapoff /swap.img
    rm -f /swap.img
    fallocate -l 8G /swap.img
    chmod 600 /swap.img
    mkswap /swap.img >/dev/null
    swapon /swap.img
fi

# 4. Redundant: the system-shutdown hook already unbinds r8169
systemctl disable --now lecoo-nic-unbind.service 2>/dev/null || true
rm -f /etc/systemd/system/lecoo-nic-unbind.service
systemctl daemon-reload

# 5. Leftover junk from earlier experiments
rm -f /usr/local/bin/disable-wakeup.sh.save /boot/acpi_override.cpio.bak

update-initramfs -u -k all
update-grub
echo ">> Cleanup done. Reboot once."
