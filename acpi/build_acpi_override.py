#!/usr/bin/env python3
r"""
build_acpi_override.py — Builds a clean, machine-native acpi_override.cpio for Lecoo Pro 14 (N155A)

1. Patches the local machine's native `/sys/firmware/acpi/tables/DSDT` (preserving all
   machine-specific DRAM/fTPM addresses) so `Method (_PTS, 1)` changes `If (Arg0)` to
   `If ((Arg0 < 0x05))` (skipping the buggy BIOS S5 _PTS handler that triggers S5 reboot),
   and bumps OEM Revision to `0x0107201A`.
2. Patches the uncorrupted factory `SSDT-AMD-CPMGPIO0` (`ssdt22.aml`, 3369 bytes) to disarm
   the 6 non-power-button `_AEI` GPIO wake pins (`0x003D`, `0x003E`, `0x003A`, `0x003B`,
   `0x0018`, `0x000B`) from `ExclusiveAndWake` to `Exclusive` and bumps OEM Revision to `2`
   WITHOUT corrupting `_EVT(0)` (`Store(CMSR(0x56), Local1)` and `B1PN = Zero` remain intact!).
"""

import sys
from pathlib import Path

OLD_PTS = bytes.fromhex("14 33 5f 50 54 53 01 a0 2c 68")
NEW_PTS = bytes.fromhex("14 36 5f 50 54 53 01 a0 2f 95 68 0a 05")

ORIG_CPMGPIO0_PINS = {
    0x5E0: 0x003D,  # Audio
    0x603: 0x003E,  # Audio
    0x626: 0x003A,  # XHC0 USB
    0x649: 0x003B,  # XHC1 USB
    0x66C: 0x0018,  # GPP2 (RTL8111 LAN) + PWRB notify
    0x68F: 0x000B,  # AC adapter
}


def patch_native_dsdt(src: Path, dst: Path) -> None:
    data = bytearray(src.read_bytes())
    if OLD_PTS in data:
        assert data.count(OLD_PTS) == 1
        idx = data.find(OLD_PTS)
        data[idx : idx + len(OLD_PTS)] = NEW_PTS
        data[4:8] = len(data).to_bytes(4, "little")
        print(f"[DSDT] Patched native _PTS at {idx:#x} (If (Arg0) -> If (Arg0 < 0x05)), new len={len(data)}")
    elif NEW_PTS in data:
        print(f"[DSDT] Native DSDT already has patched _PTS, len={len(data)}")
    else:
        raise RuntimeError("Could not find standard _PTS signature in DSDT!")

    data[24:28] = (0x0107201A).to_bytes(4, "little")
    data[9] = 0
    data[9] = (-sum(data)) & 0xFF
    assert sum(data) % 256 == 0
    dst.write_bytes(data)


def patch_clean_ssdt22(src: Path, dst: Path) -> None:
    data = bytearray(src.read_bytes())
    assert len(data) == 3369, f"Expected 3369-byte factory CPMGPIO0, got {len(data)}"
    for off, expected_pin in ORIG_CPMGPIO0_PINS.items():
        assert data[off] == 0x8C
        pin = int.from_bytes(data[off + 23 : off + 25], "little")
        assert pin == expected_pin, f"Expected pin {expected_pin:#x} at {off:#x}, got {pin:#x}"
        data[off + 7] &= ~0x10  # Clear ExclusiveAndWake -> Exclusive
    data[24:28] = (2).to_bytes(4, "little")
    data[9] = 0
    data[9] = (-sum(data)) & 0xFF
    assert sum(data) % 256 == 0
    dst.write_bytes(data)
    print(f"[SSDT22] Patched uncorrupted factory CPMGPIO0 (len={len(data)}, OEM rev=2, 6 wake pins disarmed)")


if __name__ == "__main__":
    acpi_dir = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).parent
    out_dir = acpi_dir / "kernel/firmware/acpi"
    out_dir.mkdir(parents=True, exist_ok=True)

    dsdt_src = Path("/sys/firmware/acpi/tables/DSDT")
    if dsdt_src.exists():
        try:
            patch_native_dsdt(dsdt_src, out_dir / "dsdt.aml")
        except PermissionError:
            print("[DSDT] Skipping /sys/firmware/acpi/tables/DSDT (requires root)")

    orig_ssdt22 = acpi_dir / "orig_cpmgpio0.aml"
    if orig_ssdt22.exists():
        patch_clean_ssdt22(orig_ssdt22, out_dir / "ssdt22.aml")
