# ==============================================================================
# SCRIPT: Restore-AppData.ps1
# Purpose: Restore previously backed up Application Data folders
# ==============================================================================
$ErrorActionPreference = 'Stop'

# ===== HELPER FUNCTIONS: Define before use =====

# Determine original location based on app hints and backup structure
function Determine-DestinationPath {
    param(
        [string]$SourceFolderName,
        [string]$ZipBaseName
    )
    
    # Common known apps and their typical locations
    $roamingApps = @("Microsoft", "Adobe", "Google", "Mozilla", "Apple", "Thunderbird", "Discord", "Slack", "Teams")
    $localApps = @("VirtualBox", "Android", "Temp", "Steam", "Epic")
    
    # Check if zip name or folder name contains hints
    foreach ($appHint in $roamingApps) {
        if ($ZipBaseName -like "*$appHint*" -or $SourceFolderName -like "*$appHint*") {
            return Join-Path -Path $env:APPDATA -ChildPath $SourceFolderName
        }
    }
    
    foreach ($appHint in $localApps) {
        if ($ZipBaseName -like "*$appHint*" -or $SourceFolderName -like "*$appHint*") {
            return Join-Path -Path $env:LOCALAPPDATA -ChildPath $SourceFolderName
        }
    }
    
    # Default to Roaming if unsure
    return Join-Path -Path $env:APPDATA -ChildPath $SourceFolderName
}

# ===== MAIN SCRIPT =====

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
@('BackupRootDirectory') | ForEach-Object {
    if ([string]::IsNullOrWhiteSpace($config.$_)) {
        Write-Error "Config missing required field: $_"
        exit 1
    }
}

# Validate backup root exists
if (-not (Test-Path $config.BackupRootDirectory)) {
    Write-Error "Backup directory does not exist: $($config.BackupRootDirectory)"
    exit 1
}

# Find the most recent ApplicationData backup directory
$appDataBaseDir = Join-Path $config.BackupRootDirectory "ApplicationData"

if (-not (Test-Path $appDataBaseDir)) {
    Write-Error "ApplicationData backup directory not found: $appDataBaseDir"
    Write-Host "Run Option 5 (Backup-AppData) first to create backups." -ForegroundColor Cyan
    exit 1
}

$latestBackup = Find-LatestBackupDir -BackupBaseDir $appDataBaseDir -BackupType "ApplicationData"
if (-not $latestBackup) {
    exit 1
}

$appDataBaseDir = $latestBackup.FullName
$logDir = Join-Path $appDataBaseDir "Logs"

# Ensure log directory exists
if (-not (New-DirectoryIfNotExists -Path $logDir)) {
    Write-Error "Failed to create log directory"
    exit 1
}

# Start logging
$logFile = Start-ScriptLogging -LogDirectory $logDir -ScriptName "AppData_Restore"

Write-Host "`n=== STARTING APPDATA RESTORE ===" -ForegroundColor Cyan
Write-Host "Backup source: $appDataBackupDir" -ForegroundColor DarkGray

# The backup files are in BackupDir/Backups/
$appDataBackupDir = Join-Path $appDataBaseDir "Backups"

# Validate backup directory exists and has files
if (-not (Test-Path $appDataBackupDir)) {
    Write-Error "Backup directory not found: $appDataBackupDir"
    Write-Host "Please run the backup process first (Option 5) to create AppData backups." -ForegroundColor Yellow
    Stop-ScriptLogging
    exit 1
}

$zipFiles = Get-ChildItem -Path $appDataBackupDir -Filter "*.zip" -File -ErrorAction SilentlyContinue

if ($null -eq $zipFiles -or $zipFiles.Count -eq 0) {
    Write-Error "No backup files found in: $appDataBackupDir"
    Stop-ScriptLogging
    exit 1
}

Write-Host "`nFound $($zipFiles.Count) backup file(s):`n" -ForegroundColor Yellow
foreach ($zip in $zipFiles) {
    $zipSizeFormatted = Format-ByteSize -Bytes $zip.Length
    Write-Host "  • $($zip.Name) ($zipSizeFormatted)" -ForegroundColor Cyan
}

Write-Host "`n⚠ IMPORTANT BEFORE RESTORING:" -ForegroundColor Magenta
Write-Host "  1. Close all applications whose settings will be restored" -ForegroundColor Yellow
Write-Host "  2. Backups will be restored to their ORIGINAL locations" -ForegroundColor Yellow
Write-Host "  3. Existing files WILL BE OVERWRITTEN" -ForegroundColor Red
Write-Host "  4. Some apps may require restart to reload settings" -ForegroundColor Yellow

$confirm = Read-Host "`nContinue with restore? (YES/NO)"
if ($confirm -notmatch "^(YES|Yes|Y)$") {
    Write-Host "Restore cancelled." -ForegroundColor Yellow
    Stop-ScriptLogging
    exit 0
}

$restoreCount = 0
$errorCount = 0

Write-Host "`nStarting restoration..." -ForegroundColor Yellow

foreach ($zip in $zipFiles) {
    Write-Host "`n→ Processing: $($zip.Name)" -ForegroundColor Cyan
    
    try {
        # Extract to temp location first to determine destination
        $tempExtractPath = Join-Path $env:TEMP "AppData_Restore_Temp_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
        
        if (-not (New-DirectoryIfNotExists -Path $tempExtractPath)) {
            Write-Host "  ✗ Failed to create temp directory" -ForegroundColor Red
            $errorCount++
            continue
        }
        
        Write-Host "  Extracting to temporary location..." -ForegroundColor DarkGray
        try {
            Expand-Archive -Path $zip.FullName -DestinationPath $tempExtractPath -Force -ErrorAction Stop
        } catch {
            Write-Host "  ✗ Failed to extract archive: $($_.Exception.Message)" -ForegroundColor Red
            $errorCount++
            Remove-Item -Path $tempExtractPath -Recurse -Force -ErrorAction SilentlyContinue
            continue
        }
        
        # Find extracted folder
        $extractedFolders = Get-ChildItem -Path $tempExtractPath -Directory
        
        if ($null -eq $extractedFolders -or $extractedFolders.Count -eq 0) {
            Write-Host "  ✗ No folders found in archive" -ForegroundColor Red
            $errorCount++
            Remove-Item -Path $tempExtractPath -Recurse -Force -ErrorAction SilentlyContinue
            continue
        }
        
        $sourceFolder = $extractedFolders[0]
        $zipNameWithoutExt = $zip.BaseName
        $destPath = Determine-DestinationPath -SourceFolderName $sourceFolder.Name -ZipBaseName $zipNameWithoutExt
        
        if ([string]::IsNullOrWhiteSpace($destPath)) {
            Write-Host "  ⚠ Could not determine original location. Please specify manually:" -ForegroundColor Yellow
            Write-Host "    1. AppData\Roaming" -ForegroundColor White
            Write-Host "    2. AppData\Local" -ForegroundColor White
            $choice = Read-Host "Enter choice (1 or 2)"
            
            if ($choice -eq "1") {
                $destPath = Join-Path -Path $env:APPDATA -ChildPath $sourceFolder.Name
            } elseif ($choice -eq "2") {
                $destPath = Join-Path -Path $env:LOCALAPPDATA -ChildPath $sourceFolder.Name
            } else {
                Write-Host "  ✗ Invalid choice, skipping." -ForegroundColor Red
                $errorCount++
                Remove-Item -Path $tempExtractPath -Recurse -Force -ErrorAction SilentlyContinue
                continue
            }
        }
        
        Write-Host "  Destination: $destPath" -ForegroundColor DarkGray
        
        # Backup existing folder if it exists
        if (Test-Path $destPath) {
            $backupSuffix = Get-Date -Format "yyyyMMdd_HHmmss"
            $existingBackup = "${destPath}_backup_$backupSuffix"
            Write-Host "  → Backing up existing folder to: $existingBackup" -ForegroundColor Yellow
            try {
                Rename-Item -Path $destPath -NewName "$existingBackup" -ErrorAction Stop
            } catch {
                Write-Host "  ✗ Failed to backup existing folder: $($_.Exception.Message)" -ForegroundColor Red
                $errorCount++
                Remove-Item -Path $tempExtractPath -Recurse -Force -ErrorAction SilentlyContinue
                continue
            }
        }
        
        # Copy extracted folder to destination (safer than Move-Item)
        Write-Host "  → Restoring to original location..." -ForegroundColor Cyan
        try {
            Copy-Item -Path (Join-Path $sourceFolder.FullName "*") -Destination $destPath -Recurse -Force -ErrorAction Stop
        } catch {
            Write-Host "  ✗ Failed to restore folder: $($_.Exception.Message)" -ForegroundColor Red
            $errorCount++
            Remove-Item -Path $tempExtractPath -Recurse -Force -ErrorAction SilentlyContinue
            continue
        }
        
        Write-Host "  ✓ Restore successful" -ForegroundColor Green
        $restoreCount++
        
        # Cleanup temp extraction folder
        try {
            Remove-Item -Path $tempExtractPath -Recurse -Force -ErrorAction Stop
        } catch {
            Write-Host "  ⚠ Warning: Failed to cleanup temp directory: $($_.Exception.Message)" -ForegroundColor Yellow
        }
        
    } catch {
        Write-Host "  ✗ Restore failed: $($_.Exception.Message)" -ForegroundColor Red
        $errorCount++
    }
}

# Summary
Write-Host "`n========================================================" -ForegroundColor Cyan
Write-Host "RESTORE SUMMARY" -ForegroundColor Cyan
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host "Successful restores: $restoreCount" -ForegroundColor Green
Write-Host "Failed/Skipped: $errorCount" -ForegroundColor Yellow
Write-Host "Log file: $logFile" -ForegroundColor DarkGray

Write-Host "`n✓ Restore complete! Next steps:" -ForegroundColor Green
Write-Host "  1. Restart affected applications to reload settings" -ForegroundColor Cyan
Write-Host "  2. Verify settings were restored correctly" -ForegroundColor Cyan
Write-Host "  3. Check log file for any errors or warnings" -ForegroundColor Cyan

Stop-ScriptLogging

# ===== HELPER FUNCTIONS: Defined at end (after main execution) =====
# (Helper function already defined at top of script)
