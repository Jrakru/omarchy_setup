#!/bin/bash

set -e

if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root"
   exit 1
fi

echo "=== Fixing Btrfs Swap File ==="
echo ""

SWAPFILE="/swapfile"

if [ ! -f "$SWAPFILE" ]; then
    echo "ERROR: $SWAPFILE does not exist"
    exit 1
fi

echo "Step 1: Disable any active swap..."
swapoff "$SWAPFILE" 2>/dev/null || echo "Swap was not active"

echo ""
echo "Step 2: Ensure Btrfs properties are correct..."
echo "Disabling compression..."
btrfs property set "$SWAPFILE" compression none

echo "Verifying CoW is disabled..."
lsattr "$SWAPFILE" | grep -q 'C' && echo "✓ CoW is disabled" || {
    echo "Disabling CoW..."
    chattr +C "$SWAPFILE"
}

echo ""
echo "Step 3: Recreating swap signature..."
mkswap "$SWAPFILE"

echo ""
echo "Step 4: Activating swap..."
swapon "$SWAPFILE"

echo ""
echo "Step 5: Verifying..."
if swapon --show | grep -q "$SWAPFILE"; then
    echo "✓ SUCCESS: Swap is now active"
    swapon --show | grep "$SWAPFILE"
else
    echo "✗ FAILED: Swap could not be activated"
    exit 1
fi

echo ""
echo "=== Swap File Fixed ==="
echo ""
echo "Now run: sudo ./configure-limine.sh"
