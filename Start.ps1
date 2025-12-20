# ==============================================================================
# SCRIPT: Start.ps1 (System Migration Toolkit - Main Menu)
# ==============================================================================

$PSScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition
Set-Location -Path $PSScriptRoot
$configPath = "$PSScriptRoot\config.json"

# --- DEFAULT CONFIGURATION ---
$defaultConfig = @{
    BasePath            = "." 
    ScriptDirectory     = "Scripts"
    InventoryDirectory  = "Inventories"
    InstallersDirectory = "Installers"
    LogDirectory        = "Logs"
    ExternalBackupRoot  = ""
    WslDistroName       = "Ubuntu"
    InventoryOutputCSV  = "INSTALLED-SOFTWARE-INVENTORY.csv"
    InventoryInputCSV   = "SOFTWARE-INSTALLATION-INVENTORY.csv"
}

# --- LOAD / CREATE CONFIG ---
function Load-Config {
    if (Test-Path $configPath) {
        $loaded = Get-Content $configPath -Raw | ConvertFrom-Json
        foreach ($key in $defaultConfig.Keys) {
            if (-not $loaded.PSObject.Properties[$key]) {
                $loaded | Add-Member -NotePropertyName $key -NotePropertyValue $defaultConfig[$key]
            }
        }
        $loaded | ConvertTo-Json | Out-File $configPath -Encoding UTF8
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
        $currentConfig.InventoryDirectory, 
        $currentConfig.LogDirectory, 
        $currentConfig.ScriptDirectory,
        $currentConfig.InstallersDirectory
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
    
    $backupPath = $config.Value.ExternalBackupRoot
    
    # If path is empty or invalid, prompt user
    if ([string]::IsNullOrWhiteSpace($backupPath) -or -not (Test-Path $backupPath)) {
        Write-Host "`n⚠ External Backup Location Not Set" -ForegroundColor Yellow
        Write-Host "You need to specify where WSL backups will be stored.`n" -ForegroundColor Cyan
        
        Write-Host "Default: $PSScriptRoot\migration-backups" -ForegroundColor DarkGray
        Write-Host "Enter path (press Enter for default): " -ForegroundColor Cyan -NoNewline
        $userPath = Read-Host
        
        if ([string]::IsNullOrWhiteSpace($userPath)) {
            $backupPath = "$PSScriptRoot\migration-backups"
        } else {
            $backupPath = $userPath
        }
        
        # Create the directory if it doesn't exist
        if (-not (Test-Path $backupPath)) {
            try {
                New-Item -ItemType Directory -Force -Path $backupPath | Out-Null
                Write-Host "✓ Created backup directory: $backupPath" -ForegroundColor Green
            } catch {
                Write-Host "✗ Failed to create directory: $backupPath" -ForegroundColor Red
                Write-Host "Error: $_" -ForegroundColor Red
                Write-Host "Using default location instead..." -ForegroundColor Yellow
                $backupPath = "$PSScriptRoot\migration-backups"
                New-Item -ItemType Directory -Force -Path $backupPath | Out-Null
            }
        }
        
        # Update config
        $config.Value.ExternalBackupRoot = $backupPath
        $config.Value | ConvertTo-Json | Out-File $configPath -Encoding UTF8
    }
}

$currentConfig = Load-Config
Validate-BackupPath ([ref]$currentConfig)

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
            Clear-Host; $target = "$scriptPath\Get-Inventory.ps1"
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
            Clear-Host; $target = "$scriptPath\Generate-Restore-Scripts.ps1"
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
            Clear-Host; $target = "$scriptPath\Backup-WSL.ps1"
            if (Test-Path $target) { & $target } else { Write-Error "Missing: $target" }
            Pause
        }
        "4" {
            Clear-Host; $target = "$scriptPath\Restore-WSL.ps1"
            if (Test-Path $target) { & $target } else { Write-Error "Missing: $target" }
            Pause
        }
        "Q" { exit }
        "q" { exit }
    }
} while ($true)
