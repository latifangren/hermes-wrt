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
OP_SOURCE="${1:-openwrt:latest}"
OP_DEVICE="${2:-s905x3}"
OP_VARIANT="${3:-$BUILD_VARIANT}"

SRC_NAME="${OP_SOURCE%:*}"
SRC_VER="${OP_SOURCE#*:}"

# ── Source INCLUDE utils ──
INCLUDE_PATH="${MAKE_PATH}/scripts/INCLUDE.sh"
if [[ -f "$INCLUDE_PATH" ]]; then
    source "$INCLUDE_PATH"
else
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
fi

# ── Resolve 'latest' ke versi stabil terbaru ──
resolve_latest_source() {
    local base_url="https://downloads.${SRC_NAME}.org/releases/"
    log "Resolving 'latest' from ${base_url}..."
    local latest=$(curl -sL "$base_url" | grep -oP 'href="\K[0-9]+\.[0-9]+\.[0-9]+/' | tr -d '/' | sort -V | tail -1)
    if [[ -n "$latest" ]]; then
        SRC_VER="$latest"
        log "  → ${SRC_NAME}:${SRC_VER}"
    else
        warn "  Gagal fetch latest, fallback ke ${SRC_VER}"
    fi
}

if [[ "${SRC_VER,,}" == "latest" ]]; then
    resolve_latest_source
fi
SRC_BRANCH="${SRC_VER%.*}"
SRC_MAJOR="${SRC_BRANCH%%.*}"
SRC_MINOR="${SRC_BRANCH#*.}"

# ── Download with aria2 + retry ──
# (Definitions are in INCLUDE.sh or fallback, but if we don't fall back we won't need to define it twice here)
if ! declare -f ariadl >/dev/null; then
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
fi

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
    local base_name="${SRC_NAME}-imagebuilder-${SRC_VER}-${TARGET_NAME}.Linux-x86_64"
    local archive="${base_name}.${ext}"
    local url="https://downloads.${SRC_NAME}.org/releases/${SRC_VER}/targets/${TARGET_SYS}/${archive}"

    mkdir -p "$MAKE_PATH"
    cd "$MAKE_PATH"
    ariadl "$url" "$archive"

    step "Extracting ImageBuilder..."
    case "$ext" in
        tar.xz)  tar -xJf "$archive" >/dev/null 2>&1 ;;
        tar.zst) tar -xvf "$archive" >/dev/null 2>&1 ;;
    esac
    rm -f "$archive"
    rm -rf "$OPENWRT_DIR"
    mv -f "$base_name" "$OPENWRT_DIR" || fail "Failed to extract ImageBuilder"
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

    # Add custom repos
    if [[ "$SRC_NAME" == "openwrt" ]] || [[ "$SRC_NAME" == "immortalwrt" ]]; then
        # Add kiddin9 custom packages feed if enabled
        if [[ "${ENABLE_KIDDIN9_FEED:-false}" == "true" ]]; then
            echo "src/gz kiddin9 https://dl.openwrt.ai/releases/${SRC_BRANCH}/packages/${ARCH_3}/kiddin9" >> repositories.conf
        fi
        # Add common architectures to prevent incompat warning for custom packages like mihombreng
        echo "arch all 1" >> repositories.conf
        echo "arch aarch64_generic 10" >> repositories.conf
        echo "arch aarch64_cortex-a72 15" >> repositories.conf
        echo "arch aarch64_cortex-a53 16" >> repositories.conf
        echo "arch aarch64 20" >> repositories.conf
    fi

    # Force overwrite on package install (OPKG)
    if [[ "$SRC_MAJOR" -ge 25 ]]; then
        sed -i 's/install $(BUILD_PACKAGES)/install $(BUILD_PACKAGES) --allow-downgrades/' Makefile 2>/dev/null || true
        log "OpenWrt 25.x detected: using APK-compatible flags"
    else
        sed -i 's/install $(BUILD_PACKAGES)/install $(BUILD_PACKAGES) --force-overwrite --force-downgrade/' Makefile 2>/dev/null || true
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

    # Dynamically inject hermes configurations
    mkdir -p "files/etc/config"
    cat > "files/etc/config/hermes" <<EOF
config hermes 'telegram'
	option enabled '$( [[ "${ENABLE_TELEGRAM_BOT:-false}" == "true" ]] && echo "1" || echo "0" )'
	option bot_token '${TELEGRAM_BOT_TOKEN:-}'
	option chat_id '${TELEGRAM_CHAT_ID:-}'
EOF

    # Clean up disabled tools to prevent image bloat
    if [[ "${ENABLE_HERMES_CLI:-true}" != "true" ]]; then
        rm -f "files/usr/bin/hdev"
    fi
    if [[ "${ENABLE_TELEGRAM_BOT:-false}" != "true" ]]; then
        rm -f "files/usr/bin/hbot"
        rm -f "files/etc/init.d/hbot"
    fi
    ok "Dynamic Hermes configurations written (Telegram Bot: ${ENABLE_TELEGRAM_BOT:-false})"
}

# ── Inject custom packages ──
inject_packages() {
    step "Adding custom packages"
    
    # Pendeteksian & download dinamis dari repositori paket eksternal
    local repo_url="https://github.com/latifangren/openwrt-custom-packages.git"
    local tmp_dir="/tmp/hermes-custom-pkg"
    
    log "Mengunduh paket biner eksternal dari ${repo_url}..."
    rm -rf "$tmp_dir"
    if git clone --depth 1 "$repo_url" "$tmp_dir" &>/dev/null; then
        mkdir -p "$PACKAGES_DIR"
        find "$tmp_dir" -type f \( -name "*.ipk" -o -name "*.apk" \) -exec cp -f {} "$PACKAGES_DIR/" \; 2>/dev/null || true
        ok "Paket eksternal berhasil ditarik secara dinamis!"
    else
        warn "Gagal mengklon repositori paket eksternal. Menggunakan paket lokal yang tersedia."
    fi
    rm -rf "$tmp_dir"

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
    BASE+=" luci-app-firewall luci-app-opkg luci-app-ttyd luci-app-package-manager"
    if [[ "${ENABLE_KIDDIN9_FEED:-false}" == "true" ]] || [[ "$SRC_NAME" == "immortalwrt" ]]; then
        BASE+=" luci-app-ramfree"
    fi
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
        BASE+=" btop screen pv httping adb"

    # — File Browser (Immortalwrt or Kiddin9 only) —
    if [[ "${ENABLE_KIDDIN9_FEED:-false}" == "true" ]] || [[ "$SRC_NAME" == "immortalwrt" ]]; then
        BASE+=" luci-app-filebrowser"
    fi

    # — Modem support —
    if [[ "${ENABLE_MODEM:-true}" == "true" ]]; then
        BASE+=" kmod-usb-net-rtl8150 kmod-usb-net-rtl8152 kmod-usb-net-asix kmod-usb-net-asix-ax88179"
        BASE+=" kmod-usb-net kmod-usb-wdm kmod-usb-net-qmi-wwan uqmi luci-proto-qmi"
        BASE+=" kmod-usb-serial-option kmod-usb-serial kmod-usb-serial-wwan qmi-utils"
        BASE+=" kmod-usb-acm kmod-usb-net-cdc-ncm kmod-usb-net-cdc-mbim umbim usbutils"
        BASE+=" kmod-usb-net-huawei-cdc-ncm kmod-usb-net-cdc-ether kmod-usb-net-rndis"
        BASE+=" kmod-usb-ohci kmod-usb2 kmod-usb-ehci usb-modeswitch"
        BASE+=" modemmanager modemmanager-rpcd luci-proto-modemmanager libmbim libqmi"
        BASE+=" sms-tool picocom minicom"
        BASE+=" luci-proto-ncm luci-proto-mbim luci-proto-3g"
        # Custom local packages from packages/ folder (hanya didukung jika basis OS adalah IPK < 25)
        if [[ "$SRC_MAJOR" -lt 25 ]]; then
            BASE+=" luci-app-rakitanmanager luci-app-nokia-status luci-app-mactodong"
            BASE+=" xmm-modem luci-proto-xmm luci-proto-atc atc-fib-fm350_gl atc-fib-l8x0_gl"
        fi

        if [[ "${ENABLE_KIDDIN9_FEED:-false}" == "true" ]] || [[ "$SRC_NAME" == "immortalwrt" ]]; then
            BASE+=" luci-app-3ginfo-lite luci-app-mmconfig"
            BASE+=" luci-app-modemband luci-app-modeminfo"
            BASE+=" luci-app-sms-tool-js luci-app-droidnet luci-app-lite-watchdog"
            BASE+=" modeminfo modeminfo-serial-dell modeminfo-serial-fibocom"
            BASE+=" modeminfo-serial-sierra modeminfo-serial-tw modeminfo-serial-xmm"
            BASE+=" modemband"
        fi
    fi

    # — Storage —
    if [[ "${ENABLE_KIDDIN9_FEED:-false}" == "true" ]] || [[ "$SRC_NAME" == "immortalwrt" ]]; then
        BASE+=" luci-app-diskman"
    fi
    BASE+=" smartmontools"
    BASE+=" kmod-usb-storage kmod-usb-storage-uas ntfs-3g exfat-mkfs exfat-fsck dosfstools"

    # — Network extras —
    if [[ "${ENABLE_KIDDIN9_FEED:-false}" == "true" ]] || [[ "$SRC_NAME" == "immortalwrt" ]]; then
        BASE+=" luci-app-zerotier"
    fi
    BASE+=" tailscale luci-app-cloudflared"
    BASE+=" nlbwmon luci-app-nlbwmon vnstat2 vnstati2 luci-app-vnstat2 netdata"

    # — Theme defaults (official only) —
    BASE+=" luci-theme-bootstrap luci-theme-material luci-theme-luxe"

    # — Tunnels —
    local tunnel_opt="${TUNNEL_TYPE:-all}"
    if [[ "$tunnel_opt" != "none" ]]; then
        TUNNEL+=" coreutils-nohup bash dnsmasq-full curl ca-certificates ipset ip-full"
        TUNNEL+=" libcap libcap-bin ruby ruby-yaml kmod-tun kmod-inet-diag unzip kmod-nft-tproxy"
        TUNNEL+=" microsocks"
        
        # Check feed availability
        local feed_ok=false
        if [[ "${ENABLE_KIDDIN9_FEED:-false}" == "true" ]] || [[ "$SRC_NAME" == "immortalwrt" ]]; then
            feed_ok=true
        fi

        if [[ "$feed_ok" == true ]]; then
            TUNNEL+=" chinadns-ng resolveip dns2socks ipt2socks"
            
            # Filter per tipe tunnel terpilh
            if [[ "$tunnel_opt" == "all" || "$tunnel_opt" == *"openclash"* ]]; then
                TUNNEL+=" dns2tcp tcping luci-app-openclash"
            fi
            
            if [[ "$tunnel_opt" == "all" || "$tunnel_opt" == *"nikki"* ]]; then
                TUNNEL+=" nikki luci-app-nikki"
            fi
            
            if [[ "$tunnel_opt" == "all" || "$tunnel_opt" == *"mihombreng"* ]]; then
                TUNNEL+=" mihombreng luci-app-mihombreng"
            fi
            
            if [[ "$tunnel_opt" == "all" || "$tunnel_opt" == *"passwall"* ]]; then
                TUNNEL+=" xray-core xray-plugin luci-app-passwall"
            fi
        fi
        BASE+=" $TUNNEL"
    fi

    # — Variant: full add-ons —
    if [[ "$OP_VARIANT" == "full" ]]; then
        [[ "${ENABLE_PYTHON:-false}" == "true" ]] && BASE+=" python3 python3-pip"
        [[ "${ENABLE_DOCKER:-false}" == "true" ]] && \
            BASE+=" docker docker-compose dockerd"
        if [[ "${ENABLE_KIDDIN9_FEED:-false}" == "true" ]] || [[ "$SRC_NAME" == "immortalwrt" ]]; then
            [[ "${ENABLE_DOCKER:-false}" == "true" ]] && BASE+=" luci-app-dockerman"
            [[ "${ENABLE_ADGUARD:-false}" == "true" ]] && \
                BASE+=" adguardhome luci-app-adguardhome"
            BASE+=" librespeed-go iperf3-ssl ookla-speedtest"
        fi
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
        BASE+=" ath9k-htc-firmware btrfs-progs"
        BASE+=" hostapd hostapd-utils kmod-ath kmod-ath9k kmod-ath9k-common kmod-ath9k-htc"
        BASE+=" kmod-cfg80211 kmod-crypto-acompress kmod-crypto-crc32c kmod-crypto-hash kmod-fs-btrfs"
        BASE+=" kmod-mac80211 wireless-tools wpa-cli wpa-supplicant"
        EXCLUDED+=" -procd-ujail"
    fi

    echo "${BASE}|${EXCLUDED}|${DISABLED}"
}

# ── Inject mihombreng prebuilt package ──
inject_mihombreng() {
    # Map OpenWrt arch → mihombreng release filename
    local mih_arch=""
    case "$ARCH_2" in
        aarch64) mih_arch="aarch64" ;;
        arm)     mih_arch="arm"     ;;
        x86_64)  mih_arch="x86"     ;;
        i386)    mih_arch="i386"    ;;
        mips)    mih_arch="mips"    ;;
        mipsel)  mih_arch="mipsel"  ;;
        *) warn "No mihombreng package for arch: $ARCH_2"; return 1 ;;
    esac

    local ext="ipk"
    [[ "$SRC_MAJOR" -ge 25 ]] && ext="apk"

    local tag_url="https://api.github.com/repos/latifangren/mihombreng/releases/latest"
    local tag_name
    tag_name=$(curl -sSL "$tag_url" | python3 -c "import json,sys; print(json.load(sys.stdin)['tag_name'])" 2>/dev/null) || {
        warn "Failed to get latest mihombreng release tag"
        return 1
    }

    local ver="${tag_name#v}"
    local pkg_name="mihombreng-${ver}-${mih_arch}.${ext}"
    local lui_name="luci-app-mihombreng-${ver}_all.${ext}"
    [[ "$ext" == "apk" ]] && {
        # workaround: di release v1.2.4 mihombreng apk terdeteksi sebagai nama lain (misal double extension)
        # cari lewat api github release assets yang persis berisi 'mihombreng-' * '.apk' dan tidak mengandung 'android' atau 'luci'
        local api_assets
        api_assets=$(curl -sSL "$tag_url" 2>/dev/null)
        local raw_pkg_name
        raw_pkg_name=$(echo "$api_assets" | python3 -c "import json,sys; assets=json.load(sys.stdin).get('assets',[]); print(next((a['name'] for a in assets if a['name'].startswith('mihombreng-') and a['name'].endswith('.apk') and 'android' not in a['name'] and 'luci-app-' not in a['name']), ''))" 2>/dev/null)
        if [[ -n "$raw_pkg_name" ]]; then
            pkg_name="$raw_pkg_name"
        else
            pkg_name="mihombreng-${ver}-mihombreng-1.apk.apk"
        fi
        lui_name="luci-app-mihombreng-${ver}-all.apk"
    }

    local base_url="https://github.com/latifangren/mihombreng/releases/download/${tag_name}"
    local pkg_dir="${IB_PATH}/packages"

    mkdir -p "$pkg_dir"

    step "Downloading mihombreng ${tag_name} for ${ARCH_2}..."
    ariadl "${base_url}/${pkg_name}" "${pkg_dir}/${pkg_name}" || return 1
    ariadl "${base_url}/${lui_name}" "${pkg_dir}/${lui_name}" || return 1
    ok "mihombreng packages ready in ${pkg_dir}"
}

# ── Inject Luxe theme package ──
inject_luxe_theme() {
    local ext="ipk"
    local luxe_ver="2.6.0"
    local luxe_file=""

    if [[ "$SRC_MAJOR" -ge 25 ]]; then
        ext="apk"
        luxe_file="luci-theme-luxe-2.6.0-r07072026.apk"
    elif [[ "$SRC_MAJOR" -eq 24 ]]; then
        luxe_file="luci-theme-luxe_2.6.0-r07072026_24.10_all.ipk"
    else
        luxe_file="luci-theme-luxe_2.6.0-07072026_23.05_all.ipk"
    fi

    local url="https://github.com/de-quenx/luci-theme-luxe/releases/download/v${luxe_ver}/${luxe_file}"
    local pkg_dir="${IB_PATH}/packages"
    mkdir -p "$pkg_dir"

    step "Downloading Luxe theme ${luxe_ver}..."
    ariadl "$url" "${pkg_dir}/${luxe_file}" || return 1
    ok "Luxe theme package ready at ${pkg_dir}"
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
    inject_mihombreng || true
    inject_luxe_theme || true

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
    detect_target "$OP_DEVICE"

    # If device is official, ignore selected kernel inputs
    if [[ "$TVBOX" == "false" ]]; then
        KERNEL_SOURCE="official"
        KERNEL_VERSION="official"
    fi

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
