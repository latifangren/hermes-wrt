# Hermes-WRT — Installation Guide

## Prerequisites

All installation paths require a pre-built firmware image. You can obtain one by:

- **GitHub Actions:** Fork the repository → Actions → *Build Hermes-WRT* → fill in device/source inputs → Run workflow → download from Artifacts.
- **Local build:** See [local build](#local-build-optional) at the bottom of this page.

---

## Platform-Specific Installation

### x86-64 (Generic PC / UEFI)

**Output file:** `hermes-wrt-x86-64-*.img.gz`

#### Requirements
- USB drive ≥ 2 GB *or* target disk
- `dd`, `Rufus`, or `balenaEtcher`
- The target machine must support BIOS/UEFI legacy boot from USB

#### Steps

1. **Decompress the image:**
   ```bash
   gunzip hermes-wrt-x86-64-*.img.gz
   # or on Windows: 7-Zip → Extract Here
   ```

2. **Flash to USB / target disk:**
   ```bash
   # Linux/macOS — replace /dev/sdX with your target disk
   sudo dd if=hermes-wrt-x86-64-*.img of=/dev/sdX bs=4M status=progress conv=fsync
   sudo sync
   ```
   On Windows use **Rufus** (DD image mode) or **balenaEtcher**.

3. **Boot the machine** from the USB / disk. OpenWrt will start automatically.

4. **First access:**
   - Default LAN IP: `192.168.1.1`
   - Username: `root` / Password: *(empty)*
   - Web UI: `http://192.168.1.1` (LuCI)

5. **Expand rootfs** (optional, if flashed to a larger disk):
   ```bash
   # Run inside OpenWrt shell after boot
   opkg update && opkg install parted losetup resize2fs
   # Then use LuCI → System → Disk Manager, or run resize2fs manually
   ```

> **Note:** x86-64 images include both BIOS-MBR and EFI boot support. UEFI Secure Boot is not supported.

---

### Raspberry Pi

#### Supported models

| Device string | Board |
|---|---|
| `bcm2710-rpi-3b` | Raspberry Pi 3B / 3B+ |
| `bcm2711-rpi-4b` | Raspberry Pi 4B / 400 |

**Output file:** `hermes-wrt-bcm271x-*.img.gz`

#### Requirements
- microSD card ≥ 2 GB (Class 10 / A1 recommended)
- `dd` or **Raspberry Pi Imager**

#### Steps

1. **Decompress:**
   ```bash
   gunzip hermes-wrt-bcm271x-*.img.gz
   ```

2. **Flash to microSD:**
   ```bash
   # Linux/macOS
   sudo dd if=hermes-wrt-bcm271x-*.img of=/dev/mmcblkX bs=4M status=progress conv=fsync
   sudo sync
   ```
   Or use **Raspberry Pi Imager** → *Use custom image* → select the `.img` file.

3. **Insert microSD** into the Raspberry Pi and power on.

4. **First access** — same as x86-64:
   - IP: `192.168.1.1`, user `root`, no password.

> **Raspberry Pi 5 is not supported** — the `bcm2712` target is not included in current workflow device choices.

---

### Amlogic TV Boxes

TV box images are built via the Packing Layer (see [ARCHITECTURE.md](ARCHITECTURE.md)).

**Output file:** `hermes-wrt-{device}.img.gz` in `out/tvbox/`

#### Supported SoCs

| SoC | Common devices |
|---|---|
| S905X | X96 Mini, TX3 Mini |
| S905X2 | X96 Max |
| S905X3 | X96 Max+, HK1 Box, H96 Max X3 |
| S905X4 | X98H, Tanix X4 |
| S905D | Phicomm N1 |
| S912 | TX8 Max, Tanix TX9S |
| S922X | Beelink GT-King |
| A311D | Khadas VIM3 |

#### Boot media options

Amlogic boxes support three boot paths. Choose one based on your goal.

---

##### Option 1 — Boot from SD card (non-destructive, safest)

1. **Decompress and flash** to a microSD card (≥ 4 GB):
   ```bash
   gunzip hermes-wrt-s905x3.img.gz
   sudo dd if=hermes-wrt-s905x3.img of=/dev/mmcblkX bs=4M status=progress conv=fsync
   sudo sync
   ```

2. **Insert the SD card** into the TV box.

3. **Trigger SD boot.** Most Amlogic boxes will not boot SD automatically. Use one of:
   - Short the `boot` pads on the board with a toothpick while powering on (hardware method).
   - Install the `aml_autoscript` from the BOOT partition in the Android bootloader (software method — see below).

4. **Android bootloader method (software):**
   - Boot into Android, mount the SD card's BOOT FAT32 partition.
   - Copy `aml_autoscript` and `s905_autoscript` to the root of the internal storage or run them via the Android file manager / ADB.
   - Reboot — the box will load OpenWrt from SD.

   The boot scripts are pre-built in `boot/amlogic/` and are copied to the BOOT partition during image assembly.

---

##### Option 2 — Boot from USB drive

Same process as SD card. Flash the image to a USB drive instead of microSD. USB boot has lower priority than SD on most Amlogic boxes; SD is preferred when both are inserted.

1. Flash image to USB drive (≥ 4 GB):
   ```bash
   gunzip hermes-wrt-s905x3.img.gz
   sudo dd if=hermes-wrt-s905x3.img of=/dev/sdX bs=4M status=progress conv=fsync
   ```

2. Follow the same Android bootloader method above to trigger USB boot.

---

##### Option 3 — Write to eMMC (permanent)

> **Warning:** This overwrites the internal eMMC storage. Android will be lost. This is irreversible without a USB Burning Tool and original firmware.

1. **Boot from SD or USB** first (Options 1 or 2 above).

2. Once OpenWrt is running, open an SSH session:
   ```bash
   ssh root@192.168.1.1
   ```

3. **Run the eMMC install script:**
   ```bash
   openwrt-install-amlogic
   ```
   This script (bundled with ophub kernel images) detects your eMMC device and writes the current SD/USB system to eMMC.

4. **Remove SD/USB** and reboot. The box will now boot OpenWrt from eMMC.

> If `openwrt-install-amlogic` is not present, use the manual method:
> ```bash
> # Find eMMC block device (usually mmcblk1 or mmcblk2)
> lsblk
> # Then dd the image or use dd + resize within the running system
> ```

---

#### Boot scripts explained (`boot/amlogic/`)

The `boot/amlogic/` directory contains the following files assembled into the BOOT FAT32 partition:

| File | Purpose |
|---|---|
| `aml_autoscript` / `.cmd` | Auto-boot script for Amlogic U-Boot |
| `s905_autoscript` / `.cmd` | S905-specific boot variant |
| `boot.scr` / `boot.cmd` / `boot.ini` | Main boot script (SD/USB) |
| `boot-emmc.scr` / `.cmd` / `.ini` | eMMC boot script |
| `emmc_autoscript` / `.cmd` | eMMC auto-install helper |
| `u-boot.sd` / `u-boot.usb` | U-Boot binaries for SD and USB |
| `uEnv.txt` | Environment variables for U-Boot |
| `uInitrd` | Compressed initrd image |
| `extlinux/` | Extlinux boot config (for compatible loaders) |

---

## Local Build (Optional)

Build a firmware image on your own Linux machine (Ubuntu 22.04+ recommended).

### Install dependencies

```bash
sudo apt-get update
sudo apt-get install -y \
  build-essential libncurses5-dev zlib1g-dev gawk \
  git gettext libssl-dev rsync wget unzip tar gzip \
  qemu-utils jq python3 python3-pip aria2 parted dosfstools
```

### Build

```bash
git clone https://github.com/<your-user>/hermes-wrt
cd hermes-wrt

# x86-64, full variant
sudo ./make-image.sh openwrt:24.10.0 x86-64 full

# Raspberry Pi 4
sudo ./make-image.sh openwrt:24.10.0 bcm2711-rpi-4b simple

# Amlogic S905X3, ophub kernel
sudo ./make-image.sh openwrt:24.10.0 s905x3 full

# Amlogic S905X3, armarchindo kernel
KERNEL_SOURCE=armarchindo sudo ./make-image.sh openwrt:24.10.0 s905x3 full

# ImmortalWrt — more packages available (kiddin9/modem apps)
sudo ./make-image.sh immortalwrt:24.10.0 s905x3 full
```

### Configuration

Edit `hermes.conf` before building to set persistent defaults, or pass environment variables inline:

```bash
# Pin a specific kernel version
KERNEL_VERSION=6.12.95 sudo ./make-image.sh openwrt:24.10.0 s905x3 full

# Larger image size
DISK_SIZE=2G sudo ./make-image.sh openwrt:24.10.0 s905x3 full

# Enable Docker (full variant only)
ENABLE_DOCKER=true sudo ./make-image.sh openwrt:24.10.0 s905x3 full
```

### Output

```
out/
├── *.img.gz          # x86-64 and Raspberry Pi firmware
└── tvbox/
    └── hermes-wrt-{device}.img.gz   # TV box firmware
```

Build log is saved as `build_YYYYMMDD_HHMMSS.log` in the repo root.

---

## Post-Install

### First boot defaults (applied automatically)

The `99-hermes-settings` uci-defaults script runs once on first boot and sets:

- **Hostname:** `HermesWrt`
- **Timezone:** `Asia/Jakarta` (WIB-7)
- **DNS:** Google `8.8.8.8` / `8.8.4.4`

### Changing the default password

```bash
passwd root
```

### Package management

- **OpenWrt 24.x:** `opkg update && opkg install <package>`
- **OpenWrt 25.x:** `apk add <package>`

### Network configuration

Access LuCI at `http://192.168.1.1` → Network → Interfaces to configure WAN/LAN.
