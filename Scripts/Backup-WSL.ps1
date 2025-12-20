# ==============================================================================
# SCRIPT: Backup-WSL.ps1
# PURPOSE: Exports WSL Distro + Dotfiles to External Drive/Backup Path
# ==============================================================================
$ErrorActionPreference = 'Stop'
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$RootDir = Split-Path -Parent $ScriptDir
$config = Get-Content "$RootDir\config.json" -Raw | ConvertFrom-Json

$Distro = $config.WslDistroName
$BackupDir = $config.WslBackupDirectory
$Timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$WslScriptsDir = "$RootDir\Scripts\WSL"

Write-Host "`n=== WSL MIGRATION BACKUP ===" -ForegroundColor Cyan
Write-Host "Distro: $Distro"
Write-Host "Target: $BackupDir"

# 1. Validation
if (-not (Test-Path $BackupDir)) {
    Write-Host "Creating backup directory: $BackupDir" -ForegroundColor Yellow
    New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
}

# 2. Inject Toolkit into WSL
Write-Host "`n1. Injecting helper scripts into ~/.wsl-toolkit..." -ForegroundColor Cyan
# Convert Windows path to WSL path (e.g. C:\Dev -> /mnt/c/Dev)
$wslPath = "/mnt/" + ($WslScriptsDir.Replace(":", "").Replace("\", "/").ToLower())
$deployCmd = "mkdir -p ~/.wsl-toolkit && cp $wslPath/*.sh ~/.wsl-toolkit/ && chmod +x ~/.wsl-toolkit/*.sh"
wsl -d $Distro -- bash -lc $deployCmd

# 3. Run Dotfile Backup
Write-Host "2. Running dotfile backup inside WSL..." -ForegroundColor Cyan
wsl -d $Distro -- bash -lc "~/.wsl-toolkit/backup-dotfiles.sh"

# Retrieve the file
$LatestDotfile = wsl -d $Distro -- bash -lc "ls -t ~/wsl-dotfile-backups | head -n 1" | Out-String
$LatestDotfile = $LatestDotfile.Trim()
if (-not $LatestDotfile) { Write-Error "No dotfile backup created." }

Write-Host "   -> Found: $LatestDotfile"
Write-Host "   -> Copying to backup drive..."
wsl -d $Distro -- bash -lc "cp ~/wsl-dotfile-backups/$LatestDotfile /mnt/$(($BackupDir.Replace(':','').Replace('\','/').ToLower()))/"
$targetDotfile = Join-Path $BackupDir ("WslDotfiles_{0}.tar.gz" -f $Timestamp)
Rename-Item (Join-Path $BackupDir $LatestDotfile) -NewName $targetDotfile -Force

# 4. Full Export
Write-Host "`n3. Exporting Full Distro Image (This may take time)..." -ForegroundColor Magenta
Write-Host "   -> Shutting down WSL..."
wsl --shutdown
$FullExportFile = Join-Path $BackupDir "WslBackup_${Distro}_$Timestamp.tar"
wsl --export $Distro $FullExportFile

# 5. Hash & Finish
Write-Host "`n4. Generating Hashes..." -ForegroundColor Cyan
$h1 = Get-FileHash $FullExportFile -Algorithm SHA256
$h2 = Get-FileHash $targetDotfile -Algorithm SHA256
$report = "WSL Backup Report ($Timestamp)`n---------------------------`nFull: $($h1.Hash)`nDots: $($h2.Hash)"
$report | Out-File (Join-Path $BackupDir "HashReport_$Timestamp.txt")

# Dropbox Check (Legacy Support)
$DropboxPath = Join-Path $env:USERPROFILE ("Dropbox\Backups\WSL-Backups\" + $env:COMPUTERNAME)
if (Test-Path $DropboxPath) {
    Write-Host "`nCloud Sync: Copying to Dropbox..." -ForegroundColor Yellow
    Copy-Item $FullExportFile $DropboxPath -Force
    Copy-Item $targetDotfile $DropboxPath -Force
}

Write-Host "`nSUCCESS! Backup Complete." -ForegroundColor Green
Write-Host "Location: $BackupDir"
