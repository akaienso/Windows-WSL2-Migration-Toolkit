# ==============================================================================
# SCRIPT: Start.ps1 (System Migration Toolkit - Main Menu)
# AUTHOR: Rob Moore <io@rmoore.dev>
# LICENSE: MIT
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
    InventoryOutputCSV  = "INSTALLED_SOFTWARE_INVENTORY.csv"
    InstallInputCSV     = "SOFTWARE-INSTALLATION-INVENTORY.csv"
}

# --- LOAD / CREATE CONFIG ---
function Load-Config {
    if (Test-Path $configPath) {
        $loaded = Get-Content $configPath -Raw | ConvertFrom-Json
        # Add missing keys if upgrading from older version
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
    Write-Host "  Data:      \$($currentConfig.InventoryDirectory)" -ForegroundColor DarkGray
    Write-Host "  Output:    \$($currentConfig.InstallersDirectory)" -ForegroundColor Green
    Write-Host "--------------------------------------------------------" -ForegroundColor Cyan
    Write-Host "1. Generate Application Inventory" -ForegroundColor Yellow
    Write-Host "   (Scans Windows & WSL -> Creates CSV in Inventories/)"
    Write-Host ""
    Write-Host "2. Generate Installation Scripts" -ForegroundColor Yellow
    Write-Host "   (Reads Checkbox CSV -> Creates Installers in Installers/)"
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
            Clear-Host
            $target = "$scriptPath\Get-Inventory.ps1"
            if (Test-Path $target) { & $target } 
            else { Write-Error "Missing script: $target" }
            Pause
        }

        "2" { 
            Clear-Host
            $target = "$scriptPath\Generate-Restore-Scripts.ps1"
            
            # Check for input file in Inventories folder
            $invPath = "$PSScriptRoot\$($currentConfig.InventoryDirectory)"
            $inputFile = "$invPath\$($currentConfig.InstallInputCSV)"
            
            if (-not (Test-Path $inputFile)) {
                Write-Warning "Cannot find input file: $inputFile"
                Write-Warning "Please save your Google Sheet export to the '$($currentConfig.InventoryDirectory)' folder."
            } else {
                if (Test-Path $target) { & $target } 
                else { Write-Error "Missing script: $target" }
            }
            Pause
        }

        "Q" { break }
        "q" { break }
    }
} while ($true)