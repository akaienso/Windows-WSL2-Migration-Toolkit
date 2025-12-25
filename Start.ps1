# ==============================================================================
# SCRIPT: Start.ps1 (System Migration Toolkit - Main Menu)
# ==============================================================================

$PSScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition
Set-Location -Path $PSScriptRoot
$configPath = "$PSScriptRoot\config.json"
$settingsPath = "$PSScriptRoot\settings.json"

# Initialize global variable for backup root (used by Load-Config)
$global:BackupRootTemp = ""

# --- DEFAULT CONFIGURATION ---
$defaultConfig = @{
    BasePath            = "." 
    ScriptDirectory     = "Scripts"
    LogDirectory        = "Logs"
    BackupRootDirectory = ""
    WslDistroName       = ""
    InventoryOutputCSV  = "INSTALLED-SOFTWARE-INVENTORY.csv"
    InventoryInputCSV   = "SOFTWARE-INSTALLATION-INVENTORY.csv"
}

# --- LOAD / CREATE CONFIG ---
function Load-Config {
    # Try settings.json in toolkit root first (persisted user settings)
    if (Test-Path $settingsPath) {
        $loaded = Get-Content $settingsPath -Raw | ConvertFrom-Json
        return $loaded
    }
    
    # Fall back to config.json in toolkit (default/template)
    if (Test-Path $configPath) {
        $loaded = Get-Content $configPath -Raw | ConvertFrom-Json
        foreach ($key in $defaultConfig.Keys) {
            if (-not $loaded.PSObject.Properties[$key]) {
                $loaded | Add-Member -NotePropertyName $key -NotePropertyValue $defaultConfig[$key]
            }
        }
        return $loaded
    } else {
        $defaultConfig | ConvertTo-Json | Out-File $configPath -Encoding UTF8
        return $defaultConfig
    }
}

$currentConfig = Load-Config

# --- INIT FOLDERS ---
function Init-Folders {
    $dirs = @(
        $currentConfig.ScriptDirectory
    )
    foreach ($d in $dirs) {
        if (-not (Test-Path "$PSScriptRoot\$d")) {
            New-Item -ItemType Directory -Force -Path "$PSScriptRoot\$d" | Out-Null
        }
    }
}
Init-Folders

# --- VALIDATE/SETUP BACKUP PATH ---
function Validate-BackupPath {
    param([ref]$config)
    
    $backupPath = $config.Value.BackupRootDirectory
    
    # If path is empty or invalid, use default or prompt user
    if ([string]::IsNullOrWhiteSpace($backupPath)) {
        $defaultPath = Join-Path (Split-Path -Parent $PSScriptRoot) "Windows-WSL2-Backup"
        Write-Host "`n⚠ Backup Location Not Set" -ForegroundColor Yellow
        Write-Host "You need to specify where backups will be stored.`n" -ForegroundColor Cyan
        
        Write-Host "Default: $defaultPath" -ForegroundColor DarkGray
        Write-Host "Enter path (press Enter for default): " -ForegroundColor Cyan -NoNewline
        $userPath = Read-Host
        
        if ([string]::IsNullOrWhiteSpace($userPath)) {
            $backupPath = $defaultPath
        } else {
            $backupPath = $userPath
        }
    }
    
    # Resolve the path to absolute (if relative, make it relative to toolkit parent)
    if (-not [System.IO.Path]::IsPathRooted($backupPath)) {
        $backupPath = Join-Path (Split-Path -Parent $PSScriptRoot) $backupPath
    }
    
    # Validate the path doesn't have invalid characters
    $invalidChars = [System.IO.Path]::GetInvalidPathChars()
    if ($backupPath -match "[$([regex]::Escape($invalidChars))]") {
        Write-Host "✗ Invalid path - contains illegal characters: $backupPath" -ForegroundColor Red
        Write-Host "Using default location instead..." -ForegroundColor Yellow
        $backupPath = Join-Path (Split-Path -Parent $PSScriptRoot) "Windows-WSL2-Backup"
    }
    
    # Check if the directory exists
    if (-not (Test-Path $backupPath)) {
        Write-Host "`n⚠ Backup directory does not exist: $backupPath" -ForegroundColor Yellow
        Write-Host "Create this directory? (Y/n): " -ForegroundColor Cyan -NoNewline
        $createDir = Read-Host
        
        if ([string]::IsNullOrWhiteSpace($createDir) -or $createDir -match '^[yY]$') {
            try {
                New-Item -ItemType Directory -Force -Path $backupPath | Out-Null
                Write-Host "✓ Created backup directory: $backupPath" -ForegroundColor Green
            } catch {
                Write-Host "✗ Failed to create directory: $_" -ForegroundColor Red
                Write-Host "Using default location instead..." -ForegroundColor Yellow
                $backupPath = Join-Path (Split-Path -Parent $PSScriptRoot) "Windows-WSL2-Backup"
                New-Item -ItemType Directory -Force -Path $backupPath | Out-Null
            }
        } else {
            Write-Host "Cannot proceed without backup directory." -ForegroundColor Red
            exit 1
        }
    } else {
        Write-Host "✓ Backup directory exists: $backupPath" -ForegroundColor Green
    }
    
    # Update config
    $config.Value.BackupRootDirectory = $backupPath
    
    # Store in global for later settings.json save
    $global:BackupRootTemp = $backupPath
}

$currentConfig = Load-Config
Validate-BackupPath ([ref]$currentConfig)

# --- VALIDATE/SETUP WSL DISTRO ---
function Validate-WslDistro {
    param([ref]$config)
    
    $distro = $config.Value.WslDistroName
    
    # If not set, prompt user
    if ([string]::IsNullOrWhiteSpace($distro)) {
        Write-Host "`n⚠ WSL Distro Not Configured" -ForegroundColor Yellow
        Write-Host "Scanning for installed WSL distros..." -ForegroundColor Cyan
        
        # Try to list available distros from WSL
        $availableDistros = @()
        try {
            $wslOutput = wsl --list --quiet 2>$null
            if ($wslOutput) {
                # Split, trim, and keep only lines with actual text (contain at least one letter)
                $availableDistros = @($wslOutput.Split(@("`r`n", "`n", "`r"), [System.StringSplitOptions]::None) | 
                    ForEach-Object { $_.Trim() } | 
                    Where-Object { $_ -match '[a-zA-Z]' })
            }
        } catch {
            # WSL might not be installed
        }
        
        # If exactly one distro found, use it automatically
        if ($availableDistros.Count -eq 1) {
            $distro = $availableDistros[0] -replace '\0', ''  # Strip null bytes
            Write-Host "✓ Auto-detected distro: $distro" -ForegroundColor Green
        } elseif ($availableDistros.Count -gt 1) {
            # Multiple distros - ask user to choose
            Write-Host "`nInstalled WSL Distros:" -ForegroundColor Cyan
            for ($i = 0; $i -lt $availableDistros.Count; $i++) {
                Write-Host "  $($i + 1). $($availableDistros[$i])" -ForegroundColor White
            }
            
            Write-Host "`nSelect a distro (1-$($availableDistros.Count)): " -ForegroundColor Cyan -NoNewline
            $selection = Read-Host
            
            if ($selection -match "^\d+$") {
                $selNum = [int]$selection
                if ($selNum -ge 1 -and $selNum -le $availableDistros.Count) {
                    $distro = $availableDistros[$selNum - 1] -replace '\0', ''  # Strip null bytes
                } else {
                    Write-Host "Invalid selection. Using first distro." -ForegroundColor Yellow
                    $distro = $availableDistros[0] -replace '\0', ''  # Strip null bytes
                }
            } else {
                Write-Host "Invalid input. Using first distro." -ForegroundColor Yellow
                $distro = $availableDistros[0] -replace '\0', ''  # Strip null bytes
            }
        } else {
            # No distros found - WSL must be installed with at least one distro
            Write-Host "`n✗ No WSL Distros Found" -ForegroundColor Red
            Write-Host "`nThis toolkit requires Windows Subsystem for Linux (WSL2) with at least one distro installed." -ForegroundColor Yellow
            Write-Host "`nTo use this toolkit:" -ForegroundColor Cyan
            Write-Host "  1. Install WSL2: https://docs.microsoft.com/en-us/windows/wsl/install" -ForegroundColor White
            Write-Host "  2. Install a distro (Ubuntu, Debian, etc.)" -ForegroundColor White
            Write-Host "  3. Run this toolkit again" -ForegroundColor White
            Write-Host ""
            exit 1
        }
        
        # Update config
        $config.Value.WslDistroName = $distro
        Write-Host "✓ WSL Distro set to: $distro" -ForegroundColor Green
    }
}

Validate-WslDistro ([ref]$currentConfig)

# --- DISPLAY CONFIGURATION ---
function Show-Configuration {
    param([ref]$config)
    
    Write-Host "`n╔════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║          CURRENT CONFIGURATION              ║" -ForegroundColor Cyan
    Write-Host "╚════════════════════════════════════════════╝" -ForegroundColor Cyan
    
    Write-Host "`n📁 Backup Location:" -ForegroundColor Cyan
    Write-Host "   $($config.Value.BackupRootDirectory)" -ForegroundColor White
    
    Write-Host "`n🐧 WSL Distro:" -ForegroundColor Cyan
    Write-Host "   $($config.Value.WslDistroName)" -ForegroundColor White
    
    Write-Host "`n📂 Toolkit Directories:" -ForegroundColor Cyan
    Write-Host "   Scripts:  $($config.Value.ScriptDirectory)" -ForegroundColor DarkGray
    Write-Host "   Logs:     $($config.Value.LogDirectory)" -ForegroundColor DarkGray
    
    Write-Host "`n📋 Inventory Files:" -ForegroundColor Cyan
    Write-Host "   Output: $($config.Value.InventoryOutputCSV)" -ForegroundColor DarkGray
    Write-Host "   Input:  $($config.Value.InventoryInputCSV)" -ForegroundColor DarkGray
    
    Write-Host ""
}

Show-Configuration ([ref]$currentConfig)

# --- MIGRATE LEGACY FOLDERS ---
function Migrate-LegacyFolders {
    <#
    .SYNOPSIS
    Detects and migrates user data from old toolkit directory structure
    to new external backup directory structure.
    #>
    param([ref]$config)
    
    $migrationTimestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
    $migrated = $false
    
    # Check for legacy Inventories folder in toolkit
    $legacyInvDir = Join-Path $PSScriptRoot "Inventories"
    if (Test-Path $legacyInvDir) {
        Write-Host "`n🔄 Migrating legacy Inventories folder..." -ForegroundColor Yellow
        $newInvDir = Join-Path $config.Value.BackupRootDirectory "AppData\$migrationTimestamp\Inventories"
        New-Item -ItemType Directory -Force -Path $newInvDir | Out-Null
        
        Get-ChildItem $legacyInvDir | ForEach-Object {
            Move-Item -Path $_.FullName -Destination $newInvDir -Force
            Write-Host "   ✓ Moved: $($_.Name)" -ForegroundColor Green
        }
        Remove-Item $legacyInvDir -Force -ErrorAction SilentlyContinue
        $migrated = $true
    }
    
    # Check for legacy Installers folder in toolkit
    $legacyInstDir = Join-Path $PSScriptRoot "Installers"
    if (Test-Path $legacyInstDir) {
        Write-Host "`n🔄 Migrating legacy Installers folder..." -ForegroundColor Yellow
        $newInstDir = Join-Path $config.Value.BackupRootDirectory "AppData\$migrationTimestamp\Installers"
        New-Item -ItemType Directory -Force -Path $newInstDir | Out-Null
        
        Get-ChildItem $legacyInstDir | ForEach-Object {
            Move-Item -Path $_.FullName -Destination $newInstDir -Force
            Write-Host "   ✓ Moved: $($_.Name)" -ForegroundColor Green
        }
        Remove-Item $legacyInstDir -Force -ErrorAction SilentlyContinue
        $migrated = $true
    }
    
    # Check for legacy migration-backups folder in toolkit
    $legacyBackupDir = Join-Path $PSScriptRoot "migration-backups"
    if (Test-Path $legacyBackupDir) {
        Write-Host "`n🔄 Migrating legacy migration-backups folder..." -ForegroundColor Yellow
        
        # Move WSL backups
        $legacyWslDir = Join-Path $legacyBackupDir "WSL"
        if (Test-Path $legacyWslDir) {
            $newWslDir = Join-Path $config.Value.BackupRootDirectory "WSL\$migrationTimestamp"
            New-Item -ItemType Directory -Force -Path $newWslDir | Out-Null
            Get-ChildItem $legacyWslDir | ForEach-Object {
                Move-Item -Path $_.FullName -Destination $newWslDir -Force
                Write-Host "   ✓ Moved WSL backup: $($_.Name)" -ForegroundColor Green
            }
        }
        
        # Move AppData backups
        $legacyAppDataDir = Join-Path $legacyBackupDir "AppData_Backups"
        if (Test-Path $legacyAppDataDir) {
            $newAppDataDir = Join-Path $config.Value.BackupRootDirectory "AppData\$migrationTimestamp\Backups"
            New-Item -ItemType Directory -Force -Path $newAppDataDir | Out-Null
            Get-ChildItem $legacyAppDataDir | ForEach-Object {
                Move-Item -Path $_.FullName -Destination $newAppDataDir -Force
                Write-Host "   ✓ Moved AppData backup: $($_.Name)" -ForegroundColor Green
            }
        }
        
        Remove-Item $legacyBackupDir -Force -Recurse -ErrorAction SilentlyContinue
        $migrated = $true
    }
    
    if ($migrated) {
        Write-Host "`n✓ Legacy folder migration complete!" -ForegroundColor Green
    }
}

Migrate-LegacyFolders ([ref]$currentConfig)

# --- SAVE SETTINGS TO BACKUP ROOT ---
function Save-Settings {
    param([ref]$config)
    
    # Sanitize the config: remove any null bytes from string values
    $cleanConfig = @{}
    foreach ($key in $config.Value.PSObject.Properties.Name) {
        $value = $config.Value.$key
        if ($value -is [string]) {
            $cleanConfig[$key] = $value -replace '\0', ''
        } else {
            $cleanConfig[$key] = $value
        }
    }
    $cleanConfig | ConvertTo-Json | Out-File $settingsPath -Encoding UTF8
}

Save-Settings ([ref]$currentConfig)

# --- FIND BACKUP DIRECTORY FOR RESTORE ---
function Find-BackupDirectory {
    <#
    .SYNOPSIS
    Locates the backup directory for restore operations.
    Checks default location first, then prompts user if needed.
    
    .PARAMETER BackupTypeDir
    The subdirectory for the backup type (e.g., WSL, AppData)
    
    .PARAMETER BackupType
    The name of the backup type for display purposes
    #>
    param(
        [string]$BackupTypeDir = "",
        [string]$BackupType = "Backup"
    )
    
    # If a specific backup type dir was provided, use it; otherwise use the base backup root
    $searchDir = if ($BackupTypeDir) { $BackupTypeDir } else { Join-Path (Split-Path -Parent $PSScriptRoot) "Windows-WSL2-Backup" }
    
    # Check if the search directory exists
    if (Test-Path $searchDir) {
        Write-Host "`n📂 Found $BackupType backup directory: $searchDir" -ForegroundColor Green
        
        # Find the most recent timestamped backup folder
        $timestampedBackups = @(Get-ChildItem -Path $searchDir -Directory -ErrorAction SilentlyContinue | 
                                Sort-Object LastWriteTime -Descending)
        
        if ($timestampedBackups.Count -gt 0) {
            $latestBackup = $timestampedBackups[0]
            Write-Host "📅 Most recent $BackupType backup: $($latestBackup.Name)" -ForegroundColor Cyan
            
            if ($timestampedBackups.Count -gt 1) {
                Write-Host "   (Found $($timestampedBackups.Count - 1) older backup(s))" -ForegroundColor DarkGray
            }
            
            Write-Host "`n❓ Restore from this backup?" -ForegroundColor Yellow
            Write-Host "   Path: $($latestBackup.FullName)" -ForegroundColor DarkGray
            Write-Host "   Yes (Y) / No (N) / Browse All (B): " -ForegroundColor Cyan -NoNewline
            $response = Read-Host
            
            if ($response -match "^(Y|Yes)$") {
                return $latestBackup.FullName
            } elseif ($response -match "^(B|Browse)$") {
                Write-Host "`nAvailable $BackupType backups:" -ForegroundColor Cyan
                $i = 1
                foreach ($backup in $timestampedBackups) {
                    Write-Host "  $i. $($backup.Name) ($(Get-Date $backup.LastWriteTime -Format 'yyyy-MM-dd HH:mm:ss'))" -ForegroundColor White
                }
                
                $selection = Read-Host "Select backup number"
                if ($selection -match "^\d+$" -and [int]$selection -ge 1 -and [int]$selection -le $timestampedBackups.Count) {
                    return $timestampedBackups[[int]$selection - 1].FullName
                } else {
                    Write-Host "Invalid selection. Using most recent backup." -ForegroundColor Yellow
                    return $latestBackup.FullName
                }
            }
        } else {
            Write-Host "⚠ $BackupType backup location exists but contains no timestamped directories." -ForegroundColor Yellow
        }
    }
    
    # If we reach here, ask user for custom path
    Write-Host "`n⚠ Could not locate $BackupType backups in default location." -ForegroundColor Yellow
    Write-Host "Default path: $searchDir" -ForegroundColor DarkGray
    Write-Host "`nEnter the path to your $BackupType backup directory: " -ForegroundColor Cyan -NoNewline
    $customPath = Read-Host
    
    if (Test-Path $customPath) {
        Write-Host "✓ Backup directory found: $customPath" -ForegroundColor Green
        return $customPath
    } else {
        Write-Host "✗ Path not found: $customPath" -ForegroundColor Red
        return $null
    }
}

function Show-Menu {
    Clear-Host
    Write-Host "========================================================" -ForegroundColor Cyan
    Write-Host "      SYSTEM MIGRATION TOOLKIT" -ForegroundColor Cyan
    Write-Host "========================================================" -ForegroundColor Cyan
    Write-Host "  Scripts:    \$($currentConfig.ScriptDirectory)" -ForegroundColor DarkGray
    Write-Host "  Ext Backup: $($currentConfig.ExternalBackupRoot)" -ForegroundColor DarkGray
    Write-Host "--------------------------------------------------------" -ForegroundColor Cyan
    Write-Host "1. Generate Application Inventory (Windows + WSL Apps)" -ForegroundColor Yellow
    Write-Host "2. Generate Installation Scripts" -ForegroundColor Yellow
    Write-Host "3. Backup WSL System (Full Distro Export)" -ForegroundColor Magenta
    Write-Host "4. Restore WSL System" -ForegroundColor Magenta
    Write-Host "5. Backup AppData Settings" -ForegroundColor Cyan
    Write-Host "6. Restore AppData Settings" -ForegroundColor Cyan
    Write-Host "Q. Quit" -ForegroundColor White
    Write-Host "========================================================" -ForegroundColor Cyan
}

# --- MAIN LOOP ---
do {
    $currentConfig = Load-Config
    Show-Menu
    $choice = Read-Host "Select an option"
    $scriptPath = "$PSScriptRoot\$($currentConfig.ScriptDirectory)"

    switch ($choice) {
        "1" { 
            Clear-Host; $target = "$scriptPath\ApplicationInventory\Get-Inventory.ps1"
            if (Test-Path $target) { & $target } else { Write-Error "Missing: $target" }
            Write-Host "`n✓ Inventory complete! Next steps:" -ForegroundColor Green
            Write-Host "  1. Go to Inventories/ folder" -ForegroundColor Cyan
            Write-Host "  2. Copy 'INSTALLED-SOFTWARE-INVENTORY.csv'" -ForegroundColor Cyan
            Write-Host "     → 'SOFTWARE-INSTALLATION-INVENTORY.csv'" -ForegroundColor Cyan
            Write-Host "  3. Edit with Google Sheets (recommended, see README)" -ForegroundColor Cyan
            Write-Host "  4. Set 'Keep' to TRUE for packages to restore" -ForegroundColor Cyan
            Write-Host "  5. Save and return to this menu → Option 2" -ForegroundColor Cyan
            Pause
        }
        "2" { 
            Clear-Host; $target = "$scriptPath\ApplicationInventory\Generate-Restore-Scripts.ps1"
            $inputFile = "$PSScriptRoot\$($currentConfig.InventoryDirectory)\$($currentConfig.InventoryInputCSV)"
            
            # Check if default file exists
            if (-not (Test-Path $inputFile)) {
                Write-Host "`n⚠ INPUT FILE NOT FOUND" -ForegroundColor Yellow
                Write-Host "Expected: $inputFile" -ForegroundColor Red
                Write-Host "`nOptions:" -ForegroundColor Cyan
                Write-Host "  1. Run Option 1 to generate INSTALLED-SOFTWARE-INVENTORY.csv" -ForegroundColor White
                Write-Host "  2. Copy to SOFTWARE-INSTALLATION-INVENTORY.csv and edit" -ForegroundColor White
                Write-Host "  3. Provide path to your inventory file" -ForegroundColor White
                Write-Host "  4. Exit and try again later" -ForegroundColor White
                $choice = Read-Host "`nEnter option (1/2/3/4)"
                
                if ($choice -eq "3") {
                    $customPath = Read-Host "Enter full path to your inventory CSV file"
                    if (Test-Path $customPath) {
                        $inputFile = $customPath
                        Write-Host "✓ File found: $inputFile" -ForegroundColor Green
                    } else {
                        Write-Host "✗ File not found at: $customPath" -ForegroundColor Red
                        Write-Host "Please check the path and try again." -ForegroundColor Yellow
                        Pause
                        return
                    }
                } else {
                    Write-Host "Returning to menu..." -ForegroundColor Yellow
                    Pause
                    return
                }
            }
            
            # Run script with the inputFile path
            if (Test-Path $target) { 
                & $target -InputFile $inputFile
            } else { 
                Write-Error "Missing: $target" 
            }
            Write-Host "`n✓ Restore scripts generated! Next steps:" -ForegroundColor Green
            Write-Host "  1. Review Installers/Restore_Windows.ps1 and Restore_Linux.sh" -ForegroundColor Cyan
            Write-Host "  2. For Windows: Run 'Run-Restore-Admin.bat'" -ForegroundColor Cyan
            Write-Host "  3. For WSL: Manual execution or use Option 4 for full restoration" -ForegroundColor Cyan
            Pause
        }
        "3" {
            Clear-Host; $target = "$scriptPath\WSL\Backup-WSL.ps1"
            if (Test-Path $target) { & $target } else { Write-Error "Missing: $target" }
            Pause
        }
        "4" {
            Clear-Host; $target = "$scriptPath\WSL\Restore-WSL.ps1"
            if (Test-Path $target) { & $target } else { Write-Error "Missing: $target" }
            Pause
        }
        "5" {
            Clear-Host; $target = "$scriptPath\AppData\Backup-AppData.ps1"
            if (Test-Path $target) { & $target } else { Write-Error "Missing: $target" }
            Write-Host "`n✓ AppData backup complete!" -ForegroundColor Green
            Write-Host "  Backups saved to: $($currentConfig.ExternalBackupRoot)\AppData_Backups" -ForegroundColor Cyan
            Write-Host "  Review the log file for details on what was backed up." -ForegroundColor Cyan
            Pause
        }
        "6" {
            Clear-Host; $target = "$scriptPath\AppData\Restore-AppData.ps1"
            if (Test-Path $target) { & $target } else { Write-Error "Missing: $target" }
            Write-Host "`n✓ AppData restore complete!" -ForegroundColor Green
            Write-Host "  Settings have been restored to their original locations." -ForegroundColor Cyan
            Write-Host "  You may need to restart applications to see the changes." -ForegroundColor Cyan
            Pause
        }
        "Q" { exit }
        "q" { exit }
    }
} while ($true)
