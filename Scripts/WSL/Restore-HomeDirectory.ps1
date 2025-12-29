# ==============================================================================
# SCRIPT: Restore-HomeDirectory.ps1
# Purpose: Restore home directories from backup with selective restore
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

# Validate WSL distro
if (-not (Test-WslDistro -Distro $config.WslDistroName)) {
    Write-Error "WSL distro not found: $($config.WslDistroName)"
    exit 1
}

Write-Host "`n=== HOME DIRECTORY RESTORE ===" -ForegroundColor Cyan

# Find most recent home directory backup
$homeBackupBaseDir = Join-Path $config.BackupRootDirectory "HomeDirectory"
$latestBackupDir = Find-LatestBackupDir -BackupBaseDir $homeBackupBaseDir -BackupType "HomeDirectory"

if (-not $latestBackupDir) {
    Write-Host "No home directory backups found." -ForegroundColor Yellow
    Write-Host "Run Option 4 (Backup Home Directory) first." -ForegroundColor Yellow
    exit 1
}

# Find backup archives in latest backup
$backupArchives = @(Get-ChildItem -Path $latestBackupDir.FullName -Filter "home-directories_*.tar.gz" -ErrorAction SilentlyContinue)

if ($backupArchives.Count -eq 0) {
    Write-Host "No backup archives found in: $($latestBackupDir.FullName)" -ForegroundColor Yellow
    exit 1
}

# Use most recent archive if multiple exist
$archiveToRestore = $backupArchives | Sort-Object LastWriteTime -Descending | Select-Object -First 1

Write-Host "`n✓ Found backup: $($archiveToRestore.Name)" -ForegroundColor Green
Write-Host "  Backup timestamp: $($latestBackupDir.Name)" -ForegroundColor DarkGray
Write-Host "  Archive size: $(Format-ByteSize -Bytes $archiveToRestore.Length)" -ForegroundColor DarkGray

# ===== PREVIEW ARCHIVE CONTENTS =====
Write-Host "`n📋 Preview of contents (directories that will be restored):" -ForegroundColor Yellow

$archiveWslPath = ConvertTo-WslPath -WindowsPath $archiveToRestore.FullName

try {
    $archiveContents = Invoke-WslCommand -DistroName $config.WslDistroName -Command "tar -tzf '$archiveWslPath' | grep -E '^\.\/[^/]+/?$' | sort | uniq"
    
    if ($null -ne $archiveContents) {
        foreach ($item in @($archiveContents -split "`n") | Where-Object { $_ -and $_ -notmatch '^\s*$' }) {
            $cleanName = $item -replace '^\./(.+?)/?$', '$1'
            Write-Host "  • $cleanName" -ForegroundColor Cyan
        }
    } else {
        Write-Host "  (Could not preview contents)" -ForegroundColor DarkGray
    }
} catch {
    Write-Host "  (Could not preview contents)" -ForegroundColor DarkGray
}

# ===== CONFIRMATION =====
Write-Host "`n⚠ IMPORTANT NOTES:" -ForegroundColor Magenta
Write-Host "  • Existing files in target directories WILL BE OVERWRITTEN" -ForegroundColor Yellow
Write-Host "  • A backup of existing files will be created with timestamp" -ForegroundColor Yellow
Write-Host "  • This operation cannot be undone without the pre-restore backup" -ForegroundColor Yellow

Write-Host "`nContinue with restore? (Y/N): " -ForegroundColor Cyan -NoNewline
$confirm = Read-Host

if ($confirm -notmatch "^(Y|Yes|1)$") {
    Write-Host "Restore cancelled." -ForegroundColor Yellow
    exit 0
}

# Create logs directory
$logDir = Join-Path $latestBackupDir.FullName "Logs"
if (-not (New-DirectoryIfNotExists -Path $logDir)) {
    Write-Error "Failed to create log directory"
    exit 1
}

# Start logging
$logFile = Start-ScriptLogging -LogDirectory $logDir -ScriptName "HomeDirectory_Restore"

Write-Host "`n=== STARTING RESTORE ===" -ForegroundColor Cyan

# ===== BACKUP EXISTING DATA FIRST =====
Write-Host "`n🔄 Creating backup of existing home directory files..." -ForegroundColor Yellow

$preRestoreBackup = Join-Path $latestBackupDir.FullName "pre-restore-backup_$(Get-Date -Format 'yyyyMMdd_HHmmss').tar.gz"
$preRestoreBackupWsl = ConvertTo-WslPath -WindowsPath $preRestoreBackup

# Extract list of directories from archive and backup them first
$backupCmd = @"
cd `$HOME
# Get list of directories that will be restored
tar -tzf '$archiveWslPath' | grep -E '^\.\/[^/]+/?$' | sed 's|^\./||' | sed 's|/$||' | sort | uniq | while read dir; do
    if [ -d "`$dir" ]; then
        echo "Backing up: `$dir"
    fi
done | head -20

# Create pre-restore backup
tar --ignore-failed-read -czf '$preRestoreBackupWsl' `$(tar -tzf '$archiveWslPath' | grep -E '^\.\/[^/]+/?$' | sed 's|^\./||' | sed 's|/$||' | sort | uniq) 2>/dev/null || true
echo "Pre-restore backup complete"
"@

try {
    Invoke-WslCommand -Distro $config.WslDistroName -Command $backupCmd
    
    if (Test-Path $preRestoreBackup) {
        Write-Host "✓ Pre-restore backup created: $(Split-Path -Leaf $preRestoreBackup)" -ForegroundColor Green
    } else {
        Write-Host "⚠ Could not create pre-restore backup" -ForegroundColor Yellow
    }
} catch {
    Write-Host "⚠ Error creating pre-restore backup: $_" -ForegroundColor Yellow
}

# ===== EXTRACT ARCHIVE =====
Write-Host "`n📦 Extracting backup archive..." -ForegroundColor Yellow

$restoreCmd = @"
cd `$HOME
tar --ignore-failed-read -xzf '$archiveWslPath'
echo "Restore complete"
"@

try {
    Invoke-WslCommand -Distro $config.WslDistroName -Command $restoreCmd
    Write-Host "✓ Archive extracted successfully" -ForegroundColor Green
} catch {
    Write-Error "Failed to extract archive: $_"
    Stop-ScriptLogging
    exit 1
}

# ===== FIX PERMISSIONS =====
Write-Host "`n🔐 Fixing file permissions..." -ForegroundColor Yellow

$permCmd = @"
cd `$HOME
# Fix SSH directory permissions
if [ -d ".ssh" ]; then
    chmod 700 .ssh
    chmod 600 .ssh/* 2>/dev/null || true
    echo ".ssh permissions fixed"
fi

# Fix config directory permissions
if [ -d ".config" ]; then
    find .config -type d -exec chmod 755 {} \; 2>/dev/null || true
    find .config -type f -exec chmod 644 {} \; 2>/dev/null || true
    echo ".config permissions fixed"
fi

# Fix local directory permissions
if [ -d ".local" ]; then
    find .local -type d -exec chmod 755 {} \; 2>/dev/null || true
    find .local -type f -exec chmod 644 {} \; 2>/dev/null || true
    echo ".local permissions fixed"
fi

echo "Permission fixes complete"
"@

try {
    Invoke-WslCommand -Distro $config.WslDistroName -Command $permCmd
    Write-Host "✓ File permissions fixed" -ForegroundColor Green
} catch {
    Write-Host "⚠ Warning: Could not fix all permissions: $_" -ForegroundColor Yellow
}

# ===== SUMMARY =====
Write-Host "`n════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "RESTORE SUMMARY" -ForegroundColor Cyan
Write-Host "════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "Restore source: $($archiveToRestore.Name)" -ForegroundColor Cyan
Write-Host "Destination: WSL home directory (~)" -ForegroundColor Cyan
Write-Host "Pre-restore backup: $(Split-Path -Leaf $preRestoreBackup)" -ForegroundColor DarkGray
Write-Host "Log file: $logFile" -ForegroundColor DarkGray

Write-Host "`n✓ Home directory restore complete!" -ForegroundColor Green
Write-Host "`n💡 Next steps:" -ForegroundColor Cyan
Write-Host "  • Verify restored files are correct" -ForegroundColor Yellow
Write-Host "  • If needed, rollback using: tar -xzf $preRestoreBackup" -ForegroundColor Yellow
Write-Host "  • Update SSH keys permissions if needed" -ForegroundColor Yellow

Stop-ScriptLogging
exit 0
