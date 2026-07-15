#!/bin/bash
# scripts/PACKER.sh — Kernel download & TV box image packing backend
# Used by imagebuilder.sh when building for TV box devices
#
# Kernel sources:
#   ophub       → github.com/ophub/kernel (default, most complete)
#   armarchindo → github.com/armarchindo/kernel
#   custom      → $KERNEL_URL
#   local       → $KERNEL_DIR/
# ============================================================

pack_tvbox() {
    step "Packing TV box image (kernel: ${KERNEL_SOURCE})"

    mkdir -p "$OUT_TVBOX"
    local rootfs_tgz=$(ls "${IB_PATH}/out_rootfs/"*rootfs.tar.gz 2>/dev/null | head -1)

    if [[ -z "$rootfs_tgz" ]]; then
        warn "No rootfs.tar.gz found in ${IB_PATH}/out_rootfs/"
        warn "Build ImageBuilder first, or place rootfs.tar.gz manually"
        return 1
    fi

    log "Using rootfs: $(basename $rootfs_tgz)"

    # Prepare staging
    local stage="${MAKE_PATH}/.pack_staging"
    rm -rf "$stage"
    mkdir -p "$stage/rootfs" "$stage/kernel"

    # Extract rootfs
    step "Extracting rootfs..."
    tar -xzf "$rootfs_tgz" -C "$stage/rootfs" 2>/dev/null
    ok "Rootfs extracted"

    # Download kernel
    download_kernel "$stage/kernel"

    # Pack (varies by backend)
    case "$PACKER" in
        remake)   pack_remake "$stage" ;;
        ulo)      pack_ulo "$stage" ;;
        custom)   pack_custom "$stage" ;;
        *)        pack_remake "$stage" ;;
    esac

    rm -rf "$stage"
}

# ════════════════════════════════════════════════════════════
# Kernel Download (interchangeable backends)
# ════════════════════════════════════════════════════════════

download_kernel() {
    local out="$1"
    local ver="${KERNEL_VERSION}"

    case "$KERNEL_SOURCE" in
        ophub)
            download_kernel_ophub "$out" "$ver"
            ;;
        armarchindo)
            download_kernel_armarchindo "$out" "$ver"
            ;;
        stable)
            download_kernel_stable "$out" "$ver"
            ;;
        custom)
            download_kernel_custom "$out"
            ;;
        local)
            copy_kernel_local "$out"
            ;;
        *)
            warn "Unknown kernel source: ${KERNEL_SOURCE}. Falling back to ophub."
            download_kernel_ophub "$out" "$ver"
            ;;
    esac
}

# ── OPHUB — default, most complete ──
download_kernel_ophub() {
    local out="$1" ver="${2:-auto}"
    step "Downloading kernel from ophub (${ver})"

    local api_url="https://api.github.com/repos/ophub/kernel/releases/tags/kernel_stable"
    local dl_url

    if [[ "$ver" == "auto" ]]; then
        # Get latest kernel tags
        local tags=$(curl -sL "$api_url" | grep -oE '"name": "[^"]+"' | cut -d'"' -f4 | head -5)
        # Pick first 6.x.y match
        ver=$(echo "$tags" | grep -oE '6\.[0-9]+\.[0-9]+' | head -1)
        [[ -z "$ver" ]] && ver="6.12.0"
        log "Auto-selected kernel: ${ver}"
    fi

    # ophub kernel URL format: github.com/ophub/kernel/releases/download/kernel_stable/
    # Structure: boot-${ver}.tar.gz + dtb-${ver}.tar.gz + modules-${ver}.tar.gz
    local base="https://github.com/ophub/kernel/releases/download/kernel_stable"
    local files=(
        "boot-${ver}.tar.gz"
        "dtb-${DEV_FAMILY}-${ver}.tar.gz"
        "modules-${ver}.tar.gz"
    )

    for f in "${files[@]}"; do
        ariadl "${base}/${f}" "${out}/${f}" 2>/dev/null || warn "Failed: ${f}"
    done

    extract_kernel "$out" "$ver"
}

# ── ARMARCHINDO — alternative kernel ──
download_kernel_armarchindo() {
    local out="$1" ver="${2:-auto}"
    step "Downloading kernel from armarchindo (${ver})"

    if [[ "$ver" == "auto" ]]; then
        local latest=$(curl -sL "https://api.github.com/repos/armarchindo/kernel/releases/latest" \
            | grep -oE '"tag_name": "[^"]+"' | cut -d'"' -f4)
        ver="${latest:-6.12.0}"
        log "Auto-selected kernel: ${ver}"
    fi

    local base="https://github.com/armarchindo/kernel/releases/download/${ver}"
    local files=(
        "boot-${ver}.tar.gz"
        "dtb-${DEV_FAMILY}-${ver}.tar.gz"
        "modules-${ver}.tar.gz"
    )

    for f in "${files[@]}"; do
        ariadl "${base}/${f}" "${out}/${f}" 2>/dev/null || warn "Failed: ${f}"
    done

    extract_kernel "$out" "$ver"
}

# ── KERNEL.ORG — mainline stable ──
download_kernel_stable() {
    local out="$1" ver="${2:-auto}"
    step "Downloading kernel from kernel.org (${ver})"

    if [[ "$ver" == "auto" ]]; then
        # Get latest stable version
        ver=$(curl -sL "https://www.kernel.org/releases.json" \
            | grep -oE '"version": "([0-9]+\.[0-9]+\.?[0-9]*)"' \
            | head -1 | cut -d'"' -f4)
        [[ -z "$ver" ]] && ver="6.12"
        log "Auto-selected kernel: ${ver}"
    fi

    # Download kernel source (mainline)
    local url="https://cdn.kernel.org/pub/linux/kernel/v${ver%%.*}.x/linux-${ver}.tar.xz"
    ariadl "$url" "${out}/linux-${ver}.tar.xz" || warn "Failed to download kernel source"

    warn "kernel.org download provides source, not pre-built."
    warn "For pre-built kernels, use ophub or armarchindo."
}

# ── CUSTOM URL ──
download_kernel_custom() {
    local out="$1"
    step "Downloading kernel from custom URL"
    if [[ -z "$KERNEL_URL" ]]; then
        fail "KERNEL_URL not set. Set it in hermes.conf or export KERNEL_URL=..."
    fi
    ariadl "$KERNEL_URL" "${out}/custom-kernel.tar.gz"
    tar -xzf "${out}/custom-kernel.tar.gz" -C "$out" 2>/dev/null || true
}

# ── LOCAL ──
copy_kernel_local() {
    local out="$1"
    step "Copying kernel from local: ${KERNEL_DIR}"
    if [[ -z "$KERNEL_DIR" || ! -d "$KERNEL_DIR" ]]; then
        fail "KERNEL_DIR not found: ${KERNEL_DIR}"
    fi
    cp -rf "$KERNEL_DIR/." "$out/" 2>/dev/null
    ok "Kernel copied from $KERNEL_DIR"
}

# ── Extract kernel files ──
extract_kernel() {
    local out="$1" ver="$2"
    step "Extracting kernel artifacts"
    cd "$out"
    for f in *.tar.gz; do
        [[ -f "$f" ]] && tar -xzf "$f" 2>/dev/null && rm -f "$f"
    done
    ok "Kernel extracted to $out"
}

# ════════════════════════════════════════════════════════════
# Packing Methods
# ════════════════════════════════════════════════════════════

# ── REMake (ophub) ──
pack_remake() {
    local stage="$1"
    step "Packing with ophub remake"
    log "Stage: rootfs at ${stage}/rootfs, kernel at ${stage}/kernel"
    log "TODO: call remake binary with these paths"

    # Structure expected by remake:
    # ${stage}/rootfs/ → root filesystem
    # ${stage}/kernel/ → boot/, dtb/, modules/
    # remake will generate .img.gz

    warn "remake binary not bundled. Install it manually:"
    warn "  git clone https://github.com/ophub/amlogic-s9xxx-openwrt"
    warn "  Use: sudo ./remake -b ${OP_DEVICE} -k ${KERNEL_VERSION} -r ${stage}/rootfs"

    # For now, bundle the rootfs so it's ready for manual remake
    local bundle="${OUT_TVBOX}/hermes-wrt-${OP_DEVICE}-${KERNEL_VERSION}-rootfs.tar.gz"
    cd "$stage/rootfs"
    tar -czf "$bundle" . 2>/dev/null
    ok "Rootfs bundled for remake: $bundle"
}

# ── ULO-Builder approach ──
pack_ulo() {
    local stage="$1"
    step "Packing with ULO-style approach"

    local bundle="${OUT_TVBOX}/hermes-wrt-${OP_DEVICE}-${KERNEL_VERSION}-rootfs.tar.gz"
    cd "$stage/rootfs"
    tar -czf "$bundle" . 2>/dev/null
    ok "Rootfs ready for ULO-Builder: $bundle"
}

# ── Custom packer ──
pack_custom() {
    local stage="$1"
    step "Custom packing requested"
    warn "Custom packer not implemented. Rootfs + kernel staged at:"
    warn "  rootfs: ${stage}/rootfs"
    warn "  kernel: ${stage}/kernel"
}
