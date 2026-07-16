# Hermes-WRT — Architecture

## Overview

Hermes-WRT is a shell-based firmware build system wrapping the official OpenWrt/ImmortalWrt **ImageBuilder**. Its primary design principle is a **dual-path build**: official devices get a turnkey `.img.gz` directly from ImageBuilder, while TV boxes require an extra packing layer to marry the generic rootfs with a selectable external kernel.

---

## Dual-Path Build System

```
imagebuilder.sh
      │
      ├─ detect_target()
      │        │
      │        ├─ TVBOX=false ──► build_official()
      │        │                      └─ run_make() → .img.gz → out/
      │        │
      │        └─ TVBOX=true  ──► build_tvbox()
      │                               ├─ run_make() → rootfs.tar.gz → out/rootfs/
      │                               └─ PACKER.sh:pack_tvbox()
      │                                       ├─ download_kernel()
      │                                       ├─ fallocate + parted + mkfs
      │                                       ├─ assemble boot + dtb + rootfs + modules
      │                                       └─ gzip → out/tvbox/*.img.gz
```

### Path A — Official Devices (x86-64, Raspberry Pi, generic armsr)

`detect_target()` sets `TVBOX=false` for devices that have a native OpenWrt target:

| Device string | Target system | Profile |
|---|---|---|
| `x86-64` | `x86/64` | `generic` |
| `bcm2710-rpi-3b` | `bcm27xx/bcm2710` | `rpi-3` |
| `bcm2711-rpi-4b` | `bcm27xx/bcm2711` | `rpi-4` |

`build_official()` calls `run_make()`, yang mengabaikan kernel pihak ketiga dan menggunakan kernel resmi OpenWrt/ImmortalWrt bawaan target profile. Output `.img.gz` disalin dari `bin/targets/` ke `out/`.

### Path B — TV Boxes (Amlogic / Rockchip / Allwinner)

`detect_target()` sets `TVBOX=true` for all SoC-family prefixes:

| Prefix | SoC family | Arch |
|---|---|---|
| `s905*`, `s912`, `s922`, `a311d` | Amlogic | `aarch64_generic` |
| `h5-*`, `h6-*`, `h616-*`, `h618-*` | Allwinner | `aarch64_generic` |
| `rk*` | Rockchip | `aarch64_generic` |

Because OpenWrt does not ship pre-built kernels for these SoCs, ImageBuilder is invoked with the `armsr/armv8` generic target (produces a portable `rootfs.tar.gz`). The rootfs is then handed to the **Packing Layer**.

---

## Structural Workflow

### 1. Configuration load

`imagebuilder.sh` sources `hermes.conf` at startup, then accepts CLI args `<source:version> <device> <variant>`. Environment variables override conf values at any point:

```bash
KERNEL_SOURCE=armarchindo DISK_SIZE=2G ./imagebuilder.sh openwrt:24.10.0 s905x3 full
```

### 2. ImageBuilder download (`download_ib`)

- Resolves the archive URL from `downloads.{source}.org`.
- Detects compression format: `.tar.xz` for releases before 24.10, `.tar.zst` from 24.10 onward.
- Downloads via `ariadl` (aria2c wrapper with 3-retry logic from `scripts/INCLUDE.sh`).
- Extracts and renames the directory to `imagebuilder/`.

### 3. ImageBuilder configuration (`configure_ib`)

- Patches `.config`: sets `CONFIG_TARGET_KERNEL_PARTSIZE=128` and `CONFIG_TARGET_ROOTFS_PARTSIZE` (1024 MB for `simple`/`minimal`, 2048 MB for `full`).
- For TV box targets, disables `CPIOGZ`, `EXT4FS`, `SQUASHFS`, and `IMAGES_GZIP` to produce only `rootfs.tar.gz`.
- Disables package signature verification in `repositories.conf`.
- Appends optional kiddin9 feed and multi-arch stubs so custom packages (e.g., `mihombreng`) install cleanly.
- Patches `Makefile` for force-overwrite flags (OPKG on 24.x, APK-compatible flags on 25.x).

### 4. Files & packages injection

```
inject_files()    → copies files/*  into imagebuilder/files/
inject_packages() → copies packages/* into imagebuilder/packages/
inject_mihombreng() → downloads prebuilt mihombreng .ipk/.apk into imagebuilder/packages/
```

`inject_files` mirrors the repository's `files/` directory verbatim into the ImageBuilder's `FILES=` argument path, so every file ends up at the correct rootfs path.

### 5. `make image` execution

```bash
make image PROFILE="..." PACKAGES="..." FILES="files" DISABLED_SERVICES="..."
```

- `PACKAGES` string is built by `build_package_list()`, which assembles base, tunnel, modem, storage, and variant-specific packages, then appends exclusions (`-dnsmasq`, `-procd-ujail`, etc.).
- Output artifacts are moved to `out_firmware/` (`.img.gz`) or `out_rootfs/` (`*rootfs.tar.gz`).

---

## ImageBuilder Packing Layer (TV Box)

`scripts/PACKER.sh` is sourced (not executed) by `imagebuilder.sh` and provides `pack_tvbox()`.

### Hibrid engine (default `PACKER=hibrid`)

Six sequential steps:

| Step | Action |
|---|---|
| 1 | `download_kernel()` — fetch kernel from selected source |
| 2 | `fallocate -l ${DISK_SIZE}` — allocate raw disk image |
| 3 | `parted` — MBR: FAT32 BOOT (4 MiB – 132 MiB) + ext4 ROOTFS (132 MiB – 100%) |
| 4 | `losetup -P` → `mkfs.fat` + `mkfs.ext4` → mount both partitions |
| 5 | Assemble: boot files, kernel boot/dtb, rootfs extraction, kernel modules, `rootfs/` overlay |
| 6 | Unmount, `losetup -d`, `gzip -9` → `out/tvbox/hermes-wrt-{device}.img.gz` |

A `trap cleanup EXIT` ensures loop devices are detached and staging directories removed on any failure.

### Kernel sources

| Source key | Repository | Notes |
|---|---|---|
| `ophub` *(default)* | `github.com/ophub/kernel` | Unified tarball per version; most complete |
| `armarchindo` | `github.com/armarchindo/kernel` | Separate boot/dtb/modules tarballs |
| `sib0ndt` | `github.com/sib0ndt/linux` | Custom Amlogic kernel (`kernel-amlogic-*`) |
| `custom` | `$KERNEL_URL` | Any release tarball URL |
| `local` | `$KERNEL_DIR` | Pre-downloaded local directory |

`KERNEL_VERSION=auto` resolves the latest stable tag from the selected source at build time.

---

## Kernel Modules Directory Fix

Different kernel archives use inconsistent internal layouts:

```
ophub / armarchindo  →  modules/<kver>/...   (top-level)
sib0ndt              →  lib/modules/<kver>/... (rootfs-like layout)
```

`PACKER.sh` handles both:

```bash
# lib/modules/ layout (sib0ndt)
if [[ -d "$stage/kernel/lib/modules" ]]; then
    sudo rm -rf "$stage/mnt_rootfs/lib/modules/"
    sudo cp -rf "$stage/kernel/lib/modules"/* "$stage/mnt_rootfs/lib/modules/"
# modules/ layout (ophub, armarchindo)
elif [[ -d "$stage/kernel/modules" ]]; then
    sudo rm -rf "$stage/mnt_rootfs/lib/modules/"
    sudo cp -rf "$stage/kernel/modules"/* "$stage/mnt_rootfs/lib/modules/"
fi
```

This prevents stale stock modules from the rootfs overriding the correct versioned modules from the selected kernel.

---

## First Boot Settings

`files/etc/uci-defaults/99-hermes-settings` runs **once** on first boot via OpenWrt's `uci-defaults` mechanism:

```sh
uci set system.@system[0].hostname='HermesWrt'
uci set system.@system[0].timezone='WIB-7'
uci set system.@system[0].zonename='Asia/Jakarta'
uci commit system

uci add_list dhcp.@dnsmasq[0].server='8.8.8.8'
uci add_list dhcp.@dnsmasq[0].server='8.8.4.4'
uci commit dhcp
```

The script exits `0` to signal successful execution; OpenWrt deletes it after the first boot, so it does not run again.

---

## Files Injection

### Build-time injection (`inject_files`)

The `files/` directory in the repository is a rootfs overlay. At build time, its entire tree is copied into `imagebuilder/files/` and passed to `make image FILES=files`. OpenWrt ImageBuilder merges this into the final image.

```
files/
├── etc/
│   ├── banner               # SSH/console login banner
│   └── uci-defaults/
│       └── 99-hermes-settings   # First-boot UCI configuration
```

Additional files can be placed following OpenWrt rootfs paths:

```
files/etc/config/          → default UCI configs
files/etc/rc.local         → startup hooks
files/usr/lib/lua/luci/    → LuCI theme/plugin overrides
files/root/                → root home scripts
```

### Post-pack overlay (`rootfs/`)

An optional `rootfs/` directory at the repository root is applied on top of the extracted rootfs **after** packing (step 5e of `pack_tvbox`). This allows injecting files that must survive the packing stage without being part of the ImageBuilder `FILES=` argument.

---

## Feature Toggles (hermes.conf)

| Variable | Default | Effect |
|---|---|---|
| `BUILD_VARIANT` | `full` | Package set: `full` / `simple` / `minimal` |
| `DISK_SIZE` | `1G` | TV box image size (min `512M`) |
| `KERNEL_SOURCE` | `ophub` | Kernel backend |
| `KERNEL_VERSION` | `auto` | Kernel version pin or `auto` |
| `PACKER` | `hibrid` | Packing engine |
| `ENABLE_KIDDIN9_FEED` | `false` | Add kiddin9 custom feed |
| `ENABLE_TUNNELS` | `true` | OpenClash / nikki / passwall packages |
| `ENABLE_MODEM` | `true` | USB modem / QMI / MBIM packages |
| `ENABLE_DOCKER` | `false` | Docker + dockerd |
| `ENABLE_PYTHON` | `false` | python3 + pip |
| `ENABLE_ADGUARD` | `false` | AdGuardHome |
| `ENABLE_EXTRAS` | `true` | btop, screen, pv, httping, adb |

---

## GitHub Actions Pipeline

`.github/workflows/build.yml` runs on `workflow_dispatch` with all parameters exposed as inputs. Key steps:

1. **Cleanup & Install Deps** — frees runner disk, installs `aria2`, `parted`, `dosfstools`, `jq`, `qemu-utils`, etc.
2. **Cache ImageBuilder packages** — caches `imagebuilder/dl/` keyed by source + version + device.
3. **Syntax Lint** — `bash -n` on all three shell scripts before any build work.
4. **Inject Config** — appends workflow inputs to `hermes.conf`.
5. **Build** — `sudo ./imagebuilder.sh <source:version> <device> <variant>`.
6. **Upload Artifacts** — firmware to `out/*`, retention 7 days.
7. **Upload Build Logs** — `build_*.log`, retention 3 days (uploaded even on failure).
