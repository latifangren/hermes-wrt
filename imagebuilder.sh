#!/bin/bash
#====================================================================
# Hermes-WRT ImageBuilder
# Build custom OpenWrt/ImmortalWrt firmware for TV boxes + official devices
# 
# Usage: ./imagebuilder.sh <source:version> <device> <variant>
# Example: ./imagebuilder.sh openwrt:24.10.0 s905x3 full
#          ./imagebuilder.sh immortalwrt:24.10.0 x86-64 simple
#====================================================================
set -euo pipefail

# === CONFIG ===
MAKE_PATH="${PWD}"
OPENWRT_DIR="imagebuilder"
IB_PATH="${MAKE_PATH}/${OPENWRT_DIR}"
FILES_PATH="${MAKE_PATH}/files"
PACKAGES_DIR="${MAKE_PATH}/packages"
OUT_FIRMWARE="${IB_PATH}/out_firmware"
OUT_ROOTFS="${IB_PATH}/out_rootfs"
LOG_FILE="build_$(date +%Y%m%d_%H%M%S).log"

# === ARGS ===
OP_SOURCE="${1:-openwrt:24.10.0}"       # openwrt/immortalwrt:version
OP_DEVICE="${2:-s905x3}"                 # device codename
OP_VARIANT="${3:-full}"                  # full / simple

# Parse source
SRC_NAME="${OP_SOURCE%:*}"
SRC_VER="${OP_SOURCE#*:}"
SRC_BRANCH="${SRC_VER%.*}"               # e.g. "24.10" from "24.10.0"

# === COLORS ===
PURPLE='\033[95m'; BLUE='\033[94m'
GREEN='\033[92m'; YELLOW='\033[93m'; RED='\033[91m'
RESET='\033[0m'
STEPS="${PURPLE}[STEPS]${RESET}"
INFO="${BLUE}[INFO]${RESET}"
SUCCESS="${GREEN}[SUCCESS]${RESET}"
WARN="${YELLOW}[WARN]${RESET}"
ERROR="${RED}[ERROR]${RESET}"

log()  { echo -e "${INFO} $1"; }
step() { echo -e "\n${STEPS} $1"; }
ok()   { echo -e "${SUCCESS} $1"; }
fail() { echo -e "${ERROR} $1" >&2; exit 1; }

# === HELPER: download with aria2 ===
ariadl() {
    [[ $# -lt 1 ]] && fail "Usage: ariadl <url> [output]"
    local url="$1" output="${2:-$(basename "$url")}"
    local retry=0 max_retry=3
    while [[ $retry -lt $max_retry ]]; do
        aria2c -q -d "$(dirname "$output")" -o "$(basename "$output")" "$url" 2>/dev/null && {
            ok "Downloaded: $(basename "$output")"; return 0
        }
        retry=$((retry+1)); [[ $retry -lt $max_retry ]] && sleep 2
    done
    fail "Failed to download: $url"
}

# === DETECT DEVICE TARGET ===
detect_target() {
    local dev="$1"
    case "$dev" in
        s905*|s912)
            echo "amlogic"; TARGET_PROFILE="generic"
            TARGET_SYS="armsr/armv8"; TARGET_NAME="armsr-armv8"
            ARCH_1="arm64"; ARCH_2="aarch64"; ARCH_3="aarch64_generic"
            TVBOX=true ;;
        h5-*|h6-*|h616-*|h618-*)
            echo "allwinner"; TARGET_PROFILE="generic"
            TARGET_SYS="armsr/armv8"; TARGET_NAME="armsr-armv8"
            ARCH_1="arm64"; ARCH_2="aarch64"; ARCH_3="aarch64_generic"
            TVBOX=true ;;
        rk*)
            echo "rockchip"; TARGET_PROFILE="generic"
            TARGET_SYS="armsr/armv8"; TARGET_NAME="armsr-armv8"
            ARCH_1="arm64"; ARCH_2="aarch64"; ARCH_3="aarch64_generic"
            TVBOX=true ;;
        bcm2710-*)
            echo "bcm2710"; TARGET_PROFILE="rpi-3"
            TARGET_SYS="bcm27xx/bcm2710"; TARGET_NAME="bcm27xx-bcm2710"
            ARCH_1="arm64"; ARCH_2="aarch64"; ARCH_3="aarch64_cortex-a53"
            TVBOX=false ;;
        bcm2711-*)
            echo "bcm2711"; TARGET_PROFILE="rpi-4"
            TARGET_SYS="bcm27xx/bcm2711"; TARGET_NAME="bcm27xx-bcm2711"
            ARCH_1="arm64"; ARCH_2="aarch64"; ARCH_3="aarch64_cortex-a72"
            TVBOX=false ;;
        x86-64|x86_64)
            echo "x86-64"; TARGET_PROFILE="generic"
            TARGET_SYS="x86/64"; TARGET_NAME="x86-64"
            ARCH_1="amd64"; ARCH_2="x86_64"; ARCH_3="x86_64"
            TVBOX=false ;;
        *) fail "Unknown device: $dev. Supported: s905*, s912, h5-*, h6-*, h616-*, h618-*, rk*, bcm2710-*, bcm2711-*, x86-64" ;;
    esac
}

# === DOWNLOAD IMAGEBUILDER ===
download_ib() {
    step "Downloading ${SRC_NAME} ImageBuilder ${SRC_VER}"
    local ext="tar.xz"
    [[ "${SRC_BRANCH}" == "24.10" ]] && ext="tar.zst"
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
    mv -f *-imagebuilder-* "$OPENWRT_DIR" || fail "Failed to extract ImageBuilder"
    ok "ImageBuilder ready at $OPENWRT_DIR"
}

# === CONFIGURE IMAGEBUILDER ===
configure_ib() {
    step "Configuring ImageBuilder for ${OP_DEVICE}"
    cd "$IB_PATH"
    
    # Partition sizes
    local rootsize=1024
    [[ "$OP_VARIANT" == "full" ]] && rootsize=2048
    
    [[ -f ".config" ]] || fail ".config not found!"
    sed -i "s/CONFIG_TARGET_KERNEL_PARTSIZE=.*/CONFIG_TARGET_KERNEL_PARTSIZE=128/" ".config"
    sed -i "s/CONFIG_TARGET_ROOTFS_PARTSIZE=.*/CONFIG_TARGET_ROOTFS_PARTSIZE=$rootsize/" ".config"
    
    # TV box specific: disable image formats not needed
    if [[ "$TVBOX" == true ]]; then
        sed -i "s/CONFIG_TARGET_ROOTFS_CPIOGZ=.*/# CONFIG_TARGET_ROOTFS_CPIOGZ is not set/" ".config" 2>/dev/null || true
        sed -i "s/CONFIG_TARGET_ROOTFS_EXT4FS=.*/# CONFIG_TARGET_ROOTFS_EXT4FS is not set/" ".config" 2>/dev/null || true
        sed -i "s/CONFIG_TARGET_ROOTFS_SQUASHFS=.*/# CONFIG_TARGET_ROOTFS_SQUASHFS is not set/" ".config" 2>/dev/null || true
        sed -i "s/CONFIG_TARGET_IMAGES_GZIP=.*/# CONFIG_TARGET_IMAGES_GZIP is not set/" ".config" 2>/dev/null || true
    fi
    
    # Disable signature checks
    sed -i '/option check_signature/s/^/#/' repositories.conf 2>/dev/null || true
    
    # Force overwrite on package install
    sed -i 's/install $(BUILD_PACKAGES)/install $(BUILD_PACKAGES) --force-overwrite --force-downgrade/' Makefile 2>/dev/null || true
    
    ok "Configuration done"
}

# === ADD CUSTOM FILES ===
inject_files() {
    step "Injecting custom files"
    cd "$IB_PATH"
    mkdir -p "files"
    
    if [[ -d "$FILES_PATH" ]]; then
        cp -rf "$FILES_PATH/." "files/" 2>/dev/null && ok "Custom files injected" || log "No custom files found"
    fi
}

# === ADD CUSTOM PACKAGES ===
inject_packages() {
    step "Adding custom packages"
    cd "$IB_PATH"
    mkdir -p "packages"
    
    if [[ -d "$PACKAGES_DIR" ]]; then
        cp -rf "$PACKAGES_DIR/." "packages/" 2>/dev/null && ok "Custom packages copied"
    fi
}

# === DOWNLOAD EXTRA PACKAGES FROM REPOS ===
download_extra_packages() {
    step "Downloading extra packages"
    cd "$IB_PATH/packages"
    
    # GitHub releases
    local github_pkgs=(
        "luci-app-amlogic|https://api.github.com/repos/ophub/luci-app-amlogic/releases/latest"
    )
    for entry in "${github_pkgs[@]}"; do
        local name="${entry%|*}" url="${entry#*|}"
        local dl_url=$(curl -sL "$url" | grep "browser_download_url" | grep -oE "https.*\.ipk" | head -1)
        [[ -n "$dl_url" ]] && ariadl "$dl_url" "./$(basename $dl_url)" || log "No ipk for $name"
    done
}

# === BUILD PACKAGE LIST ===
build_package_list() {
    local PACKAGES="" EXCLUDED="" OPENCLASH="" MIHOMO="" PASSWALL=""
    local CURVER="$SRC_BRANCH"
    
    # --- BASE ---
    PACKAGES+=" -dnsmasq dnsmasq-full cgi-io libiwinfo libiwinfo-data"
    PACKAGES+=" luci-base luci-lib-base luci-lib-ip luci-lib-jsonc luci-lib-nixio"
    PACKAGES+=" luci-mod-admin-full luci-mod-network luci-mod-status luci-mod-system"
    PACKAGES+=" luci-proto-ipv6 luci-proto-ppp luci-theme-bootstrap"
    PACKAGES+=" luci luci-ssl luci-compat luci-app-firewall luci-app-opkg"
    PACKAGES+=" luci-app-ttyd luci-app-poweroff luci-app-log-viewer luci-app-ramfree"
    PACKAGES+=" ttyd htop bash curl wget-ssl tar unzip unrar gzip jq nano"
    PACKAGES+=" openssh-sftp-server ca-bundle ca-certificates"
    PACKAGES+=" coreutils coreutils-base64 coreutils-nohup coreutils-stat coreutils-sleep coreutils-whoami"
    PACKAGES+=" ip-full iptables iptables-legacy iptables-mod-iprange iptables-mod-socket iptables-mod-tproxy"
    PACKAGES+=" kmod-ipt-nat kmod-tun resolveip zoneinfo-asia zoneinfo-core"
    PACKAGES+=" zram-swap block-mount parted losetup resize2fs"
    PACKAGES+=" rpcd rpcd-mod-file rpcd-mod-iwinfo rpcd-mod-luci rpcd-mod-rrdns"
    PACKAGES+=" uhttpd uhttpd-mod-ubus px5g-wolfssl"
    
    # --- MODEM SUPPORT ---
    PACKAGES+=" kmod-usb-net-rtl8150 kmod-usb-net-rtl8152 kmod-usb-net-asix kmod-usb-net-asix-ax88179"
    PACKAGES+=" kmod-usb-net kmod-usb-wdm kmod-usb-net-qmi-wwan uqmi luci-proto-qmi"
    PACKAGES+=" kmod-usb-serial-option kmod-usb-serial kmod-usb-serial-wwan qmi-utils"
    PACKAGES+=" kmod-usb-acm kmod-usb-net-cdc-ncm kmod-usb-net-cdc-mbim umbim usbutils"
    PACKAGES+=" kmod-usb-net-huawei-cdc-ncm kmod-usb-net-cdc-ether kmod-usb-net-rndis"
    PACKAGES+=" kmod-usb-ohci kmod-usb2 kmod-usb-ehci usb-modeswitch"
    PACKAGES+=" modemmanager modemmanager-rpcd luci-proto-modemmanager libmbim libqmi"
    PACKAGES+=" sms-tool luci-app-sms-tool-js picocom minicom"
    
    # --- STORAGE / NAS ---
    PACKAGES+=" luci-app-diskman luci-app-disks-info smartmontools kmod-usb-storage kmod-usb-storage-uas ntfs-3g"
    
    # --- NETWORKING ---
    PACKAGES+=" luci-app-zerotier tailscale luci-app-tailscale luci-app-cloudflared"
    PACKAGES+=" internet-detector luci-app-internet-detector internet-detector-mod-modem-restart"
    PACKAGES+=" nlbwmon luci-app-nlbwmon vnstat2 vnstati2 luci-app-vnstat2 netdata"
    PACKAGES+=" luci-app-netspeedtest luci-app-cpu-status-mini luci-app-temp-status luci-app-disks-info"
    
    # --- THEME ---
    PACKAGES+=" luci-theme-material luci-theme-argon luci-app-argon-config"
    
    # --- TUNNEL APPS ---
    OPENCLASH="coreutils-nohup bash dnsmasq-full curl ca-certificates ipset ip-full"
    OPENCLASH+=" libcap libcap-bin ruby ruby-yaml kmod-tun kmod-inet-diag unzip kmod-nft-tproxy"
    OPENCLASH+=" luci-compat luci luci-base luci-app-openclash"
    
    MIHOMO="nikki luci-app-nikki"
    
    PASSWALL="chinadns-ng resolveip dns2socks dns2tcp ipt2socks microsocks tcping"
    PASSWALL+=" xray-core xray-plugin luci-app-passwall"
    
    # --- VARIANT SELECTION ---
    if [[ "$OP_VARIANT" == "full" ]]; then
        PACKAGES+=" python3 python3-pip"
        PACKAGES+=" adguardhome luci-app-adguardhome"
        PACKAGES+=" $OPENCLASH $MIHOMO $PASSWALL"
        PACKAGES+=" docker docker-compose dockerd luci-app-dockerman"
        PACKAGES+=" librespeed-go python3-speedtest-cli iperf3-ssl"
        EXCLUDED+=" -libgd"
        DISABLED_SERVICES="AdGuardHome"
    else
        PACKAGES+=" $OPENCLASH $MIHOMO"
        DISABLED_SERVICES=""
    fi
    
    # --- SOURCE SPECIFIC ---
    if [[ "$SRC_NAME" == "openwrt" ]]; then
        EXCLUDED+=" -dnsmasq"
    elif [[ "$SRC_NAME" == "immortalwrt" ]]; then
        EXCLUDED+=" -dnsmasq -automount -libustream-openssl -default-settings-chn -luci-i18n-base-zh-cn"
        [[ "$ARCH_2" == "x86_64" ]] && EXCLUDED+=" -kmod-usb-net-rtl8152-vendor"
    fi
    
    # --- TV BOX SPECIFIC ---
    if [[ "$TVBOX" == true ]]; then
        PACKAGES+=" luci-app-amlogic ath9k-htc-firmware btrfs-progs"
        PACKAGES+=" hostapd hostapd-utils kmod-ath kmod-ath9k kmod-ath9k-common kmod-ath9k-htc"
        PACKAGES+=" kmod-cfg80211 kmod-crypto-acompress kmod-crypto-crc32c kmod-crypto-hash kmod-fs-btrfs"
        PACKAGES+=" kmod-mac80211 wireless-tools wpa-cli wpa-supplicant"
        EXCLUDED+=" -procd-ujail"
    fi
    
    # Raspberry Pi
    if [[ "$TARGET_PROFILE" == rpi-* ]]; then
        PACKAGES+=" kmod-i2c-bcm2835 i2c-tools kmod-i2c-core kmod-i2c-gpio"
    fi
    
    echo "$PACKAGES|$EXCLUDED|$DISABLED_SERVICES"
}

# === BUILD FIRMWARE ===
build_firmware() {
    step "Building firmware: ${OP_DEVICE} (${OP_VARIANT})"
    cd "$IB_PATH"
    
    local pkg_data=$(build_package_list)
    local PACKAGES="${pkg_data%%|*}"
    local rest="${pkg_data#*|}"
    local EXCLUDED="${rest%%|*}"
    local DISABLED="${rest#*|}"
    
    inject_files
    inject_packages
    download_extra_packages
    
    mkdir -p "out_firmware" "out_rootfs"
    
    step "Running make image..."
    make image PROFILE="${TARGET_PROFILE}" \
        PACKAGES="${PACKAGES} ${EXCLUDED}" \
        FILES="files" \
        DISABLED_SERVICES="${DISABLED}" 2>&1 | tee -a "$MAKE_PATH/$LOG_FILE"
    
    if [[ ${PIPESTATUS[0]} -eq 0 ]]; then
        ok "Build succeeded!"
        
        # Move artifacts
        find bin/targets -name "*.img.gz" -exec mv {} "out_firmware/" \;
        find bin/targets -name "*rootfs.tar.gz" -exec mv {} "out_rootfs/" \;
        
        # If TV box, repack with ophub kernel
        if [[ "$TVBOX" == true ]]; then
            repack_tvbox
        fi
        
        ok "All artifacts in out_firmware/ and out_rootfs/"
    else
        fail "Build failed. Check $LOG_FILE"
    fi
}

# === REPACK FOR TV BOX ===
repack_tvbox() {
    step "Repacking for TV box with ophub kernel"
    # This requires the ophub packaging tool (remake) with rootfs from ImageBuilder
    # For now, the rootfs.tar.gz is in out_rootfs/
    # TODO: Integrate ophub's remake for full device image
    log "rootfs.tar.gz ready for ophub packing in out_rootfs/"
}

# === MAIN ===
main() {
    echo "=============================================="
    echo "  Hermes-WRT ImageBuilder"
    echo "  Source: ${SRC_NAME}:${SRC_VER}"
    echo "  Device: ${OP_DEVICE}"
    echo "  Variant: ${OP_VARIANT}"
    echo "=============================================="
    
    detect_target "$OP_DEVICE"
    download_ib
    configure_ib
    
    local start=$(date +%s)
    build_firmware
    local elapsed=$(($(date +%s) - start))
    
    echo -e "\n${GREEN}=============================================="
    echo "  Build complete! (${elapsed}s)"
    echo "  Output: ${IB_PATH}/out_firmware/"
    echo "==============================================${RESET}"
}

# Run if not sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main
fi
