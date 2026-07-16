#!/bin/bash
# scripts/INCLUDE.sh — Shared utility functions for Hermes-WRT
set -euo pipefail

# ── Colors ──
PURPLE='\033[95m'; BLUE='\033[94m'; GREEN='\033[92m'
YELLOW='\033[93m'; RED='\033[91m'; RESET='\033[0m'
STEPS="${PURPLE}[STEPS]${RESET}"
INFO="${BLUE}[INFO]${RESET}"
SUCCESS="${GREEN}[SUCCESS]${RESET}"
WARN="${YELLOW}[WARN]${RESET}"
ERROR="${RED}[ERROR]${RESET}"

log()  { echo -e "${INFO} $1"; }
step() { echo -e "\n${STEPS} $1"; }
ok()   { echo -e "${SUCCESS} $1"; }
warn() { echo -e "${WARN} $1"; }
fail() { echo -e "${ERROR} $1" >&2; exit 1; }

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

# ── Check deps ──
check_deps() {
    local deps=("$@")
    for cmd in "${deps[@]}"; do
        command -v "$cmd" &>/dev/null || fail "Missing: $cmd"
    done
    ok "All dependencies satisfied"
}
