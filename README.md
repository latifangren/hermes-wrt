# Hermes-WRT

Custom OpenWrt/ImmortalWrt firmware builder wrapper untuk TV Box (Amlogic, Rockchip, Allwinner) dan Official Devices (x86-64, Raspberry Pi, generic armsr, dll) menggunakan GitHub Actions maupun mesin lokal.

---

## Fitur Utama

- **Dual-Path Build Engine**:
  - **Official Path**: Menghasilkan berkas `.img.gz` siap pakai dari official targets (x86-64, Raspberry Pi, dll) menggunakan official ImageBuilder.
  - **TV Box Path**: Membangun `rootfs.tar.gz` portable melalui ImageBuilder, diintegrasikan dengan kernel eksternal (Ophub/Armarchindo/Sib0ndt) menggunakan script `PACKER.sh` menjadi berkas disk image `.img.gz`.
- **First-Boot Customizer**: Konfigurasi otomatis hostname (`HermesWrt`), Zona Waktu (`Asia/Jakarta`), dan default Google DNS (`8.8.8.8`/`8.8.4.4`).
- **GHA Pipeline Optimasi**: Script syntax check instan, sistem caching untuk paket download, dan auto-canceling untuk run build yang menumpuk.
- **Kiddin9 Feed Toggle**: Gunakan feed pihak ketiga secara opsional. Jika dinonaktifkan, pembuatan sistem tetap aman dari kegagalan pencarian pustaka eksternal.

---

## Dokumentasi Terkait

Detil panduan lebih mendalam telah kami pisahkan untuk kerapian struktur kode:
- [**Panduan Instalasi & Flashing** (`docs/INSTALL.md`)](./docs/INSTALL.md) — Langkah instalasi untuk x86-64, Raspberry pi, serta panduan booting SD Card/USB dan eMMC TV Box.
- [**Detail Arsitektur Sistem** (`docs/ARCHITECTURE.md`)](./docs/ARCHITECTURE.md) — Alur dual-path, alur assembly partisi disk loop, struktur kernel modules, serta konfigurasi build.
- [**Peta Jalan Pengembangan** (`docs/ROADMAP.md`)](./docs/ROADMAP.md) — Rencana fitur baru, daftar target device ke depan, serta pembagian fitur-fitur build.

---

## Struktur Folder

```
hermes-wrt/
├── hermes.conf          # Konfigurasi kernel & fitur toggle
├── imagebuilder.sh      # Script parser/builder utama (dual-path)
├── make-image.sh        # Local build wrapper (sudo builder)
├── docs/                # Folder dokumentasi (Arsitektur, Panduan, Rencana)
├── scripts/
│   ├── INCLUDE.sh       # Library helper warna, download (aria2), & cek dep
│   └── PACKER.sh        # Script isolasi partisi & perakit image TV Box
├── files/               # Overlay files (banner, uci-defaults, custom config)
├── packages/            # Folder peletakan offline custom package (.ipk / .apk)
└── .github/workflows/   # Pipeline GitHub Actions (build.yml)
```

---

## Cara Penggunaan (Lokal)

Berjalan di OS berbasis Linux (Ubuntu Desktop/Server direkomendasikan):

```bash
# Build untuk OpenWrt 24.10 (x86-64, langsung jadi .img.gz)
sudo ./make-image.sh openwrt:24.10.0 x86-64 full

# Build untuk OpenWrt 24.10 (TV box S905X3)
sudo ./make-image.sh openwrt:24.10.0 s905x3 full

# Build untuk ImmortalWrt
sudo ./make-image.sh immortalwrt:24.10.0 s905x3 full

# Override konfigurasi via Environment Variable (misal: ganti sumber/versi kernel)
KERNEL_SOURCE=armarchindo KERNEL_VERSION=6.12.y sudo ./make-image.sh openwrt:24.10.0 s905x3 full
```

---

## Menu Konfigurasi (`hermes.conf`)

Gunakan berkas `hermes.conf` untuk mematikan atau menghidupkan fitur bawaan:

| Variabel | Bawaan | Pilihan Nilai |Deskripsi |
|---|---|---|---|
| `BUILD_VARIANT` | `full` | `full`, `simple`, `minimal` | Pembagian profil paket yang di-inject. |
| `DISK_SIZE` | `1G` | `512M`, `1G`, `2G`, `4G`, `8G` | Kapasitas total image TV Box. |
| `KERNEL_SOURCE` | `ophub` | `ophub`, `armarchindo`, `sib0ndt`, `custom`, `local` | Sumber kernel TV Box. |
| `KERNEL_VERSION` | `auto` | `auto`, versi kernel (misal: `6.12.95`) | Versi spesifik kernel eksternal. |
| `ENABLE_KIDDIN9_FEED`| `false`| `true` / `false` | Status feed pihak ketiga (kloning packages). |
| `ENABLE_TUNNELS` | `true` | `true` / `false` | Paket tunneling (OpenClash, Passwall, dll). |
| `ENABLE_MODEM` | `true` | `true` / `false` | Driver modem & ModemManager. |
| `ENABLE_DOCKER` | `false`| `true` / `false` | Engine Docker & Dockerman UI. |
| `ENABLE_ADGUARD` | `false`| `true` / `false` | AdGuardHome Core & LuCI interface. |

---

## Lisensi & Kredit

- **Hermes-WRT** dirilis di bawah lisensi MIT.
- Proyek ini berdiri di atas karya luar biasa para kontributor komunitas OpenWrt dan STB Indonesia. Terima kasih dan apresiasi sebesar-besarnya kepada:
  - **OpenWrt & ImmortalWrt** — Piringan basis sistem router.
  - **Ophub** ([github.com/ophub/amlogic-s9xxx-openwrt](https://github.com/ophub/amlogic-s9xxx-openwrt)) — Penemu dan pembangun integrasi kernel Amlogic TV Box.
  - **Armarchindo / DBAI** ([github.com/armarchindo/kernel](https://github.com/armarchindo/kernel)) — Penyedia kernel DBAI yang dioptimalkan untuk STB Indonesia.
  - **Sib0ndt** ([github.com/sib0ndt/linux](https://github.com/sib0ndt/linux)) — Custom kernel Amlogic TV Box.
  - **de-quenx / syntax-xidz (XIDZs-WRT)** ([github.com/de-quenx/XIDZs-WRT](https://github.com/de-quenx/XIDZs-WRT)) — Repack, ULO-Builder, and utility references.
  - **RizkiKotet-Dev & frizkyiman** — Pembangun repositori referensi CI/CD builder untuk komunitas Indonesia.
  - **Kiddin9** — Penyedia feed package mirror OpenWrt lengkap.
  - Serta seluruh pembuat package lokal (RakitanManager, Nokia Status, MacTodong, dll) yang biner kustomnya terintegrasi dalam proyek ini.
