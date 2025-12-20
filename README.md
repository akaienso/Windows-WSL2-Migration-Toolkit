# 🔄 Windows & WSL2 Migration Toolkit

> **A complete "Wipe & Restore" solution for power users.**
> Inventory Windows apps, backup WSL environments, and generate "One-Click" restore scripts.

![PowerShell](https://img.shields.io/badge/PowerShell-5.1%20%7C%207-blue) ![Platform](https://img.shields.io/badge/Platform-Windows%20%7C%20WSL2-lightgrey) ![License](https://img.shields.io/badge/License-MIT-green)

## 🚀 Features
1.  **Windows App Inventory:** Scans Winget, Store, and Registry to build a complete list of your installed software.
2.  **Restore Generator:** Creates an automated PowerShell script to re-install your Windows apps.
3.  **WSL System Backup:** Exports your full Linux distro (Ubuntu/Debian) to an external drive.
4.  **WSL Restore:** Imports your distro backup and automatically fixes permissions and dotfiles.

---

## 📖 Usage Workflow

### Part 1: Windows Applications (Inventory & Restore)
1.  Run Start.ps1 -> Option 1.
    * Scans your system.
    * Saves CSV to /Inventories/INSTALLED-SOFTWARE-INVENTORY.csv.
2.  **Edit the CSV** (see [CSV Editing Workflow](#-csv-editing-workflow) below).
    * Copy `INSTALLED-SOFTWARE-INVENTORY.csv` → `SOFTWARE-INSTALLATION-INVENTORY.csv` in Inventories folder
    * Upload to Google Sheets (recommended for non-technical users) or edit directly
    * Set "Keep" to TRUE for apps you want to restore
    * Export & save back as `SOFTWARE-INSTALLATION-INVENTORY.csv`
3.  Run Start.ps1 -> Option 2.
    * Generates /Installers/Restore_Windows.ps1.

### Part 2: WSL Environment (Full Backup)

---

## 📋 CSV Editing Workflow

### Overview
After running **Option 1 (Get-Inventory)**, you'll have `INSTALLED-SOFTWARE-INVENTORY.csv` in the Inventories folder. Before proceeding to Option 2, you need to:
1. Copy it to `SOFTWARE-INSTALLATION-INVENTORY.csv` (the user-editable input file)
2. Edit to select which packages to restore
3. Save it back to the Inventories folder

### For Non-Technical Users: Google Sheets Method
1. Navigate to your Inventories folder
2. Copy `INSTALLED-SOFTWARE-INVENTORY.csv` to `SOFTWARE-INSTALLATION-INVENTORY.csv`
3. Open `SOFTWARE-INSTALLATION-INVENTORY.csv`
4. Go to [sheets.google.com](https://sheets.google.com) → **New** → **Upload file** → Select your CSV
5. **Optional: Convert Keep column to checkboxes** for easier editing:
   - Select column G (`Keep (Y/N)`)
   - Click **Data** → **Data Validation** → Select "Checkbox"
   - Map: Checked = "TRUE", Unchecked = "FALSE"
6. **Review your packages**:
   - Filter by `Environment` to see Windows apps separately from WSL apps
   - Filter by `Category` to review "System/Driver" items (usually safe to skip)
   - Check **only** the packages you want to restore
7. **Export & Save**:
   - Click **File** → **Download** → **CSV (.csv, current sheet)**
   - Save as `SOFTWARE-INSTALLATION-INVENTORY.csv`
   - Place it back in your Inventories folder (overwrite the copied version)

### For Technical Users: Direct Edit
- Open with VS Code or any text editor
- Edit the `Keep (Y/N)` column to TRUE/FALSE/Yes/No/Y/N/1/0 (case-insensitive)
- Save as UTF-8 (no BOM)
- Avoid Excel (it may change line endings)

### Important Notes
- **Input file**: `SOFTWARE-INSTALLATION-INVENTORY.csv` (user-edited copy)
- **Output file**: `INSTALLED-SOFTWARE-INVENTORY.csv` (system-generated, can be regenerated)
- **Location**: Place both in the `Inventories/` folder
- **Line endings**: Keep as LF (`\n`), not CRLF (`\r\n`) — Google Sheets handles this automatically
- **Registry apps**: Marked "Source: Registry (Manual)" — these cannot be auto-installed and require manual search
- **Keep column**: Flexible format — accepts TRUE/Yes/Y/1 (checked) or FALSE/No/N/0 (unchecked)

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
