# Hermes-WRT

Custom OpenWrt/ImmortalWrt builder for TV boxes (Amlogic/Rockchip/Allwinner) and official devices (x86-64, Raspberry Pi, etc.).

## Konsep

```
Source (OpenWrt / ImmortalWrt)
  └── Official ImageBuilder
        ├── + custom files/      (theme, config, script)
        ├── + custom packages/   (ipk tambahan)
        ├── + kernel ophub      (khusus TV box)
        └── Output: .img.gz siap pakai
```

**Bedanya dengan ophub:** Hermes-WRT **build dari source** via ImageBuilder, bukan packaging ulang rootfs. Lo kontrol penuh package bawaan.

## Struktur

```
hermes-wrt/
├── files/              # Custom files — niru struktur rootfs OpenWrt
│   └── etc/            #   etc/config/* → config bawaan
│       └── config/     #   usr/lib/lua/luci/themes/ → tema custom
├── packages/           # Taruh custom .ipk di sini
├── scripts/            # Helper modules
├── imagebuilder.sh     # Main build script
├── make-image.sh       # Local build wrapper
└── .github/workflows/  # GitHub Actions pipeline
```

## Cara Pakai

### Lokal
```bash
sudo ./make-image.sh openwrt:24.10.0 s905x3
```

### GitHub Actions
Fork repo → klik Actions → pilih workflow → pilih device + source + tunnel → run.

## Device Support

| Kategori | Device |
|----------|--------|
| **Amlogic** | s905x, s905x2, s905x3, s905x4, s912, s905d, s905l3a, dll |
| **Rockchip** | RK3566 (Orange Pi 3B), RK3588(S) (Orange Pi 5/5 Plus) |
| **Allwinner** | H5, H6, H616, H618 (Orange Pi series) |
| **Raspberry Pi** | Pi 3B/3B+, Pi 4B/400, Pi Zero 2/W |
| **x86-64** | Generic PC/UEFI |

## Custom Files

Taruh file di `files/` dengan struktur rootfs. Contoh:
```
files/
├── etc/
│   ├── config/             # config bawaan
│   ├── banner              # login banner
│   ├── rc.local            # startup script
│   └── uci-defaults/       # one-time setup
├── usr/lib/lua/luci/themes/hermes/  # tema custom
└── root/install-custom.sh
```
