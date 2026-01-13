#!/bin/bash

set -e

if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root"
   exit 1
fi

echo "=== Recreating Btrfs Swap File Using Native btrfs Command ==="
echo ""

SWAPFILE="/swapfile"
SWAP_SIZE="48G"

echo "Step 1: Removing existing swap file if present..."
if [ -f "$SWAPFILE" ]; then
    swapoff "$SWAPFILE" 2>/dev/null || echo "Swap was not active"
    rm -f "$SWAPFILE"
    echo "✓ Old swapfile removed"
else
    echo "No existing swapfile found"
fi

echo ""
echo "Step 2: Creating swapfile using native Btrfs command..."
echo "This is MUCH faster than dd and handles all Btrfs requirements automatically:"
echo "  - Sets NOCOW attribute"
echo "  - Disables compression"
echo "  - Preallocates space"
echo "  - Formats as swap"
echo ""
echo "Creating ${SWAP_SIZE} swapfile (this should take 5-10 seconds)..."

# Use the native btrfs command which does everything correctly
btrfs filesystem mkswapfile --size "$SWAP_SIZE" "$SWAPFILE"

echo ""
echo "Step 3: Activating swap..."
swapon "$SWAPFILE"

echo ""
echo "Step 4: Verifying..."
if swapon --show | grep -q "$SWAPFILE"; then
    echo "✓ SUCCESS: Swap is now active"
    swapon --show
    echo ""
    ls -lh "$SWAPFILE"
else
    echo "✗ FAILED: Swap could not be activated"
    exit 1
fi

echo ""
echo "=== Swap File Created Successfully ==="
echo ""
echo "IMPORTANT: The swap offset has changed!"
echo "Now run: sudo ./configure-limine.sh"
echo "This will recalculate the new offset and update Limine config."
