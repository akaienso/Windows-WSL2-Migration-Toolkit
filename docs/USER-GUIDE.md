# Windows-WSL2-Migration-Toolkit: User Guide

Welcome to the Windows-WSL2-Migration-Toolkit! This guide will walk you through everything you need to know to use the toolkit effectively.

---

## Table of Contents

1. [Quick Start](#quick-start)
2. [Installation & Setup](#installation--setup)
3. [Main Features](#main-features)
4. [Step-by-Step Workflows](#step-by-step-workflows)
5. [File Management](#file-management)
6. [Troubleshooting](#troubleshooting)
7. [FAQ](#faq)
8. [Tips & Best Practices](#tips--best-practices)

---

## Quick Start

### Minimum Requirements
- Windows 10/11 with WSL2 installed
- PowerShell 5.1 or later
- 20GB+ free disk space (for WSL backups)
- Administrator access for some operations

### First Run
```powershell
# Navigate to toolkit directory
cd D:\Windows-WSL2-Migration-Toolkit

# Run the main menu
. .\Start.ps1
```

You'll be prompted to:
1. Specify a backup location (external drive recommended)
2. Select your WSL2 distro (usually Ubuntu)
3. Choose an operation from the menu

---

## Installation & Setup

### Step 1: Download the Toolkit
Clone or download the toolkit to a local directory:
```powershell
git clone https://github.com/akaienso/Windows-WSL2-Migration-Toolkit.git
# OR download as ZIP and extract
```

### Step 2: Run Start.ps1
```powershell
cd path\to\toolkit
. .\Start.ps1
```

### Step 3: Configure Settings
On first run, you'll configure:
- **Backup Root Directory**: Where backups will be stored (defaults to `./migration-backups`)
- **WSL Distro Name**: Your WSL2 distro (auto-detected if only one exists)

These settings are saved to `settings.json` in the toolkit root.

### Step 4: Verify Installation
Check that:
- `settings.json` exists in the toolkit root
- Your WSL distro is listed: `wsl --list --verbose`
- Backup directory is accessible and has write permissions

---

## Main Features

### 1. **Application Inventory**
Scan your system for installed applications across three sources:
- **Windows Store** - Modern apps installed via Microsoft Store
- **Winget** - Command-line installed packages
- **Registry** - Manually installed applications
- **WSL** - Linux packages in your WSL distro

**Output:** `INSTALLED-SOFTWARE-INVENTORY.csv`

### 2. **Application Restoration**
Create PowerShell and Bash scripts to reinstall applications:
- Windows apps via winget
- Linux packages via apt
- Manual registry entries (with guidance)

**Outputs:** `Restore_Windows.ps1`, `Restore_Linux.sh`

### 3. **WSL2 Backup & Restore**
- **Backup**: Export full WSL distro + user dotfiles to external drive
- **Restore**: Import WSL from backup with all settings intact

**Outputs:** Distro `.tar` + dotfiles `.tar.gz` + hash report

### 4. **AppData Backup & Restore**
- **Backup**: Selectively backup application settings
- **Restore**: Restore settings to original locations

**Output:** ZIP files with application-specific folders

---

## Step-by-Step Workflows

### Workflow 1: Complete System Backup

#### Step 1: Generate Inventory
```
Start.ps1 → Option 1: Get-Inventory
```
This scans your system and creates `INSTALLED-SOFTWARE-INVENTORY.csv`.

**Expected Time:** 2-5 minutes

#### Step 2: Review & Edit Inventory
1. Copy `INSTALLED-SOFTWARE-INVENTORY.csv` to `SOFTWARE-INSTALLATION-INVENTORY.csv`
2. Open in Google Sheets or Excel
3. Uncheck (set to FALSE) apps you don't want to restore
4. Save and place back in Inventories folder

**Recommended:** Use Google Sheets for easier filtering and checkbox conversion.

#### Step 3: Generate Restore Scripts
```
Start.ps1 → Option 2: Generate-Restore-Scripts
```
Creates restore scripts based on your CSV edits.

**Output Files:**
- `Restore_Windows.ps1` - For reinstalling Windows apps
- `Restore_Linux.sh` - For reinstalling Linux packages

#### Step 4: Backup WSL
```
Start.ps1 → Option 3: Backup-WSL
```
Exports your entire WSL distro and dotfiles to the backup directory.

**Expected Time:** 10-30 minutes (depending on distro size)

**Output:**
- `WslBackup_*.tar` - Full distro
- `WslDotfiles_*.tar.gz` - User configuration files
- `HashReport_*.txt` - File integrity checksums

#### Step 5: Backup AppData (Optional)
```
Start.ps1 → Option 5: Backup-AppData
```
Creates ZIP backups of selected application settings.

**Expected Time:** 2-10 minutes (depending on number of apps)

#### Step 6: Verify Backups
```powershell
# Check backup directory
$backupDir = "D:\DACdBeast-Migration-Backup"
Get-ChildItem -Path $backupDir -Recurse | Measure-Object -Sum Length

# Verify important files exist
Test-Path "$backupDir\WSL"
Test-Path "$backupDir\AppData"
```

---

### Workflow 2: System Restoration

#### Step 1: Verify Backup Files
Before restoring, ensure you have:
- WSL backup: `$BackupDir\WSL\yyyy-MM-dd_HH-mm-ss\WslBackup_*.tar`
- Dotfiles: `$BackupDir\WSL\yyyy-MM-dd_HH-mm-ss\WslDotfiles_*.tar.gz`
- Restore scripts: `Installers\Restore_Windows.ps1` and `Restore_Linux.sh`

#### Step 2: Restore WSL
```
Start.ps1 → Option 4: Restore-WSL
```

**Before Running:**
- Close all WSL terminals
- Note current distro name (will overwrite if same name)
- Ensure `C:\WSL\` directory exists or will be created

**What It Does:**
1. Imports distro from backup
2. Injects toolkit scripts
3. Restores dotfiles (`.bashrc`, `.config`, etc.)
4. Runs post-install setup (apt update + core tools)

**Expected Time:** 15-45 minutes

#### Step 3: Restore AppData (Optional)
```
Start.ps1 → Option 6: Restore-AppData
```

**Before Running:**
- Close affected applications
- Review list of backup files
- Confirm you want to overwrite existing settings

**What It Does:**
1. Extracts each ZIP to temporary location
2. Backs up existing settings
3. Restores from archive
4. Cleans up temporary files

#### Step 4: Run Restore Scripts
```powershell
# For Windows apps
. .\Installers\Restore_Windows.ps1

# For Linux apps (from WSL)
wsl -d Ubuntu -- bash /path/to/Restore_Linux.sh
```

**Note:** Registry apps must be installed manually (marked in script with guidance).

#### Step 5: Verify Restoration
```powershell
# Check WSL distro
wsl --list --verbose

# Test WSL
wsl -d Ubuntu -- echo "WSL is working!"

# Launch applications to verify settings
```

---

## File Management

### Inventory Folder Structure
```
Inventories/
├── INSTALLED-SOFTWARE-INVENTORY.csv      (System output, read-only)
├── SOFTWARE-INSTALLATION-INVENTORY.csv   (User-edited copy)
├── System_Info.txt                       (System details)
└── AppData_Folder_Map.json              (App folder mappings)
```

**Important:** Always edit the CSV copy, never the auto-generated original.

### Backup Folder Structure
```
D:\DACdBeast-Migration-Backup\
├── WSL/
│   └── yyyy-MM-dd_HH-mm-ss/
│       ├── WslBackup_Distro_*.tar
│       ├── WslDotfiles_*.tar.gz
│       └── HashReport_*.txt
├── AppData/
│   └── yyyy-MM-dd_HH-mm-ss/
│       ├── Backups/
│       │   └── AppName_*.zip
│       ├── Inventories/
│       └── Logs/
└── Logs/
    └── [Timestamp log files]
```

### CSV Column Reference

| Column | Purpose | Values |
|--------|---------|--------|
| Category | App type | System/Driver, User-Installed, System/Base |
| Application Name | Package/App name | Varies |
| Version | Installed version | Varies |
| Environment | Windows/WSL | Windows or WSL |
| Source | Where it came from | Winget, Store, Registry, Apt |
| Restoration Command | How to reinstall | Full command or manual |
| Keep (Y/N) | Include in restore? | TRUE/FALSE/Y/N |
| Backup Settings (Y/N) | Backup AppData? | TRUE/FALSE/Y/N |

---

## Troubleshooting

### Common Issues & Solutions

#### "WSL Distro not found"
**Cause:** Distro name mismatch or WSL not installed  
**Solution:**
```powershell
# List installed distros
wsl --list --verbose

# Update settings.json with correct name
# Then run Start.ps1 again
```

#### "Backup directory does not exist"
**Cause:** Path doesn't exist or network drive disconnected  
**Solution:**
```powershell
# Check backup directory
Test-Path "D:\DACdBeast-Migration-Backup"

# Create if missing
New-Item -ItemType Directory -Path "D:\DACdBeast-Migration-Backup"

# Reconnect network drive if needed
```

#### "No backup files found"
**Cause:** Backup hasn't been run yet or location is wrong  
**Solution:**
1. Run Backup-WSL.ps1 first
2. Verify backup completed successfully
3. Check `$BackupRootDirectory` in settings.json

#### "Archive extraction failed"
**Cause:** Corrupted archive or insufficient permissions  
**Solution:**
```powershell
# Check file integrity
Get-FileHash "$BackupDir\WslBackup_*.tar" -Algorithm SHA256

# Verify hash against HashReport
Compare with HashReport_*.txt in backup directory

# If mismatch, backup may be corrupted - create new backup
```

#### "Permission denied on AppData restore"
**Cause:** Application running or insufficient permissions  
**Solution:**
1. Close affected application
2. Run toolkit with administrator rights
3. Check folder ownership: `icacls "path"`

#### "Dotfile sync timeout warning"
**Cause:** WSL filesystem hasn't synced to Windows  
**Solution:**
```powershell
# The file exists in WSL, check manually:
wsl -d Ubuntu -- ls -la ~/.wsl-dotfile-backups/

# You may need to copy manually to backup directory
wsl -d Ubuntu -- cp ~/wsl-dotfile-backups/dotfiles_*.tar.gz /mnt/d/backup/path/
```

---

### Checking Log Files

All operations are logged. Find relevant logs:

**Backup Logs:**
```powershell
# Latest backup log
Get-ChildItem -Path "$BackupDir\*\Logs\*" -Filter "*.txt" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
```

**View Logs:**
```powershell
# Open in notepad
notepad "$BackupDir\Logs\AppData_Backup_20251221_2050.txt"

# Or view content
Get-Content "$BackupDir\Logs\*" | tail -50
```

---

## FAQ

### Q: How much disk space do I need?
**A:** 
- WSL backup: Size of your distro (5-50GB typically)
- AppData backup: Application data (100MB-5GB depending on apps)
- Inventory: ~1MB
- Total: Usually 10-100GB

### Q: Can I backup to a network drive?
**A:** Yes, but:
- Map the network drive first: `net use Z: \\server\share`
- Update `BackupRootDirectory` to network path
- Ensure reliable connection for large transfers
- Backup speeds will be slower

### Q: What if I have multiple WSL distros?
**A:** 
- The toolkit backs up one distro at a time
- Update `WslDistroName` in settings.json to backup a different distro
- Run Backup-WSL.ps1 for each distro you want to backup

### Q: Can I selectively restore apps?
**A:** Yes:
1. Edit the generated restore scripts before running them
2. Comment out or delete lines for apps you don't want
3. Run the modified script

### Q: What about GUI applications?
**A:** 
- **Windows GUI apps**: Fully supported via winget or installer
- **WSL GUI apps**: Require WSL GUI subsystem (Windows 11 only)
- **Linux TUI apps**: Fully supported

### Q: Can I use the toolkit for migration to a new PC?
**A:** Yes! This is the primary use case:
1. Backup on old PC
2. Move backup files to new PC
3. Configure toolkit on new PC
4. Restore from backup

### Q: How do I uninstall the toolkit?
**A:** Simply delete the toolkit folder. Settings are in `settings.json` (can also delete).

### Q: Can I recover if a backup gets corrupted?
**A:** Check the HashReport:
```powershell
# Compare file hash with report
Get-FileHash "$BackupDir\WslBackup_*.tar" -Algorithm SHA256
# Should match the value in HashReport_*.txt
```

If corrupted, create a new backup.

### Q: What if the restore scripts fail?
**A:** Check the logs and error messages:
1. Some apps may not be available via winget (retry manually)
2. Registry apps must be installed manually
3. Network issues can cause apt failures (retry manually in WSL)

---

## Tips & Best Practices

### Before Backup
- [ ] Update all applications
- [ ] Close unnecessary applications
- [ ] Verify disk space available
- [ ] Test backup directory access
- [ ] Create a recent Windows system image (for safety)

### During Backup
- [ ] Keep the terminal open and visible
- [ ] Don't interrupt the process (especially WSL export)
- [ ] Note the backup location
- [ ] Wait for completion message

### After Backup
- [ ] Verify backup files exist
- [ ] Check file sizes are reasonable
- [ ] Test hash verification
- [ ] Store backup on external/network drive
- [ ] Maintain multiple versions if space allows

### Before Restore
- [ ] Back up current system (System Image)
- [ ] Read error messages carefully
- [ ] Test restore scripts on non-critical systems first
- [ ] Ensure all prerequisite files are present

### During Restore
- [ ] Run administrator prompt
- [ ] Don't close terminals mid-operation
- [ ] Monitor disk space
- [ ] Note any failures for manual resolution

### After Restore
- [ ] Verify applications launched correctly
- [ ] Check settings are restored
- [ ] Run Windows Update and apt update
- [ ] Test network connectivity
- [ ] Verify backups of important files

### Storage Strategy
- **Primary backup**: External SSD (fast, portable)
- **Secondary backup**: USB drive (portable, slower)
- **Cloud backup**: OneDrive/Google Drive (for critical files)
- **Rotation**: Keep 2-3 recent backups, delete old ones

### Security Considerations
- Backup location has full copies of your system
- Secure backup drives with encryption if sensitive data
- Keep backup drives in safe location
- Don't share backup files with untrusted parties

### Performance Tips
- Backup during off-hours (backup operations are I/O intensive)
- Close large applications during backup (VSCode, browsers)
- Disable antivirus temporarily if backup is slow
- Use SSD for backup if possible (much faster than HDD)

---

## Getting Help

### Resources
- GitHub Issues: Report bugs or request features
- Copilot Instructions: See `.github/copilot-instructions.md`
- Error Handling Docs: See `ERROR-HANDLING-AUDIT.md`
- Quick Reference: See `ERROR-HANDLING-QUICK-REFERENCE.md`

---

## Recent Improvements (v2025.12)

This toolkit has been significantly hardened with the following improvements:

### For Users
- **More robust error messages**: Clear feedback when something goes wrong
- **Better logging**: Detailed logs show exactly what happened
- **Improved reliability**: 4 critical bugs fixed, enhanced validation throughout
- **Backward compatible**: Your existing backups work as before

### What Changed (Technical)
- Created shared utilities module for consistent patterns across all scripts
- Fixed critical bugs in restore and inventory scripts (function order, config reference, unsafe dot-sourcing)
- Enhanced error handling and CSV/JSON validation
- Improved path conversion to handle all drive letters robustly
- Better bash script logging with item-by-item progress and archive size reporting
- Enhanced permission hardening in dotfile restore operations

**No action needed on your part** — all improvements are transparent and maintain full backward compatibility with existing backups.

---

### Reporting Issues
When reporting an issue, include:
1. Command you ran (Start.ps1 option)
2. Error message received
3. Relevant log file content
4. Your system info (Windows version, WSL version, PowerShell version)
5. Steps to reproduce

### Manual Workarounds
If a script fails:
1. Check logs for specific error
2. Manually fix the issue (create directory, adjust permissions, etc.)
3. Re-run the script
4. Or perform the operation manually using raw commands

---

**Happy backing up! Your data is valuable—backup early, backup often.**
