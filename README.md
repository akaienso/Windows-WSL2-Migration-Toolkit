# 🔄 Windows & WSL2 Migration Toolkit

> **A complete "Wipe & Restore" solution for power users.**
> Inventory apps, generate restore scripts, and perform full WSL distro backups.

![PowerShell](https://img.shields.io/badge/PowerShell-5.1%20%7C%207-blue) ![Platform](https://img.shields.io/badge/Platform-Windows%20%7C%20WSL2-lightgrey) ![License](https://img.shields.io/badge/License-MIT-green)

## 🚀 Features
1.  **App Inventory:** Scans Winget, Store, Registry, and WSL packages.
2.  **Restore Generator:** Creates "One-Click" restore scripts for Windows & Linux apps.
3.  **Full WSL Backup:** Exports your entire WSL distro (filesystem + dotfiles) to an external drive or cloud storage with integrity hashes.
4.  **WSL Restore:** Imports your distro backup and automatically "self-heals" scripts and dotfiles.

---

## 📖 Usage Workflow

### 1. App Inventory (Soft Backup)
1.  Run Start.ps1 -> Option 1.
2.  Edit the CSV in /Inventories (check the "Keep" box).
3.  Run Start.ps1 -> Option 2 to generate restore scripts.

### 2. Full WSL System Backup (Hard Backup)
1.  Run Start.ps1 -> Option 3 (Backup WSL Environment).
2.  This will:
    * Inject backup helpers into WSL.
    * Export your .bashrc, .ssh, etc.
    * Export the full distro image to your configured Backup path (Default: D:\WSL-Backups).
    * Verify SHA-256 hashes.

### 3. The Fresh Start (Restore)
1.  **Windows Apps:** Run Run-Restore-Admin.bat.
2.  **WSL Distro:** Run Start.ps1 -> Option 4 (Restore WSL Environment).
    * This imports your distro from the external drive.
    * Automatically fixes SSH permissions.
    * Reinstalls core dev tools.

---

## ⚙️ Configuration
The config.json file handles paths.

```json
{
    "WslDistroName": "Ubuntu",
    "WslBackupDirectory": "D:\\WSL-Backups",
    "InventoryDirectory": "Inventories",
    "InstallersDirectory": "Installers"
}
```

## 👨‍💻 Author
**Rob Moore**
* 🌐 [rmoore.dev](https://rmoore.dev)
* 📧 [io@rmoore.dev](mailto:io@rmoore.dev)
