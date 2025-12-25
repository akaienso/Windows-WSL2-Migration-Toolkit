# ==============================================================================
# SCRIPT: Restore-AppData.ps1
# Purpose: Restore previously backed up Application Data folders
# ==============================================================================

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$RootDir = Split-Path -Parent $ScriptDir
$configPath = "$RootDir\config.json"

if (Test-Path $configPath) { 
    $config = Get-Content $configPath -Raw | ConvertFrom-Json 
} else { 
    Write-Error "Config missing: $configPath"
    exit 1
}

# Source the helper function from Start.ps1
. "$RootDir\Start.ps1"

$logDir = "$RootDir\$($config.LogDirectory)"

# Find the AppData backup directory
$AppDataBackupDir = Join-Path $config.BackupRootDirectory "AppData"
$BackupDir = Find-BackupDirectory -BackupTypeDir $AppDataBackupDir -BackupType "AppData"

if (-not $BackupDir -or -not (Test-Path $BackupDir)) {
    Write-Error "Unable to locate AppData backup directory. Restore cancelled."
    exit 1
}

$appDataBackupDir = $BackupDir

# Ensure directories exist
if (-not (Test-Path $logDir)) { 
    New-Item -ItemType Directory -Force -Path $logDir | Out-Null 
}

# Setup logging
$timestamp = Get-Date -Format "yyyyMMdd_HHmm"
$logFile = "$logDir\AppData_Restore_$timestamp.txt"
Start-Transcript -Path $logFile -Append | Out-Null

Write-Host "`n=== STARTING APPDATA RESTORE ===" -ForegroundColor Cyan
Write-Host "Backup source: $appDataBackupDir" -ForegroundColor DarkGray

# Validate backup directory exists and has files
if (-not (Test-Path $appDataBackupDir)) {
    Write-Error "Backup directory not found: $appDataBackupDir"
    Write-Host "Please run Option 5 to create backups first." -ForegroundColor Yellow
    Stop-Transcript | Out-Null
    exit 1
}

$zipFiles = Get-ChildItem -Path $appDataBackupDir -Filter "*.zip" -File -ErrorAction SilentlyContinue
if ($zipFiles.Count -eq 0) {
    Write-Error "No backup files found in: $appDataBackupDir"
    Stop-Transcript | Out-Null
    exit 1
}

Write-Host "`nFound $($zipFiles.Count) backup file(s):`n" -ForegroundColor Yellow
foreach ($zip in $zipFiles) {
    Write-Host "  • $($zip.Name) ($([Math]::Round($zip.Length / 1MB, 2)) MB)" -ForegroundColor Cyan
}

Write-Host "`n⚠ IMPORTANT BEFORE RESTORING:" -ForegroundColor Magenta
Write-Host "  1. Close all applications whose settings will be restored" -ForegroundColor Yellow
Write-Host "  2. Backups will be restored to their ORIGINAL locations" -ForegroundColor Yellow
Write-Host "  3. Existing files WILL BE OVERWRITTEN" -ForegroundColor Red
Write-Host "  4. Some apps may require restart to reload settings" -ForegroundColor Yellow

$confirm = Read-Host "`nContinue with restore? (YES/NO)"
if ($confirm -notmatch "^(YES|Yes|Y)$") {
    Write-Host "Restore cancelled." -ForegroundColor Yellow
    Stop-Transcript | Out-Null
    exit 0
}

$restoreCount = 0
$errorCount = 0

Write-Host "`nStarting restoration..." -ForegroundColor Yellow

foreach ($zip in $zipFiles) {
    Write-Host "`n→ Processing: $($zip.Name)" -ForegroundColor Cyan
    
    try {
        # Extract to temp location first to determine destination
        $tempExtractPath = "$env:TEMP\AppData_Restore_Temp_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
        New-Item -ItemType Directory -Force -Path $tempExtractPath | Out-Null
        
        Write-Host "  Extracting to temporary location..." -ForegroundColor DarkGray
        Expand-Archive -Path $zip.FullName -DestinationPath $tempExtractPath -Force -ErrorAction Stop
        
        # Find extracted folder
        $extractedFolders = Get-ChildItem -Path $tempExtractPath -Directory
        
        if ($extractedFolders.Count -eq 0) {
            Write-Host "  ✗ Failed to extract: No folders found in archive" -ForegroundColor Red
            $errorCount++
            Remove-Item -Path $tempExtractPath -Recurse -Force -ErrorAction SilentlyContinue
            continue
        }
        
        # Determine original location based on folder name pattern
        # Pattern: AppName_FolderName_timestamp.zip
        $zipNameWithoutExt = $zip.BaseName
        
        # Try to determine if this was from Roaming or Local by checking if we can find clues
        $sourceFolder = $extractedFolders[0]
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
            $existingBackup = "$destPath`_backup_$backupSuffix"
            Write-Host "  → Backing up existing folder to: $existingBackup" -ForegroundColor Yellow
            Rename-Item -Path $destPath -NewName "$destPath`_backup_$backupSuffix" -ErrorAction Stop
        }
        
        # Move extracted folder to destination
        Write-Host "  → Restoring to original location..." -ForegroundColor Cyan
        Move-Item -Path $sourceFolder.FullName -Destination $destPath -Force -ErrorAction Stop
        
        Write-Host "  ✓ Restore successful" -ForegroundColor Green
        $restoreCount++
        
        # Cleanup temp extraction folder
        Remove-Item -Path $tempExtractPath -Recurse -Force -ErrorAction SilentlyContinue
        
    } catch {
        Write-Host "  ✗ Restore failed: $($_.Exception.Message)" -ForegroundColor Red
        $errorCount++
        
        # Cleanup
        if (Test-Path $tempExtractPath) {
            Remove-Item -Path $tempExtractPath -Recurse -Force -ErrorAction SilentlyContinue
        }
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

Stop-Transcript | Out-Null

# ===== HELPER FUNCTION: Determine destination path =====
function Determine-DestinationPath {
    param(
        [string]$SourceFolderName,
        [string]$ZipBaseName
    )
    
    # Common known apps and their typical locations
    $roamingApps = @("Microsoft", "Adobe", "Google", "Mozilla", "Apple", "Thunderbird")
    $localApps = @("VirtualBox", "Android", "Temp")
    
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
