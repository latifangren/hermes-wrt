# Hermes-WRT — Roadmap

## Current State (as of 2026-07)

Hermes-WRT is a functional dual-path ImageBuilder wrapper with:

- ✅ Dual build paths: official devices (x86-64, RPi) and TV boxes (Amlogic/Rockchip/Allwinner)
- ✅ Selectable kernel sources: ophub, armarchindo, sib0ndt, custom URL, local directory
- ✅ Kernel version auto-resolution from upstream release APIs
- ✅ Hibrid packing engine (fallocate + parted + losetup — no external binary needed)
- ✅ Kernel modules directory normalization (handles both `modules/` and `lib/modules/` layouts)
- ✅ First-boot uci-defaults (hostname, timezone, DNS)
- ✅ Files overlay injection (`files/` at build time, `rootfs/` post-pack)
- ✅ Mihombreng prebuilt package auto-injection with arch + format detection
- ✅ OpenWrt 24.x (OPKG) and 25.x (APK) compatibility
- ✅ GitHub Actions CI with caching, lint, build-log upload, and concurrency control
- ✅ Feature toggles: tunnels, modem, Docker, Python, AdGuard, extras, kiddin9 feed

---

## Short-Term (Next Release)

### Build system

- [ ] **`sib0ndt` kernel source fix** — current `boot-{ver}.tar.gz` + `rootfs-{ver}.tar.gz` layout extraction needs validation against actual sib0ndt release asset naming.
- [ ] **Rockchip boot files** — `boot/rockchip/` directory (equivalent to `boot/amlogic/`) with U-Boot and extlinux configs for RK3566/RK3588 targets.
- [ ] **Allwinner boot files** — `boot/allwinner/` with H5/H6/H616/H618 boot scripts.
- [ ] **Version auto-resolve for ImmortalWrt** — `SRC_VER=latest` currently only resolves against OpenWrt releases; needs a parallel resolver for `downloads.immortalwrt.org`.
- [ ] **`packages/` directory example** — add a placeholder `.gitkeep` and usage note so contributors know where to drop custom `.ipk`/`.apk` files.
- [ ] **`rootfs/` overlay document** — add usage note explaining the post-pack `rootfs/` overlay (currently undocumented in README).

### Package updates

- [ ] **Passwall2** — evaluate availability on openwrt.ai feed and add as tunnel option when `ENABLE_KIDDIN9_FEED=true`.
- [ ] **`luci-app-homeproxy`** — SingBox-based proxy app; add when stable on immortalwrt feed.
- [ ] **`kmod-wireguard`** — add to base when not already pulled by tunnels (currently implied by some tunnel packages).

---

## Medium-Term

### Architecture

- [ ] **Multi-device batch build** — support a device list so one workflow run produces firmware for multiple targets (x86-64 + s905x3 + s905x4 in one job matrix).
- [ ] **Variant profiles as YAML/JSON** — externalize package lists from `build_package_list()` into a declarative config file (e.g., `profiles/full.yml`) to make them editable without touching the shell script.
- [ ] **Reproducible builds** — pin ImageBuilder download by SHA256 checksum rather than version string alone.
- [ ] **APK feed support for custom packages** — build a minimal APK repository for mihombreng and other unofficial packages so they integrate cleanly with OpenWrt 25.x package management.

### Kernel management

- [ ] **Kernel version matrix** — expose `KERNEL_VERSION_6_6`, `KERNEL_VERSION_6_12` etc. to allow building two images (stable + LTS kernel) in a single run.
- [ ] **Kernel signature verification** — validate downloaded kernel tarballs against ophub/armarchindo release SHA256 sums before extraction.
- [ ] **Cached kernel downloads** — cache `out/kernels/` between builds (parallel to the existing `imagebuilder/dl/` cache) to avoid re-downloading the same kernel archive on every workflow run.

### TV box improvements

- [ ] **eMMC install script bundling** — include `openwrt-install-amlogic` (or an equivalent) in the rootfs via `files/usr/sbin/` so users can write to eMMC without extra downloads.
- [ ] **Partition size tuning per variant** — `minimal` images currently get the same 1024 MB rootfs as `simple`; reduce to 512 MB for minimal.
- [ ] **Verify DTB copy for each SoC family** — current packing copies the full `dtb/` tree; validate that the correct per-device DTB is selected or add a `DEV_DTB` variable.

### CI / Workflow

- [ ] **Release automation** — add a workflow triggered by version tags to create a GitHub Release and attach firmware artifacts.
- [ ] **Build matrix** — a separate `matrix.yml` workflow that builds a representative set of devices (x86-64, s905x3, bcm2711-rpi-4b) on every push to `main`.
- [ ] **Build time reporting** — post build duration and artifact size as a workflow summary (currently only logged inside the build log).

---

## Long-Term / Exploratory

### Platform expansion

- [ ] **MediaTek Filogic (MT7988)** — investigate ImageBuilder availability for Banana Pi BPi-R4 and similar; would follow the official-device path.
- [ ] **Raspberry Pi 5 (BCM2712)** — add `bcm2712-rpi-5` target when OpenWrt/ImmortalWrt ImageBuilder ships stable support.
- [ ] **MIPS targets** — validate package list against MIPS32/MIPS64 arches (TP-Link, TP-Link EX series).

### Feature additions

- [ ] **Integrated Prometheus/Grafana stack** — optional `ENABLE_MONITORING=true` toggle adding netdata or prometheus-node-exporter with a pre-configured dashboard.
- [ ] **WireGuard server auto-setup** — a uci-defaults script that generates a WireGuard keypair and basic server config on first boot when `ENABLE_WIREGUARD_SERVER=true`.
- [ ] **Tailscale auto-auth** — support `TAILSCALE_AUTH_KEY` env injection into a uci-defaults script for zero-touch tailscale enrollment.
- [ ] **Dynamic DNS** — add `luci-app-ddns` + a sane default config to `files/etc/config/ddns` supporting Cloudflare and DuckDNS.

### Build tooling

- [ ] **Container-based local build** — provide a `Dockerfile` / `docker-compose.yml` so the build environment is reproducible on any OS without manual dependency installation.
- [ ] **Web-based config generator** — a static HTML/JS page for generating `hermes.conf` from dropdowns (device, variant, toggles) without editing files manually.

---

## Version Notes

| OpenWrt version | Package format | Status |
|---|---|---|
| 23.05.x | OPKG | Legacy; builds work but limited support |
| 24.10.x | OPKG | **Current primary target** |
| 25.x | APK | Supported; some packages may differ — check release notes |
| ImmortalWrt 24.10.x | OPKG | Supported; enables additional apps (filebrowser, modem extras) |

---

## Contributing

Issues and pull requests welcome. When adding or removing packages:

1. Test against both `openwrt:24.10.0` and `immortalwrt:24.10.0` builds.
2. Wrap feed-specific packages in the appropriate `ENABLE_KIDDIN9_FEED` or `SRC_NAME == "immortalwrt"` guard in `build_package_list()`.
3. Run `bash -n imagebuilder.sh scripts/PACKER.sh scripts/INCLUDE.sh` before opening a PR.
