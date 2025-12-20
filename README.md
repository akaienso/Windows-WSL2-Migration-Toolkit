# 🔄 Windows & WSL2 Migration Toolkit

> **A complete "Wipe & Restore" solution for power users.**
> Automatically inventory your Windows and Ubuntu (WSL2) applications, filter out system noise, and generate "One-Click" restore scripts for your fresh install.

![PowerShell](https://img.shields.io/badge/PowerShell-5.1%20%7C%207-blue) ![Platform](https://img.shields.io/badge/Platform-Windows%20%7C%20WSL2-lightgrey) ![License](https://img.shields.io/badge/License-MIT-green)

## 🚀 The Problem
Reformatting Windows is easy. Remembering exactly which 100+ utilities, CLI tools, and libraries you had installed—and re-installing them one by one—is a nightmare.

## 🛠 What This Toolkit Does
1.  **Unified Inventory:** Scans **Winget**, **Microsoft Store**, **Registry** (legacy apps), and **WSL2 (Ubuntu)** in a single pass.
2.  **Smart Filtering:** Automatically filters out "noise" (C++ Redistributables, Drivers, Linux Base System libs) so you see only *User-Installed Apps*.
3.  **Google Sheets Ready:** Outputs a CSV pre-formatted for Google Sheets with boolean checkboxes.
4.  **Restore Generator:** Reads your selected apps and auto-generates:
    * `Restore_Windows.ps1` (for Winget/Store)
    * `Restore_Linux.sh` (for Apt)

---

## 📦 Installation

1.  Clone this repository.
2.  Open PowerShell as Administrator.
3.  Run the main menu:
    ```powershell
    .\Start.ps1
    ```
    *(Note: On first run, it will auto-generate the folders `/Inventories`, `/Installers`, `/Logs`, and a `config.json` file.)*

---

## 📖 Usage Workflow

### Step 1: Scan Your Current Environment
1.  Launch `Start.ps1`.
2.  Select **Option 1: Generate Application Inventory**.
3.  The script will scan all environments and save the CSV to the `/Inventories` folder.

### Step 2: Select What to Keep
1.  Upload the CSV to **Google Drive** and open it with **Google Sheets**.
2.  Highlight the **"Keep (Y/N)"** column.
3.  Click **Insert > Checkbox**.
    * *The script pre-fills this column with `FALSE`, so they instantly become unchecked boxes.*
4.  Check the box next to every app you want to restore.
5.  **Export** the sheet as `SOFTWARE-INSTALLATION-INVENTORY.csv` (CSV format) and save it to the `/Inventories` folder.

### Step 3: Generate Installers
1.  Launch `Start.ps1`.
2.  Select **Option 2: Generate Installation Scripts**.
3.  The toolkit reads your selection and creates two files in the `/Installers` folder:
    * `Restore_Windows.ps1`
    * `Restore_Linux.sh`

### Step 4: The Fresh Start
After wiping your machine and reinstalling the toolkit:
1.  **Windows:** Run the bootstrap file `Run-Restore-Admin.bat` (located in the root). It will auto-elevate permissions and run your restore script.
2.  **Linux:** Open WSL, go to the `/Installers` folder, and run `bash Restore_Linux.sh`.

---

## ⚙️ Configuration
The tool manages paths via `config.json`. You can edit this file manually or allow the script to regenerate defaults.

```json
{
    "BasePath": ".", 
    "InventoryDirectory": "Inventories",
    "InstallersDirectory": "Installers",
    "ScriptDirectory": "Scripts",
    "LogDirectory": "Logs"
}
```

## 🛡 Features

- Winget First Strategy: If an app is found in both Winget and the Registry, the script prioritizes the Winget ID for cleaner restoration.
- Manual Install Detection: If you select a "Legacy/Registry" app that cannot be installed via CLI, the restore script adds a "Manual Attention Required" reminder at the end of the installation process.
- Smart Noise Filter:

    - Windows: Hides "KB Updates", "Intel/Nvidia Drivers", ".NET Frameworks", etc.
    - Linux: Hides "lib*", "python3-minimal", "coreutils", etc.

## 👨‍💻 Author
*Rob Moore*

🌐 [rmoore.dev](https://rmoore.dev) 
📧 [io@rmoore.dev](mailto:io@rmoore.dev)
🐙 [@akaienso](https://github.com/akaienso)

## 📄 License
MIT License. Free to use, modify, and distribute. '@ $content | Out-File -FilePath "$baseDir\README.md" -Encoding UTF8