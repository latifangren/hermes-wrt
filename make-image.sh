#!/bin/bash
# make-image.sh — Local build wrapper for Hermes-WRT
# Usage: sudo ./make-image.sh <source:version> <device> <variant>
set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
log()   { echo -e "${GREEN}[INFO]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
fail()  { echo -e "${RED}[ERROR]${NC} $1" >&2; exit 1; }

[[ $EUID -eq 0 ]] || fail "Run as root: sudo ./make-image.sh ..."

SOURCE="${1:-openwrt:24.10.0}"
DEVICE="${2:-s905x3}"
VARIANT="${3:-full}"

# Check deps
for cmd in aria2c curl tar gzip jq make; do
    command -v $cmd &>/dev/null || fail "Missing: $cmd"
done

log "Hermes-WRT Builder"
log "  Source:  $SOURCE"
log "  Device:  $DEVICE"
log "  Variant: $VARIANT"
log "  Config:  hermes.conf (edit to change kernel source)"
echo ""

chmod +x imagebuilder.sh
exec ./imagebuilder.sh "$SOURCE" "$DEVICE" "$VARIANT"
