#!/bin/bash
# GRUB Configuration Script for Hibernation
# This script safely configures GRUB to support hibernation with swap file
# It creates backups before making any modifications

set -e  # Exit on error

echo "=== GRUB Hibernation Configuration Script ==="
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
GRUB_CONFIG="/etc/default/grub"
GRUB_BACKUP_DIR="/root/grub-backups"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
GRUB_BACKUP="${GRUB_BACKUP_DIR}/grub-${TIMESTAMP}.bak"

# Step 1: Check if GRUB config exists
echo "Step 1: Checking GRUB configuration..."
if [ ! -f "$GRUB_CONFIG" ]; then
    error "GRUB configuration file not found at $GRUB_CONFIG"
fi

info "GRUB config found: $GRUB_CONFIG"

# Step 2: Create backup directory
echo ""
echo "Step 2: Creating backup directory..."
mkdir -p "$GRUB_BACKUP_DIR"
success "Backup directory created: $GRUB_BACKUP_DIR"

# Step 3: Create backup of original GRUB config
echo ""
echo "Step 3: Creating backup of current GRUB configuration..."
cp "$GRUB_CONFIG" "$GRUB_BACKUP"
success "Backup created: $GRUB_BACKUP"

# Also create a simpler backup without timestamp for easy access
cp "$GRUB_CONFIG" "${GRUB_BACKUP_DIR}/grub-last-backup.bak"
success "Easy-access backup: ${GRUB_BACKUP_DIR}/grub-last-backup.bak"

# Step 4: Check if swap file exists
echo ""
echo "Step 4: Checking for swap file..."
if [ ! -f /swapfile ]; then
    warning "Swap file not found at /swapfile"
    echo "You may need to run setup-hibernation.sh first"
    echo ""
    read -p "Continue anyway? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        info "Exiting. Please run setup-hibernation.sh first to create swap file."
        exit 0
    fi
fi

# Step 5: Get root partition UUID
echo ""
echo "Step 5: Getting root partition UUID..."
ROOT_UUID=$(findmnt -n -o UUID /)
if [ -z "$ROOT_UUID" ]; then
    error "Could not find root partition UUID"
fi
success "Root UUID: $ROOT_UUID"

# Step 6: Get swap file offset
echo ""
echo "Step 6: Calculating swap file offset..."
if [ -f /swapfile ]; then
    if command -v filefrag &> /dev/null; then
        SWAP_OFFSET=$(filefrag -v /swapfile 2>/dev/null | awk 'NR==4 {print $4}' | tr -d '.')
        if [ -n "$SWAP_OFFSET" ]; then
            success "Swap offset: $SWAP_OFFSET"
        else
            error "Could not calculate swap offset"
        fi
    else
        error "filefrag command not found. Cannot calculate swap offset."
    fi
else
    error "Swap file not found at /swapfile"
fi

# Step 7: Check if resume parameters already exist
echo ""
echo "Step 7: Checking existing GRUB configuration..."
if grep -q "resume=" "$GRUB_CONFIG"; then
    warning "Resume parameters already configured in GRUB"
    echo ""
    grep "resume=" "$GRUB_CONFIG" | grep -o 'resume=[^"]*'
    echo ""
    read -p "Do you want to replace existing configuration? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        info "Keeping existing configuration. Exiting."
        exit 0
    fi
fi

# Step 8: Analyze current GRUB_CMDLINE_LINUX_DEFAULT
echo ""
echo "Step 8: Analyzing current GRUB configuration..."
GRUB_CMDLINE=""
if grep -q '^GRUB_CMDLINE_LINUX_DEFAULT=' "$GRUB_CONFIG"; then
    GRUB_CMDLINE=$(grep '^GRUB_CMDLINE_LINUX_DEFAULT=' "$GRUB_CONFIG" | sed "s/^GRUB_CMDLINE_LINUX_DEFAULT='//" | sed "s/'$//")
    info "Found existing GRUB_CMDLINE_LINUX_DEFAULT"
    echo "  Current: $GRUB_CMDLINE"
elif grep -q '^GRUB_CMDLINE_LINUX="' "$GRUB_CONFIG"; then
    # Handle quoted version without DEFAULT
    GRUB_CMDLINE=$(grep '^GRUB_CMDLINE_LINUX="' "$GRUB_CONFIG" | sed "s/^GRUB_CMDLINE_LINUX='//" | sed "s/'$//")
    info "Found existing GRUB_CMDLINE_LINUX"
    echo "  Current: $GRUB_CMDLINE"
else
    warning "GRUB_CMDLINE_LINUX_DEFAULT not found in $GRUB_CONFIG"
    echo "This is unusual. The file may have a different structure."
    echo ""
    echo "Current file contents:"
    cat "$GRUB_CONFIG"
    read -p "Continue anyway? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        info "Exiting. Please check your GRUB configuration manually."
        exit 1
    fi
fi

# Step 9: Remove existing resume parameters if present
echo ""
echo "Step 9: Preparing to add resume parameters..."
if echo "$GRUB_CMDLINE" | grep -q "resume="; then
    info "Removing existing resume parameters from GRUB config..."
    # Create a sed command to remove resume parameters
    GRUB_CMDLINE=$(echo "$GRUB_CMDLINE" | sed -E 's/resume=[^[:space:]]+//g' | sed -E 's/[[:space:]]+resume=[^[:space:]]+//g')
    success "Old resume parameters removed"
else
    info "No existing resume parameters found"
fi

# Step 10: Add resume parameters
echo ""
echo "Step 10: Adding resume parameters to GRUB configuration..."

# Prepare the new resume string
RESUME_STRING="resume=UUID=$ROOT_UUID resume_offset=$SWAP_OFFSET"

# Check if GRUB_CMDLINE is empty
if [ -z "$GRUB_CMDLINE" ]; then
    # No existing config, create new
    GRUB_CMDLINE="$RESUME_STRING"
    info "Created new GRUB_CMDLINE_LINUX_DEFAULT with resume parameters"
else
    # Append to existing config
    GRUB_CMDLINE="$GRUB_CMDLINE $RESUME_STRING"
    info "Appended resume parameters to existing configuration"
fi

success "Resume parameters added: $RESUME_STRING"

# Step 11: Backup the modified config before writing
echo ""
echo "Step 11: Creating backup of modified configuration..."
MODIFIED_BACKUP="${GRUB_BACKUP_DIR}/grub-modified-${TIMESTAMP}.bak"
cp "$GRUB_CONFIG" "$MODIFIED_BACKUP"
success "Pre-modification backup: $MODIFIED_BACKUP"

# Step 12: Write new configuration
echo ""
echo "Step 12: Writing new GRUB configuration..."
# Determine which variable name to use
if grep -q '^GRUB_CMDLINE_LINUX_DEFAULT=' "$GRUB_CONFIG"; then
    # Use DEFAULT version
    cp "$GRUB_CONFIG" "${GRUB_CONFIG}.new"
    sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT=\"$GRUB_CMDLINE\"|g" "${GRUB_CONFIG}.new"
    mv "${GRUB_CONFIG}.new" "$GRUB_CONFIG"
elif grep -q '^GRUB_CMDLINE_LINUX="' "$GRUB_CONFIG"; then
    # Use non-DEFAULT version
    cp "$GRUB_CONFIG" "${GRUB_CONFIG}.new"
    sed -i "s|^GRUB_CMDLINE_LINUX=.*|GRUB_CMDLINE_LINUX=\"$GRUB_CMDLINE\"|g" "${GRUB_CONFIG}.new"
    mv "${GRUB_CONFIG}.new" "$GRUB_CONFIG"
else
    # Add the line
    cp "$GRUB_CONFIG" "${GRUB_CONFIG}.new"
    sed -i "\$a\\GRUB_CMDLINE_LINUX_DEFAULT=\"$GRUB_CMDLINE\"" "${GRUB_CONFIG}.new"
    mv "${GRUB_CONFIG}.new" "$GRUB_CONFIG"
fi

success "New GRUB configuration written to $GRUB_CONFIG"

# Step 13: Display configuration comparison
echo ""
echo "Step 13: Configuration comparison..."
echo ""
echo "--- Original (from backup) ---"
grep "^GRUB_CMDLINE" "$GRUB_BACKUP" | head -5
echo ""
echo "--- New configuration ---"
grep "^GRUB_CMDLINE" "$GRUB_CONFIG" | head -5
echo ""

# Step 14: Update GRUB
echo ""
echo "Step 14: Updating GRUB configuration..."
read -p "Do you want to update GRUB now? (Y/n): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Nn]$ ]]; then
    if command -v grub-mkconfig &> /dev/null; then
        grub-mkconfig -o /boot/grub/grub.cfg
        success "GRUB configuration updated successfully!"
        info "New GRUB config: /boot/grub/grub.cfg"
    else
        error "grub-mkconfig command not found"
    fi
    
    # Check if GRUB binary exists
    echo ""
    if [ -f /boot/grub/grub.cfg ]; then
        success "GRUB config file exists at /boot/grub/grub.cfg"
        if grep -q "resume=" /boot/grub/grub.cfg; then
            echo ""
            grep "resume=" /boot/grub/grub.cfg | head -3
            
            echo ""
            info "Verifying resume offset in generated GRUB config..."
            GRUB_ACTUAL_OFFSET=$(grep -oP 'resume_offset=\K[0-9]+' /boot/grub/grub.cfg | head -1)
            if [ -n "$GRUB_ACTUAL_OFFSET" ]; then
                if [ "$GRUB_ACTUAL_OFFSET" = "$SWAP_OFFSET" ]; then
                    success "Resume offset verified: $GRUB_ACTUAL_OFFSET matches expected $SWAP_OFFSET"
                else
                    error "Resume offset mismatch! Expected: $SWAP_OFFSET, Found in grub.cfg: $GRUB_ACTUAL_OFFSET"
                fi
            else
                warning "Could not extract resume_offset from grub.cfg for verification"
            fi
        fi
    else
        warning "GRUB config file not found at /boot/grub/grub.cfg"
    fi
else
    warning "Skipping GRUB update. You can update it later with:"
    echo "  sudo grub-mkconfig -o /boot/grub/grub.cfg"
fi

# Step 15: Create summary file
echo ""
echo "Step 15: Creating configuration summary..."
SUMMARY_FILE="/root/grub-configuration-summary.txt"
cat > "$SUMMARY_FILE" <<EOF
GRUB HIBERNATION CONFIGURATION SUMMARY
========================================

Date: $(date)
System: omarchy

CONFIGURATION DETAILS
--------------------
Root Partition UUID: $ROOT_UUID
Swap File: /swapfile
Swap Offset: $SWAP_OFFSET

Resume Parameters: resume=UUID=$ROOT_UUID resume_offset=$SWAP_OFFSET

BACKUP FILES
-------------
Original Configuration: $GRUB_BACKUP
Easy-Access Backup: ${GRUB_BACKUP_DIR}/grub-last-backup.bak
Pre-Modification Backup: $MODIFIED_BACKUP

Modified Configuration: $GRUB_CONFIG
Generated GRUB Config: /boot/grub/grub.cfg

NEXT STEPS
-----------
1. Review the comparison above to ensure it looks correct
2. If you haven't rebooted yet, reboot your system:
   sudo reboot

3. After reboot, test hibernation:
   sudo systemctl hibernate

4. Verify hibernation works correctly

TO RESTORE ORIGINAL CONFIGURATION
---------------------------------
If you need to restore the original GRUB configuration:

sudo cp $GRUB_BACKUP $GRUB_CONFIG
sudo grub-mkconfig -o /boot/grub/grub.cfg

Or use the easy-access backup:

sudo cp ${GRUB_BACKUP_DIR}/grub-last-backup.bak $GRUB_CONFIG
sudo grub-mkconfig -o /boot/grub/grub.cfg

TESTING HIBERNATION
-----------------
After reboot, test hibernation manually:

1. Save all your work
2. Run: sudo systemctl hibernate
3. System should power off and write memory to /swapfile
4. Power on the system
5. System should resume exactly where it was
6. Verify all applications are still running

TROUBLESHOOTING
----------------
If hibernation doesn't work:

1. Check swap file: ls -l /swapfile
2. Check swap is active: swapon --show
3. Check GRUB params: grep "resume=" /boot/grub/grub.cfg
4. Check kernel logs: journalctl -b | grep -i "hibernate"

FILES CREATED
------------
EOF

success "Summary file created: $SUMMARY_FILE"

# Display summary
echo ""
echo "=== Configuration Summary ==="
echo ""
echo "✅ GRUB configuration updated successfully!"
echo ""
echo "Configuration details:"
echo "  Root UUID: $ROOT_UUID"
echo "  Swap offset: $SWAP_OFFSET"
echo "  Resume params: resume=UUID=$ROOT_UUID resume_offset=$SWAP_OFFSET"
echo ""
echo "Backup locations:"
echo "  Original: $GRUB_BACKUP"
echo "  Easy access: ${GRUB_BACKUP_DIR}/grub-last-backup.bak"
echo "  Pre-modification: $MODIFIED_BACKUP"
echo ""
echo "Documentation:"
echo "  Summary: $SUMMARY_FILE"
echo ""
echo "📋 Next steps:"
echo "1. Review the configuration summary: cat $SUMMARY_FILE"
echo "2. REBOOT your system: sudo reboot"
echo "3. Test hibernation: sudo systemctl hibernate"
echo ""
echo "⚠️  IMPORTANT: You must reboot for GRUB changes to take effect!"
echo ""
echo "=== Script Complete ==="
