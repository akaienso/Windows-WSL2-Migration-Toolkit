# ==============================================================================
# SCRIPT: Generate-Restore-Scripts.ps1
# AUTHOR: Rob Moore <io@rmoore.dev>
# LOCATION: /Scripts/
# ==============================================================================

# --- LOAD CONFIGURATION ---
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$RootDir = Split-Path -Parent $ScriptDir
$configPath = "$RootDir\config.json"

if (Test-Path $configPath) {
    $config = Get-Content $configPath -Raw | ConvertFrom-Json
} else {
    Write-Error "Config file missing. Run Start.ps1 first."
    exit
}

# --- RESOLVE PATHS ---
$invDir = "$RootDir\$($config.InventoryDirectory)"
$installDir = "$RootDir\$($config.InstallersDirectory)"

# Input File
$csvPath  = "$invDir\$($config.InstallInputCSV)"

# Output Files (Now go to /Installers folder)
$winScriptPath = "$installDir\Restore_Windows.ps1"
$linuxScriptPath = "$installDir\Restore_Linux.sh"

# Ensure Installers folder exists (Double check)
if (-not (Test-Path $installDir)) { New-Item -ItemType Directory -Force -Path $installDir | Out-Null }

Write-Host "`n========================================================" -ForegroundColor Cyan
Write-Host " STARTING RESTORE SCRIPT GENERATION" -ForegroundColor Cyan
Write-Host " INPUT: $csvPath" -ForegroundColor Cyan
Write-Host "========================================================" -ForegroundColor Cyan

# --- VALIDATION ---
if (-not (Test-Path $csvPath)) {
    Write-Host "`nERROR: Input file not found!" -ForegroundColor Red
    Write-Host "Looking for: $csvPath" -ForegroundColor Red
    Write-Host "Please ensure file is in the '$($config.InventoryDirectory)' folder." -ForegroundColor Yellow
    exit
}

# --- READ CSV ---
Write-Host "Reading inventory file... " -NoNewline -ForegroundColor Yellow
try {
    $inventory = Import-Csv -Path $csvPath
    Write-Host "$($inventory.Count) rows loaded." -ForegroundColor Green
} catch {
    Write-Host "FAILED" -ForegroundColor Red; Write-Error $_; exit
}

$winCommands = @()
$linuxCommands = @()
$manualWarnings = @()
$keptCount = 0

Write-Host "Processing selections... " -NoNewline -ForegroundColor Yellow
foreach ($row in $inventory) {
    $keep = $row.'Keep (Y/N)'
    if ($keep -match "TRUE|Yes|Y|1") {
        $keptCount++
        if ($row.Environment -eq "Windows") {
            if ($row.Source -match "Registry") { $manualWarnings += $row.'Application Name' }
            else { $winCommands += $row.'Restoration Command' }
        } elseif ($row.Environment -match "WSL") {
            $cmd = $row.'Restoration Command' -replace "sudo ", ""
            $linuxCommands += $cmd
        }
    }
}
Write-Host "$keptCount applications selected." -ForegroundColor Green

# --- GENERATE WINDOWS ---
Write-Host "Writing Windows script... " -NoNewline -ForegroundColor Yellow
$winContent = @"
# AUTOMATED WINDOWS RESTORE SCRIPT
# Source: $csvPath
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
Write-Host "Done." -ForegroundColor Green

# --- GENERATE LINUX ---
Write-Host "Writing Linux script... " -NoNewline -ForegroundColor Yellow
$linuxContent = @"
#!/bin/bash
# AUTOMATED LINUX RESTORE SCRIPT
echo "Starting Linux App Restoration..."
echo "Updating Apt Repositories..."
sudo apt update && sudo apt upgrade -y
"@
foreach ($cmd in $linuxCommands) { $linuxContent += "`necho 'Installing: $cmd'`nsudo $cmd" }
$linuxContent += "`n`necho 'Done!'"
$linuxContent = $linuxContent -replace "`r`n", "`n"
[System.IO.File]::WriteAllText($linuxScriptPath, $linuxContent)
Write-Host "Done." -ForegroundColor Green

Write-Host "`nSUCCESS! Scripts created in '$($config.InstallersDirectory)' folder:" -ForegroundColor Green
Write-Host " $winScriptPath" -ForegroundColor White
Write-Host " $linuxScriptPath" -ForegroundColor White