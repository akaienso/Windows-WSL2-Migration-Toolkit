# ==============================================================================
# SCRIPT: Restore-WSL.ps1
# PURPOSE: Imports Full WSL Distro from External Drive
# ==============================================================================
$ErrorActionPreference = 'Stop'
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$RootDir = Split-Path -Parent $ScriptDir
$config = Get-Content "$RootDir\config.json" -Raw | ConvertFrom-Json

# Source the helper function from Start.ps1
. "$RootDir\Start.ps1"

$Distro = $config.WslDistroName

# Find the backup directory
Write-Host "`n=== WSL SYSTEM RESTORE ===" -ForegroundColor Cyan
$BackupDir = Find-BackupDirectory

if (-not $BackupDir -or -not (Test-Path $BackupDir)) {
    Write-Error "Unable to locate backup directory. Restore cancelled."
}

$InstallLocation = "C:\WSL\$Distro"
$WslScriptsDir = "$RootDir\Scripts\WSL"

Write-Host "Source: $BackupDir" -ForegroundColor Yellow
Write-Host "Dest:   $InstallLocation"

# 1. Find Backups
$FullBackup = Get-ChildItem "$BackupDir\WslBackup_*.tar" | Sort LastWriteTime -Descending | Select -First 1
$DotBackup = Get-ChildItem "$BackupDir\WslDotfiles_*.tar.gz" | Sort LastWriteTime -Descending | Select -First 1

if (-not $FullBackup) { Write-Error "No Backup Tar found in $BackupDir" }
Write-Host "Found Backup: $($FullBackup.Name)" -ForegroundColor Green

# 2. Import
Write-Host "`n1. Importing Distro..." -ForegroundColor Yellow
if (Test-Path $InstallLocation) { Write-Warning "Target folder exists. Proceeding anyway..." }
else { New-Item -ItemType Directory -Path $InstallLocation -Force | Out-Null }
wsl --import $Distro $InstallLocation $FullBackup.FullName

# 3. Inject Scripts
Write-Host "2. Starting WSL & Injecting Tools..." -ForegroundColor Cyan
wsl -d $Distro -- echo "Booted."
$wslPath = "/mnt/" + ($WslScriptsDir.Replace(":", "").Replace("\", "/").ToLower())
$deployCmd = "mkdir -p ~/.wsl-toolkit && cp $wslPath/*.sh ~/.wsl-toolkit/ && chmod +x ~/.wsl-toolkit/*.sh"
wsl -d $Distro -- bash -lc $deployCmd

# 4. Restore Dotfiles
Write-Host "3. Restoring Dotfiles..." -ForegroundColor Cyan
$wslBackupPath = "/mnt/" + ($BackupDir.Replace(":", "").Replace("\", "/").ToLower())
wsl -d $Distro -- bash -lc "mkdir -p ~/restore && cp $wslBackupPath/$($DotBackup.Name) ~/restore/"
wsl -d $Distro -- bash -lc "~/.wsl-toolkit/restore-dotfiles.sh ~/restore/$($DotBackup.Name)"

# 5. Post Install
Write-Host "4. Running Post-Install Setup..." -ForegroundColor Cyan
wsl -d $Distro -- bash -lc "~/.wsl-toolkit/post-restore-install.sh"

Write-Host "`nRESTORE COMPLETE!" -ForegroundColor Green
Write-Host "You can now run: wsl -d $Distro"
