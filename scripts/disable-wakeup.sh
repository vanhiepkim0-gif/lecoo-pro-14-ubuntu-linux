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

# 4. Xóa cờ B1PN/WOLE/ECS3 bị kẹt trong EC RAM (0xA7) sau khi thức dậy từ Sleep
modprobe -r ec_sys 2>/dev/null || true
modprobe ec_sys write_support=1 2>/dev/null || true
if [ -e /sys/kernel/debug/ec/ec0/io ]; then
    python3 -c '
try:
    with open("/sys/kernel/debug/ec/ec0/io", "r+b", buffering=0) as f:
        f.seek(0xA7)
        a7 = f.read(1)[0]
        if a7 & 0x51:
            f.seek(0xA7)
            f.write(bytes([a7 & ~0x51]))
except Exception:
    pass
' 2>/dev/null || true
fi
