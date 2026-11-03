# Lenovo Lecoo Pro 14 (2025 / N155A) — Ubuntu & Linux Complete Fix (Shutdown Reboot & Sleep `s2idle`)

Bộ giải pháp triệt để và tài liệu phân tích kỹ thuật (Root-Cause Analysis) sửa lỗi **Shutdown tự khởi động lại sau 8–10 giây (S5 Reboot)** và **Sleep (`s2idle`) tự tỉnh dậy sau 1 giây** trên laptop **Lenovo Lecoo Pro 14 2025 (Mã mainboard: `N155A`)** chạy Ubuntu / Linux.

> **English summary included below.** This repository provides a verified, production-tested fix for the **Lecoo Pro 14 (N155A, AMD Ryzen 7 H255 Phoenix, BIOS `N155A_00_V1.2_PKID` / `2.5` OEM rev `0x01072009`, EC `IT5571-07`)** where shutting down (`poweroff.target`) causes the laptop to automatically power back on after ~8–10 seconds, and suspending (`s2idle`) wakes up immediately within ~0.5–1 second.

---

## 1. Cấu hình phần cứng đã kiểm chứng (Tested Hardware)

| Thành phần | Thông số trên máy kiểm chứng |
|---|---|
| **Model** | Lenovo Lecoo Pro 14 (2025) / Motherboard `N155A` |
| **CPU / SoC** | AMD Ryzen 7 H255 (Phoenix) w/ Radeon 780M Graphics |
| **BIOS** | `N155A_00_V1.2_PKID` (`06/18/2025`, DSDT OEM Revision `0x01072009` / BIOS 2.5) |
| **Embedded Controller (EC)** | ITE `IT5571-07` (EC Firmware `10.05` / `10.11`) |
| **NIC / Wi-Fi** | Realtek RTL8111/8168 (`r8169`, `0b:00.0`) + Realtek RTL8852BE (`rtw89_8852be`, `0c:00.0`) |
| **OS / Kernel** | Ubuntu 24.04 / 26.04 LTS (Linux Kernel `6.x` – `7.0.0-42-generic`) |

---

## 2. Triệu chứng lỗi (Symptoms)

1. **Tắt máy (Shutdown) biến thành Khởi động lại (Reboot):**
   - Khi bấm **Power Off / Shutdown** (hoặc `sudo poweroff`), hệ thống đi tới `Reached target poweroff.target`, đèn nguồn tắt nhưng khoảng **8–10 giây sau máy tự động bật nguồn khởi động lại**.
2. **Chế độ ngủ (Sleep / `s2idle`) tự tỉnh dậy ngay sau 1 giây:**
   - Khi gập màn hình hoặc bấm **Suspend**, máy vừa vào `PM: suspend entry (s2idle)` thì chỉ **0.5–1 giây sau** đã tự thoát (`PM: suspend exit`) và bật sáng màn hình trở lại.
3. **Bản vá cộng đồng cũ bị mất tác dụng hoặc chập chờn:**
   - Dùng gói `acpi_override.cpio` dựng sẵn từ các repo đời đầu (BIOS 1.x) khiến tỷ lệ lỗi Shutdown tự bật lại tăng lên hoặc không có tác dụng trên BIOS 2.5 (`0x01072009`).

---

## 3. Cài đặt nhanh trong 1 lệnh (Quick Install)

```bash
git clone https://github.com/vanhiepkim0-gif/lecoo-pro-14-ubuntu-linux.git
cd lecoo-pro-14-ubuntu-linux
sudo ./install.sh
```

Sau khi chạy xong, bạn có thể **Shutdown** hoặc **Reboot** ngay.

### Kiểm tra sau khi khởi động lại (Verification)

```bash
# 1. Xác nhận đúng 3 bảng SSDT (WLAN, INTGPP01, CPMGPIO0 v2) được nâng cấp và KHÔNG ghi đè DSDT ngoại lai:
journalctl -b -k | grep "Table Upgrade"
# Kết quả chuẩn:
# ACPI: Table Upgrade: override [SSDT-   AMD-    WLAN]
# ACPI: Table Upgrade: override [SSDT-   AMD-INTGPP01]
# ACPI: Table Upgrade: override [SSDT-   AMD-CPMGPIO0]

# 2. Xác nhận toàn bộ thiết bị trong /proc/acpi/wakeup đều *disabled:
cat /proc/acpi/wakeup
```

---

## 4. Bài học xương máu & Phân tích nguyên nhân gốc rễ (Root-Cause Deep Dive)

Qua quá trình dịch ngược toàn bộ bảng ACPI (`.dsl`/`.aml`), đối chiếu với nhánh nghiên cứu `2.5fix` và phân tích nhật ký phần cứng trên BIOS `0x01072009`, chúng tôi phát hiện **4 nguyên nhân cốt lõi** khiến các cách sửa thông thường thất bại:

### Bài học 1: Bảng `SSDT` trong gói `acpi_override.cpio` cũ bị Kernel âm thầm bỏ qua
Trình nạp bảng ACPI qua initrd của Linux (`drivers/acpi/tables.c`) chỉ chấp nhận ghi đè một bảng ACPI khi **số `OEM Revision` của bảng mới lớn hơn nghiêm ngặt (`>`) số `OEM Revision` trong BIOS**.
- Các bảng `ssdt8.aml` (`WLAN`), `ssdt21.aml` (`INTGPP01`), `ssdt22.aml` (`CPMGPIO0`) khi biên dịch lại bằng `iasl` giữ nguyên `OEM Revision = 0x00000001` (bằng với BIOS).
- Hệ quả: Kernel chỉ in `ACPI: SSDT ACPI table found in initrd` nhưng **không thực hiện `Table Upgrade`**!
- **Khắc phục:** Tăng `OEM Revision` (bytes `24..27` trong header `.aml`) của cả 3 bảng SSDT lên `0x00000002` và tính lại checksum.

### Bài học 2: Ghi đè `dsdt.aml` từ bản dump của máy khác làm HỎNG hàm `_PTS(5)` khi Shutdown
Trong gói vá cũ của `LaVashikk/lecoo-linux-acpi-fix`, file `patched/dsdt.dsl` đã sửa hàm `_PTS` (Prepare To Sleep) từ `If (Arg0)` thành:
```asl
If ((Arg0 < 0x05))
{
    \_SB.TPM.TPTS (Arg0)
    SPTS (Arg0)
    MPTS (Arg0)
    \_SB.PCI0.NPTS (Arg0)
}
```
- Khi Linux tắt máy (`S5`, `Arg0 == 5`), điều kiện `Arg0 < 0x05` làm **bỏ qua toàn bộ hàm `SPTS(5)`**!
- Trong `DSDT` gốc của máy, `SPTS(5)` chịu trách nhiệm ghi các thanh ghi phần cứng AMD FCH (`0xFED80000` / `0xFED80300`): đặt `CLPS = 1`, `SLPS = 1`, xóa cờ `PEWS` (`PCIEXPWAK_STS`) và đặc biệt là đặt `PWDE = 1` (`0xFED803BB` bit 6) để chuẩn bị ngắt nguồn S5.
- Không những thế, `dsdt.aml` dựng sẵn còn chứa cứng các địa chỉ vùng nhớ RAM động (`PPIM = 0x97479F18`, `OGNV = 0x97479698`, `NRSB = 0x97467000`) của một máy khác, gây lệch địa chỉ bộ nhớ khi thực thi AML.
- **Khắc phục:** **Loại bỏ hoàn toàn `dsdt.aml` khỏi `acpi_override.cpio`** để hệ thống sử dụng đúng bảng `DSDT` gốc của BIOS máy (nơi `_PTS(5)` và địa chỉ RAM hoàn toàn chính xác).

### Bài học 3: Tại sao tắt `/proc/acpi/wakeup` vẫn không chặn được máy tự thức dậy? (Bí mật nằm ở `_AEI` GPIO trong `ssdt22.aml`)
Trong bảng `ssdt22.aml` (`SSDT-AMD-CPMGPIO0`), đối tượng `\_SB.GPIO._AEI` khai báo 7 chân ngắt GPIO (`GpioInt`). Trong bản vá cũ của `LaVashikk`, mới chỉ có 2 chân Audio (`0x003D`, `0x003E`) được chuyển sang `Exclusive`, còn **4 chân quan trọng nhất vẫn bị để là `ExclusiveAndWake` (bit 4 = `0x10` trong `int_flags`)**:

| Offset trong `ssdt22.aml` | Chân GPIO (`Pin`) | Thiết bị / Hành vi trong hàm `_EVT` | Cờ cũ | Cờ sau khi vá |
|---|---|---|---|---|
| `0x60a` | `0x0000` (`gpio 0`) | Nút nguồn / Bàn phím (`PNP0C0C`) | `0x0011` (`Wake`) | `0x0011` (**Giữ `Wake`**) |
| `0x62d` | `0x003D` (`gpio 61`) | Audio Endpoint 1 | `0x0000` | `0x0000` (`Exclusive`) |
| `0x650` | `0x003E` (`gpio 62`) | Audio Endpoint 2 | `0x0000` | `0x0000` (`Exclusive`) |
| `0x673` | `0x003A` (`gpio 58`) | Bộ điều khiển USB `XHC0` | `0x0010` (`Wake`) | `0x0000` (**`Exclusive`**) |
| `0x696` | `0x003B` (`gpio 59`) | Bộ điều khiển USB `XHC1` | `0x0010` (`Wake`) | `0x0000` (**`Exclusive`**) |
| `0x6b9` | `0x0018` (`gpio 24`) | Card LAN `GPP2` (`r8169`) + **`Notify(\_SB.PWRB, 0x80)`** | `0x0013` (`Wake`) | `0x0003` (**`Exclusive`**) |
| `0x6dc` | `0x000B` (`gpio 11`) | Sự kiện sạc AC (`ADP1`) | `0x0013` (`Wake`) | `0x0003` (**`Exclusive`**) |

- Hãy nhìn vào chân `0x0018` (`amd_gpio 24`): khi card mạng Realtek RTL8111 (`r8169`) chuyển sang trạng thái D3 lúc Sleep hoặc Shutdown, nó kéo chân GPIO `0x18` xuống mức thấp. Trong AML của bảng `CPMGPIO0`, `Case (0x18)` không chỉ gọi `Notify (\_SB.PCI0.GPP2, 0x02)` mà còn gọi **`Notify (\_SB.PWRB, 0x80)` (giả lập sự kiện nhấn nút nguồn!)**.
- Các chân `_AEI` GPIO này được driver `pinctrl_amd` nạp trực tiếp từ bảng AML vào thanh ghi phần cứng `WakeCntrl`, nên **mọi can thiệp qua `/proc/acpi/wakeup` hay `/sys/devices/.../power/wakeup` đều vô tác dụng**.
- **Khắc phục:** Dùng script [`acpi/patch_ssdt22.py`](acpi/patch_ssdt22.py) xóa bit `0x10` (`_WKC`) của cả 4 chân `0x003A`, `0x003B`, `0x0018`, `0x000B` trong `ssdt22.aml`.

### Bài học 4: Khóa chặt bước cuối cùng trước khi ngắt nguồn S5 (`lecoo-poweroff-fix.shutdown`)
Khi bạn cắm thêm **USB Hub ngoài** hoặc **đầu thu chuột không dây 2.4G** vào cổng USB (`xhci_hcd`), hoặc khi driver mạng `r8169` / Wi-Fi `rtw89_8852be` tắt nguồn ở bước S5, xung `PME#` / `WAKE#` trên bus PCIe có thể kích hoạt thanh ghi `PM1_STS` của AMD FCH và làm EC `IT5571-07` bật máy lại sau 8–10 giây.

Do đó, script [`scripts/lecoo-poweroff-fix.shutdown`](scripts/lecoo-poweroff-fix.shutdown) được đặt tại `/usr/lib/systemd/system-shutdown/` (chạy ở giây cuối cùng sau khi mọi dịch vụ đã dừng và ổ đĩa đã unmount) để thực hiện 4 chốt chặn phần cứng:
1. Chạy lại `/usr/local/bin/disable-wakeup.sh` để khóa mọi wakeup source trong `/proc/acpi/wakeup` và `/sys/devices`.
2. Hạ toàn bộ interface mạng và **unbind** cả 4 nhóm driver PCI trước khi vào S5:
   - `r8169` (`0000:0b:00.0` — Realtek Gigabit LAN)
   - `rtw89_8852be` (`0000:0c:00.0` — Realtek Wi-Fi 6)
   - `xhci_hcd` (`0000:6e:00.3`, `0000:6e:00.4`, `0000:70:00.3`, `0000:70:00.4` — USB Controllers)
   - `thunderbolt` (`0000:70:00.5`, `0000:70:00.6` — USB4/Thunderbolt NHI)
3. Mask và clear toàn bộ các ngắt ACPI GPE (`gpe0A`, `gpe10`, `gpe16`, `gpe19`, `gpe1A`) trong `/sys/firmware/acpi/interrupts/`.
4. Ghi trực tiếp vào thanh ghi I/O ACPI `PM1_EN` (`0x0803` bit 6: **`PEWD / PCIEXPWAK_DIS = 1`**) để khóa cứng tính năng đánh thức qua PCIe ở cấp độ chipset AMD FCH, xóa cờ `PEWS` (`0x0801` bit 6), và đảm bảo các bit `CLPS=1`, `SLPS=1`, `PWDE=1` (`0xFED80000`) được thiết lập chuẩn xác.

---

## 5. Kinh nghiệm sử dụng chế độ Sleep (`s2idle`) trên Lecoo Pro 14 N155A

- **Sleep (`s2idle`) hoạt động ổn định 100%** sau khi nạp `ssdt22.aml` (`CPMGPIO0` v2) trong repo này: máy không còn bị tự thức dậy sau 1 giây như trước.
- **Cách đánh thức máy khi đang Sleep:** Vì đã cắt quyền wake của cổng USB ngoài (để tránh chuột không dây / USB Hub làm máy tự sáng màn hình trong balo), khi muốn đánh thức máy bạn hãy **nhấn phím bất kỳ trên bàn phím tích hợp của laptop, bấm nút nguồn, hoặc mở nắp màn hình**.
- **Tuyệt đối không ép sang `deep` (S3):** CPU AMD Ryzen 7 H255 (Phoenix) trên máy này chỉ hỗ trợ chuẩn ngủ hiện đại `[s2idle]` (S0ix). Không thêm `mem_sleep_default=deep` vào GRUB vì firmware đã vô hiệu hóa S3 (`XS3`).
- **Mức tiêu thụ pin khi Sleep:** Khoảng `~0.8% – 1.2% / giờ`. Nghỉ trưa hoặc di chuyển vài tiếng dùng Sleep rất tiện; nghỉ qua đêm nên Shutdown.

---

## 6. Cấu trúc thư mục (Repository Structure)

```text
.
├── acpi/
│   ├── acpi_override.cpio               # Initrd CPIO archive nạp qua GRUB_EARLY_INITRD_LINUX_CUSTOM
│   ├── patch_ssdt22.py                  # Script Python vá trực tiếp cờ GpioInt Wake & OEM Rev trong ssdt22.aml
│   └── kernel/firmware/acpi/
│       ├── ssdt8.aml                    # SSDT-AMD-WLAN (OEM Rev 2)
│       ├── ssdt21.aml                   # SSDT-AMD-INTGPP01 (OEM Rev 2)
│       └── ssdt22.aml                   # SSDT-AMD-CPMGPIO0 (OEM Rev 2, đã tắt wake 0x18/0x3A/0x3B/0x0B)
├── scripts/
│   ├── disable-wakeup.sh                # Tắt wakeup trong /proc/acpi/wakeup, sysfs và GPE lúc boot/resume
│   └── lecoo-poweroff-fix.shutdown      # Hook system-shutdown khóa PCIe wake & unbind driver trước S5
├── systemd/
│   ├── disable-wakeup.service           # Chạy disable-wakeup.sh khi boot và sau khi resume từ sleep
│   └── lecoo-nic-unbind.service         # Unbind sớm r8169 khi bắt đầu quá trình tắt máy
├── install.sh                           # Script cài đặt tự động toàn bộ
└── uninstall.sh                         # Script gỡ cài đặt
```

---

## 7. Credits & Tham khảo (References)

- [`LaVashikk/lecoo-linux-acpi-fix`](https://github.com/LaVashikk/lecoo-linux-acpi-fix) — Nghiên cứu ACPI ban đầu cho dòng Lecoo Pro 14 N155A.
- [`monstorix/lecoo-linux-acpi-fix` (nhánh `2.5fix`)](https://github.com/monstorix/lecoo-linux-acpi-fix/tree/2.5fix) — Phân tích chuyên sâu về BIOS 2.5 (`0x01072009`), chân GPIO `0x0018` và vấn đề lệch bảng `DSDT`.
- [`disorder133/lecoo-control`](https://github.com/disorder133/lecoo-control) — Công cụ điều khiển quạt, hiệu năng và giới hạn sạc pin qua EC `IT5571-07` cho Lecoo N155A trên Linux.
