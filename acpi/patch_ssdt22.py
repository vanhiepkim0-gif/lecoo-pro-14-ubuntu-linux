#!/usr/bin/env python3
r"""
patch_ssdt22.py — Binary AML patcher for Lecoo Pro 14 (N155A) SSDT-AMD-CPMGPIO0 (ssdt22.aml)

Why this exists:
1. Linux's initrd ACPI table override (`drivers/acpi/tables.c`) silently ignores any
   table in `acpi_override.cpio` whose `oem_revision` is not strictly greater than
   the firmware's `oem_revision` (0x00000001).
2. In `LaVashikk/lecoo-linux-acpi-fix`, `ssdt22.aml` (`CPMGPIO0`) only disarmed
   Audio GPIO pins `0x003D` and `0x003E`, leaving 4 critical `_AEI` GPIO pins armed
   with `ExclusiveAndWake` (bit 4 = 0x10 in ACPI 5.0 GpioInt descriptor flags):
   - Pin 0x003A (GPIO 58): XHC0 USB controller wake
   - Pin 0x003B (GPIO 59): XHC1 USB controller wake
   - Pin 0x0018 (GPIO 24): GPP2 (Realtek RTL8111 LAN) wake + Notify(\_SB.PWRB, 0x80)
   - Pin 0x000B (GPIO 11): AC adapter wake
   Because `_AEI` GPIO wake pins are programmed directly by `pinctrl_amd` from AML,
   they CANNOT be disabled via `/proc/acpi/wakeup` or `/sys/devices/.../power/wakeup`.

This script:
- Bumps `oem_revision` (bytes 24..28) to >= 2 if needed.
- Clears the `_WKC` (Wake Capability, 0x10) bit in `int_flags` on pins
  `0x003A`, `0x003B`, `0x0018`, and `0x000B` (leaving only `0x0000` Power Button / Keyboard wake).
- Recomputes the 1-byte ACPI table checksum at byte 9 so `(sum(table) % 256) == 0`.
"""

import sys
from pathlib import Path

PINS_TO_DISARM = {
    0x673: 0x003A,  # XHC0 USB wake
    0x696: 0x003B,  # XHC1 USB wake
    0x6B9: 0x0018,  # GPP2 (RTL8111 LAN) + PWRB notify wake
    0x6DC: 0x000B,  # AC adapter wake
}

ALL_GPIOINT_OFFSETS = [0x60A, 0x62D, 0x650, 0x673, 0x696, 0x6B9, 0x6DC]


def patch_ssdt22(path: Path) -> None:
    data = bytearray(path.read_bytes())
    sig = data[0:4].decode("ascii", errors="replace")
    oem_table_id = data[16:24].decode("ascii", errors="replace").strip()
    oem_rev = int.from_bytes(data[24:28], "little")
    print(f"Table: {sig} OEM_TABLE_ID={oem_table_id!r} OEM_REV={oem_rev:#x} len={len(data)}")

    if oem_rev < 2:
        data[24:28] = (2).to_bytes(4, "little")
        print(" -> Bumped OEM_REV to 0x00000002")

    for off, expected_pin in PINS_TO_DISARM.items():
        assert data[off] == 0x8C, f"Expected GpioInt tag 0x8C at {off:#x}"
        pin = int.from_bytes(data[off + 23 : off + 25], "little")
        assert pin == expected_pin, f"Expected pin {expected_pin:#06x} at {off:#x}, got {pin:#06x}"
        old_flags = int.from_bytes(data[off + 7 : off + 9], "little")
        data[off + 7] &= ~0x10  # Clear ExclusiveAndWake -> Exclusive
        new_flags = int.from_bytes(data[off + 7 : off + 9], "little")
        print(f" -> Disarmed pin {pin:#06x} at {off:#x}: int_flags {old_flags:#06x} -> {new_flags:#06x}")

    data[9] = 0
    data[9] = (-sum(data)) & 0xFF
    assert sum(data) % 256 == 0, "Checksum verification failed!"
    path.write_bytes(data)

    print("\nFinal GpioInt table state:")
    for off in ALL_GPIOINT_OFFSETS:
        int_flags = int.from_bytes(data[off + 7 : off + 9], "little")
        pin = int.from_bytes(data[off + 23 : off + 25], "little")
        wake = "Wake" if (int_flags & 0x10) else "Non-Wake (Exclusive)"
        print(f"  offset={off:#x} pin={pin:#06x} int_flags={int_flags:#06x} [{wake}]")


if __name__ == "__main__":
    target = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).parent / "kernel/firmware/acpi/ssdt22.aml"
    patch_ssdt22(target)
