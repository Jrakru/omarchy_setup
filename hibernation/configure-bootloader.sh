#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/bootloader-detect.sh"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info() {
    echo -e "${BLUE}ℹ INFO${NC}: $1"
}

error() {
    echo -e "${RED}✗ ERROR${NC}: $1"
    exit 1
}

echo "=== Bootloader Configuration Dispatcher ==="
echo ""

if [[ $EUID -ne 0 ]]; then
    error "This script must be run as root (use sudo)"
fi

info "Detecting bootloader..."
BOOTLOADER=$(detect_bootloader)
echo -e "${GREEN}Detected: $BOOTLOADER${NC}"
echo ""

CONFIGURE_SCRIPT=$(get_configure_script "$BOOTLOADER")

if [ -z "$CONFIGURE_SCRIPT" ] || [ ! -f "$CONFIGURE_SCRIPT" ]; then
    error "No configuration script found for $BOOTLOADER"
fi

info "Using configuration script: $(basename "$CONFIGURE_SCRIPT")"
echo ""
echo "========================================"
echo ""

exec "$CONFIGURE_SCRIPT" "$@"
