# 🔄 Windows & WSL2 Migration Toolkit

> **A complete "Wipe & Restore" solution for power users.**
> Inventory Windows apps, backup WSL environments, and generate "One-Click" restore scripts.

![PowerShell](https://img.shields.io/badge/PowerShell-5.1%20%7C%207-blue) ![Platform](https://img.shields.io/badge/Platform-Windows%20%7C%20WSL2-lightgrey) ![License](https://img.shields.io/badge/License-MIT-green)

## � Documentation

For comprehensive guides and reference materials, see:
- **[Documentation Index](docs/INDEX.md)** - Start here for guidance by role- **[User Guide](docs/USER-GUIDE.md)** - Step-by-step workflows, troubleshooting, and FAQ
- **[Developer Guide](docs/DEVELOPER-GUIDE.md)** - Architecture, code patterns, and extending the toolkit
- **[Error Handling Guide](docs/ERROR-HANDLING-AUDIT.md)** - Complete error handling framework and patterns
- **[Quick Reference](docs/ERROR-HANDLING-QUICK-REFERENCE.md)** - Common errors and quick fixes

## �🚀 Features
1.  **Windows App Inventory:** Scans Winget, Store, and Registry to build a complete list of your installed software.
2.  **Restore Generator:** Creates an automated PowerShell script to re-install your Windows apps.
3.  **AppData Backup & Restore:** Selectively backup application settings and configuration files to an external drive, then restore them after a fresh install.
4.  **WSL System Backup:** Exports your full Linux distro (Ubuntu/Debian) to an external drive.
5.  **WSL Restore:** Imports your distro backup and automatically fixes permissions and dotfiles.

---

## 📖 Usage Workflow

### Part 1: Windows Applications (Inventory & Restore)
1.  Run Start.ps1 -> Option 1.
    * Scans your system.
    * Saves CSV to /Inventories/INSTALLED-SOFTWARE-INVENTORY.csv.
    * Includes two decision columns: `Keep (Y/N)` and `Backup Settings (Y/N)` (both default to FALSE).

2.  **Edit the CSV** (see [CSV Editing Workflow](#-csv-editing-workflow) below).
    * Copy `INSTALLED-SOFTWARE-INVENTORY.csv` → `SOFTWARE-INSTALLATION-INVENTORY.csv` in Inventories folder
    * Upload to Google Sheets (recommended for non-technical users) or edit directly
    * **Set `Keep (Y/N)` to TRUE** for apps you want to reinstall after a fresh Windows install
    * **Set `Backup Settings (Y/N)` to TRUE** for apps whose settings/configuration you want to backup (optional but recommended)
    * Export & save back as `SOFTWARE-INSTALLATION-INVENTORY.csv`

3.  Run Start.ps1 -> Option 2.
    * Generates /Installers/Restore_Windows.ps1 (installs apps marked with `Keep (Y/N)` = TRUE).


### Part 1B: Application Settings Backup (Optional)
If you want to backup application settings (configuration files, preferences, etc.) before a fresh install:

1.  Run Start.ps1 -> Option 5.
    * Reads `SOFTWARE-INSTALLATION-INVENTORY.csv`
    * For each app marked with `Backup Settings (Y/N)` = TRUE, searches %APPDATA% and %LOCALAPPDATA%
    * Uses fuzzy matching on the application name to find config folders
    * Compresses matching folders into ZIP files with timestamps
    * Saves to `[ExternalBackupRoot]\AppData_Backups`
    * Generates detailed log of backed-up folders

2.  After your fresh Windows install, run Start.ps1 -> Option 6.
    * Reads ZIP files from `[ExternalBackupRoot]\AppData_Backups`
    * Restores each backup to its original location
    * Creates timestamped backups of existing data before overwriting
    * After restore, restart affected applications to reload settings

**⚠️ Important Notes on AppData Backup:**
- Uses "fuzzy matching" — may miss folders if the app name differs from folder name (e.g., "Mozilla Firefox" vs "Mozilla")
- Only backs up user-installed Windows applications (skips Store apps and WSL packages)
- Some applications may require re-authentication or additional configuration after restore
- This is complementary to app restoration — backup settings independently from reinstalling the app itself

### Part 2: WSL Environment (Full Backup)

---

## 📋 CSV Editing Workflow

### Overview
After running **Option 1 (Get-Inventory)**, you'll have `INSTALLED-SOFTWARE-INVENTORY.csv` in the Inventories folder with two decision columns:
- **`Keep (Y/N)`**: Set to TRUE for apps you want to reinstall
- **`Backup Settings (Y/N)`**: Set to TRUE for apps whose settings you want to backup (optional)

Before proceeding, you need to:
1. Copy it to `SOFTWARE-INSTALLATION-INVENTORY.csv` (the user-editable input file)
2. Edit to select which packages to restore and/or backup settings for
3. Save it back to the Inventories folder


### For Non-Technical Users: Google Sheets Method
1. Navigate to your Inventories folder
2. Copy `INSTALLED-SOFTWARE-INVENTORY.csv` to `SOFTWARE-INSTALLATION-INVENTORY.csv`
3. Open `SOFTWARE-INSTALLATION-INVENTORY.csv`
4. Go to [sheets.google.com](https://sheets.google.com) → **New** → **Upload file** → Select your CSV
5. **Optional: Convert boolean columns to checkboxes** for easier editing:
   - Select column G (`Keep (Y/N)`) and optionally column H (`Backup Settings (Y/N)`)
   - Click **Data** → **Data Validation** → Select "Checkbox"
   - Map: Checked = "TRUE", Unchecked = "FALSE"
6. **Review and mark your packages**:
   - Filter by `Environment` to see Windows apps separately from WSL apps
   - Filter by `Category` to review "System/Driver" items (usually safe to skip)
   - **For app reinstallation**: Check **`Keep (Y/N)`** for apps you want to reinstall after fresh Windows install
   - **For settings backup**: Check **`Backup Settings (Y/N)`** for apps whose configuration you want to preserve (independent choice — you can keep settings without reinstalling, or vice versa)
7. **Export & Save**:
   - Click **File** → **Download** → **CSV (.csv, current sheet)**
   - Save as `SOFTWARE-INSTALLATION-INVENTORY.csv`
   - Place it back in your Inventories folder (overwrite the copied version)

### For Technical Users: Direct Edit
- Open with VS Code or any text editor
- Edit the `Keep (Y/N)` column to TRUE/FALSE/Yes/No/Y/N/1/0 (case-insensitive)
- Edit the `Backup Settings (Y/N)` column similarly (optional)
- Save as UTF-8 (no BOM)
- Avoid Excel (it may change line endings)

### Important Notes
- **Input file**: `SOFTWARE-INSTALLATION-INVENTORY.csv` (user-edited copy)
- **Output file**: `INSTALLED-SOFTWARE-INVENTORY.csv` (system-generated, can be regenerated)
- **Location**: Place both in the `Inventories/` folder
- **Line endings**: Keep as LF (`\n`), not CRLF (`\r\n`) — Google Sheets handles this automatically
- **Registry apps**: Marked "Source: Registry (Manual)" — these cannot be auto-installed and require manual search
- **Keep column**: Flexible format — accepts TRUE/Yes/Y/1 (checked) or FALSE/No/N/0 (unchecked)
- **Backup Settings column**: Same flexible format — set TRUE for apps whose configuration you want to preserve



---

### Part 2: WSL Environment (Full Backup)
1.  Run Start.ps1 -> Option 3.
    * Injects backup helpers into WSL.
    * Exports the full distro image to your External Backup Root (Default: D:\Migration-Backups\WSL).
    * Verifies integrity hashes.

### Part 3: The Fresh Start
1.  **Windows Apps:** Run Run-Restore-Admin.bat (in the root folder).
2.  **WSL Distro:** Run Start.ps1 -> Option 4.

---

## ⚙️ Configuration
The config.json file handles paths and settings.

```json
{
    "ExternalBackupRoot": "",
    "WslDistroName": "Ubuntu",
    "InventoryDirectory": "Inventories",
    "InstallersDirectory": "Installers"
}
```

* **ExternalBackupRoot**: Where heavy backup files (like WSL images) are stored. **Leave empty on first run**—you'll be prompted to set this location. If you don't provide one, it defaults to `./migration-backups` (relative to the toolkit folder).
* **WslDistroName**: The name of your WSL distro (default: Ubuntu).
* **InventoryDirectory**: Where lightweight CSVs are stored locally.
* **InstallersDirectory**: Where generated restore scripts are saved.

## 👨‍💻 Author
**Rob Moore**
* 🌐 [rmoore.dev](https://rmoore.dev)
* 📧 [io@rmoore.dev](mailto:io@rmoore.dev)
