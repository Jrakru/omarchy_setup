#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/bootloader-detect.sh"

echo "=== Hibernation Setup Script ==="
echo "This will configure your system for hibernation on low battery"
echo ""

SWAP_FILE="/swapfile"
SWAP_SIZE="48G"

if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root (use sudo)"
   exit 1
fi

BOOTLOADER=$(detect_bootloader)
echo "Detected bootloader: $BOOTLOADER"
echo ""

# Step 1: Check if swap file already exists
echo "Step 1: Checking existing swap configuration..."
if [ -f "$SWAP_FILE" ]; then
    echo "Swap file already exists at $SWAP_FILE"
    read -p "Do you want to recreate it? This will remove the existing one. (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "Disabling existing swap file..."
        swapoff "$SWAP_FILE" 2>/dev/null || true
        echo "Removing existing swap file..."
        rm -f "$SWAP_FILE"
    else
        echo "Keeping existing swap file"
    fi
fi

# Step 2: Detect filesystem type
echo "Step 2: Detecting filesystem type..."
FS_TYPE=$(df -T / | awk 'NR==2 {print $2}')
echo "Root filesystem: $FS_TYPE"

# Step 3: Create swap file if it doesn't exist
if [ ! -f "$SWAP_FILE" ]; then
    echo "Step 3: Creating swap file ($SWAP_SIZE)..."
    
    if [ "$FS_TYPE" = "btrfs" ]; then
        echo "Btrfs detected: Using dd to prevent fragmentation..."
        SWAP_SIZE_MB=$(echo "$SWAP_SIZE" | sed 's/G//' | awk '{print $1 * 1024}')
        dd if=/dev/zero of="$SWAP_FILE" bs=1M count="$SWAP_SIZE_MB" status=progress
        
        echo "Disabling Copy-on-Write for swap file..."
        chattr +C "$SWAP_FILE"
        
        echo "Disabling compression for swap file..."
        btrfs property set "$SWAP_FILE" compression none
    else
        echo "Using fallocate for fast allocation..."
        fallocate -l "$SWAP_SIZE" "$SWAP_FILE"
    fi
    
    chmod 600 "$SWAP_FILE"
    mkswap "$SWAP_FILE"
    echo "Swap file created successfully"
else
    echo "Using existing swap file"
fi

# Step 4: Enable swap
echo "Step 4: Enabling swap file..."
swapon "$SWAP_FILE" 2>/dev/null || echo "Swap may already be enabled"
echo "Current swap usage:"
swapon --show

# Step 5: Add to /etc/fstab
echo "Step 5: Updating /etc/fstab..."
if ! grep -q "$SWAP_FILE" /etc/fstab; then
    echo "$SWAP_FILE none swap defaults 0 0" >> /etc/fstab
    echo "Added swap file to /etc/fstab"
else
    echo "Swap file already in /etc/fstab"
fi

# Step 6: Get root partition UUID
echo "Step 6: Getting root partition UUID..."
ROOT_UUID=$(findmnt -n -o UUID /)
echo "Root UUID: $ROOT_UUID"

# Step 7: Get swap file offset
echo "Step 7: Calculating swap file offset..."
SWAP_OFFSET=$(filefrag -v "$SWAP_FILE" | awk 'NR==4 {print $4}' | tr -d '.')
echo "Swap offset: $SWAP_OFFSET"

# Step 8: Create configuration info
echo ""
echo "=== Configuration Summary ==="
echo "Swap file: $SWAP_FILE"
echo "Root UUID: $ROOT_UUID"
echo "Swap offset: $SWAP_OFFSET"
echo ""

echo ""

CONFIGURE_SCRIPT=$(get_configure_script "$BOOTLOADER")
CONFIGURE_SCRIPT_NAME=$(basename "$CONFIGURE_SCRIPT" 2>/dev/null || echo "configure-bootloader.sh")

echo "Step 8: Creating next steps instructions..."
cat > /root/hibernation-next-steps.txt <<EOF
HIBERNATION CONFIGURATION - NEXT STEPS
=======================================

Detected bootloader: $BOOTLOADER

Configuration values:
- Root UUID: $ROOT_UUID
- Swap file: $SWAP_FILE ($SWAP_SIZE)
- Swap offset: $SWAP_OFFSET

Resume parameters to be added:
  resume=UUID=$ROOT_UUID
  resume_offset=$SWAP_OFFSET

NEXT STEPS:
-----------

1. Configure your bootloader to enable hibernation:

   Run: sudo ./configure-bootloader.sh

   (This will automatically detect and configure $BOOTLOADER)

   Or run the bootloader-specific script:
   Run: sudo ./$CONFIGURE_SCRIPT_NAME

2. Reboot your system for changes to take effect:

   Run: sudo reboot

3. Test hibernation after reboot:

   Run: sudo systemctl hibernate

4. Verify the configuration:

   Run: ./test-scripts/test-hibernation.sh

MANUAL CONFIGURATION (if needed):
----------------------------------

EOF

case "$BOOTLOADER" in
    limine)
        cat >> /root/hibernation-next-steps.txt <<'EOF'
For Limine with UKI:
1. Edit /etc/default/limine
2. Add after the KERNEL_CMDLINE[default] line:
   KERNEL_CMDLINE[default]+=" resume=UUID=$ROOT_UUID resume_offset=$SWAP_OFFSET"
3. Rebuild UKI: sudo limine-update
4. Reboot
EOF
        ;;
    grub)
        cat >> /root/hibernation-next-steps.txt <<'EOF'
For GRUB:
1. Edit /etc/default/grub
2. Find: GRUB_CMDLINE_LINUX_DEFAULT="..."
3. Add inside quotes: resume=UUID=$ROOT_UUID resume_offset=$SWAP_OFFSET
4. Update GRUB: sudo grub-mkconfig -o /boot/grub/grub.cfg
5. Reboot
EOF
        ;;
    systemd-boot)
        cat >> /root/hibernation-next-steps.txt <<'EOF'
For systemd-boot:
1. Edit boot entries in /boot/loader/entries/*.conf
2. Add to options line: resume=UUID=$ROOT_UUID resume_offset=$SWAP_OFFSET
3. Reboot
EOF
        ;;
    *)
        cat >> /root/hibernation-next-steps.txt <<'EOF'
Bootloader not detected or unknown.
Please add these kernel parameters manually:
  resume=UUID=$ROOT_UUID
  resume_offset=$SWAP_OFFSET
EOF
        ;;
esac

sed -i "s/\$ROOT_UUID/$ROOT_UUID/g" /root/hibernation-next-steps.txt
sed -i "s/\$SWAP_OFFSET/$SWAP_OFFSET/g" /root/hibernation-next-steps.txt
sed -i "s/\$SWAP_FILE/$SWAP_FILE/g" /root/hibernation-next-steps.txt
sed -i "s/\$SWAP_SIZE/$SWAP_SIZE/g" /root/hibernation-next-steps.txt
sed -i "s/\$BOOTLOADER/$BOOTLOADER/g" /root/hibernation-next-steps.txt
sed -i "s/\$CONFIGURE_SCRIPT_NAME/$CONFIGURE_SCRIPT_NAME/g" /root/hibernation-next-steps.txt

echo ""
echo "✅ Swap file setup complete!"
echo ""
echo "📋 Next steps:"
echo "1. Configure bootloader: sudo ./configure-bootloader.sh"
echo "2. Reboot your system: sudo reboot"
echo "3. Test hibernation: sudo systemctl hibernate"
echo "4. Verify setup: ./test-scripts/test-hibernation.sh"
echo ""
echo "⚠️  IMPORTANT: You must configure bootloader and reboot for hibernation to work!"
echo ""
echo "Detailed instructions saved to: /root/hibernation-next-steps.txt"
echo ""

cat /root/hibernation-next-steps.txt

echo ""
echo "=== Setup Complete ==="
