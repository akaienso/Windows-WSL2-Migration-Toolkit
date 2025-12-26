# ==============================================================================
# SCRIPT: Backup-WSL.ps1
# PURPOSE: Exports Full WSL Distro to External Drive
# ==============================================================================
$ErrorActionPreference = 'Stop'
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

$Distro = $config.WslDistroName
# Create a timestamp-based subdirectory under WSL backup type
$Timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$WslBackupBaseDir = Join-Path $config.BackupRootDirectory "WSL"
$BackupDir = Join-Path $WslBackupBaseDir $Timestamp
$WslScriptsDir = "$RootDir\Scripts\WSL"

Write-Host "`n=== WSL SYSTEM BACKUP ===" -ForegroundColor Cyan
Write-Host "Distro: $Distro"
Write-Host "Backup Root: $($config.BackupRootDirectory)"

# Validate distro exists
$distroExists = wsl -l --quiet | ForEach-Object { $_.Trim() } | Where-Object { $_ -match [regex]::Escape($Distro) }
if (-not $distroExists) {
    Write-Error "WSL Distro '$Distro' not found. Available distros: $(wsl -l --quiet | Out-String)"
    exit 1
}

# --- CHECK FOR EXISTING WSL BACKUPS ---
$existingBackups = @(Get-ChildItem -Path $WslBackupBaseDir -Directory -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)

if ($existingBackups.Count -gt 0) {
    Write-Host "`n⚠ Found $($existingBackups.Count) existing WSL backup(s):" -ForegroundColor Yellow
    foreach ($backup in $existingBackups | Select-Object -First 5) {
        Write-Host "   • $($backup.Name)" -ForegroundColor DarkGray
    }
    if ($existingBackups.Count -gt 5) {
        Write-Host "   ... and $($existingBackups.Count - 5) more" -ForegroundColor DarkGray
    }
    
    Write-Host "`n❓ Replace existing WSL backups with a new one?" -ForegroundColor Cyan
    Write-Host "   Note: This will DELETE all existing WSL backups and create a fresh backup with current timestamp." -ForegroundColor DarkGray
    Write-Host "   Yes (Y) / No (N): " -ForegroundColor Cyan -NoNewline
    $response = Read-Host
    
    if ($response -match "^(Y|Yes)$") {
        Write-Host "`nRemoving existing WSL backups..." -ForegroundColor Yellow
        foreach ($backup in $existingBackups) {
            Remove-Item -Path $backup.FullName -Recurse -Force -ErrorAction SilentlyContinue
            Write-Host "   ✓ Deleted: $($backup.Name)" -ForegroundColor DarkGray
        }
        Write-Host "Existing WSL backups removed." -ForegroundColor Green
    } else {
        Write-Host "Keeping existing WSL backups. Creating new backup in separate directory." -ForegroundColor Cyan
    }
}

Write-Host "`nTarget: $BackupDir"

if (-not (Test-Path $BackupDir)) {
    Write-Host "Creating backup directory: $BackupDir" -ForegroundColor Yellow
    New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
}

# 1. Inject Toolkit into WSL
Write-Host "`n1. Injecting helper scripts into ~/.wsl-toolkit..." -ForegroundColor Cyan
# Convert Scripts/WSL path to WSL mount path
$wslScriptsDrive = $WslScriptsDir.Substring(0, 1).ToLower()
$wslScriptsPath = $WslScriptsDir.Substring(2).Replace("\", "/").ToLower()
$wslPath = "/mnt/$wslScriptsDrive$wslScriptsPath"
$deployCmd = "mkdir -p ~/.wsl-toolkit && cp $wslPath/*.sh ~/.wsl-toolkit/ && chmod +x ~/.wsl-toolkit/*.sh"
if (-not (wsl -d $Distro -- test -d "$wslPath")) {
    Write-Error "WSL toolkit scripts directory not found at: $wslPath"
    exit 1
}
wsl -d $Distro -- bash -lc $deployCmd
if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to inject toolkit scripts into WSL"
    exit 1
}

# 2. Run Dotfile Backup
Write-Host "2. Running dotfile backup inside WSL..." -ForegroundColor Cyan
wsl -d $Distro -- bash -lc "~/.wsl-toolkit/backup-dotfiles.sh"
if ($LASTEXITCODE -ne 0) {
    Write-Error "Dotfile backup script failed"
    exit 1
}

$LatestDotfile = wsl -d $Distro -- bash -lc "ls -t ~/wsl-dotfile-backups 2>/dev/null | head -n 1" | Out-String
$LatestDotfile = $LatestDotfile.Trim()
if (-not $LatestDotfile) { 
    Write-Error "No dotfile backup created. Check that ~/wsl-dotfile-backups/ exists in the distro."
    exit 1
}

Write-Host "   -> Found: $LatestDotfile"
Write-Host "   -> Copying to backup drive..."

# Convert Windows path to WSL mount path properly
# D:\path\to\dir → /mnt/d/path/to/dir
$driveLetter = $BackupDir.Substring(0, 1).ToLower()
$pathWithoutDrive = $BackupDir.Substring(2).Replace("\", "/").ToLower()
$wslBackupPath = "/mnt/$driveLetter$pathWithoutDrive"

# Create the backup directory in WSL if it doesn't exist
wsl -d $Distro -- bash -lc "mkdir -p '$wslBackupPath'"
if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to create backup directory in WSL: $wslBackupPath"
    exit 1
}

# Copy the dotfiles to the backup directory with renamed filename
$targetDotfile = "WslDotfiles_{0}.tar.gz" -f $Timestamp
wsl -d $Distro -- bash -lc "cp ~/wsl-dotfile-backups/$LatestDotfile '$wslBackupPath/$targetDotfile'"
if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to copy dotfile backup to: $wslBackupPath/$targetDotfile"
    exit 1
}

# 3. Full Export
Write-Host "`n3. Exporting Full Distro Image (This may take time)..." -ForegroundColor Magenta
Write-Host "   -> Shutting down WSL..."
wsl --shutdown
$FullExportFile = Join-Path $BackupDir "WslBackup_${Distro}_$Timestamp.tar"
Write-Host "   -> Exporting to: $FullExportFile"
wsl --export $Distro $FullExportFile
if ($LASTEXITCODE -ne 0) {
    Write-Error "WSL distro export failed"
    exit 1
}
if (-not (Test-Path $FullExportFile)) {
    Write-Error "Export file not created: $FullExportFile"
    exit 1
}

# 4. Hash & Finish
Write-Host "`n4. Generating Hashes..." -ForegroundColor Cyan
$h1 = Get-FileHash $FullExportFile -Algorithm SHA256

$targetDotfilePath = Join-Path $BackupDir $targetDotfile

# Wait for dotfile to appear on Windows side (WSL filesystem sync)
$maxWait = 30
$waited = 0
while (-not (Test-Path $targetDotfilePath) -and $waited -lt $maxWait) {
    Start-Sleep -Seconds 1
    $waited++
}

if (-not (Test-Path $targetDotfilePath)) {
    Write-Host "⚠ Warning: Dotfile backup exists but not accessible at: $targetDotfilePath" -ForegroundColor Yellow
    Write-Host "It may be in the WSL filesystem at: $wslBackupPath/$targetDotfile" -ForegroundColor Yellow
    $h2 = "N/A (file sync timeout)"
} else {
    $h2 = Get-FileHash $targetDotfilePath -Algorithm SHA256
}

$report = "WSL Backup Report ($Timestamp)`n---------------------------`nFull: $($h1.Hash)`nDots: $(if ($h2 -is [string]) { $h2 } else { $h2.Hash })"
$report | Out-File (Join-Path $BackupDir "HashReport_$Timestamp.txt")

Write-Host "`nSUCCESS! Backup Complete." -ForegroundColor Green
Write-Host "Location: $BackupDir"
