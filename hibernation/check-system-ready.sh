#!/bin/bash
# Dry-run script to verify system is ready for hibernation setup
# This checks prerequisites without making any changes

set -e

echo "=== Hibernation Pre-Flight Check ==="
echo "This script verifies your system is ready for hibernation setup"
echo "NO CHANGES will be made to your system"
echo ""

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

PASS_COUNT=0
FAIL_COUNT=0
WARN_COUNT=0

check_pass() {
    echo -e "${GREEN}✓ PASS${NC}: $1"
    ((PASS_COUNT++))
}

check_fail() {
    echo -e "${RED}✗ FAIL${NC}: $1"
    ((FAIL_COUNT++))
}

check_warn() {
    echo -e "${YELLOW}⚠ WARNING${NC}: $1"
    ((WARN_COUNT++))
}

info() {
    echo -e "${BLUE}ℹ INFO${NC}: $1"
}

echo "=== System Requirements ==="
echo ""

echo "Check 1: Root privileges..."
if [[ $EUID -eq 0 ]]; then
    check_fail "Running as root - please run as normal user (script will prompt for sudo when needed)"
    exit 1
else
    check_pass "Running as normal user"
fi

echo ""
echo "Check 2: Bootloader detection..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/bootloader-detect.sh"

BOOTLOADER=$(detect_bootloader)
info "Detected bootloader: $BOOTLOADER"

case "$BOOTLOADER" in
    limine)
        check_pass "Limine bootloader detected"
        if [ -f /etc/default/limine ]; then
            check_pass "Limine config exists at /etc/default/limine"
        fi
        ;;
    grub)
        check_pass "GRUB bootloader detected"
        if [ -f /etc/default/grub ]; then
            check_pass "GRUB config exists at /etc/default/grub"
        fi
        ;;
    systemd-boot)
        check_pass "systemd-boot detected"
        ;;
    unknown)
        check_fail "Could not detect bootloader (checked: GRUB, Limine, systemd-boot)"
        ;;
esac

echo ""
echo "Check 3: Required commands..."
REQUIRED_CMDS="filefrag findmnt swapon mkswap systemctl df awk sed grep"
MISSING_CMDS=""
for cmd in $REQUIRED_CMDS; do
    if ! command -v $cmd &> /dev/null; then
        MISSING_CMDS="$MISSING_CMDS $cmd"
        check_fail "Missing command: $cmd"
    fi
done

if [ -z "$MISSING_CMDS" ]; then
    check_pass "All required commands available"
else
    echo "  Install missing: $MISSING_CMDS"
fi

echo ""
echo "Check 13: Filesystem type..."
FS_TYPE=$(df -T / | awk 'NR==2 {print $2}')
info "Root filesystem: $FS_TYPE"

case "$FS_TYPE" in
    btrfs)
        check_pass "Btrfs detected (supported with CoW disabled)"
        if ! command -v chattr &> /dev/null; then
            check_fail "chattr command not found (needed for Btrfs CoW disable)"
        fi
        ;;
    ext4|xfs)
        check_pass "$FS_TYPE detected (fully supported)"
        ;;
    *)
        check_warn "Filesystem $FS_TYPE - verify hibernation compatibility"
        ;;
esac

echo ""
echo "Check 13: Available disk space..."
ROOT_AVAIL=$(df -BG / | awk 'NR==2 {print $4}' | sed 's/G//')
REQUIRED_SPACE=48
info "Available on root: ${ROOT_AVAIL}GB"
info "Required for swap: ${REQUIRED_SPACE}GB"

if [ "$ROOT_AVAIL" -ge "$REQUIRED_SPACE" ]; then
    check_pass "Sufficient disk space (${ROOT_AVAIL}GB available)"
else
    check_fail "Insufficient disk space - need ${REQUIRED_SPACE}GB, have ${ROOT_AVAIL}GB"
    echo "  Free up space or reduce swap size in setup-hibernation.sh"
fi

echo ""
echo "Check 13: System RAM..."
RAM_GB=$(free -g | grep Mem | awk '{print $2}')
info "Total RAM: ${RAM_GB}GB"

if [ "$RAM_GB" -ge 32 ]; then
    check_pass "RAM: ${RAM_GB}GB (48GB swap recommended)"
elif [ "$RAM_GB" -ge 16 ]; then
    check_warn "RAM: ${RAM_GB}GB - consider adjusting swap size to $(($RAM_GB * 3 / 2))GB"
elif [ "$RAM_GB" -ge 8 ]; then
    check_warn "RAM: ${RAM_GB}GB - adjust swap size to $(($RAM_GB * 2))GB"
else
    check_pass "RAM: ${RAM_GB}GB"
fi

echo ""
echo "Check 13: Existing swap configuration..."
if [ -f /swapfile ]; then
    SWAP_SIZE=$(du -h /swapfile | cut -f1)
    check_warn "Swap file already exists at /swapfile (size: $SWAP_SIZE)"
    echo "  Setup script will offer to recreate it"
    
    if swapon --show | grep -q /swapfile; then
        info "Swap file is currently active"
    else
        info "Swap file exists but not active"
    fi
else
    check_pass "No existing /swapfile (clean setup)"
fi

ZRAM_COUNT=$(swapon --show | grep -c zram || true)
if [ "$ZRAM_COUNT" -gt 0 ]; then
    ZRAM_SIZE=$(swapon --show | grep zram | awk '{print $3}')
    info "zram swap detected ($ZRAM_SIZE) - this is fine, will supplement with /swapfile"
fi

echo ""
echo "Check 13: Bootloader resume configuration..."
CONFIG_FILE=$(get_bootloader_config_file "$BOOTLOADER")

if [ -n "$CONFIG_FILE" ] && [ -f "$CONFIG_FILE" ]; then
    if check_resume_params "$BOOTLOADER"; then
        check_warn "Resume parameters already configured in $BOOTLOADER"
        echo "  Setup script will update them if needed"
    else
        check_pass "$BOOTLOADER config ready for hibernation parameters"
    fi
elif [ "$BOOTLOADER" = "unknown" ]; then
    check_fail "Cannot verify - bootloader not detected"
else
    info "Bootloader config will be created during setup"
fi

echo ""
echo "Check 14: Kernel hibernation support..."
if [ -f /sys/power/state ]; then
    POWER_STATES=$(cat /sys/power/state)
    info "Available power states: $POWER_STATES"
    
    if echo "$POWER_STATES" | grep -q "disk"; then
        check_pass "Kernel supports hibernation (disk state available)"
    else
        check_fail "Kernel does not support hibernation - 'disk' state missing"
    fi
else
    check_fail "/sys/power/state not found - kernel may not support power management"
fi

echo ""
echo "Check 15: Battery monitor script..."
BATTERY_SCRIPT="$HOME/.local/share/omarchy/bin/omarchy-battery-monitor"
if [ -f "$BATTERY_SCRIPT" ]; then
    check_pass "Battery monitor script exists"
    
    if grep -q "systemctl hibernate" "$BATTERY_SCRIPT"; then
        check_warn "Battery monitor already configured for hibernation"
    else
        info "Battery monitor will be updated to trigger hibernation"
    fi
else
    check_warn "Battery monitor script not found at $BATTERY_SCRIPT"
    echo "  You may need to set up hibernation triggers manually"
fi

echo ""
echo "Check 16: Systemd logind..."
if systemctl is-active --quiet systemd-logind; then
    check_pass "systemd-logind is running"
else
    check_warn "systemd-logind is not running"
fi

if [ -f /etc/systemd/logind.conf ]; then
    check_pass "logind.conf exists (can be configured for hibernate button)"
else
    check_warn "logind.conf not found"
fi

echo ""
echo "Check 13: Root partition UUID..."
ROOT_UUID=$(findmnt -n -o UUID / 2>/dev/null || echo "")
if [ -n "$ROOT_UUID" ]; then
    check_pass "Root UUID detected: $ROOT_UUID"
else
    check_fail "Could not detect root partition UUID"
fi

echo ""
echo "Check 13: Backup directories..."
if [ -d /root ]; then
    if [ -w /root ] || sudo -n test -w /root 2>/dev/null; then
        check_pass "Can write to /root for backup files"
    else
        info "/root directory exists (will need sudo for backups)"
    fi
else
    check_fail "/root directory not found"
fi

echo ""
echo "=== Pre-Flight Check Summary ==="
echo ""
echo "Results:"
echo "  ✓ Passed:   $PASS_COUNT"
echo "  ⚠ Warnings: $WARN_COUNT"
echo "  ✗ Failed:   $FAIL_COUNT"
echo ""

if [ $FAIL_COUNT -eq 0 ]; then
    echo -e "${GREEN}✓ System is ready for hibernation setup!${NC}"
    echo ""
    echo "Next steps:"
    echo "  1. Run: sudo ./install-hibernation.sh    (automated full setup)"
    echo "  2. Or follow manual steps in README.md"
    exit 0
elif [ $FAIL_COUNT -le 2 ]; then
    echo -e "${YELLOW}⚠ System has minor issues but may work${NC}"
    echo ""
    echo "Review the failures above and decide if you want to proceed"
    echo "Some issues may be acceptable depending on your system"
    exit 1
else
    echo -e "${RED}✗ System is NOT ready for hibernation setup${NC}"
    echo ""
    echo "Please fix the failures above before proceeding"
    echo "Common fixes:"
    echo "  - Free up disk space: df -h /"
    echo "  - Install missing packages: sudo pacman -S <package>"
    echo "  - Check kernel config: zcat /proc/config.gz | grep CONFIG_HIBERNATION"
    exit 2
fi
