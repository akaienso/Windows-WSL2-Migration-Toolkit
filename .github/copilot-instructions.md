# Copilot Instructions for Windows-WSL2-Migration-Toolkit

## Project Overview
This is a **system migration automation tool** for Windows users with WSL2. It orchestrates three independent workflows:
1. **Windows App Inventory** → CSV editing → Generate restoration scripts
2. **WSL2 Full System Backup** → Distro export + dotfile archive to external drive
3. **WSL2 System Restore** → Import backup + re-inject dotfiles + post-install setup

**Key insight**: The toolkit bridges PowerShell (Windows host) and Bash (WSL guest) using `wsl --exec` commands and cross-mounted paths (`/mnt/c/...`).

## Architecture & Data Flow

### Configuration Management (`config.json`)
- Single source of truth for paths and distro name
- Used by all scripts via `Get-Content | ConvertFrom-Json`
- Default values embedded in `Start.ps1` (fallback mechanism)
- **Key fields**: `ExternalBackupRoot`, `WslDistroName`, `InventoryDirectory`, `InstallersDirectory`, `LogDirectory`, `InventoryOutputCSV`, `InventoryInputCSV`

### Four-Step User Workflow
```
Start.ps1 (Main Menu)
├─ Option 1: Get-Inventory.ps1 → Scan Windows/WSL → INSTALLED_SOFTWARE_INVENTORY.csv
├─ Option 2: Generate-Restore-Scripts.ps1 → Read CSV → Restore_Windows.ps1 + Restore_Linux.sh
├─ Option 3: Backup-WSL.ps1 → Export distro + dotfiles to ExternalBackupRoot\WSL
└─ Option 4: Restore-WSL.ps1 → Import distro + restore dotfiles + post-install
```

### Data Inventory Pipeline
**Get-Inventory.ps1** scans four sources (merged with deduplication):
1. **Winget** exports to JSON, parsed for packages
2. **Microsoft Store** via `Get-AppxPackage` (filters non-removable, non-framework)
3. **Registry** scans HKLM/HKCU uninstall keys (marked "Manual")
4. **WSL2 Apt** via `wsl --exec apt-mark showmanual` to list user packages

**Each entry** gets category classification:
- Windows: Filters system keywords (C++, .NET, Drivers, etc.) → "System/Driver (Auto-Detected)"
- WSL: Filters linux keywords (lib*, systemd, etc.) → "System/Base (Linux)"
- Otherwise: "User-Installed Application"

**CSV schema**: `Category`, `Application Name`, `Version`, `Environment`, `Source`, `Restoration Command`, `Keep (Y/N)`
- User edits `Keep (Y/N)` column (TRUE/FALSE) to select apps for restoration

### CSV Editing Workflow
**After running Option 1 (Get-Inventory)**, you have `INSTALLED-SOFTWARE-INVENTORY.csv` in the Inventories folder. This is the system-generated output. **Copy it** to `SOFTWARE-INSTALLATION-INVENTORY.csv` (the user-editable input file) before proceeding with Step 2. This design prevents regenerating inventory from overwriting user edits.

#### Recommended: Google Sheets Method (Non-Technical Users)
1. Copy `INSTALLED-SOFTWARE-INVENTORY.csv` to `SOFTWARE-INSTALLATION-INVENTORY.csv` in Inventories folder
2. Download `SOFTWARE-INSTALLATION-INVENTORY.csv`
3. **Upload to Google Sheets**: Go to [sheets.google.com](https://sheets.google.com) → New → Upload file → Select your CSV
4. **Convert Keep column to checkboxes** (optional but cleaner):
   - Select the `Keep (Y/N)` column (column G)
   - **Data** → **Data Validation** → Select "Checkbox"
   - Map: Checked = "TRUE", Unchecked = "FALSE"
5. **Review & Filter**:
   - Filter by `Environment` to see Windows apps separately from WSL apps
   - Filter by `Category` to review "System/Driver" items (usually safe to skip)
   - Check **only** packages you want to restore
6. **Export & Replace**:
   - **File** → **Download** → **CSV (.csv, current sheet)**
   - Save as `SOFTWARE-INSTALLATION-INVENTORY.csv`
   - Place back in your Inventories folder (overwrite the copied version)

#### Alternative: Manual CSV Editor (Technical Users)
- Open with VS Code or any text editor
- Edit `Keep (Y/N)` column to TRUE/FALSE/Yes/No/Y/N/1/0 (case-insensitive)
- Save as UTF-8 (important: no BOM)
- Avoid Excel (it may change line endings to CRLF)

#### Important Gotchas
- **Two file naming pattern**: 
  - `INSTALLED-SOFTWARE-INVENTORY.csv` = output from Step 1 (regenerable)
  - `SOFTWARE-INSTALLATION-INVENTORY.csv` = input to Step 2 (user-edited, protected from overwrites)
- **Location**: Place both in `Inventories/` folder
- **Line endings**: Keep as LF (`\n`), not CRLF (`\r\n`) — Google Sheets handles this correctly
- **Registry apps**: Source = "Registry (Manual)" cannot be auto-installed; you'll need to search for them manually via Winget or website
- **Keep column format**: Accepts loose values — any of TRUE/Yes/Y/1 (checked) or FALSE/No/N/0 (unchecked)

### Restoration Script Generation
**Generate-Restore-Scripts.ps1**:
- Reads **SOFTWARE-INSTALLATION-INVENTORY.csv** (user-edited, not output)
- Filters rows where `Keep (Y/N)` = "TRUE|Yes|Y|1"
- **Windows apps**: Build `winget install` commands (except Registry source → manual warnings)
- **WSL apps**: Build `sudo apt install` commands (with newline normalization to `\n`)
- Output: `Restore_Windows.ps1` + `Restore_Linux.sh` to `InstallersDirectory`

### WSL Backup/Restore Sequence

#### Backup (Backup-WSL.ps1)
1. Create `ExternalBackupRoot\WSL` directory
2. **Inject toolkit**: Copy `Scripts\WSL\*.sh` to `~/.wsl-toolkit/` inside distro
3. **Backup dotfiles**: Run `backup-dotfiles.sh` → Creates `~/wsl-dotfile-backups/dotfiles_TIMESTAMP.tar.gz`
4. **Export full distro**: `wsl --export DISTRO output.tar` (shuts down WSL first)
5. **Generate hashes**: SHA256 for both files → `HashReport_TIMESTAMP.txt`

#### Restore (Restore-WSL.ps1)
1. Find latest backups (by LastWriteTime DESC)
2. **Import distro**: `wsl --import DISTRO C:\WSL\DISTRO backup.tar`
3. **Inject toolkit** (same as backup)
4. **Restore dotfiles**: Copy tar.gz to WSL, run `restore-dotfiles.sh` to extract
5. **Post-install**: Run `post-restore-install.sh` (custom setup hooks)

## Project Conventions & Patterns

### PowerShell Style
- **Error handling**: `$ErrorActionPreference = 'Stop'` at top of scripts (Backup/Restore only)
- **Path handling**: `Split-Path` + `Join-Path` for cross-platform safety; avoid string interpolation
- **Config loading**: Function `Load-Config` in Start.ps1 merges defaults with persisted JSON
- **Logging**: `Start-Transcript` in inventory scripts, timestamped log files in `LogDirectory`
- **Color output**: Cyan (headers), Yellow (progress), Magenta (critical), Red (errors), Green (success)
- **WSL paths**: Convert Windows paths to mount: `"c:\path"` → `/mnt/c/path` (lowercase, forward slashes)

### Bash Style (WSL Scripts)
- **Set strict mode**: `set -u` (error on undefined variables)
- **Path expansion**: Use `$HOME`, `$TIMESTAMP` for consistency
- **Tar operations**: `--ignore-failed-read` flag (graceful on permission errors)
- **Line endings**: All `.sh` files must use `\n` (LF), not `\r\n`

### CSV Conventions
- **Input file**: `SOFTWARE-INSTALLATION-INVENTORY.csv` (user-edited)
- **Output file**: `INSTALLED_SOFTWARE_INVENTORY.csv` (system-generated, not edited)
- Boolean column: `Keep (Y/N)` accepts loose matching: `"TRUE|Yes|Y|1"` (case-insensitive via `-match`)
- Restoration Command: Includes full command (e.g., `winget install --id foo -e`), not just package name

### Directory Structure
```
./Scripts/
  Get-Inventory.ps1          # Main inventory scanner
  Generate-Restore-Scripts.ps1  # Script generator
  Backup-WSL.ps1             # Backup orchestrator
  Restore-WSL.ps1            # Restore orchestrator
  WSL/
    backup-dotfiles.sh       # Tar up user dotfiles
    restore-dotfiles.sh      # Extract dotfiles
    post-restore-install.sh  # Custom post-install hooks
./Inventories/              # CSVs and system info
./Installers/               # Generated restore scripts
./Logs/                      # Timestamped transcript logs
```

## Critical Workflows & Commands

### Run Sequence
```powershell
# Start interactive menu (calls scripts based on user choice)
. .\Start.ps1

# Or call scripts directly
. .\Scripts\Get-Inventory.ps1
. .\Scripts\Generate-Restore-Scripts.ps1
. .\Scripts\Backup-WSL.ps1
. .\Scripts\Restore-WSL.ps1
```

### Manual Testing
```powershell
# Test config loading
$config = Get-Content .\config.json -Raw | ConvertFrom-Json; $config

# Test WSL command execution
wsl --exec bash -lc "echo 'test'"
wsl -d Ubuntu -- apt list --installed | head

# Verify paths work cross-platform
$BackupDir = "D:\Migration-Backups\WSL"
$wslPath = "/mnt/" + ($BackupDir.Replace(":", "").Replace("\", "/").ToLower())
# Should output: /mnt/d/migration-backups/wsl
```

### Edge Cases & Debugging
- **WSL not installed**: Scripts fail silently on `wsl --exec` (catch blocks suppress errors)
- **Path encoding**: `Replace(":", "").Replace("\", "/").ToLower()` handles drive letters
- **Dotfile restore permissions**: `post-restore-install.sh` handles `chown` if needed
- **Distro already exists**: Restore warns but proceeds (old install gets overwritten)
- **Registry apps**: Marked "Source: Registry (Manual)" because no uninstall command available

## Extension Points & Common Tasks

### Adding a New Inventory Source
1. In `Get-Inventory.ps1`, add STEP N section (follow existing pattern)
2. Create PSCustomObject with same schema as existing entries
3. Append to `$masterList`
4. Use `Get-AppCategory` for categorization
5. Track in `$knownApps` to avoid duplicates

### Adding Custom Post-Install
Edit `post-restore-install.sh`:
```bash
#!/bin/bash
# Add custom setup after dotfiles restored
sudo apt install -y custom-package
python3 -m pip install user-package
```

### Changing Backup Location
Edit `config.json` → `ExternalBackupRoot` (paths automatically converted for WSL cross-mount)

### Supporting a Different WSL Distro
Edit `config.json` → `WslDistroName` and verify distro has `apt` (scripts assume Ubuntu/Debian)

## Known Limitations & TODOs
- No parallel script execution (sequential for safety)
- Registry apps require manual search before install
- Distro import overwrites existing installation without backup
- No rollback mechanism if restore fails mid-process
