# ==============================================================================
# SCRIPT: Generate-Restore-Scripts.ps1
# Purpose: Read inventory CSV and generate restore scripts for Windows and Linux
# ==============================================================================
$ErrorActionPreference = 'Stop'

param(
    [string]$InputFile = ""
)

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$RootDir = Split-Path -Parent (Split-Path -Parent $ScriptDir)

# Import shared utilities
$utilsPath = Join-Path $RootDir "Scripts\Utils.ps1"
if (-not (Test-Path $utilsPath)) {
    Write-Error "Utilities module not found: $utilsPath"
    exit 1
}
. $utilsPath

$config = Load-Config -RootDirectory $RootDir

# Validate required config fields
@('BackupRootDirectory', 'InventoryInputCSV', 'InventoryOutputCSV') | ForEach-Object {
    if ([string]::IsNullOrWhiteSpace($config.$_)) {
        Write-Error "Config missing required field: $_"
        exit 1
    }
}

# Determine input CSV path
if ([string]::IsNullOrWhiteSpace($InputFile)) {
    # Find the most recent Inventory timestamped directory
    $invBaseDir = Join-Path $config.BackupRootDirectory "Inventory"
    
    if (-not (Test-Path $invBaseDir)) {
        Write-Error "Inventory directory not found: $invBaseDir"
        Write-Host "Run Option 1 (Get-Inventory) first to generate one." -ForegroundColor Cyan
        exit 1
    }
    
    $latestDir = Find-LatestBackupDir -BackupBaseDir $invBaseDir -BackupType "Inventory"
    if (-not $latestDir) {
        exit 1
    }
    
    $csvPath = Join-Path $latestDir.FullName "Inventories" $config.InventoryInputCSV
    $installDir = Join-Path $latestDir.FullName "Installers"
} else {
    # Custom InputFile path
    if (-not (Test-Path $InputFile)) {
        Write-Error "Input file not found: $InputFile"
        exit 1
    }
    $csvPath = $InputFile
    # Put scripts in same directory structure as the CSV
    $timestampDir = Split-Path -Parent (Split-Path -Parent $InputFile)
    $installDir = Join-Path $timestampDir "Installers"
}

# Validate input CSV exists
if (-not (Test-Path $csvPath)) {
    Write-Host "Input CSV not found: $csvPath" -ForegroundColor Yellow
    Write-Host "Checking for output CSV to create input from..." -ForegroundColor Yellow
    
    # Try to use output CSV as fallback
    $outputCsvPath = Join-Path (Split-Path -Parent $csvPath) $config.InventoryOutputCSV
    if (Test-Path $outputCsvPath) {
        Write-Host "Creating input CSV from output CSV..." -ForegroundColor Yellow
        Copy-Item -Path $outputCsvPath -Destination $csvPath -Force
        Write-Host "Created: $csvPath" -ForegroundColor Green
    } else {
        Write-Error "Neither input nor output CSV found. Run Option 1 (Get-Inventory) first."
        exit 1
    }
}

# Validate CSV format
if (-not (Test-CsvFile -CsvPath $csvPath -RequiredColumns @('Keep (Y/N)', 'Restoration Command', 'Environment'))) {
    exit 1
}

# Create installer directory
if (-not (New-DirectoryIfNotExists -Path $installDir)) {
    Write-Error "Failed to create installer directory"
    exit 1
}

$winScriptPath = Join-Path $installDir "Restore_Windows.ps1"
$linuxScriptPath = Join-Path $installDir "Restore_Linux.sh"

Write-Host "`nReading inventory: $csvPath" -ForegroundColor Cyan

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

Write-Host "✓ Restore scripts generated successfully!" -ForegroundColor Green
Write-Host "Windows script: $winScriptPath" -ForegroundColor Cyan
Write-Host "Linux script:   $linuxScriptPath" -ForegroundColor Cyan
Write-Host "`nNext steps:" -ForegroundColor Yellow
Write-Host "  1. Review the scripts before running" -ForegroundColor White
Write-Host "  2. Run Restore_Windows.ps1 after fresh Windows install" -ForegroundColor White
Write-Host "  3. Run Restore_Linux.sh in WSL after distro restore" -ForegroundColor White
