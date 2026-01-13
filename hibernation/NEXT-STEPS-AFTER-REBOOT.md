# Hibernation Setup - Next Steps After Reboot

**Last Updated:** January 12, 2026  
**Configuration Date:** January 12, 2026 19:22

---

## ✅ What Was Completed Before Reboot

- ✅ Created 48GB swapfile using native Btrfs command
- ✅ Calculated swap offset: `253674462`
- ✅ Updated Limine configuration with hibernation parameters
- ✅ Rebuilt UKI (Unified Kernel Image)
- ✅ Backed up original config to: `/root/limine-backups/limine-20260112-192203.bak`

---

## 📋 Configuration Details

| Parameter | Value |
|-----------|-------|
| **Swap File** | `/swapfile` |
| **Swap Size** | 48GB |
| **Root UUID** | `42296ced-9cca-4801-9b68-f72f310aa248` |
| **Swap Offset** | `253674462` |
| **Bootloader** | Limine with UKI |
| **UKI Location** | `/boot/EFI/Linux/omarchy_linux.efi` |
| **Config File** | `/etc/default/limine` |

---

## 🚀 Step 1: Verify Kernel Parameters Loaded

After reboot, first verify the hibernation parameters were loaded:

```bash
cat /proc/cmdline | grep resume
```

**Expected output should contain:**
```
resume=UUID=42296ced-9cca-4801-9b68-f72f310aa248 resume_offset=253674462
```

**If you DON'T see these parameters:**
- The UKI didn't load correctly
- See troubleshooting section below

**If you DO see these parameters:**
- ✅ Proceed to Step 2

---

## 🧪 Step 2: Verify Swap is Active

Check that the swapfile is active:

```bash
swapon --show
```

**Expected output:**
```
NAME       TYPE      SIZE USED PRIO
/dev/zram0 partition   4G   0B  100
/swapfile  file       48G   0B   -2
```

**If swapfile is missing:**
```bash
sudo swapon /swapfile
swapon --show
```

---

## 🧪 Step 3: Test Hibernation Manually

**⚠️ IMPORTANT: Save all your work first!**

Close unnecessary applications and save everything, then:

```bash
sudo systemctl hibernate
```

### What Should Happen:

1. **Screen goes black**
2. **System powers off completely** (all lights off, fans stop)
3. **Power the system back on** (press power button)
4. **System resumes from hibernation:**
   - No boot logo (or brief boot)
   - Screen comes back to life
   - All applications/windows exactly as you left them
   - Check if all your work is still there

### If Hibernation Works:

✅ **SUCCESS!** Proceed to Step 4.

### If Hibernation Fails:

See **Troubleshooting** section below.

---

## 🧪 Step 4: Run Comprehensive Test Suite

Run the full test script to verify everything:

```bash
cd ~/git/omarchy_setup/hibernation
./test-scripts/test-hibernation.sh
```

This checks 15+ things including:
- Swap file existence and size
- Swap activation
- Kernel parameters
- Bootloader configuration
- File permissions
- Btrfs compatibility

**Expected output:** All tests should pass ✅

---

## 🔧 Step 5: Enable Production Features (Optional)

Once hibernation works reliably, enable these features:

### A. Add "Hibernate" to Power Menu

```bash
cd ~/git/omarchy_setup/hibernation
sudo ./logind-config/enable-hibernate-menu.sh
```

This adds a "Hibernate" option to:
- System power menu
- Lock screen power options
- Shutdown dialog

### B. Enable Low-Battery Auto-Hibernation

```bash
cd ~/git/omarchy_setup/hibernation
sudo ./install-hibernation.sh
```

This configures:
- **10% battery:** Warning notification "Time to recharge!"
- **5% battery:** Auto-hibernates to prevent data loss
- **Failure fallback:** If hibernation fails, system powers off after 10s warning

**After install, verify the battery monitor:**
```bash
systemctl --user status omarchy-battery-monitor.timer
systemctl --user status omarchy-battery-monitor.service
```

---

## 🔍 Troubleshooting

### Problem: Kernel Parameters Not Loaded

**Symptoms:** `cat /proc/cmdline | grep resume` returns nothing

**Solutions:**

1. **Check Limine config:**
   ```bash
   sudo cat /etc/default/limine | grep resume
   ```
   
   Should show:
   ```
   KERNEL_CMDLINE[default]+=" resume=UUID=42296ced-9cca-4801-9b68-f72f310aa248 resume_offset=253674462"
   ```

2. **If parameters are in config but not loaded:**
   ```bash
   sudo limine-update
   sudo reboot
   ```

3. **If parameters are NOT in config:**
   ```bash
   cd ~/git/omarchy_setup/hibernation
   sudo ./configure-limine.sh
   sudo reboot
   ```

---

### Problem: Hibernation Fails or System Just Suspends

**Symptoms:** System suspends instead of hibernating, or errors appear

**Check logs:**
```bash
journalctl -b | grep -i "hibernate\|swap\|resume"
```

**Common issues:**

1. **"Not enough swap space" error:**
   ```bash
   free -h
   ```
   Swap should be ≥ 48GB. If not:
   ```bash
   sudo swapon /swapfile
   ```

2. **Swap file fragmented or has holes:**
   ```bash
   sudo filefrag -v /swapfile | head -10
   ```
   Should show contiguous blocks. If fragmented, recreate:
   ```bash
   cd ~/git/omarchy_setup/hibernation
   sudo ./recreate-btrfs-swap.sh
   sudo ./configure-limine.sh
   sudo reboot
   ```

3. **Wrong swap offset:**
   ```bash
   sudo filefrag -v /swapfile | awk 'NR==4 {gsub(/\.\./,"",$4); print $4}'
   ```
   Compare with `/proc/cmdline`. If different, reconfigure:
   ```bash
   cd ~/git/omarchy_setup/hibernation
   sudo ./configure-limine.sh
   sudo reboot
   ```

---

### Problem: System Won't Resume After Hibernation

**Symptoms:** System boots normally instead of resuming

**Solutions:**

1. **Verify swap was written to during hibernation:**
   ```bash
   sudo filefrag -v /swapfile | grep -A5 "extent"
   ```

2. **Check if resume was attempted:**
   ```bash
   journalctl -b | grep -i resume
   ```

3. **Verify kernel has resume support:**
   ```bash
   zgrep CONFIG_HIBERNATION /proc/config.gz
   ```
   Should show: `CONFIG_HIBERNATION=y`

4. **Try hibernating with more free RAM:**
   - Close browsers, applications
   - Free up memory
   - Try hibernating again

---

### Problem: Battery Monitor Not Working

**Verify installation:**
```bash
systemctl --user status omarchy-battery-monitor.timer
```

**Check battery level is readable:**
```bash
omarchy-battery-remaining
```

**View recent logs:**
```bash
journalctl --user -u omarchy-battery-monitor.service -n 50
```

**Restart the timer:**
```bash
systemctl --user restart omarchy-battery-monitor.timer
```

---

## 🆘 Emergency Rollback

If hibernation completely breaks your system:

### Rollback Limine Configuration

```bash
sudo cp /root/limine-backups/limine-20260112-192203.bak /etc/default/limine
sudo limine-update
sudo reboot
```

### Disable Swap File

```bash
sudo swapoff /swapfile
sudo sed -i '/\/swapfile/d' /etc/fstab
```

### Remove Hibernation Scripts

```bash
sudo systemctl --user stop omarchy-battery-monitor.timer
sudo systemctl --user disable omarchy-battery-monitor.timer
```

---

## 📊 Expected Behavior Summary

### After Manual Hibernation Test:

| Time | What Happens |
|------|--------------|
| T+0s | Command issued: `sudo systemctl hibernate` |
| T+2s | Screen goes black |
| T+5s | System begins writing RAM to swap (48GB write) |
| T+30s-60s | System powers off completely |
| T+60s | User presses power button |
| T+65s | BIOS/UEFI boot screen (brief) |
| T+70s | Kernel loads and detects hibernation image |
| T+75s | System reads swap back into RAM |
| T+90s | Desktop appears with all windows/apps restored |

### After Low Battery Auto-Hibernation:

| Battery | What Happens |
|---------|--------------|
| 10% | Notification: "Time to recharge!" |
| 5% | Critical notification: "CRITICAL: Hibernating Now!" |
| 5% (2s later) | `systemctl hibernate` triggered |
| 5% (if hibernate fails) | 10s warning, then `systemctl poweroff` |

---

## 🔗 Additional Resources

**Configuration Files:**
- Limine config: `/etc/default/limine`
- Limine backup: `/root/limine-backups/limine-20260112-192203.bak`
- Summary: `/root/hibernation-limine-summary.txt`
- Battery monitor: `~/.local/share/omarchy/bin/omarchy-battery-monitor`

**Documentation:**
- Main README: `~/git/omarchy_setup/hibernation/README.md`
- Test script: `~/git/omarchy_setup/hibernation/test-scripts/test-hibernation.sh`
- Arch Wiki: https://wiki.archlinux.org/title/Power_management/Suspend_and_hibernate
- Btrfs Swapfile: https://btrfs.readthedocs.io/en/latest/Swapfile.html

---

## ✅ Quick Success Checklist

After reboot, verify these in order:

- [ ] Kernel parameters loaded: `cat /proc/cmdline | grep resume`
- [ ] Swap is active: `swapon --show` shows `/swapfile`
- [ ] Manual hibernation works: `sudo systemctl hibernate`
- [ ] System resumes with all apps intact
- [ ] Test suite passes: `./test-scripts/test-hibernation.sh`
- [ ] (Optional) Power menu has "Hibernate" option
- [ ] (Optional) Battery monitor enabled and running

---

## 📞 Need Help?

If you encounter issues:

1. Run the test script: `./test-scripts/test-hibernation.sh`
2. Check logs: `journalctl -b | grep -i "hibernate\|swap\|resume"`
3. Verify kernel params: `cat /proc/cmdline | grep resume`
4. Check swap status: `swapon --show`
5. Review summary: `sudo cat /root/hibernation-limine-summary.txt`

---

**Generated:** January 12, 2026 19:22  
**Script Version:** v1.2 (Multi-bootloader support)  
**Kernel:** 6.18.3-arch1-1  
**Filesystem:** Btrfs on `/dev/mapper/root`
