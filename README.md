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
    * Saves CSV to /Inventories/INSTALLED_SOFTWARE_INVENTORY.csv.
2.  Edit the CSV (Set "Keep" to TRUE for apps you want).
3.  Run Start.ps1 -> Option 2.
    * Generates /Installers/Restore_Windows.ps1.

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
The config.json file handles paths.

{
    "ExternalBackupRoot": "D:\\Migration-Backups",
    "WslDistroName": "Ubuntu",
    "InventoryDirectory": "Inventories",
    "InstallersDirectory": "Installers"
}

* **ExternalBackupRoot**: Where heavy backup files (like WSL images) are stored.
* **InventoryDirectory**: Where lightweight CSVs are stored locally.

## 👨‍💻 Author
**Rob Moore**
* 🌐 [rmoore.dev](https://rmoore.dev)
* 📧 [io@rmoore.dev](mailto:io@rmoore.dev)
