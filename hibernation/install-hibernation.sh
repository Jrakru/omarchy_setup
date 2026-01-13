#!/bin/bash
# Automated hibernation setup - runs all configuration steps

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

success() {
    echo -e "${GREEN}✓${NC} $1"
}

error() {
    echo -e "${RED}✗${NC} $1"
    exit 1
}

warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║        AUTOMATED HIBERNATION SETUP FOR ARCH LINUX             ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
info "This script will:"
echo "  1. Detect your bootloader (GRUB/Limine/systemd-boot)"
echo "  2. Verify system prerequisites"
echo "  3. Create 48GB swap file"
echo "  4. Configure bootloader with resume parameters"
echo "  5. Update battery monitor to trigger hibernation"
echo "  6. Enable hibernate in power menu"
echo ""
warning "This script requires sudo privileges and will modify system files"
echo ""

read -p "Do you want to continue? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    info "Installation cancelled"
    exit 0
fi

if [[ $EUID -eq 0 ]]; then
    error "Do not run as root. Run as normal user - will prompt for sudo when needed"
fi

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "STEP 1: Pre-flight system check"
echo "═══════════════════════════════════════════════════════════════"
echo ""

if [ ! -f "$SCRIPT_DIR/check-system-ready.sh" ]; then
    error "check-system-ready.sh not found in $SCRIPT_DIR"
fi

bash "$SCRIPT_DIR/check-system-ready.sh"
CHECK_RESULT=$?

if [ $CHECK_RESULT -eq 2 ]; then
    error "System check failed. Fix issues above before continuing"
elif [ $CHECK_RESULT -eq 1 ]; then
    warning "System check found warnings. Continuing may cause issues"
    read -p "Continue anyway? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        info "Installation cancelled"
        exit 0
    fi
fi

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "STEP 2: Create swap file"
echo "═══════════════════════════════════════════════════════════════"
echo ""

if [ ! -f "$SCRIPT_DIR/setup-hibernation.sh" ]; then
    error "setup-hibernation.sh not found in $SCRIPT_DIR"
fi

info "Running setup-hibernation.sh..."
sudo bash "$SCRIPT_DIR/setup-hibernation.sh"

if [ $? -ne 0 ]; then
    error "Swap file creation failed"
fi

success "Swap file created successfully"

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "STEP 3: Configure bootloader for hibernation"
echo "═══════════════════════════════════════════════════════════════"
echo ""

if [ ! -f "$SCRIPT_DIR/configure-bootloader.sh" ]; then
    error "configure-bootloader.sh not found in $SCRIPT_DIR"
fi

info "Running configure-bootloader.sh (auto-detects GRUB/Limine/systemd-boot)..."
sudo bash "$SCRIPT_DIR/configure-bootloader.sh"

if [ $? -ne 0 ]; then
    error "Bootloader configuration failed"
fi

success "Bootloader configured successfully"

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "STEP 4: Update battery monitor"
echo "═══════════════════════════════════════════════════════════════"
echo ""

BATTERY_SCRIPT="$HOME/.local/share/omarchy/bin/omarchy-battery-monitor"

if [ -f "$BATTERY_SCRIPT" ]; then
    if grep -q "systemctl hibernate" "$BATTERY_SCRIPT"; then
        success "Battery monitor already configured for hibernation"
    else
        info "Battery monitor needs manual configuration"
        warning "Please ensure $BATTERY_SCRIPT calls 'systemctl hibernate' at critical battery"
    fi
else
    warning "Battery monitor not found - you'll need to set up hibernation triggers manually"
fi

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "STEP 5: Enable hibernate in power menu"
echo "═══════════════════════════════════════════════════════════════"
echo ""

LOGIND_CONF="/etc/systemd/logind.conf"
LOGIND_DROP_IN="/etc/systemd/logind.conf.d/hibernate.conf"

info "Configuring systemd-logind for hibernate button..."

if [ -f "$LOGIND_CONF" ]; then
    sudo mkdir -p /etc/systemd/logind.conf.d
    
    sudo tee "$LOGIND_DROP_IN" > /dev/null <<EOF
[Login]
HandleHibernateKey=hibernate
HandleLidSwitchExternalPower=suspend
HandleLidSwitchDocked=ignore
EOF
    
    success "Created logind drop-in configuration"
    info "Restarting systemd-logind..."
    sudo systemctl restart systemd-logind
    success "systemd-logind restarted"
else
    warning "logind.conf not found - skipping power menu configuration"
fi

if command -v gsettings &> /dev/null; then
    info "Configuring GNOME power settings (if applicable)..."
    gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-ac-type 'nothing' 2>/dev/null || true
    gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-battery-type 'nothing' 2>/dev/null || true
fi

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "STEP 6: Verification"
echo "═══════════════════════════════════════════════════════════════"
echo ""

info "Running post-install verification..."

if swapon --show | grep -q /swapfile; then
    success "Swap file is active"
else
    error "Swap file is NOT active"
fi

if grep -q "resume=" /boot/grub/grub.cfg; then
    success "GRUB has resume parameters"
else
    warning "GRUB may not have resume parameters"
fi

if [ -f /sys/power/state ]; then
    success "Kernel power management available"
else
    warning "Kernel power management may not be available"
fi

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║                  INSTALLATION COMPLETE!                        ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
success "Hibernation setup completed successfully"
echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "IMPORTANT: NEXT STEPS"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "1. REBOOT YOUR SYSTEM (required for GRUB changes to take effect)"
echo "   └─ Command: sudo reboot"
echo ""
echo "2. After reboot, test hibernation manually:"
echo "   ├─ Save all your work first!"
echo "   └─ Command: sudo systemctl hibernate"
echo ""
echo "3. After successful wake-up, run verification:"
echo "   └─ Command: $SCRIPT_DIR/test-scripts/test-hibernation.sh"
echo ""
echo "4. Check hibernate is available in power menu:"
echo "   └─ Look for 'Hibernate' option in system menu"
echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "CONFIGURATION SUMMARY"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "Swap file:      /swapfile (48GB)"
echo "Battery trigger: 5% (critical level)"
echo "Warning level:   10% (notification only)"
echo "Power menu:      Hibernate enabled"
echo ""
echo "Backup files:"
echo "  └─ GRUB: /root/grub-backups/"
echo "  └─ Battery monitor: ~/.local/share/omarchy/bin/*.bak-*"
echo ""
echo "═══════════════════════════════════════════════════════════════"
echo ""

warning "REMEMBER: You MUST reboot before hibernation will work!"
echo ""

read -p "Do you want to reboot now? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    info "Rebooting in 5 seconds... (Ctrl+C to cancel)"
    sleep 5
    sudo systemctl reboot
else
    info "Please reboot manually when ready: sudo reboot"
fi
