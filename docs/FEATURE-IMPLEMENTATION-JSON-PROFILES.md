# Feature Implementation Summary: JSON Profiles & Home Directory Backup

**Date:** December 28, 2025  
**Status:** COMPLETE ✅

---

## Overview

Replaced CSV-based selection workflows with **JSON-based profiles** stored in `settings.json`. Added **Home Directory backup/restore** with preset profiles and interactive selection. This provides a much cleaner, more persistent user experience.

---

## New Features Implemented

### 1. JSON Profile System
**File:** `config.json` (updated)  
**Persisted in:** `settings.json` (created by user on first run)

Three new profile sections replace CSV workflows:

```json
{
  "AppSelectionProfile": {
    "Name": "Default",
    "LastUpdated": "2025-12-28T10:00:00Z",
    "SelectedApps": {
      "Windows": ["app1", "app2"],
      "WSL": ["package1", "package2"]
    }
  },
  
  "AppDataBackupProfile": {
    "Name": "Default",
    "SelectedApps": ["Firefox", "VS Code"],
    "FolderMappings": { "Firefox": "Mozilla Firefox" }
  },
  
  "HomeDirectoryProfile": {
    "Name": "Default",
    "SelectedDirectories": [".ssh", ".config", ".bashrc"],
    "PresetProfiles": {
      "Essential": { "Directories": [...] },
      "Standard": { "Directories": [...] },
      "Full": { "Directories": ["*"] }
    }
  }
}
```

**Key Benefits:**
- Selections persist automatically
- No CSV editing required
- Profiles can be easily shared, backed up, or reset
- Supports multiple named profiles (future enhancement)

---

### 2. Interactive App Selection Script
**File:** `Scripts/ApplicationInventory/Select-Apps-Interactive.ps1` (NEW)  
**Called by:** Option 2 in menu OR automatically after Get-Inventory  
**Output:** Updates `settings.json` with selected apps

**Features:**
- Shows all discovered applications organized by category
- Supports [Y/N] prompts for each app
- Retains previous selections if they exist (with option to reset)
- Saves selections to `AppSelectionProfile` in `settings.json`
- Categories:
  - System/Driver (Auto-Detected)
  - System/Base (Linux)
  - User-Installed Application

**Workflow:**
```
Get-Inventory.ps1
  ↓ [Offers to continue]
  ↓
Select-Apps-Interactive.ps1 [NEW]
  ↓ [Saves to settings.json]
  ↓
Generate-Restore-Scripts.ps1
```

---

### 3. Home Directory Backup Script
**File:** `Scripts/WSL/Backup-HomeDirectory.ps1` (NEW)  
**Menu Option:** 6  
**Output:** Timestamped TAR.GZ archive + profile

**Features:**
- Auto-discovers home directories with sizes
- 4 preset profiles:
  - **Essential:** Config files only (.ssh, .bashrc, .zshrc, .gitconfig)
  - **Standard:** Essential + common dirs (.config, .local, Documents)
  - **Full:** Everything except caches/trash
  - **Custom:** User selects individual directories
- [Y/N] prompts for custom selection
- Saves selections to `HomeDirectoryProfile` in `settings.json`
- Creates TAR.GZ archives with `--ignore-failed-read` (graceful on permission errors)
- Archives stored in: `BackupRoot/HomeDirectory/[timestamp]/`

**Example Archive:**
```
home-directories_20251228_143022.tar.gz (includes selected dirs from preset)
```

---

### 4. Home Directory Restore Script
**File:** `Scripts/WSL/Restore-HomeDirectory.ps1` (NEW)  
**Menu Option:** 7  
**Input:** Latest backup from `BackupRoot/HomeDirectory/`

**Features:**
- Auto-locates latest backup
- Previews contents before restore
- Creates pre-restore backup (timestamped, separate archive)
- Asks for confirmation before overwriting
- Fixes file permissions post-restore:
  - `.ssh/`: 700 (dir) / 600 (files)
  - `.config/`: 755 (dir) / 644 (files)
  - `.local/`: 755 (dir) / 644 (files)
- Provides rollback instructions if needed

---

### 5. Refactored Get-Inventory.ps1
**File:** `Scripts/ApplicationInventory/Get-Inventory.ps1` (MODIFIED)  
**New Behavior:**
- Still generates CSV (for reference)
- **NEW:** Automatically offers to launch Select-Apps-Interactive.ps1
- User can skip and run interactively later

---

### 6. Refactored Backup-AppData.ps1
**File:** `Scripts/AppData/Backup-AppData.ps1` (REPLACED)  
**Input:** `AppDataBackupProfile` from `settings.json`  
**Output:** ZIP files + AppData_Folder_Map.json

**Changes:**
- ✅ Reads from `settings.json` profile instead of CSV
- ✅ Skips CSV-based "Backup Settings (Y/N)" column
- ✅ Uses profile's `SelectedApps` list
- ✅ Retains fuzzy-matching logic for folder discovery
- ✅ Preserves backward compatibility with AppData_Folder_Map.json
- ✅ Prompts to configure apps if profile is empty

---

### 7. Updated Start.ps1 Menu
**File:** `Start.ps1` (MODIFIED)

**New Menu Layout:**
```
1. Generate Application Inventory
2. Select Apps to Restore (Interactive)        [NEW]
3. Generate Installation Scripts
4. Backup WSL System
5. Restore WSL System
6. Backup Home Directory (Configs/Dotfiles)   [NEW]
7. Restore Home Directory                      [NEW]
8. Backup AppData Settings (was 5)
9. Restore AppData Settings (was 6)
Q. Quit
```

**Simplified Flow:**
```
Option 1 → Inventory generated (→ Option 2 offered)
        ↓
Option 2 → Interactive selection (saves to settings.json)
        ↓
Option 3 → Generate scripts (reads from settings.json profile)
```

---

## Migration Path (for existing users with CSV)

### If You Have Existing CSV Files:
1. Run **Option 1** (Get-Inventory) - CSV still generated
2. Run **Option 2** (Select-Apps-Interactive)
   - Script detects CSV selections (if any)
   - Offers to restore previous choices
   - Saves to `settings.json` instead
3. Delete old CSV files (optional, they still work as reference)

### No Data Loss:
- CSV files remain untouched
- All selections automatically migrate to `settings.json`
- Can delete CSV anytime after profile is saved

---

## File Structure Changes

### New Files
```
Scripts/
  ApplicationInventory/
    Select-Apps-Interactive.ps1    [NEW]
  
  WSL/
    Backup-HomeDirectory.ps1       [NEW]
    Restore-HomeDirectory.ps1      [NEW]
```

### Modified Files
```
config.json                        [Added profile schemas]
Start.ps1                          [Menu reorganized 4→9 options]
Scripts/ApplicationInventory/
  Get-Inventory.ps1               [Auto-launches interactive selection]
Scripts/AppData/
  Backup-AppData.ps1              [Now reads JSON profiles]
```

### Backup of Legacy Code
```
Scripts/AppData/
  Backup-AppData.ps1.bak          [Original CSV-based version]
```

---

## Configuration Details

### config.json
Template with empty profiles. Profiles get populated in `settings.json` on first use.

### settings.json
User-persisted settings file. Created/updated automatically:
- After initial Start.ps1 setup
- After running Get-Inventory → Select-Apps-Interactive
- After running Backup-HomeDirectory
- After running Backup-AppData

### Example settings.json (after Option 2)
```json
{
  "BackupRootDirectory": "D:\\Windows-WSL2-Backup",
  "WslDistroName": "Ubuntu",
  "AppSelectionProfile": {
    "Name": "Default",
    "LastUpdated": "2025-12-28T14:30:00Z",
    "SelectedApps": {
      "Windows": ["Microsoft.VLC", "Git.Git"],
      "WSL": ["curl", "wget", "build-essential"]
    }
  },
  "HomeDirectoryProfile": {
    "Name": "Default",
    "LastUpdated": "2025-12-28T14:35:00Z",
    "SelectedDirectories": [".ssh", ".bashrc", ".config", "Documents"]
  }
}
```

---

## User Workflows

### Workflow 1: App Restore (New Interactive Way)
```
Start.ps1
  ↓ Option 1: Get-Inventory
    (scans Windows/WSL)
  ↓ [Prompts] Continue with selection? → Y
  ↓ Option 2: Select-Apps-Interactive
    [Shows each app, [Y/N] to select]
    [Saves selections to settings.json]
  ↓ Option 3: Generate-Restore-Scripts
    (reads from settings.json profile)
    [Creates Restore_Windows.ps1 + Restore_Linux.sh]
```

### Workflow 2: Home Directory Backup
```
Start.ps1
  ↓ Option 6: Backup-HomeDirectory
    [Discovers directories with sizes]
    [Preset: E/S/F/C]
    [Creates TAR.GZ archive]
    [Saves selections to settings.json]
```

### Workflow 3: Home Directory Restore
```
Start.ps1
  ↓ Option 7: Restore-HomeDirectory
    [Locates latest backup]
    [Previews contents]
    [Confirmation prompt]
    [Pre-restore backup created]
    [Restores + fixes permissions]
```

### Workflow 4: AppData Backup (JSON-based)
```
Start.ps1
  ↓ Option 8: Backup-AppData
    [Reads from settings.json profile]
    [Fuzzy-matches folders]
    [Creates ZIP files]
    [Saves folder mappings]
```

---

## Benefits Summary

| Feature | Before | After |
|---------|--------|-------|
| App Selection | CSV editing (error-prone) | Interactive [Y/N] prompts |
| Selection Persistence | Manual CSV copies | Auto-saved to settings.json |
| Home Directory Backup | Not available | ✅ New with 4 presets |
| AppData Selection | CSV "Backup Settings" column | JSON profile |
| Configuration | Multiple file types | Single settings.json |
| User Friction | High (CSV editing) | Low (interactive) |
| Recovery | Manual from CSV | Auto-saved profiles |

---

## Testing Checklist

- [x] Syntax validation (all new scripts)
- [x] config.json updated with profile schemas
- [x] Start.ps1 menu updated (options 1-9)
- [ ] **End-to-end testing needed** (see next section)

---

## Next Steps / Testing

### Critical: End-to-End Test
Run through all 9 menu options in sequence:

**Phase 1: Inventory & Selection**
```
1. Get-Inventory → verify CSV created
2. Select-Apps-Interactive → select some apps
   → verify settings.json created/updated
```

**Phase 2: Restore Scripts**
```
3. Generate-Restore-Scripts → verify reads from profile
   → scripts created
```

**Phase 3: WSL Backup/Restore**
```
4. Backup-WSL → verify backup created
5. Restore-WSL → (optional, requires backup from step 4)
```

**Phase 4: Home Directory Backup/Restore**
```
6. Backup-HomeDirectory → select preset/custom
   → verify TAR.GZ created
   → verify profile saved
7. Restore-HomeDirectory → verify pre-restore backup + restore
```

**Phase 5: AppData Backup/Restore**
```
8. Backup-AppData → verify reads profile
   → prompts if empty
9. Restore-AppData → (optional, requires backup from step 8)
```

### Known Limitations
- Home directory backup only works in WSL (uses tar + bash scripts)
- AppData backup only works for Windows apps (Store/WSL skipped)
- Profiles in settings.json must be manually reset/edited (no UI to manage multiple profiles yet)

### Future Enhancements
- [ ] Multiple named profiles (e.g., "Work", "Gaming", "Minimal")
- [ ] Profile comparison tool
- [ ] Web UI for selection (instead of CLI)
- [ ] Dry-run mode for backups
- [ ] Incremental home directory backups

---

## Commit Message
```
feat: Replace CSV with JSON profiles + add home directory backup

- New interactive app selection script (Option 2)
- New home directory backup/restore scripts (Options 6-7)
- Refactored Backup-AppData to use JSON profiles
- Updated Start.ps1 menu (4→9 options)
- All selections now persist to settings.json
- Home directory backup supports 4 presets (Essential/Standard/Full/Custom)
- Backward compatible with existing CSV files
```

---

**Implementation Complete ✅**  
All scripts tested for syntax. Ready for end-to-end testing.
