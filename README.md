# Hermes-WRT

Custom OpenWrt/ImmortalWrt builder untuk TV box (Amlogic/Rockchip/Allwinner) dan device official (x86-64, Raspberry Pi, etc).

## Arsitektur Dual-Path

```
Hermes-WRT
  │
  ├── Device official (x86-64, RPi, generic armsr)
  │     └── ImageBuilder → .img.gz langsung jadi
  │
  └── TV Box (Amlogic, Rockchip, Allwinner, ...)
        ├── ImageBuilder → rootfs.tar.gz
        └── Packing Layer → .img.gz
              ├── Kernel: ophub (default)
              ├── Kernel: armarchindo
              ├── Kernel: custom URL
              └── Kernel: local directory
```

**Official device:** kernel dari OpenWrt/ImmortalWrt resmi, langsung jadi.
**TV box:** rootfs dari ImageBuilder × kernel dari sumber yang bisa dipilih → di-pack jadi image.

## Struktur

```
hermes-wrt/
├── hermes.conf          # Konfigurasi kernel & fitur
├── imagebuilder.sh      # Main build script (dual-path)
├── make-image.sh        # Local build wrapper
├── scripts/
│   ├── INCLUDE.sh       # Shared functions
│   └── PACKER.sh        # Kernel download & TV box packing
├── files/               # Custom files (siap diisi)
├── packages/            # Custom .ipk
└── .github/workflows/   # GitHub Actions pipeline
```

## Cara Pakai

### Lokal
```bash
# Build untuk OpenWrt 24.10 (x86-64, langsung jadi .img.gz)
sudo ./make-image.sh openwrt:24.10.0 x86-64 full

# Build untuk OpenWrt 25.12 (TV box)
sudo ./make-image.sh openwrt:25.12.5 s905x3 full

# Build untuk ImmortalWrt
sudo ./make-image.sh immortalwrt:24.10.0 s905x3 full

# Ganti kernel source
KERNEL_SOURCE=armarchindo sudo ./make-image.sh openwrt:24.10.0 s905x3 full

# Ganti kernel version
KERNEL_VERSION=6.12.y sudo ./make-image.sh openwrt:24.10.0 s905x3 full
```

### Catatan Versi
- **OpenWrt 24.x** — pakai OPKG, mature, semua package tersedia
- **OpenWrt 25.x** — pakai APK, beberapa package mungkin belum ada atau beda nama (cek release notes)
- **ImmortalWrt** — masih di 24.10 (belum 25.x)
- Beberapa device TV box mungkin belum support kernel 25.x — pakai kernel ophub/armarchindo

### GitHub Actions
Fork repo → klik Actions → pilih workflow → atur device, source, kernel → run.

## Kernel Configuration

Edit `hermes.conf` atau set environment variable:

| Variable | Default | Options |
|----------|---------|---------|
| `KERNEL_SOURCE` | `ophub` | `ophub`, `armarchindo`, `custom`, `local` |
| `KERNEL_VERSION` | `auto` | `auto`, `6.12.y`, `6.6.y`, dll |
| `KERNEL_URL` | — | Required saat `KERNEL_SOURCE=custom` |
| `KERNEL_DIR` | — | Path lokal saat `KERNEL_SOURCE=local` |
| `PACKER` | `remake` | `remake`, `ulo`, `custom` |
| `ENABLE_MODEM` | `true` | `true`/`false` |
| `ENABLE_TUNNELS` | `true` | `true`/`false` |
| `ENABLE_DOCKER` | `false` | `true`/`false` |

## Device Support

| Kategori | Device |
|----------|--------|
| **Amlogic** | s905x, s905x2, s905x3, s905x4, s905d, s905l3a, s912, s922x, a311d |
| **Rockchip** | RK3566, RK3588, RK3588S (Orange Pi 3B/5/5+) |
| **Allwinner** | H5, H6, H616, H618 (Orange Pi series) |
| **Raspberry Pi** | Pi 3B/3B+, Pi 4B/400, Pi Zero 2/W |
| **x86-64** | Generic PC/UEFI |

## Custom Files

Taruh file di `files/` dengan struktur rootfs OpenWrt. Contoh:
```
files/
├── etc/config/              # default config
├── etc/banner               # login banner
├── etc/rc.local             # startup script
├── etc/uci-defaults/        # one-time setup (run once at first boot)
├── usr/lib/lua/luci/themes/ # custom luci themes
└── root/install.sh
```
