#!/bin/bash
# 1. Tắt các thiết bị đang *enabled trong /proc/acpi/wakeup (không toggle nhầm)
awk '$3 == "*enabled" {print $1}' /proc/acpi/wakeup 2>/dev/null | while read -r dev; do
    echo "$dev" > /proc/acpi/wakeup 2>/dev/null || true
done

# 2. Tắt wakeup trong /sys/devices (trừ nút nguồn PNP0C0C)
find /sys/devices -name wakeup 2>/dev/null | while read -r f; do
    if [[ "$f" != *"PNP0C0C"* ]] && grep -q "^enabled$" "$f" 2>/dev/null; then
        echo disabled > "$f" 2>/dev/null || true
    fi
done

# 3. Mask các ACPI GPE đánh thức PCIe/USB (gpe10, gpe16, gpe19, gpe1A)
for gpe in gpe10 gpe16 gpe19 gpe1A; do
    if [ -f "/sys/firmware/acpi/interrupts/$gpe" ]; then
        echo disable > "/sys/firmware/acpi/interrupts/$gpe" 2>/dev/null || true
    fi
done
