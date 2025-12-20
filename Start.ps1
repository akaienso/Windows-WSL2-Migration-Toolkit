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
    WslBackupDirectory  = "D:\WSL-Backups"
    WslDistroName       = "Ubuntu"
    InventoryOutputCSV  = "INSTALLED_SOFTWARE_INVENTORY.csv"
    InstallInputCSV     = "SOFTWARE-INSTALLATION-INVENTORY.csv"
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

function Show-Menu {
    Clear-Host
    Write-Host "========================================================" -ForegroundColor Cyan
    Write-Host "      SYSTEM MIGRATION TOOLKIT" -ForegroundColor Cyan
    Write-Host "========================================================" -ForegroundColor Cyan
    Write-Host "  Scripts:   \$($currentConfig.ScriptDirectory)" -ForegroundColor DarkGray
    Write-Host "  Backups:   $($currentConfig.WslBackupDirectory)" -ForegroundColor DarkGray
    Write-Host "  WSL Distro:$($currentConfig.WslDistroName)" -ForegroundColor DarkGray
    Write-Host "--------------------------------------------------------" -ForegroundColor Cyan
    Write-Host "1. Generate Application Inventory" -ForegroundColor Yellow
    Write-Host "   (Scans Windows & WSL -> Creates CSV)"
    Write-Host ""
    Write-Host "2. Generate Installation Scripts" -ForegroundColor Yellow
    Write-Host "   (Reads CSV -> Creates Installers)"
    Write-Host ""
    Write-Host "3. Backup WSL Environment" -ForegroundColor Magenta
    Write-Host "   (Full Export + Dotfiles -> External Drive)"
    Write-Host ""
    Write-Host "4. Restore WSL Environment" -ForegroundColor Magenta
    Write-Host "   (Import Distro + Fix Permissions)"
    Write-Host ""
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
            Pause
        }
        "2" { 
            Clear-Host; $target = "$scriptPath\Generate-Restore-Scripts.ps1"
            $inputFile = "$PSScriptRoot\$($currentConfig.InventoryDirectory)\$($currentConfig.InstallInputCSV)"
            if (-not (Test-Path $inputFile)) {
                Write-Warning "Input file not found: $inputFile"
            } else {
                if (Test-Path $target) { & $target } else { Write-Error "Missing: $target" }
            }
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
        "Q" { break }
        "q" { break }
    }
} while ($true)
