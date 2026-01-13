#!/bin/bash
# Enable hibernate option in power menu
# This configures systemd-logind to handle hibernate requests

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info() { echo -e "${BLUE}ℹ${NC} $1"; }
success() { echo -e "${GREEN}✓${NC} $1"; }
error() { echo -e "${RED}✗${NC} $1"; exit 1; }
warning() { echo -e "${YELLOW}⚠${NC} $1"; }

echo "=== Enable Hibernate in Power Menu ==="
echo ""

if [[ $EUID -ne 0 ]]; then
    error "This script must be run as root (use sudo)"
fi

LOGIND_DROP_IN_DIR="/etc/systemd/logind.conf.d"
LOGIND_DROP_IN="$LOGIND_DROP_IN_DIR/hibernate.conf"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_CONF="$SCRIPT_DIR/hibernate.conf"

echo "Step 1: Checking systemd-logind..."
if systemctl is-active --quiet systemd-logind; then
    success "systemd-logind is running"
else
    warning "systemd-logind is not running"
    info "Starting systemd-logind..."
    systemctl start systemd-logind
fi

echo ""
echo "Step 2: Creating logind drop-in configuration..."

mkdir -p "$LOGIND_DROP_IN_DIR"
success "Drop-in directory exists: $LOGIND_DROP_IN_DIR"

if [ -f "$SOURCE_CONF" ]; then
    cp "$SOURCE_CONF" "$LOGIND_DROP_IN"
    success "Installed hibernate.conf"
else
    info "Creating hibernate.conf from template..."
    cat > "$LOGIND_DROP_IN" <<EOF
[Login]

HandleHibernateKey=hibernate

HandleLidSwitchExternalPower=suspend

HandleLidSwitchDocked=ignore
EOF
    success "Created hibernate.conf"
fi

echo ""
info "Configuration details:"
cat "$LOGIND_DROP_IN"

echo ""
echo "Step 3: Restarting systemd-logind..."
systemctl restart systemd-logind
success "systemd-logind restarted"

echo ""
echo "Step 4: Verifying configuration..."
if [ -f "$LOGIND_DROP_IN" ]; then
    success "Drop-in configuration installed at $LOGIND_DROP_IN"
else
    error "Drop-in configuration not found"
fi

echo ""
success "Hibernate is now enabled in power menu!"
echo ""
info "What this configures:"
echo "  • Hibernate key/button → triggers hibernation"
echo "  • Lid close (on external power) → suspend"
echo "  • Lid close (docked) → no action"
echo ""
info "To test:"
echo "  1. Check your desktop environment's power menu for 'Hibernate' option"
echo "  2. Or run: systemctl hibernate"
echo ""
warning "Note: Hibernation must be properly configured (swap + GRUB) first!"
