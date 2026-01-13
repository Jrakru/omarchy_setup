#!/bin/bash
# Limine + UKI Configuration Script for Hibernation
# This script safely configures Limine to support hibernation with swap file
# It creates backups before making any modifications

set -e  # Exit on error

echo "=== Limine Hibernation Configuration Script ==="
echo ""

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

info() {
    echo -e "${BLUE}ℹ INFO${NC}: $1"
}

success() {
    echo -e "${GREEN}✓ SUCCESS${NC}: $1"
}

warning() {
    echo -e "${YELLOW}⚠ WARNING${NC}: $1"
}

error() {
    echo -e "${RED}✗ ERROR${NC}: $1"
    exit 1
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    error "This script must be run as root (use sudo)"
fi

# Configuration files
LIMINE_CONFIG="/etc/default/limine"
LIMINE_BACKUP_DIR="/root/limine-backups"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
LIMINE_BACKUP="${LIMINE_BACKUP_DIR}/limine-${TIMESTAMP}.bak"

# Step 1: Check if Limine config exists
echo "Step 1: Checking Limine configuration..."
if [ ! -f "$LIMINE_CONFIG" ]; then
    error "Limine configuration file not found at $LIMINE_CONFIG"
fi
success "Limine configuration file found"

# Step 2: Check if swap file exists
echo ""
echo "Step 2: Verifying swap file..."
SWAPFILE="/swapfile"
if [ ! -f "$SWAPFILE" ]; then
    error "Swap file not found at $SWAPFILE. Run setup-hibernation.sh first!"
fi
success "Swap file exists"

# Step 3: Get root UUID
echo ""
echo "Step 3: Getting root partition UUID..."
ROOT_UUID=$(findmnt -no UUID /)
if [ -z "$ROOT_UUID" ]; then
    error "Could not determine root partition UUID"
fi
info "Root UUID: $ROOT_UUID"

# Step 4: Calculate swap offset
echo ""
echo "Step 4: Calculating swap file offset..."
info "This may take a moment for large swap files..."

# Get the physical offset of the swap file
SWAP_OFFSET=$(filefrag -v "$SWAPFILE" 2>/dev/null | awk 'NR==4 {gsub(/\.\./,"",$4); print $4}')

if [ -z "$SWAP_OFFSET" ]; then
    error "Could not determine swap file offset"
fi
info "Swap offset: $SWAP_OFFSET"

# Step 5: Create backup directory
echo ""
echo "Step 5: Creating backup..."
mkdir -p "$LIMINE_BACKUP_DIR"
cp "$LIMINE_CONFIG" "$LIMINE_BACKUP"
success "Backup created: $LIMINE_BACKUP"

# Step 6: Check if resume parameters already exist
echo ""
echo "Step 6: Checking for existing resume parameters..."
if grep -q "resume=UUID=" "$LIMINE_CONFIG"; then
    warning "Resume parameters already exist in Limine config"
    read -p "Do you want to update them? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        info "Keeping existing configuration. Exiting."
        exit 0
    fi
    # Remove existing resume parameters
    sed -i '/resume=UUID=/d' "$LIMINE_CONFIG"
    sed -i '/resume_offset=/d' "$LIMINE_CONFIG"
    info "Removed old resume parameters"
fi

# Step 7: Add resume parameters to kernel command line
echo ""
echo "Step 7: Adding resume parameters to kernel command line..."

# Find the KERNEL_CMDLINE[default] line and add resume parameters on the next line
sed -i "/^KERNEL_CMDLINE\[default\]=/a KERNEL_CMDLINE[default]+=\" resume=UUID=$ROOT_UUID resume_offset=$SWAP_OFFSET\"" "$LIMINE_CONFIG"

success "Resume parameters added to Limine configuration"

# Step 8: Rebuild UKI
echo ""
echo "Step 8: Rebuilding UKI with new kernel parameters..."
if command -v limine-update &>/dev/null; then
    limine-update
    success "UKI rebuilt successfully"
else
    error "limine-update command not found. Cannot rebuild UKI."
fi

# Step 9: Verify the changes
echo ""
echo "Step 9: Verifying configuration..."
if grep -q "resume=UUID=$ROOT_UUID" "$LIMINE_CONFIG" && grep -q "resume_offset=$SWAP_OFFSET" "$LIMINE_CONFIG"; then
    success "Resume parameters verified in config file"
else
    error "Resume parameters not found in config file after modification"
fi

# Step 10: Check if swap is active
echo ""
echo "Step 10: Checking swap status..."
if swapon --show | grep -q "$SWAPFILE"; then
    success "Swap file is already active"
else
    info "Swap file exists but not active"
    info "Attempting to activate swap file..."
    if swapon "$SWAPFILE" 2>&1; then
        success "Swap file activated"
    else
        warning "Could not activate swap file automatically"
        echo "  This may happen if:"
        echo "  - Swap was active during setup and needs to be re-enabled after reboot"
        echo "  - The swap signature needs to be recreated"
        echo ""
        echo "  After rebooting, verify with: swapon --show"
        echo "  If swap still not active, run: sudo swapon $SWAPFILE"
    fi
fi

# Step 11: Create summary file
echo ""
echo "Step 11: Creating configuration summary..."
SUMMARY_FILE="/root/hibernation-limine-summary.txt"
cat > "$SUMMARY_FILE" << EOF
Hibernation Configuration Summary
Generated: $(date)
==================================

Root UUID: $ROOT_UUID
Swap File: $SWAPFILE
Swap Offset: $SWAP_OFFSET

Limine Configuration:
  Config file: $LIMINE_CONFIG
  Backup: $LIMINE_BACKUP

Resume Parameters Added:
  resume=UUID=$ROOT_UUID
  resume_offset=$SWAP_OFFSET

Next Steps:
1. REBOOT your system for changes to take effect
2. After reboot, test hibernation with: sudo systemctl hibernate
3. Verify with: ./test-scripts/test-hibernation.sh

To verify kernel parameters after reboot:
  cat /proc/cmdline | grep resume

Rollback Instructions (if needed):
  sudo cp $LIMINE_BACKUP $LIMINE_CONFIG
  sudo limine-update
  sudo reboot
EOF

success "Summary saved to: $SUMMARY_FILE"

# Final output
echo ""
echo "╔════════════════════════════════════════════════════════╗"
echo "║           Configuration Complete!                      ║"
echo "╚════════════════════════════════════════════════════════╝"
echo ""
success "Hibernation has been configured successfully"
echo ""
echo "IMPORTANT NEXT STEPS:"
echo "1. REBOOT your system now"
echo "2. After reboot, verify with: cat /proc/cmdline | grep resume"
echo "3. Test hibernation: sudo systemctl hibernate"
echo "4. Run test script: ./test-scripts/test-hibernation.sh"
echo ""
echo "Configuration details saved to: $SUMMARY_FILE"
echo ""
