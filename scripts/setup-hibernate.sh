#!/bin/bash
# Enable hibernate (ACPI S4) on Lecoo Pro 14 N155A - Ubuntu, ext4 root, /swap.img swapfile.
# Usage: sudo bash setup-hibernate.sh [SWAP_GB]   (default: RAM + 2 GB)
set -euo pipefail
[ "$(id -u)" = 0 ] || { echo "Run with sudo"; exit 1; }

SWAP=/swap.img
RAM_GB=$(( ($(awk '/MemTotal/{print $2}' /proc/meminfo) + 1048575) / 1048576 ))
SWAP_GB=${1:-$((RAM_GB + 2))}
CUR_GB=$(( $(stat -c %s "$SWAP" 2>/dev/null || echo 0) / 1073741824 ))

if [ "$CUR_GB" -lt "$SWAP_GB" ]; then
    echo ">> Recreating $SWAP with ${SWAP_GB}G (was ${CUR_GB}G)"
    swapoff "$SWAP" 2>/dev/null || true
    rm -f "$SWAP"
    fallocate -l "${SWAP_GB}G" "$SWAP"
    chmod 600 "$SWAP"
    mkswap "$SWAP" >/dev/null
    swapon "$SWAP"
fi
grep -q "^$SWAP" /etc/fstab || echo "$SWAP none swap sw 0 0" >> /etc/fstab

UUID=$(findmnt -no UUID -T "$SWAP")
OFFSET=$(filefrag -v "$SWAP" | awk '$1=="0:" {gsub(/\./,"",$4); print $4; exit}')
echo ">> resume=UUID=$UUID resume_offset=$OFFSET"

# GRUB kernel cmdline
#   Put resume= into GRUB_CMDLINE_LINUX (not _DEFAULT): _DEFAULT here contains
#   escaped quotes (acpi_osi=\"!Windows 2020\") that break simple sed edits.
[ -f /etc/default/grub.bak-hibernate ] || cp /etc/default/grub /etc/default/grub.bak-hibernate
sed -i -E '/^GRUB_CMDLINE_LINUX=/d' /etc/default/grub
echo "GRUB_CMDLINE_LINUX=\"resume=UUID=$UUID resume_offset=$OFFSET\"" >> /etc/default/grub
grep ^GRUB_CMDLINE /etc/default/grub

# initramfs resume hook
echo "RESUME=UUID=$UUID resume_offset=$OFFSET" > /etc/initramfs-tools/conf.d/resume

# Use ACPI S4 (like Windows), not S5 shutdown
mkdir -p /etc/systemd/sleep.conf.d
cat > /etc/systemd/sleep.conf.d/lecoo-hibernate.conf <<'EOF'
[Sleep]
AllowHibernation=yes
AllowSuspendThenHibernate=yes
HibernateMode=platform
# suspend-then-hibernate: s2idle first, hibernate after this delay
HibernateDelaySec=3h
EOF

update-initramfs -u -k all
update-grub
echo ">> Done. Reboot, then test:  sudo systemctl hibernate"
