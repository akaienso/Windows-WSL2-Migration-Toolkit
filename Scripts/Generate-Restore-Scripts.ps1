# ==============================================================================
# SCRIPT: Generate-Restore-Scripts.ps1
# ==============================================================================
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$RootDir = Split-Path -Parent $ScriptDir
$configPath = "$RootDir\config.json"
$config = Get-Content $configPath -Raw | ConvertFrom-Json

$invDir = "$RootDir\$($config.InventoryDirectory)"
$installDir = "$RootDir\$($config.InstallersDirectory)"
$csvPath  = "$invDir\$($config.InstallInputCSV)"
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
# Ensure Unix Line Endings
$linuxContent = $linuxContent -replace "`r`n", "`n"
[System.IO.File]::WriteAllText($linuxScriptPath, $linuxContent)

Write-Host "SUCCESS! Scripts created in '$($config.InstallersDirectory)'" -ForegroundColor Green
