# ==============================================================================
# SCRIPT: Backup-WSL.ps1
# PURPOSE: Exports Full WSL Distro to External Drive with Dotfiles
# ==============================================================================
$ErrorActionPreference = 'Stop'

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
@('BackupRootDirectory', 'WslDistroName') | ForEach-Object {
    if ([string]::IsNullOrWhiteSpace($config.$_)) {
        Write-Error "Config missing required field: $_"
        exit 1
    }
}

$Distro = $config.WslDistroName

# Validate distro exists
if (-not (Test-WslDistro -Distro $Distro)) {
    Write-Error "WSL Distro '$Distro' not found or WSL is not installed"
    exit 1
}

# Create timestamped backup directory
$Timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$WslBackupBaseDir = Join-Path $config.BackupRootDirectory "WSL"
$BackupDir = Join-Path $WslBackupBaseDir $Timestamp
$WslScriptsDir = Join-Path $RootDir "Scripts\WSL"

Write-Host "`n=== WSL SYSTEM BACKUP ===" -ForegroundColor Cyan
Write-Host "Distro: $Distro" -ForegroundColor Yellow
Write-Host "Backup Root: $($config.BackupRootDirectory)" -ForegroundColor Yellow
Write-Host "Backup Target: $BackupDir" -ForegroundColor Yellow

# Create backup directory
if (-not (New-DirectoryIfNotExists -Path $BackupDir)) {
    Write-Error "Failed to create backup directory: $BackupDir"
    exit 1
}

# Check for existing WSL backups
$existingBackups = @(Get-ChildItem -Path $WslBackupBaseDir -Directory -ErrorAction SilentlyContinue | 
                     Sort-Object LastWriteTime -Descending)

if ($existingBackups.Count -gt 0) {
    Write-Host "`n⚠ Found $($existingBackups.Count) existing WSL backup(s):" -ForegroundColor Yellow
    foreach ($backup in $existingBackups | Select-Object -First 5) {
        Write-Host "   • $($backup.Name)" -ForegroundColor DarkGray
    }
    if ($existingBackups.Count -gt 5) {
        Write-Host "   ... and $($existingBackups.Count - 5) more" -ForegroundColor DarkGray
    }
    
    Write-Host "`n❓ Delete existing WSL backups and create a new one?" -ForegroundColor Cyan
    Write-Host "   (Creating in separate directory if you choose No)" -ForegroundColor DarkGray
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

# 1. Inject Toolkit into WSL
Write-Host "`n1. Injecting helper scripts into ~/.wsl-toolkit..." -ForegroundColor Cyan
$wslPath = ConvertTo-WslPath -WindowsPath $WslScriptsDir
if (-not $wslPath) {
    Write-Error "Failed to convert script path to WSL format"
    exit 1
}

$deployCmd = "mkdir -p ~/.wsl-toolkit && cp $wslPath/*.sh ~/.wsl-toolkit/ && chmod +x ~/.wsl-toolkit/*.sh"
if (-not (Invoke-WslCommand -Distro $Distro -Command $deployCmd)) {
    Write-Error "Failed to inject toolkit scripts into WSL"
    exit 1
}

# 2. Run Dotfile Backup
Write-Host "2. Running dotfile backup inside WSL..." -ForegroundColor Cyan
if (-not (Invoke-WslCommand -Distro $Distro -Command "~/.wsl-toolkit/backup-dotfiles.sh")) {
    Write-Error "Dotfile backup script failed"
    exit 1
}

$LatestDotfile = wsl -d $Distro -- bash -lc "ls -t ~/wsl-dotfile-backups 2>/dev/null | head -n 1" 2>$null | Out-String
$LatestDotfile = $LatestDotfile.Trim()
if (-not $LatestDotfile) { 
    Write-Error "No dotfile backup created. Check that ~/.wsl-dotfile-backups exists in the distro."
    exit 1
}

Write-Host "   -> Found: $LatestDotfile" -ForegroundColor Green
Write-Host "   -> Copying to backup drive..."

# Convert Windows path to WSL mount path properly
$wslBackupPath = ConvertTo-WslPath -WindowsPath $BackupDir
if (-not $wslBackupPath) {
    Write-Error "Failed to convert backup path to WSL format"
    exit 1
}

# Create the backup directory in WSL if it doesn't exist
$createDirCmd = "mkdir -p '$wslBackupPath'"
if (-not (Invoke-WslCommand -Distro $Distro -Command $createDirCmd)) {
    Write-Error "Failed to create backup directory in WSL: $wslBackupPath"
    exit 1
}

# Copy the dotfiles to the backup directory with renamed filename
$targetDotfile = "WslDotfiles_{0}.tar.gz" -f $Timestamp
$copyCmd = "cp ~/wsl-dotfile-backups/$LatestDotfile '$wslBackupPath/$targetDotfile'"
if (-not (Invoke-WslCommand -Distro $Distro -Command $copyCmd)) {
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
Write-Host "Location: $BackupDir" -ForegroundColor Cyan
Write-Host "`nBackup Contents:" -ForegroundColor Yellow
Write-Host "  • Full distro: $FullExportFile" -ForegroundColor White
Write-Host "  • Dotfiles: $targetDotfile" -ForegroundColor White
Write-Host "  • Hash report: HashReport_$Timestamp.txt" -ForegroundColor White
Write-Host "`nNext Steps:" -ForegroundColor Cyan
Write-Host "  1. Verify backup integrity using hash report" -ForegroundColor White
Write-Host "  2. Keep backup on safe external storage" -ForegroundColor White
Write-Host "  3. After clean Windows install, run Option 4 (Restore-WSL) to restore" -ForegroundColor White
