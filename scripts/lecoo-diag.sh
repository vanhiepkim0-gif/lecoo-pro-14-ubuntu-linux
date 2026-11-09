#!/bin/bash
# /usr/local/bin/lecoo-diag.sh <tag>
# Dump EC RAM + ACPI PM/GPE registers + wake sources to /var/log/lecoo-diag/
# so a good shutdown and a bad (auto re-power-on) shutdown can be diffed.
TAG="${1:-manual}"
DIR=/var/log/lecoo-diag
mkdir -p "$DIR"
OUT="$DIR/$(date +%Y%m%d-%H%M%S)-$TAG.log"
{
    echo "=== $TAG  $(date -Is)  boot_id=$(cat /proc/sys/kernel/random/boot_id)"
    echo "uptime: $(cat /proc/uptime)"
    echo "--- power_supply"
    for p in /sys/class/power_supply/*; do
        echo "$(basename "$p"): online=$(cat "$p/online" 2>/dev/null) status=$(cat "$p/status" 2>/dev/null) cap=$(cat "$p/capacity" 2>/dev/null)"
    done
    echo "--- suspend_stats success=$(cat /sys/power/suspend_stats/success 2>/dev/null) fail=$(cat /sys/power/suspend_stats/fail 2>/dev/null) last_wakeup_irq=$(cat /sys/power/pm_wakeup_irq 2>/dev/null)"
    modprobe ec_sys write_support=1 2>/dev/null
    echo "--- EC RAM (ec0/io)"
    [ -e /sys/kernel/debug/ec/ec0/io ] && od -A x -t x1 -v /sys/kernel/debug/ec/ec0/io
    echo "--- IO ports 0x800-0x83F (PM1_STS/EN, PM1_CNT, GPE0 ...)"
    dd if=/dev/port bs=1 skip=$((0x800)) count=64 2>/dev/null | od -A x -t x1 -v
    echo "--- GPEs (non-zero / enabled)"
    for g in /sys/firmware/acpi/interrupts/gpe*; do
        v=$(cat "$g" 2>/dev/null); echo "$v" | awk '$1!=0 || /enabled/ {f=1} END{exit !f}' && echo "$(basename "$g"): $v"
    done
    echo "--- /proc/acpi/wakeup enabled"
    grep -i enabled /proc/acpi/wakeup
    echo "--- sysfs wakeup enabled"
    grep -l '^enabled$' $(find /sys/devices -name wakeup -path '*power/wakeup' 2>/dev/null) 2>/dev/null
    echo "--- rtc wakealarm: $(cat /sys/class/rtc/rtc0/wakealarm 2>/dev/null)"
    echo "--- lsusb"; lsusb 2>/dev/null
    echo "--- amd_gpio irqs"; grep -i amd_gpio /proc/interrupts
} > "$OUT" 2>&1
# keep last 40 logs
ls -1t "$DIR"/*.log 2>/dev/null | tail -n +41 | xargs -r rm -f
