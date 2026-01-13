# Hibernation Setup for Arch Linux

## Overview

This setup configures your Arch Linux system to hibernate automatically when the battery reaches critically low levels (5%), preventing data loss when the battery completely dies.

## Problem Solved

Your system was experiencing:
- **Insufficient swap space**: Only 4GB zram swap with 32GB RAM
- **No hibernation trigger**: Battery monitor only sent notifications
- **System dies**: When battery reached 0%, system powered off without hibernation

## Solution Components

1. **Automatic bootloader detection** - Supports GRUB, Limine, and systemd-boot
2. **Swap file creation** (48GB) - 1.5x RAM for optimal hibernation reliability
3. **Battery monitor enhancement** - Triggers hibernate at 5% battery  
4. **Bootloader configuration** - Kernel parameters for resume from swap
5. **Power menu integration** - Hibernate option in system power menu
6. **Testing scripts** - Verify configuration before relying on it

## Pre-Requisites

- Arch Linux system
- Root/sudo access
- At least 48GB free disk space on root partition
- Battery-powered laptop

## Bootloader Support

This hibernation setup **automatically detects** and configures your bootloader:

| Bootloader | Status | Detection Method |
|------------|--------|------------------|
| **Limine** | ✅ Fully Supported | `/etc/default/limine` exists |
| **GRUB** | ✅ Fully Supported | `/etc/default/grub` exists |
| **systemd-boot** | ⚠️ Partial | `bootctl status` succeeds |

All scripts detect your bootloader and use the correct configuration method automatically.

## Quick Start (Automated)

**Recommended**: Use the automated installer

```bash
cd ~/git/omarchy_setup/hibernation

# 1. Check if your system is ready (dry-run, no changes)
./check-system-ready.sh

# 2. Run the automated installer (does everything for you)
sudo ./install-hibernation.sh

# 3. Reboot (required for bootloader changes)
sudo reboot

# 4. After reboot, test hibernation
sudo systemctl hibernate

# 5. Verify everything works
./test-scripts/test-hibernation.sh
```

## Quick Start (Manual)

If you prefer step-by-step control:

```bash
cd ~/git/omarchy_setup/hibernation

# 1. Check system prerequisites
./check-system-ready.sh

# 2. Create swap file
sudo ./setup-hibernation.sh

# 3. Configure bootloader (auto-detects GRUB/Limine/systemd-boot)
sudo ./configure-bootloader.sh

# 4. Enable hibernate in power menu
sudo ./logind-config/enable-hibernate-menu.sh

# 5. Reboot your system
sudo reboot

# 6. Test hibernation
sudo systemctl hibernate

# 7. Run the test script to verify everything
./test-scripts/test-hibernation.sh
```

## Available Scripts

| Script | Purpose | Requires Root |
|--------|---------|---------------|
| `check-system-ready.sh` | Pre-flight check (dry-run, no changes) | No |
| `install-hibernation.sh` | **Automated full setup** (recommended) | Yes |
| `setup-hibernation.sh` | Create swap file only | Yes |
| `configure-bootloader.sh` | **Auto-detect and configure bootloader** | Yes |
| `configure-grub.sh` | Configure GRUB only (legacy) | Yes |
| `configure-limine.sh` | Configure Limine only | Yes |
| `logind-config/enable-hibernate-menu.sh` | Add hibernate to power menu | Yes |
| `test-scripts/test-hibernation.sh` | Verify configuration (15+ tests) | No |

## Detailed Setup Instructions

### Step 1: Run Setup Script

The setup script automates:
- Creating a 48GB swap file at `/swapfile`
- Setting correct permissions (600)
- Adding to `/etc/fstab`
- Calculating swap offset and root UUID
- Creating GRUB configuration instructions

```bash
sudo ./setup-hibernation.sh
```

### Step 2: Configure Bootloader

The system automatically detects your bootloader (GRUB, Limine, or systemd-boot):

```bash
cd ~/git/omarchy_setup/hibernation
sudo ./configure-bootloader.sh
```

This script will:
- Detect which bootloader you're using
- Create automatic backups of your configuration
- Calculate the root UUID and swap offset
- Add resume parameters to the bootloader configuration
- Rebuild boot images (UKI for Limine, grub.cfg for GRUB)
- Create a summary file with all details

**For manual configuration:**
- GRUB users: `sudo ./configure-grub.sh`
- Limine users: `sudo ./configure-limine.sh`
- systemd-boot users: `sudo ./configure-systemd-boot.sh` (if available)


### Step 3: Enable Hibernate in Power Menu

Make hibernate accessible from your system's power menu:

```bash
cd ~/git/omarchy_setup/hibernation
sudo ./logind-config/enable-hibernate-menu.sh
```

This configures systemd-logind to:
- Add "Hibernate" option to power menus
- Handle hibernate button/key presses
- Configure lid switch behavior

### Step 4: Reboot

**This is critical!** The GRUB changes won't take effect until you reboot:

```bash
sudo reboot
```

### Step 5: Test Hibernation

Before relying on automatic hibernation, test it manually:

```bash
# Save your work first!
sudo systemctl hibernate
```

After waking up:
1. Check that all your applications are still running
2. Verify system stability
3. Check for any error messages with:
   ```bash
   journalctl -b -1 | grep -i "hibernate\|swap\|resume"
   ```

### Step 6: Verify Configuration

Run the test script to ensure everything is configured correctly:

```bash
cd ~/git/omarchy_setup/hibernation
./test-scripts/test-hibernation.sh
```

This will check:
- Swap file existence and permissions
- Swap activation status
- /etc/fstab configuration
- GRUB hibernation parameters
- Kernel hibernation support
- Memory/swap size compatibility
- Battery monitor script configuration
- UPower configuration (if present)
- Filesystem compatibility (Btrfs CoW check)
- Active kernel command line parameters

## How to Use Hibernate

### Battery Monitor Logic

The modified battery monitor script (`~/.local/share/omarchy/bin/omarchy-battery-monitor`) now:

1. **10% battery**: Shows warning notification "Time to recharge!"
2. **5% battery (CRITICAL)**: 
   - Shows critical notification "CRITICAL: Hibernating Now!"
   - Waits 2 seconds for notification to display
   - Triggers `systemctl hibernate`
3. **Above 10%**: Clears all notification flags

### Hibernation Process

When `systemctl hibernate` is triggered:

1. **System state snapshot**: Current memory contents (32GB) are written to swap file
2. **Power off**: System powers down completely
3. **Resume**: On boot, GRUB parameters tell kernel to restore from swap file
4. **Restore**: Memory contents are read back, system resumes exactly where it left off

### Why Swap File Must Be Large

Hibernation writes your **entire RAM** to disk. If swap is too small:
- Hibernation fails
- System may crash or refuse to hibernate
- You lose data when battery dies

## Troubleshooting

### Hibernation Fails

**Symptoms**: System freezes, shows error, or just suspends instead

**Solutions**:
1. Check swap size: `free -h` - Swap should be ≥ RAM size
2. Check swap is active: `swapon --show`
3. Check GRUB parameters: `grep "resume=" /boot/grub/grub.cfg`
4. Check kernel logs: `journalctl -b | grep -i "hibernate\|swap"`

### System Won't Resume

**Symptoms**: System boots normally instead of resuming

**Solutions**:
1. Verify GRUB parameters are correct in `/etc/default/grub`
2. Regenerate GRUB: `sudo grub-mkconfig -o /boot/grub/grub.cfg`
3. Check `/boot/grub/grub.cfg` contains resume parameters
4. Verify root UUID: `findmnt -n -o UUID /`
5. Verify swap offset: `sudo filefrag -v /swapfile | awk 'NR==4 {print $4}' | tr -d '.'`

### Battery Monitor Not Triggering

**Symptoms**: System dies at 0% without hibernating

**Solutions**:
1. Check battery monitor is running: `systemctl --user status omarchy-battery-monitor.timer`
2. Check script has hibernate command: `grep "systemctl hibernate" ~/.local/share/omarchy/bin/omarchy-battery-monitor`
3. Check battery level reading: `omarchy-battery-remaining`
4. Check timer is active: `systemctl --user list-timers --all | grep battery`
5. Check script logs: `journalctl --user -u omarchy-battery-monitor.service`

### Swap File Not Created

**Symptoms**: "No space left on device" or permission errors

**Solutions**:
1. Check available space: `df -h /` - Need at least 48GB free
2. Check filesystem: `df -T /` - Must support swap files (Btrfs, XFS, ext4)
3. For Btrfs, you may need:
   ```bash
   sudo chattr +C /swapfile  # Disable copy-on-write
   sudo btrfs property set / compression none
   ```

### GRUB Not Updating

**Symptoms**: Changes to `/etc/default/grub` don't take effect

**Solutions**:
1. Regenerate GRUB config: `sudo grub-mkconfig -o /boot/grub/grub.cfg`
2. Check bootloader location: `sudo fdisk -l | grep EFI` or `sudo fdisk -l | grep BIOS`
3. For EFI systems, verify EFI partition is mounted at `/boot`

## Configuration Files

### Modified Files

- `~/.local/share/omarchy/bin/omarchy-battery-monitor` - Added hibernation trigger
- `/etc/fstab` - Added swap file entry
- `/etc/default/grub` - Added resume parameters

### New Files

- `/swapfile` - 36GB swap file for hibernation
- `/root/hibernation-grub-instructions.txt` - GRUB configuration details

### Scripts

- `setup-hibernation.sh` - Automated setup script
- `test-scripts/test-hibernation.sh` - Verification and testing script

## Customization

### Change Critical Battery Level

Edit `~/.local/share/omarchy/bin/omarchy-battery-monitor`:

```bash
CRITICAL_THRESHOLD=5  # Change to your preferred percentage
```

### Change Warning Level

Edit the same file:

```bash
BATTERY_THRESHOLD=10  # Warning notification level
```

### Adjust Swap File Size

In `setup-hibernation.sh`, change:
```bash
SWAP_SIZE="48G"  # Must be >= 1.5x your RAM size for reliability
```

## Safety Precautions

1. **Test before relying**: Always test hibernation manually first
2. **Save work**: Before testing, save all open documents
3. **Backup important data**: Have backups in case of unexpected behavior
4. **Monitor logs**: Check `journalctl` after hibernation for errors
5. **Keep charger nearby**: During testing, ensure you can charge if needed

## Security Considerations

### Unencrypted Hibernation Images

⚠️ **IMPORTANT**: This hibernation setup uses an **unencrypted swap file**.

**What this means**:
- When you hibernate, your **entire RAM contents** are written to `/swapfile`
- This includes: passwords, encryption keys, browser sessions, SSH keys, GPG keys, API tokens, and any other sensitive data in memory
- Anyone with **physical access** to your laptop can read the hibernation image
- The data persists until the next hibernation or until the swap file is overwritten

**Who should be concerned**:
- Laptops used in shared environments
- Systems containing highly sensitive data
- Devices at risk of theft or seizure
- Systems subject to compliance requirements (HIPAA, PCI-DSS, etc.)

**Mitigation options**:

1. **Accept the risk** (recommended for personal laptops in your control)
   - Physical security is your main protection
   - This setup is fine for most home users

2. **Encrypted swap** (advanced users only)
   - Requires: dm-crypt, initramfs modifications, keyfile management
   - Performance impact: ~5-10 seconds added to hibernate/resume
   - Setup complexity: High (not covered in this guide)
   - See: https://wiki.archlinux.org/title/Dm-crypt/Swap_encryption

3. **Disable hibernation when not needed**
   - Only enable hibernation when actively using on battery
   - Use suspend-to-RAM (sleep) for short periods instead

**Best practices**:
- Lock your screen before walking away (screen lock does not protect hibernation images)
- Enable full disk encryption (LUKS) for additional protection
- Store sensitive data encrypted even in memory (password managers, encrypted containers)
- Consider whether hibernation is necessary for your use case

## Uninstallation

To remove hibernation configuration:

```bash
# Disable swap
sudo swapoff /swapfile

# Remove from fstab
sudo sed -i '/\/swapfile/d' /etc/fstab

# Remove swap file
sudo rm /swapfile

# Remove GRUB resume parameters
# You can restore from backup: sudo cp /root/grub-backups/grub-last-backup.bak /etc/default/grub
# Or use the configure-grub.sh script to reconfigure
sudo grub-mkconfig -o /boot/grub/grub.cfg

# Restore original battery monitor script
# (Keep a backup of the original script before modification)
```

## References

- [Arch Wiki: Power Management](https://wiki.archlinux.org/title/Power_management)
- [Arch Wiki: Suspend and Hibernate](https://wiki.archlinux.org/title/Power_management/Suspend_and_hibernate)
- [Arch Wiki: Laptop](https://wiki.archlinux.org/title/Laptop)

## Support

If you encounter issues:

1. Run the test script: `./test-scripts/test-hibernation.sh`
2. Check system logs: `journalctl -b -1`
3. Check battery monitor logs: `journalctl --user -u omarchy-battery-monitor.service`
4. Verify swap: `swapon --show`
5. Check bootloader config (GRUB: `/etc/default/grub`, Limine: `/etc/default/limine`)
6. Check active kernel params: `cat /proc/cmdline | grep resume`

## License

This setup script is provided as-is for personal use on your Arch Linux system.

## Version

- **v1.2** - Multi-bootloader support (January 12, 2026)
  - Added automatic bootloader detection (GRUB, Limine, systemd-boot)
  - Created configure-bootloader.sh dispatcher script
  - Added configure-limine.sh for Limine + UKI setups
  - Updated all scripts to detect and use correct bootloader
  - Added lib/bootloader-detect.sh shared utility
  - Updated documentation to reflect bootloader flexibility
- **v1.1** - Enhanced reliability and security (January 12, 2026)
  - Increased swap size to 48GB (1.5x RAM) for better reliability
  - Fixed Btrfs swap file fragmentation (use dd instead of fallocate)
  - Added hibernation failure fallback (poweroff if hibernate fails)
  - Added resume offset verification in configure-grub.sh
  - Added filesystem compatibility checks in test script
  - Added kernel command line verification
  - Added comprehensive security documentation
- **v1.0** - Initial setup with 36GB swap file and 5% critical threshold
- Created: January 12, 2026
- Tested on: Arch Linux kernel 6.18.3-arch1-1 with Btrfs filesystem