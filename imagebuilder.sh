#!/bin/bash
#====================================================================
# Hermes-WRT ImageBuilder
# Dual-path: official devices (RPi/x86) build direct .img.gz
#            TV boxes build rootfs → pack with selectable kernel
#
# Usage: ./imagebuilder.sh <source:version> <device> <variant>
# Example: ./imagebuilder.sh openwrt:24.10.0 s905x3 full
#          KERNEL_SOURCE=armarchindo ./imagebuilder.sh openwrt:24.10.0 s905x3 full
#          ./imagebuilder.sh immortalwrt:24.10.0 x86-64 simple
#====================================================================
set -euo pipefail

# ── Load config ──
HERMES_CONF="${PWD}/hermes.conf"
[[ -f "$HERMES_CONF" ]] && source "$HERMES_CONF"

# ── Paths ──
MAKE_PATH="${PWD}"
OPENWRT_DIR="imagebuilder"
IB_PATH="${MAKE_PATH}/${OPENWRT_DIR}"
FILES_PATH="${MAKE_PATH}/files"
PACKAGES_DIR="${MAKE_PATH}/packages"
SCRIPTS_PATH="${MAKE_PATH}/scripts"
CONF_PATH="${MAKE_PATH}/hermes.conf"
OUT_FIRMWARE="${MAKE_PATH}/out"
OUT_ROOTFS="${OUT_FIRMWARE}/rootfs"
OUT_TVBOX="${OUT_FIRMWARE}/tvbox"
LOG_FILE="${MAKE_PATH}/build_$(date +%Y%m%d_%H%M%S).log"

# ── Args ──
OP_SOURCE="${1:-openwrt:24.10.0}"
OP_DEVICE="${2:-s905x3}"
OP_VARIANT="${3:-$BUILD_VARIANT}"

SRC_NAME="${OP_SOURCE%:*}"
SRC_VER="${OP_SOURCE#*:}"
SRC_BRANCH="${SRC_VER%.*}"
SRC_MAJOR="${SRC_BRANCH%%.*}"
SRC_MINOR="${SRC_BRANCH#*.}"

# ── Colors ──
PURPLE='\033[95m'; BLUE='\033[94m'; GREEN='\033[92m'
YELLOW='\033[93m'; RED='\033[91m'; RESET='\033[0m'
STEPS="${PURPLE}[STEPS]${RESET}"; INFO="${BLUE}[INFO]${RESET}"
SUCCESS="${GREEN}[SUCCESS]${RESET}"; WARN="${YELLOW}[WARN]${RESET}"
ERROR="${RED}[ERROR]${RESET}"

log()   { echo -e "${INFO} $1"; }
step()  { echo -e "\n${STEPS} $1"; }
ok()    { echo -e "${SUCCESS} $1"; }
warn()  { echo -e "${WARN} $1"; }
fail()  { echo -e "${ERROR} $1" >&2; exit 1; }

# ── Download with aria2 + retry ──
ariadl() {
    [[ $# -lt 1 ]] && fail "Usage: ariadl <url> [output]"
    local url="$1" output="${2:-$(basename "$url")}"
    local retry=0
    while [[ $retry -lt 3 ]]; do
        aria2c -q -d "$(dirname "$output")" -o "$(basename "$output")" "$url" 2>/dev/null && {
            ok "Downloaded: $(basename "$output")"; return 0
        }
        retry=$((retry+1)); [[ $retry -lt 3 ]] && sleep 2
    done
    fail "Failed to download: $url"
}

# ── Detect device target & architecture ──
detect_target() {
    local dev="$1"

    # TV Box: Amlogic
    if [[ "$dev" =~ ^s905|^s912|^s922|^a311d ]]; then
        DEV_FAMILY="amlogic";      TVBOX=true
        TARGET_PROFILE="generic";  TARGET_SYS="armsr/armv8"
        TARGET_NAME="armsr-armv8"; ARCH_3="aarch64_generic"

    # TV Box: Allwinner
    elif [[ "$dev" =~ ^h5-|^h6-|^h616-|^h618-|^h7- ]]; then
        DEV_FAMILY="allwinner";    TVBOX=true
        TARGET_PROFILE="generic";  TARGET_SYS="armsr/armv8"
        TARGET_NAME="armsr-armv8"; ARCH_3="aarch64_generic"

    # TV Box: Rockchip
    elif [[ "$dev" =~ ^rk ]]; then
        DEV_FAMILY="rockchip";     TVBOX=true
        TARGET_PROFILE="generic";  TARGET_SYS="armsr/armv8"
        TARGET_NAME="armsr-armv8"; ARCH_3="aarch64_generic"

    # Official: Raspberry Pi 3
    elif [[ "$dev" =~ ^bcm2710- ]]; then
        DEV_FAMILY="bcm2710";      TVBOX=false
        TARGET_PROFILE="rpi-3";    TARGET_SYS="bcm27xx/bcm2710"
        TARGET_NAME="bcm27xx-bcm2710"; ARCH_3="aarch64_cortex-a53"

    # Official: Raspberry Pi 4
    elif [[ "$dev" =~ ^bcm2711- ]]; then
        DEV_FAMILY="bcm2711";      TVBOX=false
        TARGET_PROFILE="rpi-4";    TARGET_SYS="bcm27xx/bcm2711"
        TARGET_NAME="bcm27xx-bcm2711"; ARCH_3="aarch64_cortex-a72"

    # Official: x86-64
    elif [[ "$dev" == x86-64 || "$dev" == x86_64 ]]; then
        DEV_FAMILY="x86-64";       TVBOX=false
        TARGET_PROFILE="generic";  TARGET_SYS="x86/64"
        TARGET_NAME="x86-64";      ARCH_3="x86_64"

    # Official: Router/embedded (tentang)
    elif [[ "$dev" =~ ^samsung|^qemu|^virt|^generic- ]]; then
        DEV_FAMILY="armsr";        TVBOX=false
        TARGET_PROFILE="generic";  TARGET_SYS="armsr/armv8"
        TARGET_NAME="armsr-armv8"; ARCH_3="aarch64_generic"

    else
        fail "Unknown device: $dev\nSupports: s905*, s912, s922, a311d, h5-*, h6-*, h616-*, h618-*, rk*, bcm2710-*, bcm2711-*, x86-64, generic-*"
    fi

    # Set arch family
    case "$ARCH_3" in
        aarch64*)  ARCH_1="arm64";  ARCH_2="aarch64" ;;
        x86_64)    ARCH_1="amd64";  ARCH_2="x86_64"  ;;
    esac
}

# ── Download ImageBuilder ──
download_ib() {
    step "Downloading ${SRC_NAME} ImageBuilder ${SRC_VER} for ${TARGET_NAME}"

    # Archive format: tar.xz before 24.10, tar.zst from 24.10 onward
    local ext="tar.xz"
    if [[ "$SRC_MAJOR" -gt 24 ]] || [[ "$SRC_MAJOR" -eq 24 && "$SRC_MINOR" -ge 10 ]]; then
        ext="tar.zst"
    fi
    local url="https://downloads.${SRC_NAME}.org/releases/${SRC_VER}/targets/${TARGET_SYS}/${SRC_NAME}-imagebuilder-${SRC_VER}-${TARGET_NAME}.Linux-x86_64.${ext}"

    mkdir -p "$MAKE_PATH"
    cd "$MAKE_PATH"
    ariadl "$url"

    step "Extracting ImageBuilder..."
    case "$ext" in
        tar.xz)  tar -xJf *-imagebuilder-* >/dev/null 2>&1 ;;
        tar.zst) tar -xvf *-imagebuilder-* >/dev/null 2>&1 ;;
    esac
    rm -f *-imagebuilder-*.${ext}
    rm -rf "$OPENWRT_DIR"
    mv -f *-imagebuilder-* "$OPENWRT_DIR" || fail "Failed to extract ImageBuilder"
    ok "ImageBuilder ready at $OPENWRT_DIR"
}

# ── Configure ImageBuilder ──
configure_ib() {
    step "Configuring ImageBuilder"
    cd "$IB_PATH"

    local rootsize=1024
    [[ "$OP_VARIANT" == "full" ]] && rootsize=2048

    [[ -f ".config" ]] || fail ".config not found!"

    sed -i "s/CONFIG_TARGET_KERNEL_PARTSIZE=.*/CONFIG_TARGET_KERNEL_PARTSIZE=128/" ".config"
    sed -i "s/CONFIG_TARGET_ROOTFS_PARTSIZE=.*/CONFIG_TARGET_ROOTFS_PARTSIZE=$rootsize/" ".config"

    # TV box: disable unneeded image formats
    if [[ "$TVBOX" == true ]]; then
        sed -i "s/CONFIG_TARGET_ROOTFS_CPIOGZ=.*/# CONFIG_TARGET_ROOTFS_CPIOGZ is not set/" ".config" 2>/dev/null || true
        sed -i "s/CONFIG_TARGET_ROOTFS_EXT4FS=.*/# CONFIG_TARGET_ROOTFS_EXT4FS is not set/" ".config" 2>/dev/null || true
        sed -i "s/CONFIG_TARGET_ROOTFS_SQUASHFS=.*/# CONFIG_TARGET_ROOTFS_SQUASHFS is not set/" ".config" 2>/dev/null || true
        sed -i "s/CONFIG_TARGET_IMAGES_GZIP=.*/# CONFIG_TARGET_IMAGES_GZIP is not set/" ".config" 2>/dev/null || true
    fi

    # Disable signature checks
    sed -i '/option check_signature/s/^/#/' repositories.conf 2>/dev/null || true
    # Force overwrite on package install (OPKG)
    sed -i 's/install $(BUILD_PACKAGES)/install $(BUILD_PACKAGES) --force-overwrite --force-downgrade/' Makefile 2>/dev/null || true

    # 25.x uses APK — different force flag
    if [[ "$SRC_MAJOR" -ge 25 ]]; then
        sed -i 's/install $(BUILD_PACKAGES)/install $(BUILD_PACKAGES) --allow-downgrades/' Makefile 2>/dev/null || true
        log "OpenWrt 25.x detected: using APK-compatible flags"
    fi

    ok "ImageBuilder configured (rootfs: ${rootsize}M)"
}

# ── Inject custom files ──
inject_files() {
    step "Injecting custom files"
    cd "$IB_PATH"
    mkdir -p "files"
    if [[ -d "$FILES_PATH" ]]; then
        cp -rf "$FILES_PATH/." "files/" 2>/dev/null
        ok "Custom files injected from files/"
    fi
}

# ── Inject custom packages ──
inject_packages() {
    step "Adding custom packages"
    cd "$IB_PATH"
    mkdir -p "packages"
    if [[ -d "$PACKAGES_DIR" ]]; then
        cp -rf "$PACKAGES_DIR/." "packages/" 2>/dev/null
        ok "Custom packages copied"
    fi
}

# ── Build package list ──
build_package_list() {
    local BASE="" TUNNEL="" EXCLUDED="" DISABLED=""

    # — Base system —
    BASE+=" -dnsmasq dnsmasq-full"
    BASE+=" luci luci-ssl luci-compat luci-base luci-mod-admin-full luci-mod-network"
    BASE+=" luci-mod-status luci-mod-system luci-proto-ipv6 luci-proto-ppp"
    BASE+=" luci-app-firewall luci-app-opkg luci-app-ttyd luci-app-poweroffdevice"
    BASE+=" luci-app-log-viewer luci-app-ramfree luci-app-package-manager"
    BASE+=" libiwinfo libiwinfo-data cgi-io"
    BASE+=" ttyd htop bash curl wget-ssl tar unzip unrar gzip jq nano"
    BASE+=" openssh-sftp-server ca-bundle ca-certificates"
    BASE+=" coreutils coreutils-base64 coreutils-nohup coreutils-stat coreutils-sleep"
    BASE+=" ip-full iptables iptables-legacy iptables-mod-iprange iptables-mod-tproxy"
    BASE+=" kmod-ipt-nat kmod-tun resolveip zoneinfo-asia zoneinfo-core"
    BASE+=" zram-swap block-mount parted losetup resize2fs"
    BASE+=" rpcd rpcd-mod-file rpcd-mod-iwinfo rpcd-mod-luci rpcd-mod-rrdns"
    BASE+=" uhttpd uhttpd-mod-ubus px5g-mbedtls"
    [[ "${ENABLE_EXTRAS:-true}" == "true" ]] && \
        BASE+=" btop fastfetch screen pv httping adb"
    BASE+=" luci-app-filebrowser"

    # — Modem support —
    if [[ "${ENABLE_MODEM:-true}" == "true" ]]; then
        BASE+=" kmod-usb-net-rtl8150 kmod-usb-net-rtl8152 kmod-usb-net-asix kmod-usb-net-asix-ax88179"
        BASE+=" kmod-usb-net kmod-usb-wdm kmod-usb-net-qmi-wwan uqmi luci-proto-qmi"
        BASE+=" kmod-usb-serial-option kmod-usb-serial kmod-usb-serial-wwan qmi-utils"
        BASE+=" kmod-usb-acm kmod-usb-net-cdc-ncm kmod-usb-net-cdc-mbim umbim usbutils"
        BASE+=" kmod-usb-net-huawei-cdc-ncm kmod-usb-net-cdc-ether kmod-usb-net-rndis"
        BASE+=" kmod-usb-ohci kmod-usb2 kmod-usb-ehci usb-modeswitch"
        BASE+=" modemmanager modemmanager-rpcd luci-proto-modemmanager libmbim libqmi"
        BASE+=" sms-tool luci-app-sms-tool-js picocom minicom"
        BASE+=" luci-proto-ncm luci-proto-xmm luci-proto-atc"
        BASE+=" luci-app-3ginfo-lite luci-app-modemband luci-app-modeminfo luci-app-mmconfig"
        BASE+=" luci-app-droidnet luci-app-netmonitor luci-app-lite-watchdog"
        BASE+=" modeminfo modeminfo-serial-dell modeminfo-serial-fibocom"
        BASE+=" modeminfo-serial-sierra modeminfo-serial-tw modeminfo-serial-xmm"
        BASE+=" xmm-modem modemband"
    fi

    # — Storage —
    BASE+=" luci-app-diskman luci-app-disks-info smartmontools"
    BASE+=" kmod-usb-storage kmod-usb-storage-uas ntfs-3g exfat-mkfs exfat-fsck dosfstools"

    # — Network extras —
    BASE+=" luci-app-zerotier tailscale luci-app-tailscale luci-app-cloudflared"
    BASE+=" internet-detector luci-app-internet-detector internet-detector-mod-modem-restart"
    BASE+=" nlbwmon luci-app-nlbwmon vnstat2 vnstati2 luci-app-vnstat2 netdata"
    BASE+=" luci-app-netspeedtest luci-app-cpu-status-mini luci-app-temp-status"
    BASE+=" luci-app-eqosplus luci-app-ipinfo"

    # — Theme defaults —
    BASE+=" luci-theme-bootstrap luci-theme-material"
    BASE+=" luci-theme-argon luci-app-argon-config"
    BASE+=" luci-theme-alpha luci-theme-material3"

    # — Tunnels —
    if [[ "${ENABLE_TUNNELS:-true}" == "true" ]]; then
        TUNNEL+=" coreutils-nohup bash dnsmasq-full curl ca-certificates ipset ip-full"
        TUNNEL+=" libcap libcap-bin ruby ruby-yaml kmod-tun kmod-inet-diag unzip kmod-nft-tproxy"
        TUNNEL+=" luci-compat luci luci-base luci-app-openclash"
        TUNNEL+=" nikki luci-app-nikki"
        TUNNEL+=" chinadns-ng resolveip dns2socks dns2tcp ipt2socks microsocks tcping"
        TUNNEL+=" xray-core xray-plugin luci-app-passwall"
        BASE+=" $TUNNEL"
    fi

    # — Variant: full add-ons —
    if [[ "$OP_VARIANT" == "full" ]]; then
        [[ "${ENABLE_PYTHON:-false}" == "true" ]] && BASE+=" python3 python3-pip"
        [[ "${ENABLE_DOCKER:-false}" == "true" ]] && \
            BASE+=" docker docker-compose dockerd luci-app-dockerman"
        [[ "${ENABLE_ADGUARD:-false}" == "true" ]] && \
            BASE+=" adguardhome luci-app-adguardhome"
        BASE+=" librespeed-go iperf3-ssl ookla-speedtest"
    fi

    # — Source-specific excludes —
    if [[ "$SRC_NAME" == "openwrt" ]]; then
        EXCLUDED+=" -dnsmasq"
    elif [[ "$SRC_NAME" == "immortalwrt" ]]; then
        EXCLUDED+=" -dnsmasq -automount -libustream-openssl -default-settings-chn -luci-i18n-base-zh-cn"
        [[ "$ARCH_2" == "x86_64" ]] && EXCLUDED+=" -kmod-usb-net-rtl8152-vendor"
    fi

    # — TV box specifics —
    if [[ "$TVBOX" == true ]]; then
        BASE+=" luci-app-amlogic ath9k-htc-firmware btrfs-progs"
        BASE+=" hostapd hostapd-utils kmod-ath kmod-ath9k kmod-ath9k-common kmod-ath9k-htc"
        BASE+=" kmod-cfg80211 kmod-crypto-acompress kmod-crypto-crc32c kmod-crypto-hash kmod-fs-btrfs"
        BASE+=" kmod-mac80211 wireless-tools wpa-cli wpa-supplicant"
        EXCLUDED+=" -procd-ujail"
    fi

    echo "${BASE}|${EXCLUDED}|${DISABLED}"
}

# ── Run make image ──
run_make() {
    cd "$IB_PATH"

    local pkg_data=$(build_package_list)
    local PACKAGES="${pkg_data%%|*}"
    local rest="${pkg_data#*|}"
    local EXCLUDED="${rest%%|*}"
    local DISABLED="${rest#*|}"

    inject_files
    inject_packages

    step "Running make image..."
    mkdir -p "out_firmware" "out_rootfs"

    make image PROFILE="${TARGET_PROFILE}" \
        PACKAGES="${PACKAGES} ${EXCLUDED}" \
        FILES="files" \
        DISABLED_SERVICES="${DISABLED}" 2>&1 | tee -a "$LOG_FILE"

    if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
        fail "Build failed. Check $LOG_FILE"
    fi

    ok "make image succeeded"

    # Collect artifacts
    find "${IB_PATH}/bin/targets" -name "*.img.gz" -exec mv {} "out_firmware/" \; 2>/dev/null || true
    find "${IB_PATH}/bin/targets" -name "*rootfs.tar.gz" -exec mv {} "out_rootfs/" \; 2>/dev/null || true
}

# ── PATH A: Official device (direct output) ──
build_official() {
    log "PATH: Official device — building .img.gz directly"
    run_make

    mkdir -p "$OUT_FIRMWARE"
    cp -rf "${IB_PATH}/out_firmware"/* "$OUT_FIRMWARE/" 2>/dev/null || true
    ok "Firmware ready: $OUT_FIRMWARE/"
}

# ── PATH B: TV Box (rootfs → pack with kernel) ──
build_tvbox() {
    log "PATH: TV box — building rootfs.tar.gz, then packing with kernel"
    run_make

    # Source the packer
    local packer="${SCRIPTS_PATH}/PACKER.sh"
    if [[ -f "$packer" ]]; then
        source "$packer"
        pack_tvbox
    else
        warn "PACKER.sh not found. rootfs.tar.gz is in ${IB_PATH}/out_rootfs/"
        warn "Use it with remake/ULO manually."
    fi
}

# ═══════════════════════════════════════════════════════
# MAIN
# ═══════════════════════════════════════════════════════
main() {
    echo "╔══════════════════════════════════════════╗"
    echo "║        Hermes-WRT ImageBuilder           ║"
    echo "╠══════════════════════════════════════════╣"
    echo "║ Source: ${SRC_NAME}:${SRC_VER}"
    echo "║ Device: ${OP_DEVICE}"
    echo "║ Variant: ${OP_VARIANT}"
    echo "║ Kernel: ${KERNEL_SOURCE} (${KERNEL_VERSION})"
    echo "╚══════════════════════════════════════════╝"

    # Version compatibility note
    if [[ "$SRC_MAJOR" -ge 25 ]]; then
        echo "  ℹ️  OpenWrt 25.x uses APK packages — some packages may differ from 24.x"
    elif [[ "$SRC_MAJOR" -lt 24 ]]; then
        echo "  ⚠️  Older releases may have limited package availability"
    fi

    detect_target "$OP_DEVICE"

    if [[ "$TVBOX" == true ]]; then
        echo "  → TV Box family: ${DEV_FAMILY}"
    else
        echo "  → Official device: ${DEV_FAMILY}"
    fi

    download_ib
    configure_ib

    local start=$(date +%s)

    if [[ "$TVBOX" == true ]]; then
        build_tvbox
    else
        build_official
    fi

    local elapsed=$(($(date +%s) - start))
    echo -e "\n${GREEN}✓ Build complete in ${elapsed}s${RESET}"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main
fi
