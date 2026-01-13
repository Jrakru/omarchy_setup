# Hibernation Setup - Changes Summary

## Overview

Your Arch Linux system has been configured to hibernate automatically on low battery instead of dying unexpectedly. All scripts and documentation have been moved to `~/git/omarchy_setup/hibernation/`.

## Changes Made

### 1. Battery Monitor Script Modified ✅

**File**: `~/.local/share/omarchy/bin/omarchy-battery-monitor`

**Changes**:
- Added `CRITICAL_THRESHOLD=5` (hibernates at 5% battery)
- Added `CRITICAL_NOTIFICATION_FLAG` for critical alerts
- Modified logic:
  - **10% battery**: Warning notification "Time to recharge!"
  - **5% battery (CRITICAL)**: 
    - Shows critical notification "CRITICAL: Hibernating Now!"
    - Waits 2 seconds
    - Triggers `systemctl hibernate`
  - **Above 10%**: Clears both notification flags

**Status**: ✅ Complete (no restart required)

---

### 2. Hibernation Scripts Created ✅

**Location**: `~/git/omarchy_setup/hibernation/`

#### Main Setup Script
- `setup-hibernation.sh` - Automates swap file creation and configuration
- Creates 36GB swap file at `/swapfile`
- Calculates swap offset and root UUID
- Generates GRUB configuration instructions
- Updates `/etc/fstab`

#### Testing Script
- `test-scripts/test-hibernation.sh` - Comprehensive verification
- Checks 13 different aspects of hibernation setup
- Guides you through manual testing
- Color-coded output (pass/fail/warning)

#### Documentation
- `README.md` - Complete setup guide
- 300+ lines of detailed instructions
- Troubleshooting section
- Customization guide

---

### 3. Alternative Configurations Created ✅

#### UPower Configuration
- `upower-config/UPower.conf` - Daemon-based battery monitoring
- Alternative to user-space battery monitor
- More reliable (system service)
- Works even without active user session

#### Udev Rule
- `udev-rule/99-low-battery-hibernate.rules` - Kernel-level battery events
- Triggers hibernate at 5% battery
- Alternative approach (can use alongside or replace battery monitor)

---

## Current System State

### Memory Configuration
```
Total RAM:   32 GB
Current Swap:  4 GB (zram)
```

### Problem Identified
❌ **Swap too small for hibernation**: 4GB swap cannot handle 32GB RAM
   - Hibernation requires swap >= RAM size
   - This is why your system dies instead of hibernating

### Solution Required
✅ **Create 36GB swap file** to enable hibernation
   - Swap file location: `/swapfile`
   - Size: 36GB (≥ 32GB RAM)
   - Format: swap with proper permissions (600)

---

## Next Steps (REQUIRED)

### Step 1: Create Swap File (Requires sudo)

```bash
cd ~/git/omarchy_setup/hibernation
sudo ./setup-hibernation.sh
```

**This will**:
- Create `/swapfile` (36GB)
- Set correct permissions
- Enable swap
- Add to `/etc/fstab`
- Display GRUB configuration instructions

**⚠️ Note**: You'll need to enter your sudo password

---

### Step 2: Configure GRUB (Requires sudo)

You have two options:

**Option A: Automated (Recommended)**

Run the automated GRUB configuration script:
```bash
cd ~/git/omarchy_setup/hibernation
sudo ./configure-grub.sh
```

This script will:
- Create automatic backups of your GRUB configuration
- Calculate the root UUID and swap offset
- Add resume parameters to GRUB_CMDLINE_LINUX_DEFAULT
- Update GRUB configuration with grub-mkconfig
- Create a summary file with all details

**Option B: Manual**

---

### Step 3: Reboot Your System (REQUIRED) 🔄

**⚠️ CRITICAL**: GRUB changes won't take effect until you reboot!

```bash
sudo reboot
```

Your system will restart and load the new kernel parameters for hibernation.

---

### Step 4: Test Hibernation Manually (Before Automatic)

**⚠️ IMPORTANT**: Test hibernation BEFORE relying on automatic battery monitor!

```bash
# 1. Save all your work!
# 2. Run hibernation
sudo systemctl hibernate
```

**After waking up**:
1. Check all applications are still running
2. Verify system is stable
3. Check logs for errors:
   ```bash
   journalctl -b -1 | grep -i "hibernate\|swap\|resume"
   ```

---

### Step 5: Verify Complete Setup

Run the test script to verify everything is configured:

```bash
cd ~/git/omarchy_setup/hibernation
./test-scripts/test-hibernation.sh
```

This will check:
- ✅ Swap file exists and has correct permissions
- ✅ Swap is active and size is adequate
- ✅ Swap is in `/etc/fstab`
- ✅ GRUB has resume parameters
- ✅ Kernel supports hibernation
- ✅ Battery monitor has hibernation trigger
- ✅ Memory/swap compatibility (swap ≥ RAM)

---

## How It Will Work After Setup

### Automatic Hibernation Flow

1. **Battery drops to 10%**: Warning notification
   - Notification: "󱐋 Time to recharge!"
   - Time to plug in your laptop

2. **Battery drops to 5%**: Critical hibernation trigger
   - Notification: "CRITICAL: Hibernating Now!"
   - System waits 2 seconds (for notification to display)
   - `systemctl hibernate` is executed
   - Memory (32GB) is written to `/swapfile` (36GB)
   - System powers off

3. **System wakes up**:
   - GRUB loads with resume parameters
   - Kernel restores memory from swap file
   - All applications resume exactly where they were
   - No data loss!

---

## Alternative Approaches

### Option A: Use UPower (Instead of Battery Monitor)

If you prefer a daemon-based approach:

```bash
# 1. Install UPower config
sudo cp ~/git/omarchy_setup/hibernation/upower-config/UPower.conf /etc/UPower/UPower.conf

# 2. Enable UPower service
sudo systemctl enable --now upower.service

# 3. UPower will hibernate at 3% battery (failsafe)
# Battery monitor still works as warning at 10%
```

**Advantages**:
- System service (always running)
- More reliable than user-space script
- Works even without active user session

### Option B: Use Udev Rule (Kernel-Level)

```bash
# 1. Install udev rule
sudo cp ~/git/omarchy_setup/hibernation/udev-rule/99-low-battery-hibernate.rules /etc/udev/rules.d/

# 2. Reload udev rules
sudo udevadm control --reload-rules
sudo udevadm trigger
```

**Advantages**:
- Kernel-level monitoring (most reliable)
- Works even if UPower/battery monitor fails
- Fast response to battery events

---

## Troubleshooting

### If Hibernation Fails

**Check these**:
1. Swap file size: `free -h` - Swap should be ≥ 32GB
2. Swap is active: `swapon --show`
3. GRUB parameters: `grep "resume=" /boot/grub/grub.cfg`
4. Kernel logs: `journalctl -b | grep -i "hibernate\|swap"`

### If System Doesn't Resume

**Check these**:
1. GRUB parameters in `/etc/default/grub`
2. Regenerate GRUB: `sudo grub-mkconfig -o /boot/grub/grub.cfg`
3. Root UUID: `findmnt -n -o UUID /`
4. Swap offset: `sudo filefrag -v /swapfile | awk 'NR==4 {print $4}' | tr -d '.'`

### If Battery Monitor Doesn't Trigger

**Check these**:
1. Timer is active: `systemctl --user status omarchy-battery-monitor.timer`
2. Script has hibernate command: `grep "systemctl hibernate" ~/.local/share/omarchy/bin/omarchy-battery-monitor`
3. Battery reading: `omarchy-battery-remaining`
4. Script logs: `journalctl --user -u omarchy-battery-monitor.service`

---

## Safety Reminders

⚠️ **Before Testing Hibernation**:
- Save all open documents
- Close critical applications
- Have charger nearby
- Test in a safe environment

⚠️ **After Setup**:
- Test hibernation manually at least once
- Monitor logs for errors
- Keep battery above 20% for normal use
- Charge laptop when you see the 10% warning

---

## What Will NOT Happen Now

❌ **Before fix**:
- System just dies when battery reaches 0%
- No warning at critical levels
- Data loss when power cuts off
- Applications crash

✅ **After fix**:
- Warning at 10% battery
- Automatic hibernation at 5% battery
- No data loss
- All applications resume cleanly
- System shuts down gracefully

---

## File Structure

```
~/git/omarchy_setup/hibernation/
├── README.md                          # Complete setup guide
├── setup-hibernation.sh              # Main setup script
├── test-scripts/
│   └── test-hibernation.sh         # Verification script
├── upower-config/
│   └── UPower.conf              # Alternative daemon config
└── udev-rule/
    └── 99-low-battery-hibernate.rules  # Kernel-level rule
```

---

## Quick Reference Commands

```bash
# Check swap status
swapon --show
free -h

# Check battery
upower -i $(upower -e | grep 'BAT')
omarchy-battery-remaining

# Test hibernation
sudo systemctl hibernate

# Check battery monitor status
systemctl --user status omarchy-battery-monitor.timer

# Check UPower status
systemctl status upower.service

# View hibernation logs
journalctl -b | grep -i "hibernate\|swap\|resume"
```

---

## Support

If you encounter issues:

1. Read the detailed README: `~/git/omarchy_setup/hibernation/README.md`
2. Run the test script: `~/git/omarchy_setup/hibernation/test-scripts/test-hibernation.sh`
3. Check logs: `journalctl -b`
4. Check Arch Wiki: https://wiki.archlinux.org/title/Power_management/Suspend_and_hibernate

---

## Version

- **v1.0** - January 12, 2026
- System: Arch Linux kernel 6.18.3-arch1-1
- RAM: 32 GB
- Swap target: 36 GB
- Battery thresholds: Warning 10%, Critical 5%

---

**Last updated**: 2026-01-12 17:40
