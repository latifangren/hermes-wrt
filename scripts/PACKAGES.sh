#!/bin/bash
# scripts/PACKAGES.sh — Package definitions for Hermes-WRT
# Source this from imagebuilder.sh or use as reference.
# Each entry: "package_name|repo_url"
# Repo types: github (via API), custom (direct + pattern matching)

declare -A REPOS
REPOS=(
    [KIDDIN9]="https://dl.openwrt.ai/releases/24.10/packages/aarch64_generic/kiddin9"
    [IMMORTALWRT]="https://downloads.immortalwrt.org/releases/packages-24.10/aarch64_generic"
    [OPENWRT]="https://downloads.openwrt.org/releases/packages-24.10/aarch64_generic"
    [GSPOTX2F]="https://github.com/gSpotx2f/packages-openwrt/raw/refs/heads/master/current"
    [FANTASTIC]="https://fantastic-packages.github.io/packages/releases/24.10/packages/x86_64"
)

# GitHub packages (auto-download from latest release)
declare -a PACKAGES_GITHUB=(
    "luci-app-amlogic|https://api.github.com/repos/ophub/luci-app-amlogic/releases/latest"
    "luci-app-alpha-config|https://api.github.com/repos/animegasan/luci-app-alpha-config/releases/latest"
    "luci-theme-material3|https://api.github.com/repos/AngelaCooljx/luci-theme-material3/releases/latest"
    "luci-app-neko|https://api.github.com/repos/nosignals/openwrt-neko/releases/latest"
)

# Static custom packages (repo-based)
declare -a PACKAGES_CUSTOM=(
    "modemmanager-rpcd|${REPOS[OPENWRT]}/packages"
    "luci-proto-modemmanager|${REPOS[OPENWRT]}/luci"
    "libqmi|${REPOS[OPENWRT]}/packages"
    "libmbim|${REPOS[OPENWRT]}/packages"
    "modemmanager|${REPOS[OPENWRT]}/packages"
    "sms-tool|${REPOS[OPENWRT]}/packages"
    "tailscale|${REPOS[OPENWRT]}/packages"
    "luci-app-tailscale|${REPOS[KIDDIN9]}"
    "luci-app-diskman|${REPOS[KIDDIN9]}"
    "luci-app-poweroff|${REPOS[KIDDIN9]}"
    "modeminfo|${REPOS[KIDDIN9]}"
    "luci-app-modeminfo|${REPOS[KIDDIN9]}"
    "luci-theme-alpha|${REPOS[KIDDIN9]}"
    "luci-app-adguardhome|${REPOS[KIDDIN9]}"
    "mihomo|${REPOS[KIDDIN9]}"
    "sing-box|${REPOS[KIDDIN9]}"
    "luci-app-zerotier|${REPOS[IMMORTALWRT]}/luci"
    "luci-app-ramfree|${REPOS[IMMORTALWRT]}/luci"
    "luci-app-3ginfo-lite|${REPOS[IMMORTALWRT]}/luci"
    "luci-app-argon-config|${REPOS[IMMORTALWRT]}/luci"
    "luci-theme-argon|${REPOS[IMMORTALWRT]}/luci"
    "luci-app-openclash|${REPOS[IMMORTALWRT]}/luci"
    "luci-app-passwall|${REPOS[IMMORTALWRT]}/luci"
    "luci-app-internet-detector|${REPOS[GSPOTX2F]}"
    "internet-detector|${REPOS[GSPOTX2F]}"
    "internet-detector-mod-modem-restart|${REPOS[GSPOTX2F]}"
    "luci-app-cpu-status-mini|${REPOS[GSPOTX2F]}"
    "luci-app-disks-info|${REPOS[GSPOTX2F]}"
    "luci-app-log-viewer|${REPOS[GSPOTX2F]}"
    "luci-app-temp-status|${REPOS[GSPOTX2F]}"
    "luci-app-netspeedtest|${REPOS[FANTASTIC]}/luci"
)

# Tunnel apps — download manually or specify IPK paths
download_clash_core() {
    local arch="$1" # arm64, amd64
    local outdir="${2:-files/etc/openclash/core}"
    mkdir -p "$outdir"
    local api="https://api.github.com/repos/MetaCubeX/mihomo/releases/latest"
    local pattern="mihomo-linux-${arch}-compatible"
    local url=$(curl -sL "$api" | grep "browser_download_url" | grep -oE "https.*${pattern}-v[0-9]+\.[0-9]+\.[0-9]+\.gz" | head -1)
    [[ -z "$url" ]] && { log "No Clash core found for $arch"; return 1; }
    ariadl "$url" "${outdir}/clash_meta.gz"
    gzip -d "${outdir}/clash_meta.gz" 2>/dev/null || true
}

download_passwall() {
    local arch="$1"
    local outdir="${2:-packages}"
    mkdir -p "$outdir"
    local api="https://api.github.com/repos/xiaorouji/openwrt-passwall/releases"
    local pattern="passwall_packages_ipk_${arch}"
    local url=$(curl -sL "$api" | grep "browser_download_url" | grep -oE "https.*${pattern}.*\.zip" | head -1)
    [[ -z "$url" ]] && { log "No Passwall found for $arch"; return 1; }
    ariadl "$url" "${outdir}/passwall.zip"
    unzip -qo "${outdir}/passwall.zip" -d "$outdir" && rm "${outdir}/passwall.zip"
}
