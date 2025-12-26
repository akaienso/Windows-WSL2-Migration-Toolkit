# ==============================================================================
# SCRIPT: Generate-Restore-Scripts.ps1
# ==============================================================================
param(
    [string]$InputFile = ""
)

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$RootDir = Split-Path -Parent (Split-Path -Parent $ScriptDir)
$configPath = "$RootDir\config.json"

# Load config (try settings.json first in toolkit root)
function Load-Config {
    $settingsPath = "$RootDir\settings.json"
    
    # Try settings.json in toolkit root first (persisted user settings)
    if (Test-Path $settingsPath) {
        return Get-Content $settingsPath -Raw | ConvertFrom-Json
    }
    
    # Fall back to config.json
    if (Test-Path $configPath) {
        return Get-Content $configPath -Raw | ConvertFrom-Json
    }
    
    Write-Error "Config missing."
    exit 1
}

$config = Load-Config

# Use provided InputFile, or find the most recent timestamped inventory
if ([string]::IsNullOrWhiteSpace($InputFile)) {
    # Find the most recent Inventory timestamped directory
    $invBaseDir = "$($config.BackupRootDirectory)\Inventory"
    $latestDir = Get-ChildItem -Path $invBaseDir -Directory -ErrorAction SilentlyContinue | 
                 Sort-Object LastWriteTime -Descending | 
                 Select-Object -First 1
    
    if (-not $latestDir) {
        Write-Host "`n⚠ INPUT FILE NOT FOUND" -ForegroundColor Yellow
        Write-Host "Expected: $invBaseDir\[timestamp]\Inventories\$($config.InventoryInputCSV)" -ForegroundColor Red
        Write-Host "`nNo inventory directories found." -ForegroundColor Red
        Write-Host "Run Option 1 (Get-Inventory) first to generate one." -ForegroundColor Cyan
        exit 1
    }
    
    $csvPath = "$($latestDir.FullName)\Inventories\$($config.InventoryInputCSV)"
    $installDir = "$($latestDir.FullName)\Installers"
} else {
    $csvPath = $InputFile
    # When using custom InputFile, put scripts in the same timestamped directory as the CSV
    $timestampDir = Split-Path -Parent (Split-Path -Parent $InputFile)
    $installDir = "$timestampDir\Installers"
}

# Validate input CSV exists
if (-not (Test-Path $csvPath)) {
    Write-Error "Inventory CSV not found: $csvPath"
    exit 1
}

# Create installer directory
if (-not (Test-Path $installDir)) {
    try {
        New-Item -ItemType Directory -Force -Path $installDir | Out-Null
    } catch {
        Write-Error "Failed to create installer directory: $_"
        exit 1
    }
}

$winScriptPath = "$installDir\Restore_Windows.ps1"
$linuxScriptPath = "$installDir\Restore_Linux.sh"

if (-not (Test-Path $installDir)) { New-Item -ItemType Directory -Force -Path $installDir | Out-Null }
if (-not (Test-Path $csvPath)) { Write-Error "Input file missing: $csvPath"; exit }

$inventory = Import-Csv -Path $csvPath
$winCommands = @(); $linuxCommands = @(); $manualWarnings = @()

foreach ($row in $inventory) {
    if ($row.'Keep (Y/N)' -match "TRUE|Yes|Y|1") {
        if ($row.Environment -eq "Windows") {
            if ($row.Source -match "Registry") { $manualWarnings += $row.'Application Name' }
            else { $winCommands += $row.'Restoration Command' }
        } elseif ($row.Environment -match "WSL") {
            $linuxCommands += ($row.'Restoration Command' -replace "sudo ", "")
        }
    }
}

# WINDOWS SCRIPT
$winContent = @"
# AUTOMATED WINDOWS RESTORE SCRIPT
Write-Host "Starting Windows App Restoration..." -ForegroundColor Cyan
winget settings --enable InstallerHashOverride
winget source update
"@
foreach ($cmd in $winCommands) { $winContent += "`nWrite-Host 'Installing: $cmd' -ForegroundColor Yellow`n$cmd" }
if ($manualWarnings.Count -gt 0) {
    $winContent += "`n`nWrite-Host '--- MANUAL INSTALL REQUIRED FOR: ---' -ForegroundColor Red"
    foreach ($app in $manualWarnings) { $winContent += "`nWrite-Host ' - $app' -ForegroundColor White" }
}
$winContent += "`n`nWrite-Host 'Done!' -ForegroundColor Green"
$winContent | Out-File -FilePath $winScriptPath -Encoding UTF8

# LINUX SCRIPT
$linuxContent = @"
#!/bin/bash
# AUTOMATED LINUX RESTORE SCRIPT
echo "Starting Linux App Restoration..."
sudo apt update && sudo apt upgrade -y
"@
foreach ($cmd in $linuxCommands) { $linuxContent += "`necho 'Installing: $cmd'`nsudo $cmd" }
$linuxContent += "`n`necho 'Done!'"
$linuxContent = $linuxContent -replace "`r`n", "`n"
[System.IO.File]::WriteAllText($linuxScriptPath, $linuxContent)

Write-Host "SUCCESS! Scripts created in '$($config.InstallersDirectory)'" -ForegroundColor Green
