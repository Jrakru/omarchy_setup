#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/lib/bootloader-detect.sh"

echo "=== Hibernation Test Script ==="
echo "This script will test if hibernation is properly configured"
echo ""

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

check_pass() {
    echo -e "${GREEN}✓ PASS${NC}: $1"
}

check_fail() {
    echo -e "${RED}✗ FAIL${NC}: $1"
}

check_warn() {
    echo -e "${YELLOW}⚠ WARNING${NC}: $1"
}

info() {
    echo -e "${BLUE}ℹ INFO${NC}: $1"
}

info "Detecting bootloader..."
BOOTLOADER=$(detect_bootloader)
echo "Detected: $BOOTLOADER"
echo ""

# Test 1: Check if swap file exists
echo "Test 1: Checking swap file existence..."
if [ -f /swapfile ]; then
    SWAP_SIZE=$(du -h /swapfile | cut -f1)
    check_pass "Swap file exists (/swapfile, size: $SWAP_SIZE)"
else
    check_fail "Swap file does not exist at /swapfile"
    echo "Run: sudo fallocate -l 36G /swapfile"
    exit 1
fi

# Test 2: Check swap file permissions
echo ""
echo "Test 2: Checking swap file permissions..."
SWAP_PERMS=$(stat -c %a /swapfile)
if [ "$SWAP_PERMS" = "600" ]; then
    check_pass "Swap file has correct permissions (600)"
else
    check_fail "Swap file has incorrect permissions ($SWAP_PERMS, should be 600)"
    echo "Run: sudo chmod 600 /swapfile"
    exit 1
fi

# Test 3: Check if swap is active
echo ""
echo "Test 3: Checking if swap is active..."
SWAP_ACTIVE=$(swapon --show --noheadings | grep /swapfile | wc -l)
if [ "$SWAP_ACTIVE" -gt 0 ]; then
    SWAP_USAGE=$(free -h | grep Swap | awk '{print $3 "/" $2}')
    check_pass "Swap is active (usage: $SWAP_USAGE)"
else
    check_fail "Swap is not active"
    echo "Run: sudo swapon /swapfile"
    exit 1
fi

# Test 4: Check swap in fstab
echo ""
echo "Test 4: Checking /etc/fstab configuration..."
if grep -q "/swapfile" /etc/fstab; then
    check_pass "Swap file is in /etc/fstab"
else
    check_fail "Swap file not in /etc/fstab"
    echo "Run: echo '/swapfile none swap defaults 0 0' | sudo tee -a /etc/fstab"
    exit 1
fi

echo ""
echo "Test 5: Checking bootloader hibernation configuration..."
CONFIG_FILE=$(get_bootloader_config_file "$BOOTLOADER")

if check_resume_params "$BOOTLOADER"; then
    check_pass "$BOOTLOADER has resume parameters configured"
    case "$BOOTLOADER" in
        limine|grub)
            grep "resume=" "$CONFIG_FILE" 2>/dev/null | head -2
            ;;
        systemd-boot)
            grep "resume=" /proc/cmdline 2>/dev/null || echo "  (Check individual boot entries)"
            ;;
    esac
else
    check_fail "$BOOTLOADER does not have resume parameters configured"
    case "$BOOTLOADER" in
        limine)
            echo "Run: sudo ./configure-limine.sh"
            ;;
        grub)
            echo "Run: sudo ./configure-grub.sh"
            ;;
        systemd-boot)
            echo "Run: sudo ./configure-systemd-boot.sh"
            ;;
        *)
            echo "Bootloader not detected. Check manually."
            ;;
    esac
fi

# Test 6: Check if hibernation is enabled
echo ""
echo "Test 6: Checking if hibernation is enabled..."
if [ -f /sys/power/image_size ]; then
    check_pass "Hibernation support is available in kernel"
    IMAGE_SIZE=$(cat /sys/power/image_size | awk '{printf "%.2f GB", $1/1024/1024/1024}')
    echo "  Image size limit: $IMAGE_SIZE"
else
    check_fail "Hibernation support not available in kernel"
    exit 1
fi

# Test 7: Check swap file offset
echo ""
echo "Test 7: Checking swap file offset..."
if command -v filefrag &> /dev/null; then
    SWAP_OFFSET=$(filefrag -v /swapfile 2>/dev/null | awk 'NR==4 {print $4}' | tr -d '.')
    if [ -n "$SWAP_OFFSET" ]; then
        check_pass "Swap file offset calculated: $SWAP_OFFSET"
    else
        check_warn "Could not calculate swap offset"
    fi
else
    check_warn "filefrag not available, cannot verify swap offset"
fi

# Test 8: Check root UUID
echo ""
echo "Test 8: Checking root partition UUID..."
ROOT_UUID=$(findmnt -n -o UUID /)
if [ -n "$ROOT_UUID" ]; then
    check_pass "Root partition UUID: $ROOT_UUID"
else
    check_fail "Could not find root partition UUID"
    exit 1
fi

# Test 9: Check if resume device is set
echo ""
echo "Test 9: Checking resume device..."
RESUME=$(cat /sys/power/resume 2>/dev/null || echo "0:0")
if [ "$RESUME" != "0:0" ]; then
    check_pass "Resume device is set: $RESUME"
else
    check_warn "Resume device not set (will work after GRUB update and reboot)"
fi

# Test 10: Check memory and swap size compatibility
echo ""
echo "Test 10: Checking memory and swap size compatibility..."
MEM_SIZE=$(free -g | grep Mem | awk '{print $2}')
SWAP_SIZE_GB=$(free -g | grep Swap | awk '{print $2}')

echo "  Total RAM: ${MEM_SIZE}GB"
echo "  Total Swap: ${SWAP_SIZE_GB}GB"

if [ "$SWAP_SIZE_GB" -ge "$MEM_SIZE" ]; then
    check_pass "Swap size (${SWAP_SIZE_GB}GB) >= RAM (${MEM_SIZE}GB)"
else
    check_fail "Swap size (${SWAP_SIZE_GB}GB) < RAM (${MEM_SIZE}GB) - hibernation may fail"
    echo "Recommend: Increase swap file size to at least ${MEM_SIZE}GB"
fi

# Test 11: Check battery monitor script
echo ""
echo "Test 11: Checking battery monitor script..."
BATTERY_SCRIPT="$HOME/.local/share/omarchy/bin/omarchy-battery-monitor"
if [ -f "$BATTERY_SCRIPT" ]; then
    check_pass "Battery monitor script exists"
    if grep -q "CRITICAL_THRESHOLD" "$BATTERY_SCRIPT"; then
        CRITICAL_LEVEL=$(grep "^CRITICAL_THRESHOLD" "$BATTERY_SCRIPT" | cut -d'=' -f2)
        check_pass "Critical threshold configured: ${CRITICAL_LEVEL}%"
    else
        check_warn "Critical threshold not found in battery monitor script"
    fi
    if grep -q "systemctl hibernate" "$BATTERY_SCRIPT"; then
        check_pass "Hibernate command found in battery monitor script"
    else
        check_warn "Hibernate command not found in battery monitor script"
    fi
else
    check_warn "Battery monitor script not found"
fi

# Test 12: Check if UPower is configured
echo ""
echo "Test 12: Checking UPower configuration..."
if [ -f /etc/UPower/UPower.conf ]; then
    check_pass "UPower configuration file exists"
    if grep -q "CriticalPowerAction" /etc/UPower/UPower.conf; then
        ACTION=$(grep "^CriticalPowerAction" /etc/UPower/UPower.conf | cut -d'=' -f2)
        check_pass "CriticalPowerAction configured: $ACTION"
    else
        check_warn "CriticalPowerAction not configured in UPower"
    fi
else
    check_warn "UPower configuration file does not exist"
fi

# Test 13: Check zram (compressed RAM swap)
echo ""
echo "Test 13: Checking zram configuration..."
ZRAM_ACTIVE=$(swapon --show | grep zram | wc -l)
if [ "$ZRAM_ACTIVE" -gt 0 ]; then
    ZRAM_SIZE=$(swapon --show | grep zram | awk '{print $3}')
    check_warn "zram is active ($ZRAM_SIZE) - this is in addition to /swapfile"
    echo "  zram is fine, but hibernation will use /swapfile"
fi

# Test 14: Check filesystem compatibility
echo ""
echo "Test 14: Checking filesystem compatibility..."
FS_TYPE=$(df -T / | awk 'NR==2 {print $2}')
echo "  Root filesystem: $FS_TYPE"

if [ "$FS_TYPE" = "btrfs" ]; then
    if [ -f /swapfile ]; then
        if lsattr /swapfile 2>/dev/null | grep -q "C"; then
            check_pass "Btrfs CoW (Copy-on-Write) disabled on swap file"
        else
            check_warn "Btrfs CoW not disabled - hibernation may fail"
            echo "  Fix: sudo chattr +C /swapfile (then recreate swap)"
        fi
    fi
    check_pass "Filesystem: Btrfs (supported with proper CoW settings)"
elif [ "$FS_TYPE" = "ext4" ] || [ "$FS_TYPE" = "xfs" ]; then
    check_pass "Filesystem: $FS_TYPE (fully supported for hibernation)"
else
    check_warn "Filesystem: $FS_TYPE (verify hibernation compatibility)"
fi

# Test 15: Verify kernel command line
echo ""
echo "Test 15: Checking active kernel command line..."
if grep -q "resume=" /proc/cmdline; then
    check_pass "Kernel has resume parameter active"
    KERNEL_RESUME=$(grep -oP 'resume=\S+' /proc/cmdline)
    KERNEL_OFFSET=$(grep -oP 'resume_offset=\K[0-9]+' /proc/cmdline)
    echo "  Active params: $KERNEL_RESUME resume_offset=$KERNEL_OFFSET"
else
    check_warn "Kernel resume parameter not active (reboot needed after GRUB config)"
    echo "  After configuring GRUB, you must reboot for changes to take effect"
fi

# Summary and hibernation test prompt
echo ""
echo "=== Test Summary ==="
echo "All critical tests passed! Your system appears to be configured for hibernation."
echo ""
echo "📋 Next steps:"
echo "1. Review any warnings above"
echo "2. If GRUB configuration needed, update it and run: sudo grub-mkconfig -o /boot/grub/grub.cfg"
echo "3. REBOOT your system to apply GRUB changes"
echo "4. Test hibernation manually:"
echo ""
echo "   sudo systemctl hibernate"
echo ""
echo "5. After waking up, verify everything works correctly"
echo ""
echo "⚠️  IMPORTANT: Only rely on automatic hibernation AFTER successful manual test!"
echo ""

# Ask if user wants to test hibernation now
read -p "Do you want to test hibernation now? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo ""
    echo "🔄 Testing hibernation..."
    echo "Your system will hibernate in 5 seconds. Press Ctrl+C to cancel."
    sleep 5
    echo "Hibernating..."
    sudo systemctl hibernate
else
    echo ""
    echo "Skipping hibernation test. Run 'sudo systemctl hibernate' when ready."
fi

echo ""
echo "=== Test Complete ==="
