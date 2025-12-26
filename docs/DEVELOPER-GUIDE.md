# Windows-WSL2-Migration-Toolkit: Developer Guide

This guide is for developers who want to understand, modify, or extend the Windows-WSL2-Migration-Toolkit.

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Project Structure](#project-structure)
3. [Core Concepts](#core-concepts)
4. [Script Organization](#script-organization)
5. [Error Handling Framework](#error-handling-framework)
6. [Configuration System](#configuration-system)
7. [Development Patterns](#development-patterns)
8. [Adding New Features](#adding-new-features)
9. [Testing & Debugging](#testing--debugging)
10. [Code Standards](#code-standards)

---

## Architecture Overview

The Windows-WSL2-Migration-Toolkit is a **bridging utility** that orchestrates workflows across Windows (host) and WSL2 (guest) environments using PowerShell on Windows and Bash in WSL.

### High-Level Flow

```
Start.ps1 (Main Menu)
  ├─ Get-Inventory.ps1 → Collect apps from 4 sources
  ├─ Generate-Restore-Scripts.ps1 → Create restore scripts from CSV
  ├─ Backup-WSL.ps1 → Export distro + dotfiles
  ├─ Restore-WSL.ps1 → Import distro + restore dotfiles
  ├─ Backup-AppData.ps1 → Backup application settings
  └─ Restore-AppData.ps1 → Restore application settings
```

### Design Principles

1. **Modular** - Each operation is a separate script
2. **Configuration-driven** - Settings in `settings.json`
3. **External backups** - Backups stored outside git repo
4. **Clear errors** - Every failure has actionable guidance
5. **Portable** - No hardcoded paths
6. **Safe** - Validates everything before long operations

---

## Project Structure

```
Windows-WSL2-Migration-Toolkit/
├── Start.ps1                          # Main entry point, menu, helpers
├── config.json                        # Factory defaults (committed)
├── settings.json                      # User settings (git-ignored)
├── README.md                          # Quick start guide
│
├── Scripts/
│   ├── Utils.ps1                      # Shared utilities module (NEW)
│   ├── ApplicationInventory/
│   │   ├── Get-Inventory.ps1         # Scan for installed apps (IMPROVED)
│   │   └── Generate-Restore-Scripts.ps1 # Build restore scripts (IMPROVED)
│   ├── AppData/
│   │   ├── Backup-AppData.ps1        # Backup app settings (IMPROVED)
│   │   └── Restore-AppData.ps1       # Restore app settings (FIXED)
│   └── WSL/
│       ├── Backup-WSL.ps1            # Export distro (IMPROVED)
│       ├── Restore-WSL.ps1           # Import distro (FIXED)
│       ├── backup-dotfiles.sh        # Backup dotfiles (ENHANCED)
│       ├── restore-dotfiles.sh       # Restore dotfiles (ENHANCED)
│       └── post-restore-install.sh   # Post-install hooks (ENHANCED)
│
├── Inventories/                       # User runs Get-Inventory
│   ├── INSTALLED-SOFTWARE-INVENTORY.csv (auto-generated)
│   ├── SOFTWARE-INSTALLATION-INVENTORY.csv (user-edited)
│   └── System_Info.txt
│
├── Installers/                        # User-generated restore scripts
│   ├── Restore_Windows.ps1
│   └── Restore_Linux.sh
│
├── Logs/                              # Runtime transcript logs
│   └── [Timestamped logs]
│
└── docs/                              # Documentation
    ├── USER-GUIDE.md
    ├── DEVELOPER-GUIDE.md
    ├── ERROR-HANDLING-AUDIT.md
    ├── ERROR-HANDLING-QUICK-REFERENCE.md
    ├── COMPLETION-SUMMARY.md
    ├── DETAILED-CHANGES-LOG.md
    └── FINAL-AUDIT-VERIFICATION.md
```

---

## Core Concepts

### 1. Configuration Management

**Two-File Pattern:**
- `config.json` - Factory defaults, never user-edited
- `settings.json` - User settings, created on first run

**Loading Order:**
```powershell
# Try settings.json first (user config)
if (Test-Path "$RootDir\settings.json") {
    return Get-Content $settingsPath -Raw | ConvertFrom-Json
}
# Fall back to config.json
if (Test-Path "$configPath") {
    return Get-Content $configPath -Raw | ConvertFrom-Json
}
```

**Key Fields:**
```json
{
  "WslDistroName": "Ubuntu",
  "BackupRootDirectory": "D:\\DACdBeast-Migration-Backup",
  "LogDirectory": "Logs",
  "ScriptDirectory": "Scripts",
  "InventoryInputCSV": "SOFTWARE-INSTALLATION-INVENTORY.csv",
  "InventoryOutputCSV": "INSTALLED-SOFTWARE-INVENTORY.csv",
  "BasePath": "."
}
```

### 2. Path Resolution

Paths work cross-platform by using a base + relative pattern:

```powershell
$RootDir = Split-Path -Parent (Split-Path -Parent $ScriptDir)
$BackupDir = Join-Path $config.BackupRootDirectory "WSL\$timestamp"
```

For WSL access, convert Windows paths to mount points:
```powershell
# D:\path\to\backup → /mnt/d/path/to/backup
$driveLetter = $path.Substring(0, 1).ToLower()
$pathWithoutDrive = $path.Substring(2).Replace("\", "/").ToLower()
$wslPath = "/mnt/$driveLetter$pathWithoutDrive"
```

### 3. Timestamped Backup Structure

Each backup creates a timestamped subdirectory:
```
BackupRootDirectory/
├── WSL/
│   └── 2025-12-21_14-30-45/
│       ├── WslBackup_Ubuntu_*.tar
│       ├── WslDotfiles_*.tar.gz
│       └── HashReport_*.txt
└── AppData/
    └── 2025-12-21_14-30-45/
        ├── Backups/
        ├── Inventories/
        └── Logs/
```

This allows **multiple backups** without collision.

### 4. CSV Data Pipeline

**Generation:**
```
System Scan (Winget + Store + Registry + Apt)
    ↓
Merge & Deduplicate
    ↓
Add Category Classification
    ↓
Export to CSV
    ↓
INSTALLED-SOFTWARE-INVENTORY.csv
```

**User Editing:**
```
Copy INSTALLED → SOFTWARE-INSTALLATION-INVENTORY.csv
    ↓
User edits Keep (Y/N) column
    ↓
Save and return
```

**Restoration:**
```
Read SOFTWARE-INSTALLATION-INVENTORY.csv
    ↓
Filter rows where Keep = TRUE
    ↓
Generate restoration commands
    ↓
Create Restore_Windows.ps1 + Restore_Linux.sh
```

---

## Script Organization

### Utils.ps1 - Shared Utilities Module (NEW)

**Location:** `Scripts/Utils.ps1` (400+ lines, 15 exported functions)

**Purpose:** Centralized utility functions used by all other scripts to eliminate code duplication and provide robust, tested patterns.

**Key Functions:**

| Function | Purpose |
|----------|---------|
| `Load-Config` | Unified configuration loading with precedence: settings.json → config.json → hardcoded defaults |
| `ConvertTo-WslPath` | Robust Windows→WSL path conversion (handles all drive letters A-Z, edge cases) |
| `Invoke-WslCommand` | Safe WSL command execution with distro validation and error handling |
| `Find-LatestBackupDir` | Locates most recent timestamped backup directory by scanning filesystem |
| `New-DirectoryIfNotExists` | Atomic directory creation with validation and error handling |
| `Test-CsvFile` | Validates CSV structure, required columns, and encoding before processing |
| `Test-WslDistro` | Validates that WSL distro is installed and accessible |
| `Save-JsonFile` | Safe JSON file writing with error handling and null byte sanitization |
| `Load-JsonFile` | Safe JSON file reading with error handling |
| `Format-ByteSize` | Converts byte counts to human-readable format (KB, MB, GB) |
| `Start-ScriptLogging` | Begins unified logging with timestamp and proper error capture |
| `Stop-ScriptLogging` | Ends logging and returns transcript path |
| `Get-ToolkitRoot` | Reliably discovers toolkit root directory from any script location |
| `Get-SafeFilename` | Sanitizes filenames by removing invalid characters |
| `Export-ModuleMember` | Exports all functions for use by other scripts |

**Usage Pattern (all scripts):**
```powershell
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$RootDir = Split-Path -Parent (Split-Path -Parent $ScriptDir)
$utilsPath = Join-Path $RootDir "Scripts\Utils.ps1"
if (-not (Test-Path $utilsPath)) { Write-Error "Utils.ps1 not found"; exit 1 }
. $utilsPath

# Now use functions directly
$config = Load-Config
$wslPath = ConvertTo-WslPath -WindowsPath "C:\backup\folder"
Invoke-WslCommand -DistroName $config.WslDistroName -Command "ls -la"
```

**Example: Load Config with Proper Precedence**
```powershell
# Old way (fragile, duplicated):
if (Test-Path "$RootDir\settings.json") {
    $config = Get-Content "$RootDir\settings.json" -Raw | ConvertFrom-Json
} else {
    $config = Get-Content "$RootDir\config.json" -Raw | ConvertFrom-Json
}

# New way (robust, centralized):
$config = Load-Config
# Automatically tries settings.json → config.json → hardcoded defaults
```

**Example: Convert Windows Path to WSL**
```powershell
# Old way (fragile):
$wslPath = "/mnt/" + ($backupDir.Substring(0,1).ToLower()) + $backupDir.Substring(2).Replace("\", "/")

# New way (robust, tested):
$wslPath = ConvertTo-WslPath -WindowsPath $backupDir
# Handles: C:\, D:\, Z:\, UNC paths, special characters
```

**Example: Execute WSL Command Safely**
```powershell
# Old way (error-prone):
wsl --exec bash -lc "command"
# Fails silently if distro doesn't exist

# New way (with validation):
Invoke-WslCommand -DistroName $config.WslDistroName -Command "command"
# Validates distro first, clear error messages, handles exit codes
```

---

### Start.ps1 - Entry Point & Helpers

**Responsibilities:**
- Display main menu
- Load/save configuration
- Validate distro selection
- Manage backup path selection
- Provide helper functions to other scripts

**Key Functions:**
```powershell
Load-Config                    # Load settings or config
Save-Settings [ref]$config    # Persist user config to settings.json
Validate-BackupPath           # Prompt for and validate backup directory
Validate-WslDistro [ref]$cfg  # Select/validate WSL distro
Find-BackupDirectory           # Locate timestamped backup folder
Show-Configuration             # Display current settings
Show-Menu                      # Display operation menu
```

### Get-Inventory.ps1 - System Scanning

**Workflow:**
1. Creates timestamped backup directory
2. Scans 4 sources in parallel:
   - **Winget**: `winget export -o JSON`
   - **Microsoft Store**: `Get-AppxPackage`
   - **Registry**: `HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall`
   - **WSL Apt**: `wsl --exec apt-mark showmanual`
3. Categorizes each app (System vs User-Installed)
4. Deduplicates entries
5. Exports to CSV with restoration commands

**Output Schema:**
```csv
Category,Application Name,Version,Environment,Source,Restoration Command,Keep (Y/N)
```

**Key Variables:**
```powershell
$masterList          # Array of all PSCustomObjects
$knownApps          # Hashtable for deduplication
$winSystemKeywords  # Regex patterns for Windows system apps
$linuxSystemKeywords # Regex patterns for Linux system packages
```

### Generate-Restore-Scripts.ps1 - Script Generation

**Workflow:**
1. Loads user-edited CSV (`SOFTWARE-INSTALLATION-INVENTORY.csv`)
2. Filters rows where `Keep (Y/N)` = TRUE
3. Groups by environment (Windows vs WSL)
4. Generates respective scripts
5. Outputs to `Installers/` directory

**Windows Script Output:**
```powershell
# Restore_Windows.ps1
winget install --id PackageId -e
winget install --id AnotherPackage -e
# Registry apps are commented with manual instructions
```

**Linux Script Output:**
```bash
# Restore_Linux.sh
sudo apt install -y package1 package2 package3
```

### Backup-WSL.ps1 - WSL Export

**Workflow:**
1. Validate distro exists
2. Create timestamped backup directory
3. Inject toolkit scripts (`~/.wsl-toolkit/`)
4. Run dotfile backup inside WSL
5. Copy dotfiles to backup drive (with 30-sec wait for sync)
6. Shutdown WSL
7. Export distro to tar file
8. Generate SHA256 hashes

**Key Features:**
- **30-second wait loop**: Handles WSL filesystem sync delays
- **File verification**: Ensures export completed
- **Hash report**: Integrity verification for restore

### Restore-WSL.ps1 - WSL Import

**Workflow:**
1. Find latest WSL backup directory
2. Import distro from tar file
3. Inject toolkit scripts
4. Restore dotfiles
5. Run post-install setup (apt update, install core tools)

**Environment Variables:**
```powershell
$Distro                # WSL distro name
$InstallLocation      # Where distro will be installed (C:\WSL\)
$BackupDir            # Where backup files are located
```

### Backup-AppData.ps1 - Settings Backup

**Workflow:**
1. Create timestamped backup directory
2. Load inventory CSV
3. Filter for apps with "Backup Settings = TRUE"
4. For each app:
   - Search AppData\Roaming and AppData\Local
   - Create ZIP archive
   - Log operation
5. Save folder mapping for later restore

**Key Functions:**
```powershell
Find-AppDataFolders        # Fuzzy search for app folders
Select-FolderFromMatches   # Let user pick if multiple matches
Prompt-ManualEntry        # Get folder name from user
Save-FolderMapping        # Persist app→folder map
```

### Restore-AppData.ps1 - Settings Restore

**Workflow:**
1. Find latest AppData backup
2. For each ZIP file:
   - Extract to temp location
   - Backup existing folder
   - Move restored folder to original location
   - Clean up temp files
3. Report results

**Error Handling:**
- Try-catch on each archive (one failure doesn't stop others)
- Temporary file cleanup on error
- Detailed logging of each step

---

## Error Handling Framework

### Pattern 1: Configuration Validation

```powershell
# Always validate config before use
if ([string]::IsNullOrWhiteSpace($config.BackupRootDirectory)) {
    Write-Error "BackupRootDirectory not configured. Run Start.ps1."
    exit 1
}

if (-not (Test-Path $config.BackupRootDirectory)) {
    Write-Error "Backup directory does not exist: $($config.BackupRootDirectory)"
    exit 1
}
```

### Pattern 2: File Operation Wrapping

```powershell
# Always use try-catch for file operations
try {
    New-Item -ItemType Directory -Force -Path $dirPath | Out-Null
} catch {
    Write-Error "Failed to create directory: $_"
    exit 1
}
```

### Pattern 3: External Command Exit Codes

```powershell
# Always check exit codes after external commands
wsl --export $Distro $exportFile
if ($LASTEXITCODE -ne 0) {
    Write-Error "WSL export failed with exit code $LASTEXITCODE"
    exit 1
}
```

### Pattern 4: File Existence Verification

```powershell
# Verify output files were actually created
if (-not (Test-Path $createdFile)) {
    Write-Error "Expected file was not created: $createdFile"
    exit 1
}
```

### Pattern 5: Filesystem Sync Handling

```powershell
# WSL→Windows filesystem sync can have delays
$maxWait = 30
$waited = 0
while (-not (Test-Path $targetPath) -and $waited -lt $maxWait) {
    Start-Sleep -Seconds 1
    $waited++
}

if (-not (Test-Path $targetPath)) {
    Write-Host "⚠ Warning: File sync timeout" -ForegroundColor Yellow
    # Continue anyway, file may be in WSL filesystem
}
```

---

## Configuration System

### Settings Persistence

User settings are saved to `settings.json`:

```powershell
# Load
$config = Get-Content "$RootDir\settings.json" | ConvertFrom-Json

# Modify
$config.WslDistroName = "Ubuntu"

# Save (with null byte sanitization)
$jsonString = $config | ConvertTo-Json
$jsonString = $jsonString -replace '\0', ''  # Remove null bytes
$jsonString | Out-File "$RootDir\settings.json" -Encoding UTF8 -Force
```

### Environment Variables

Scripts inherit from PowerShell session:
- `$PSScriptRoot` - Current script directory
- `$MyInvocation.MyCommand.Definition` - Script path
- `$LASTEXITCODE` - Exit code from last command

### Path Composition

```powershell
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$RootDir = Split-Path -Parent (Split-Path -Parent $ScriptDir)
# For subdirectory scripts, go up two levels
# For root scripts, go up one level
```

---

## Development Patterns

### Adding Configuration Options

**Step 1:** Add to `config.json`:
```json
{
  "NewOption": "default_value"
}
```

**Step 2:** Document in this file

**Step 3:** Load in script:
```powershell
$config = Load-Config
$value = $config.NewOption
```

### Adding Validation Functions

**Pattern:**
```powershell
function Validate-Something {
    param(
        [string]$Value
    )
    
    if ([string]::IsNullOrWhiteSpace($Value)) {
        Write-Error "Value cannot be empty"
        return $false
    }
    
    # Validation logic
    if (-not (Test-Path $Value)) {
        Write-Error "Path does not exist: $Value"
        return $false
    }
    
    return $true
}

# Usage
if (-not (Validate-Something $config.SomeValue)) {
    exit 1
}
```

### Adding Error Logging

```powershell
# Use Start-Transcript for automatic logging
$logFile = "$logDir\Operation_$(Get-Date -Format 'yyyyMMdd_HHmm').txt"
Start-Transcript -Path $logFile -Append | Out-Null

# Your operations...

Stop-Transcript | Out-Null
```

### Adding Menu Options

**In Start.ps1:**
```powershell
function Show-Menu {
    Write-Host "`nSelect an operation:" -ForegroundColor Cyan
    Write-Host "1) Get Inventory"
    Write-Host "2) Generate Restore Scripts"
    Write-Host "3) Backup WSL"
    Write-Host "4) Restore WSL"
    Write-Host "5) Backup AppData"
    Write-Host "6) Restore AppData"
    Write-Host "7) New Option Here"  # Add new option
    Write-Host "0) Exit"
    
    $choice = Read-Host "Enter option number"
    
    switch ($choice) {
        # ... existing cases ...
        "7" {
            . "$ScriptDir\Scripts\NewFeature\New-Script.ps1"
        }
    }
}
```

---

## Adding New Features

### Example: Add New Backup Type

**Step 1:** Create script directory:
```powershell
New-Item -ItemType Directory -Path "Scripts\NewFeature"
```

**Step 2:** Create backup script (e.g., `Backup-NewFeature.ps1`):
```powershell
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$RootDir = Split-Path -Parent (Split-Path -Parent $ScriptDir)
$utilsPath = Join-Path $RootDir "Scripts\Utils.ps1"
if (-not (Test-Path $utilsPath)) { Write-Error "Utils.ps1 not found"; exit 1 }
. $utilsPath

# Load config via Utils (not manually)
$config = Load-Config

# Validate prerequisites
if ([string]::IsNullOrWhiteSpace($config.BackupRootDirectory)) {
    Write-Error "Configuration required"
    exit 1
}

# Create timestamped directory using Utils function
$timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$backupDir = Join-Path $config.BackupRootDirectory "NewFeature\$timestamp"
New-DirectoryIfNotExists -Path $backupDir

# Your backup logic here
Write-Host "Backup complete: $backupDir" -ForegroundColor Green
```

**Key Improvements:**
- Import Utils.ps1 instead of duplicating functions
- Use `Load-Config` instead of inline JSON parsing
- Use `New-DirectoryIfNotExists` for reliable directory creation
- Use `Start-ScriptLogging`/`Stop-ScriptLogging` for unified logging

# Your backup logic here
Write-Host "Backup complete: $backupDir" -ForegroundColor Green
```

**Step 3:** Create restore script (e.g., `Restore-NewFeature.ps1`):
```powershell
# Similar structure to backup script
# Find latest backup, restore from it
```

**Step 4:** Add to Start.ps1 menu

**Step 5:** Add documentation

---

## Testing & Debugging

### Running Scripts in Development

**Interactive Mode:**
```powershell
# Load script without running
. .\Scripts\ApplicationInventory\Get-Inventory.ps1

# Call functions manually for testing
$config = Load-Config
Validate-WslDistro ([ref]$config)
```

**Debug Mode:**
```powershell
# Enable strict error reporting
$ErrorActionPreference = 'Stop'

# Use Write-Debug and -Debug flag
Write-Debug "Debug info: $value"
. .\script.ps1 -Debug
```

### Testing Error Paths

**Test 1: Missing Config**
```powershell
# Rename settings.json temporarily
Rename-Item settings.json settings.json.bak
. .\Start.ps1
# Should show error message
Rename-Item settings.json.bak settings.json
```

**Test 2: Invalid WSL Distro**
```powershell
# Edit settings.json: set WslDistroName = "NonExistent"
# Run Backup-WSL.ps1
# Should show clear error message
```

**Test 3: Missing Backup Directory**
```powershell
# Edit settings.json: set BackupRootDirectory = "Z:\NonExistent"
# Run any backup operation
# Should show validation error
```

### Viewing Logs

```powershell
# Find latest log
Get-ChildItem -Path "$BackupDir\*\Logs\" -Filter "*.txt" | Sort-Object LastWriteTime -Descending | Select-Object -First 1 | Get-Content
```

### WSL Debugging

```powershell
# Check distro status
wsl --list --verbose

# Run command in distro
wsl -d Ubuntu -- pwd

# SSH into distro
wsl -d Ubuntu

# Check WSL version
wsl --version
```

---

## Code Standards

### PowerShell Style

```powershell
# ✅ GOOD
if ($value -eq $null) {
    Write-Error "Value is null"
    exit 1
}

# ❌ AVOID
if (!$value) { ... }  # Unclear intent
```

**Naming Conventions:**
- Functions: `Verb-Noun` (Get-Config, Validate-Path)
- Variables: `$camelCase` for local, `$PascalCase` for module-wide
- Constants: `$CONSTANT_CASE`

**Error Handling:**
- Use `Write-Error` + `exit 1` for fatal errors
- Use `Write-Host "message" -ForegroundColor Yellow` for warnings
- Use `Write-Host "message" -ForegroundColor Green` for success
- Never swallow errors silently

**Comments:**
```powershell
# Section comments with dashes
# STEP 1: Load Configuration
$config = Load-Config

# Inline comments for complex logic
$distros = wsl -l --quiet | Where-Object { $_ -match [regex]::Escape($distroName) }
```

### Bash Style

```bash
#!/usr/bin/env bash
set -u  # Exit on undefined variables
set -e  # Exit on any error (optional, use in critical sections)

# Comments
CONSTANT_CASE="values"
local_var="values"

# Functions
function Do-Something {
    # Implementation
}

# Error handling
if ! command; then
    echo "Error message" >&2
    exit 1
fi
```

### Documentation

**Function Documentation:**
```powershell
<#
.SYNOPSIS
Brief description

.DESCRIPTION
Longer description of what the function does.

.PARAMETER ConfigObject
The configuration object

.RETURNS
What the function returns

.EXAMPLE
How to use the function
#>
function Do-Something {
    param(
        [PSCustomObject]$ConfigObject
    )
    # Implementation
}
```

---

## Performance Considerations

### Backup Performance

- **WSL Export**: 1-2GB per minute (depends on disk)
- **Dotfile Tar**: 100-500MB per minute
- **AppData Zip**: 10-50MB per minute

**Optimization:**
- Use SSD for backup (much faster)
- Run during off-hours (system load)
- Close large applications during backup
- Disable antivirus temporarily if slow

### Script Startup Time

- **Load-Config**: <10ms
- **Start-Transcript**: <50ms
- **WSL distro list**: 1-2 seconds
- **CSV import**: 10-100ms per 1000 rows

**Optimization:**
- Cache distro list if calling multiple times
- Use ForEach instead of iterative loops
- Minimize file I/O in loops

---

## Troubleshooting Development

### Common Issues

**Issue:** Script fails with "command not found"
- **Cause:** Distro not installed or wrong name
- **Fix:** Check `wsl --list --verbose`

**Issue:** "Permission denied" on file operations
- **Cause:** File is locked or insufficient permissions
- **Fix:** Close applications, run as administrator

**Issue:** CSV parsing errors
- **Cause:** Invalid line endings (CRLF vs LF)
- **Fix:** Ensure UTF-8 encoding, LF line endings

**Issue:** JSON serialization fails
- **Cause:** Special characters or null bytes
- **Fix:** Sanitize strings: `$str -replace '\0', ''`

---

## Recent Improvements & Changes (v2025.12)

### Major Refactoring Overview

**All scripts have been hardened, improved, and now use a centralized Utils.ps1 module.**

### Files Modified (7 PowerShell + 3 Bash)

#### PowerShell Scripts

| Script | Status | Changes |
|--------|--------|---------|
| `Scripts\Utils.ps1` | **NEW** | Created 400+ line module with 15 utilities |
| `Get-Inventory.ps1` | IMPROVED | Fixed timestamp shadowing, added registry filtering, uses Utils |
| `Generate-Restore-Scripts.ps1` | FIXED | Fixed config reference bug, added CSV validation, uses Utils |
| `Backup-AppData.ps1` | IMPROVED | Added directory validation, better error handling, uses Utils |
| `Restore-AppData.ps1` | FIXED | Fixed function definition order, improved path detection |
| `Backup-WSL.ps1` | IMPROVED | Replaced fragile path conversion with `ConvertTo-WslPath` |
| `Restore-WSL.ps1` | FIXED | Removed unsafe dot-sourcing, added local helper function |

#### Bash Scripts

| Script | Status | Changes |
|--------|--------|---------|
| `backup-dotfiles.sh` | ENHANCED | Item-by-item logging, archive size reporting |
| `restore-dotfiles.sh` | ENHANCED | Permission hardening (.ssh 700/600, .config 755/644) |
| `post-restore-install.sh` | ENHANCED | Package installation diagnosis, individual package fallback |

### Critical Bug Fixes

1. **Get-Inventory: Timestamp Variable Shadowing**
   - OLD: Reused `$timestamp` variable with different formats
   - NEW: Distinct variables (`$timestampDir` vs `$logTimestamp`)
   - Impact: Prevented directory creation failures

2. **Generate-Restore-Scripts: Config Reference Bug**
   - OLD: Referenced non-existent `$config.InstallersDirectory`
   - NEW: Uses calculated `$installDir` path
   - Impact: Script would fail when attempting to save restore scripts

3. **Restore-AppData: Function Definition Order**
   - OLD: Function `Determine-DestinationPath` defined AFTER being called
   - NEW: Helper function moved to TOP of script
   - Impact: Critical: Script could not execute at all

4. **Restore-WSL: Unsafe Dot-Sourcing**
   - OLD: Contained `. "$RootDir\Start.ps1"` (loads entire menu into execution scope)
   - NEW: Removed dot-source, added local `Find-BackupDirectory` function
   - Impact: Security improvement, prevents side effects from menu code

### Robustness Improvements

**Path Conversion:**
```powershell
# OLD (fragile)
$wslPath = "/mnt/" + ($path.Substring(0,1).ToLower()) + $path.Substring(2).Replace("\", "/")
# Fails on: UNC paths, edge cases, Z: drives

# NEW (robust)
$wslPath = ConvertTo-WslPath -WindowsPath $path
# Handles: All drive letters A-Z, UNC paths, special characters
```

**Configuration Loading:**
```powershell
# OLD (duplicated everywhere)
if (Test-Path "$RootDir\settings.json") {
    $config = Get-Content "$RootDir\settings.json" -Raw | ConvertFrom-Json
} else {
    $config = Get-Content "$RootDir\config.json" -Raw | ConvertFrom-Json
}

# NEW (centralized, tested once)
$config = Load-Config
# Proper precedence: settings.json → config.json → hardcoded defaults
```

**Directory Creation:**
```powershell
# OLD (error-prone)
New-Item -ItemType Directory -Force -Path $dir | Out-Null
# Doesn't validate, can fail silently

# NEW (validated)
New-DirectoryIfNotExists -Path $dir
# Validates existence, throws clear errors, atomic operation
```

**CSV Validation:**
```powershell
# OLD (no validation)
$csv = Import-Csv $file
# Crashes if file missing, format wrong, encoding bad

# NEW (defensive)
Test-CsvFile -Path $file -RequiredColumns @("Name", "Keep")
# Validates before import, clear error messages
```

**Logging:**
```powershell
# OLD (inline, inconsistent)
$logFile = "logs\$(Get-Date -Format 'yyyyMMdd_HHmm').txt"
Start-Transcript -Path $logFile

# NEW (centralized, unified)
$logFile = Start-ScriptLogging
# Proper timestamp format, consistent location, automatic cleanup
```

### Enhanced Error Handling

**Registry Filtering:**
- NEW: Validates `SystemComponent` check
- NEW: Requires `UninstallString` before inclusion
- Impact: Prevents system packages from being marked for reinstall

**CSV Validation:**
- NEW: Checks file exists before processing
- NEW: Validates required columns present
- NEW: Verifies encoding (UTF-8 preferred)
- Impact: Prevents silent failures with cryptic error messages

**Directory Validation:**
- NEW: `Test-WslDistro` validates distro existence
- NEW: Validates backup directory is writable
- NEW: Confirms path length doesn't exceed limits
- Impact: Clear feedback before operations begin

**JSON Operations:**
- NEW: `Save-JsonFile` sanitizes null bytes
- NEW: `Load-JsonFile` validates JSON syntax
- Impact: Prevents corruption, clearer error messages

### Performance & Logging Improvements

**Bash Scripts:**
- Enhanced logging shows each file backed up/restored
- Archive size reporting for backup operations
- Better error recovery with fallback mechanisms
- Permission hardening for sensitive directories

**PowerShell Scripts:**
- Unified logging format via `Start-ScriptLogging`
- Timestamp handling centralized in Utils
- Batch CSV operations (no line-by-line processing)

### Testing Coverage

All improvements have been verified to:
- ✅ Load correctly with proper precedence
- ✅ Handle edge cases (special characters, long paths)
- ✅ Provide clear error messages on failure
- ✅ Maintain backward compatibility
- ✅ No breaking changes to existing backups

---

## Resources

- [PowerShell Documentation](https://docs.microsoft.com/powershell/)
- [WSL Documentation](https://docs.microsoft.com/windows/wsl/)
- [Bash Guide](https://www.gnu.org/software/bash/manual/)

---

**Happy developing! Contributions welcome.**
