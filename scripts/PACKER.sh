#!/bin/bash
# scripts/PACKER.sh — TV box image packer (hibrid engine)
# Used by imagebuilder.sh when building for TV box devices
#
# Kernel sources:
#   ophub       → github.com/ophub/kernel (default, most complete)
#   armarchindo → github.com/armarchindo/kernel
#   sib0ndt     → github.com/sib0ndt/linux (custom Amlogic kernel)
#   custom      → KERNEL_URL
#   local       → KERNEL_DIR/
#
# Packing methods:
#   hibrid   → fallocate + parted + losetup (default, gak perlu remake binary)
#   remake   → ophub remake tool (legacy)
# ============================================================

# ── Build raw disk image (hibrid method) ──
# Global state for cleanup trap
LOOP_DEV=""

pack_tvbox() {
    step "Packing TV box image"

    local original_kernel_version="${KERNEL_VERSION:-auto}"
    original_kernel_version="${original_kernel_version,,}"

    IFS='_' read -r -a kernel_versions <<< "$original_kernel_version"
    if [[ ${#kernel_versions[@]} -gt 1 ]]; then
        log "Multi-kernel build requested: ${original_kernel_version}"
    fi

    local kernel_version
    for kernel_version in "${kernel_versions[@]}"; do
        [[ -z "$kernel_version" ]] && continue
        KERNEL_VERSION="$kernel_version"
        pack_tvbox_single "$kernel_version"
    done

    KERNEL_VERSION="$original_kernel_version"
}

pack_tvbox_single() {
    local kernel_version="${1:-${KERNEL_VERSION:-auto}}"
    kernel_version="${kernel_version,,}"
    KERNEL_VERSION="$kernel_version"

    local kernel_name
    kernel_name=$(echo "$kernel_version" | tr '/[:space:]' '--' | tr -cd '[:alnum:]._-')
    [[ -z "$kernel_name" ]] && kernel_name="auto"

    local disk_img="${OUT_TVBOX}/hermes-wrt-${OP_DEVICE}-${kernel_name}.img"
    local rootfs_tgz=$(ls "${IB_PATH}/out_rootfs/"*rootfs.tar.gz 2>/dev/null | head -1)

    [[ -z "$rootfs_tgz" ]] && { warn "No rootfs.tar.gz found. Build ImageBuilder first."; return 1; }
    log "Rootfs: $(basename "$rootfs_tgz")"
    log "Kernel selector: ${kernel_version}"

    local stage="${MAKE_PATH}/.pack_staging_${kernel_name}"
    rm -rf "$stage"
    mkdir -p "$stage/rootfs" "$stage/kernel" "$stage/boot"

    cleanup() {
        if [[ -n "${LOOP_DEV:-}" ]]; then
            log "Cleaning up mounts and loop devices..."
            sudo umount "${LOOP_DEV}p1" "${LOOP_DEV}p2" 2>/dev/null || true
            sudo losetup -d "$LOOP_DEV" 2>/dev/null || true
            LOOP_DEV=""
        fi
        if [[ -n "${stage:-}" ]]; then
            rm -rf "$stage" 2>/dev/null || true
        fi
    }
    trap cleanup EXIT

    # ── Step 1: Download kernel ──
    step "[1/6] Downloading kernel (${KERNEL_SOURCE})..."
    download_kernel "$stage/kernel"

    # ── Step 2: Create raw disk ──
    step "[2/6] Creating raw disk image (${DISK_SIZE:-1G})..."
    mkdir -p "$OUT_TVBOX"
    rm -f "$disk_img" "${disk_img}.gz"
    fallocate -l "${DISK_SIZE:-1G}" "$disk_img"

    # ── Step 3: Partition ──
    step "[3/6] Partitioning MBR: BOOT (128MB) + ROOTFS (sisa)..."
    sudo parted -s "$disk_img" mklabel msdos
    sudo parted -s "$disk_img" mkpart primary fat32 4MiB 132MiB
    sudo parted -s "$disk_img" mkpart primary ext4 132MiB 100%

    # ── Step 4: Format + mount ──
    step "[4/6] Mounting + formatting..."
    LOOP_DEV=$(sudo losetup -P -f --show "$disk_img")
    sleep 1
    mkdir -p "$stage/mnt_boot" "$stage/mnt_rootfs"
    sudo mkfs.fat -F 32 -n "BOOT" "${LOOP_DEV}p1"   >/dev/null 2>&1
    sudo mkfs.ext4 -F -L "ROOTFS" "${LOOP_DEV}p2"   >/dev/null 2>&1
    sudo mount "${LOOP_DEV}p1" "$stage/mnt_boot"
    sudo mount "${LOOP_DEV}p2" "$stage/mnt_rootfs"

    # ── Step 5: Assemble ──
    step "[5/6] Assembling image contents..."

    # 5a. Boot files dari repo (per-family)
    local boot_src="${MAKE_PATH}/boot/${DEV_FAMILY}"
    if [[ -d "$boot_src" ]]; then
        log "  Copying boot files (${boot_src})"
        sudo cp -rf "$boot_src"/* "$stage/mnt_boot/" 2>/dev/null || true
    fi

    # Patch FDT (DTB) dynamically for specific amlogic boards in uEnv.txt & extlinux.conf
    if [[ "$DEV_FAMILY" == "amlogic" && -f "$stage/mnt_boot/uEnv.txt" ]]; then
        local dtb_file=""
        case "$OP_DEVICE" in
            s905x-b860h*)     dtb_file="/dtb/amlogic/meson-gxl-s905x-b860h.dtb" ;;
            s905x-hg680p*)    dtb_file="/dtb/amlogic/meson-gxl-s905x-p212.dtb"  ;;
            s905x2-b860hv5*)  dtb_file="/dtb/amlogic/meson-g12a-b860h-v5.dtb"  ;;
            s905x2-hg680-fj*) dtb_file="/dtb/amlogic/meson-g12a-hg680-fj.dtb" ;;
            s905x3-hk1*)      dtb_file="/dtb/amlogic/meson-sm1-hk1box-vontar-x3.dtb" ;;
            s905x3-x96max*)   dtb_file="/dtb/amlogic/meson-sm1-x96-max-plus.dtb"    ;;
            s905x3-x96air*)   dtb_file="/dtb/amlogic/meson-sm1-x96-air.dtb"         ;;
            s905x3-h96max*)   dtb_file="/dtb/amlogic/meson-sm1-h96-max-x3.dtb"      ;;
            s905x4-advan*)    dtb_file="/dtb/amlogic/meson-s4-advan-at01.dtb"      ;;
            s905x4-generic*)  dtb_file="/dtb/amlogic/meson-s4-x96-x4.dtb"          ;;
            s905x4-v*)        dtb_file="/dtb/amlogic/meson-s4-x96-x4.dtb"          ;;
            s905w-x96mini*)   dtb_file="/dtb/amlogic/meson-gxl-s905w-tx3-mini.dtb" ;;
            s905w-tx3mini*)   dtb_file="/dtb/amlogic/meson-gxl-s905w-tx3-mini.dtb" ;;
            s905w-x96w*)      dtb_file="/dtb/amlogic/meson-gxl-s905w-p281.dtb"     ;;
            s905lb-q96mini*)  dtb_file="/dtb/amlogic/meson-gxl-s905x-p212.dtb"     ;;
            s912-generic*)    dtb_file="/dtb/amlogic/meson-gxm-nexbox-a1.dtb"       ;;
            s922x-gtking*)    dtb_file="/dtb/amlogic/meson-g12b-gtking-pro.dtb"    ;;
            *)
                # Default fallback jika tidak ada tipe spesifik
                dtb_file="/dtb/amlogic/meson-g12b-gtking-pro.dtb"
                ;;
        esac
        log "  Configuring DTB for $OP_DEVICE: $dtb_file"
        sudo sed -i "s|^FDT=.*|FDT=$dtb_file|" "$stage/mnt_boot/uEnv.txt"
        if [[ -f "$stage/mnt_boot/extlinux/extlinux.conf.bak" ]]; then
            sudo sed -i "s|meson-g12b-gtking-pro.dtb|$(basename "$dtb_file")|g" "$stage/mnt_boot/extlinux/extlinux.conf.bak"
        fi
    fi

    # 5b. Kernel boot/? dtb/ → BOOT partition
    if [[ -d "$stage/kernel/boot" ]]; then
        log "  Copying kernel boot files"
        sudo cp -rf "$stage/kernel/boot"/* "$stage/mnt_boot/" 2>/dev/null || true
    fi
    if [[ -d "$stage/kernel/dtb" ]]; then
        log "  Copying DTB files"
        mkdir -p "$stage/mnt_boot/dtb"
        sudo cp -rf "$stage/kernel/dtb"/* "$stage/mnt_boot/dtb/" 2>/dev/null || true
    fi

    # 5c. Rootfs
    log "  Extracting rootfs.tar.gz..."
    sudo tar -xzf "$rootfs_tgz" -C "$stage/mnt_rootfs/" --numeric-owner

    # 5d. Kernel modules — handle both layout: modules/ (ophub) or lib/modules/ (sib0ndt, rootfs-*.tar.gz)
    if [[ -d "$stage/kernel/lib/modules" ]]; then
        log "  Installing kernel modules from lib/modules"
        sudo rm -rf "$stage/mnt_rootfs/lib/modules/"
        sudo mkdir -p "$stage/mnt_rootfs/lib/modules/"
        sudo cp -rf "$stage/kernel/lib/modules"/* "$stage/mnt_rootfs/lib/modules/" 2>/dev/null || true
    elif [[ -d "$stage/kernel/modules" ]]; then
        log "  Installing kernel modules from modules"
        sudo rm -rf "$stage/mnt_rootfs/lib/modules/"
        sudo mkdir -p "$stage/mnt_rootfs/lib/modules/"
        sudo cp -rf "$stage/kernel/modules"/* "$stage/mnt_rootfs/lib/modules/" 2>/dev/null || true
    fi

    # 5e. files/ overlay
    local files_src="${MAKE_PATH}/rootfs"
    if [[ -d "$files_src" && -n "$(ls -A "$files_src")" ]]; then
        log "  Applying files overlay (rootfs/)"
        sudo cp -rf "$files_src"/* "$stage/mnt_rootfs/" 2>/dev/null || true
    fi

    # 5f. mihombreng inject
    # (packages are pre-installed in rootfs during make image, so no raw injection needed)
    :

    # ── Step 6: Unmount + compress ──
    step "[6/6] Unmounting + compressing..."
    sudo umount "${LOOP_DEV}p1" "${LOOP_DEV}p2"
    sudo losetup -d "$LOOP_DEV"
    LOOP_DEV=""

    gzip -9 "$disk_img"

    local out_file="${disk_img}.gz"
    [[ -f "$out_file" ]] || { warn "Failed to create .img.gz"; return 1; }
    ok "Image ready: $(basename "$out_file")"
    echo "$out_file"

    rm -rf "$stage" 2>/dev/null || true
    trap - EXIT
}

# ════════════════════════════════════════════════════════════════
# Kernel Download Backends
# ════════════════════════════════════════════════════════════════

download_kernel() {
    local out="$1"
    local ver="${KERNEL_VERSION:-auto}"

    case "${KERNEL_SOURCE:-ophub}" in
        ophub)        download_kernel_ophub "$out" "$ver" ;;
        armarchindo)  download_kernel_armarchindo "$out" "$ver" ;;
        sib0ndt)      download_kernel_sib0ndt "$out" "$ver" ;;
        stable)       download_kernel_stable "$out" "$ver" ;;
        custom)       download_kernel_custom "$out" ;;
        local)        copy_kernel_local "$out" ;;
        *)
            warn "Unknown kernel source: ${KERNEL_SOURCE}. Falling back to ophub."
            download_kernel_ophub "$out" "$ver"
            ;;
    esac
}

# ── Ophub (default) ──
download_kernel_ophub() {
    local out="$1" ver="${2:-auto}"
    step "  Kernel from ophub (${ver})"

    local release_tag="kernel_stable"
    local tags=""
    if [[ "${ver,,}" == "auto" || "${ver,,}" =~ ^[0-9]+\.[0-9]+\.y$ ]]; then
        tags=$(curl -sL "https://api.github.com/repos/ophub/kernel/releases/tags/kernel_stable" 2>/dev/null \
            | grep -oE '"name": "[^"]+"' || true)
    fi

    if [[ "${ver,,}" == "auto" ]]; then
        # Fetch release tags, fallback to 6.12.95 if rate-limited or fails
        if [[ -n "$tags" ]]; then
            ver=$(echo "$tags" | cut -d'"' -f4 | grep -oE '6\.[0-9]+\.[0-9]+' | sort -V | tail -1 || true)
        fi
        [[ -z "$ver" ]] && ver="6.12.95"
        log "    Auto-selected: ${ver}"
    elif [[ "${ver,,}" =~ ^([0-9]+\.[0-9]+)\.y$ ]]; then
        local branch="${BASH_REMATCH[1]}"
        local resolved=""
        if [[ -n "$tags" ]]; then
            resolved=$(echo "$tags" | cut -d'"' -f4 | grep -oE "${branch//./\\.}\.[0-9]+" | sort -V | tail -1 || true)
        fi
        if [[ -z "$resolved" && "$branch" == "5.4" ]]; then
            release_tag="kernel_flippy"
            tags=$(curl -sL "https://api.github.com/repos/ophub/kernel/releases/tags/${release_tag}" 2>/dev/null \
                | grep -oE '"name": "[^"]+"' || true)
            resolved=$(echo "$tags" | cut -d'"' -f4 | grep -oE '5\.4\.[0-9]+' | sort -V | tail -1 || true)
        fi
        [[ -z "$resolved" ]] && fail "Unable to resolve ophub kernel selector: ${ver}"
        log "    Resolved ${ver} -> ${resolved} (${release_tag})"
        ver="$resolved"
    fi

    # Downloader logic:
    # 1. Download the unified package (e.g. 6.12.95.tar.gz)
    # 2. Extract it to staging
    # 3. Inside it, extract boot-[ver]-ophub.tar.gz, dtb-[family]-[ver]-ophub.tar.gz, and modules-[ver]-ophub.tar.gz
    local base="https://github.com/ophub/kernel/releases/download/${release_tag}"
    local pack_file="${ver}.tar.gz"

    mkdir -p "$out"
    step "    Downloading unified kernel package: ${pack_file}..."
    ariadl "${base}/${pack_file}" "${out}/${pack_file}"

    step "    Extracting unified kernel package..."
    tar -xf "${out}/${pack_file}" -C "$out"
    rm -f "${out}/${pack_file}"

    # Move content of subfolder to root out
    cp -rf "$out/${ver}"/* "$out/"
    rm -rf "$out/${ver}"

    # Now we have three tarballs in $out: e.g. boot-6.12.95-ophub.tar.gz, dtb-amlogic-6.12.95-ophub.tar.gz, modules-6.12.95-ophub.tar.gz
    # Rename them so extract_kernel_tars can find & extract them as usual
    for f in "$out"/*.tar.gz; do
        [[ -f "$f" ]] || continue
        # Rename option to clean name format: e.g. boot-6.12.95-ophub.tar.gz -> boot-6.12.95.tar.gz
        local base_f=$(basename "$f")
        local new_f=$(echo "$base_f" | sed 's/-ophub//')
        mv "$f" "$out/$new_f"
    done

    extract_kernel_tars "$out"
}

# ── Armarchindo ──
download_kernel_armarchindo() {
    local out="$1" ver="${2:-auto}"
    step "  Kernel from armarchindo (${ver})"
    if [[ "${ver,,}" == "auto" ]]; then
        ver="6.1.66-dbai"
        log "    Auto-selected stable: ${ver}"
    fi

    local target_filename="${ver,,}.tar.gz"
    log "    Searching for kernel asset: ${target_filename} in armarchindo/kernel..."
    local api_url="https://api.github.com/repos/armarchindo/kernel/releases"
    local download_url=""
    
    download_url=$(curl -sL "$api_url" | jq -r ".[] | .assets[] | select(.name | ascii_downcase == \"${target_filename}\") | .browser_download_url" 2>/dev/null | head -1)

    if [[ -z "$download_url" || "$download_url" == "null" ]]; then
        # Fallback tebak URL ke tag kernel_dbai biasa
        download_url="https://github.com/armarchindo/kernel/releases/download/kernel_dbai/${ver}.tar.gz"
        log "    API rate limit/error. Trying fallback URL: ${download_url}"
    fi

    mkdir -p "$out"
    local pack_file="armarchindo-kernel-${ver}.tar.gz"

    step "    Downloading unified armarchindo kernel..."
    if ! ariadl "$download_url" "${out}/${pack_file}"; then
        # Jika gagal (karena masalah case-sensitive di url fallback), coba tebak versi aslinya (misal caps DBAI)
        local base_ver="${ver%-dbai}-DBAI"
        [[ "$ver" == *"aw64"* ]] && base_ver="${ver%-aw64-dbai}-AW64-DBAI"
        local fallback_url="https://github.com/armarchindo/kernel/releases/download/kernel_dbai/${base_ver}.tar.gz"
        log "    Retrying with capitalized name: ${fallback_url}"
        ariadl "$fallback_url" "${out}/${pack_file}"
    fi

    step "    Extracting unified kernel package..."
    tar -xf "${out}/${pack_file}" -C "$out"
    rm -f "${out}/${pack_file}"
    extract_kernel_tars "$out"
}

# ── Sib0ndt (custom Amlogic kernel) ──
download_kernel_sib0ndt() {
    local out="$1" ver="${2:-auto}"
    step "  Kernel from sib0ndt (${ver})"
    if [[ "${ver,,}" == "auto" ]]; then
        local tags=$(curl -sL "https://api.github.com/repos/sib0ndt/linux/releases" \
            | grep -oE '"tag_name": "[^"]+"' | cut -d'"' -f4 | grep "kernel-amlogic")
        ver=$(echo "$tags" | head -1)
        ver="${ver:-kernel-amlogic-7.0.0}"
        log "    Auto-selected: ${ver}"
    fi

    local base="https://github.com/sib0ndt/linux/releases/download/${ver}"
    local files=(
        "boot-${ver#kernel-amlogic-}.tar.gz"
        "rootfs-${ver#kernel-amlogic-}.tar.gz"
    )

    mkdir -p "$out"
    for f in "${files[@]}"; do
        ariadl "${base}/${f}" "${out}/${f}" 2>/dev/null || warn "Failed: ${f}"
    done
    extract_kernel_tars "$out"
}

# ── Kernel.org (source only, not prebuilt) ──
download_kernel_stable() {
    local out="$1" ver="${2:-auto}"
    step "  Kernel from kernel.org (${ver})"
    if [[ "${ver,,}" == "auto" ]]; then
        ver=$(curl -sL "https://www.kernel.org/releases.json" \
            | grep -oE '"version": "([0-9]+\.[0-9]+\.?[0-9]*)"' | head -1 | cut -d'"' -f4)
        [[ -z "$ver" ]] && ver="6.12"
        log "    Selected: ${ver}"
    fi
    warn "  kernel.org provides source, not pre-built boot/modules archives."
    warn "  Use ophub, armarchindo, or sib0ndt for Amlogic TV boxes."
}

# ── Custom URL ──
download_kernel_custom() {
    local out="$1"
    if [[ -z "${KERNEL_URL:-}" ]]; then
        warn "KERNEL_URL not set. Skipping."
        return 1
    fi
    mkdir -p "$out"
    ariadl "$KERNEL_URL" "${out}/custom-kernel.tar.gz"
    tar -xzf "${out}/custom-kernel.tar.gz" -C "$out" 2>/dev/null || true
}

# ── Local ──
copy_kernel_local() {
    local out="$1"
    if [[ -z "${KERNEL_DIR:-}" || ! -d "$KERNEL_DIR" ]]; then
        warn "KERNEL_DIR not found: ${KERNEL_DIR:-unset}. Skipping."
        return 1
    fi
    mkdir -p "$out"
    cp -rf "$KERNEL_DIR/." "$out/" 2>/dev/null
}

# ── Extract kernel tarballs ──
extract_kernel_tars() {
    local out="$1"
    cd "$out"
    for f in *.tar.gz *.tar.xz; do
        [[ -f "$f" ]] || continue
        log "    Extracting: $f"
        tar -xf "$f" 2>/dev/null && rm -f "$f"
    done
}

# ════════════════════════════════════════════════════════════════
# Legacy Packing Methods (backward compat)
# ════════════════════════════════════════════════════════════════

# ── REMake (ophub) ──
pack_remake() {
    local stage="$1"
    step "  Legacy pack: ophub remake"
    warn "  remake binary not bundled. rootfs + kernel staged at:"
    warn "    rootfs: ${stage}/mnt_rootfs"
    warn "    kernel: ${stage}/kernel"
    local bundle="${OUT_TVBOX}/hermes-wrt-${OP_DEVICE}-${KERNEL_VERSION}-rootfs.tar.gz"
    cd "$stage/rootfs"
    tar -czf "$bundle" . 2>/dev/null
    ok "  Rootfs ready for remake: $bundle"
}

# ── ULO-style ──
pack_ulo() {
    local stage="$1"
    step "  Legacy pack: ULO-style"
    local bundle="${OUT_TVBOX}/hermes-wrt-${OP_DEVICE}-${KERNEL_VERSION}-rootfs.tar.gz"
    cd "$stage/rootfs"
    tar -czf "$bundle" .
    ok "  Rootfs ready for ULO: $bundle"
}

# ── Custom ──
pack_custom() {
    local stage="$1"
    step "  Custom pack"
    warn "  Rootfs + kernel staged at: ${stage}"
}
