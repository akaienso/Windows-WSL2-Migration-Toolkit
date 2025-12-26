# ==============================================================================
# SCRIPT: Backup-AppData.ps1
# Purpose: Selectively backup Application Data folders for chosen apps
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
@('BackupRootDirectory', 'InventoryInputCSV') | ForEach-Object {
    if ([string]::IsNullOrWhiteSpace($config.$_)) {
        Write-Error "Config missing required field: $_"
        exit 1
    }
}

# Validate backup root exists
if (-not (Test-Path $config.BackupRootDirectory)) {
    Write-Error "Backup directory does not exist: $($config.BackupRootDirectory)"
    Write-Host "Run Start.ps1 to create and configure the backup directory." -ForegroundColor Cyan
    exit 1
}

# Find the most recent timestamped Inventory directory
$invBaseDir = Join-Path $config.BackupRootDirectory "Inventory"
$latestInvDir = Find-LatestBackupDir -BackupBaseDir $invBaseDir -BackupType "Inventory"
if (-not $latestInvDir) {
    exit 1
}

# Use the inventory timestamp to organize ApplicationData backup in parallel structure
$invTimestamp = $latestInvDir.Name
$appDataBaseDir = Join-Path $config.BackupRootDirectory "ApplicationData"
$invDir = Join-Path $latestInvDir.FullName "Inventories"
$logDir = Join-Path $appDataBaseDir $invTimestamp "Logs"
$appDataBackupDir = Join-Path $appDataBaseDir $invTimestamp "Backups"
$csvPath = Join-Path $invDir $config.InventoryInputCSV
$folderMapPath = Join-Path $invDir "AppData_Folder_Map.json"

# Ensure directories exist
if (-not (New-DirectoryIfNotExists -Path $logDir) -or -not (New-DirectoryIfNotExists -Path $appDataBackupDir)) {
    Write-Error "Failed to create required backup directories"
    exit 1
}

# Start logging
$logFile = Start-ScriptLogging -LogDirectory $logDir -ScriptName "AppData_Backup"

Write-Host "`n=== STARTING APPDATA BACKUP ===" -ForegroundColor Cyan
Write-Host "CSV: $csvPath" -ForegroundColor DarkGray
Write-Host "Backup destination: $appDataBackupDir" -ForegroundColor DarkGray
Write-Host "Folder map: $folderMapPath" -ForegroundColor DarkGray

# --- CHECK FOR EXISTING APPDATA BACKUPS ---
$existingBackups = @(Get-ChildItem -Path $appDataBaseDir -Directory -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)

if ($existingBackups.Count -gt 0) {
    Write-Host "`n⚠ Found $($existingBackups.Count) existing ApplicationData backup(s):" -ForegroundColor Yellow
    foreach ($backup in $existingBackups | Select-Object -First 5) {
        Write-Host "   • $($backup.Name)" -ForegroundColor DarkGray
    }
    if ($existingBackups.Count -gt 5) {
        Write-Host "   ... and $($existingBackups.Count - 5) more" -ForegroundColor DarkGray
    }
    
    Write-Host "`n❓ Keep existing ApplicationData backups or create a new one?" -ForegroundColor Cyan
    Write-Host "   (New backup will use current timestamp and coexist with old backups)" -ForegroundColor DarkGray
    Write-Host "   Create New (N) / Keep Old (K): " -ForegroundColor Cyan -NoNewline
    $response = Read-Host
    
    if ($response -match "^(K|Keep)$") {
        Write-Host "Keeping existing ApplicationData backups." -ForegroundColor Cyan
        # Use the most recent backup directory
        $latestBackup = $existingBackups | Select-Object -First 1
        $invTimestamp = $latestBackup.Name
        $appDataBackupDir = "$appDataBaseDir\$invTimestamp\Backups"
    }
}

if (-not (Test-Path $appDataBackupDir)) { 
    try {
        New-Item -ItemType Directory -Force -Path $appDataBackupDir | Out-Null
    } catch {
        Write-Error "Failed to create backup directory: $_"
        Stop-Transcript | Out-Null
        exit 1
    }
}

# Load or create folder mapping
$folderMap = Load-JsonFile -FilePath $folderMapPath

# Validate CSV exists and has required columns
if (-not (Test-CsvFile -CsvPath $csvPath -RequiredColumns @('Backup Settings (Y/N)', 'Application Name', 'Environment', 'Source'))) {
    Write-Host "Please run Option 1 to generate inventory, then set 'Backup Settings (Y/N)' to TRUE for apps to backup." -ForegroundColor Yellow
    Stop-ScriptLogging
    exit 1
}

# ===== HELPER FUNCTION: Convert PSObject to Hashtable =====
function ConvertTo-Hashtable {
    param(
        [Parameter(ValueFromPipeline)]
        $InputObject
    )
    
    if ($InputObject -eq $null) { return @{} }
    
    $hash = @{}
    $InputObject.PSObject.Properties | ForEach-Object {
        $hash[$_.Name] = $_.Value
    }
    return $hash
}

# ===== HELPER FUNCTION: Stricter fuzzy search =====
function Find-AppDataFolders {
    param(
        [string]$AppName,
        [string]$SearchPath,
        [string]$LocationName
    )
    
    if (-not (Test-Path $SearchPath)) {
        return @()
    }
    
    # Extract primary keyword from package ID (last part after dot, or first word)
    $parts = $AppName.Split('.')
    $primaryKeyword = $parts[-1]  # "Obsidian.Obsidian" → "Obsidian"
    
    # Also try first part if it's not a common suffix
    if ($parts.Count -gt 1 -and $parts[0].Length -gt 2) {
        $primaryKeyword = $parts[0]  # For some formats
    }
    
    $primaryLower = $primaryKeyword.ToLower()
    $matches = @()
    
    try {
        $folders = Get-ChildItem -Path $SearchPath -Directory -ErrorAction SilentlyContinue
        
        foreach ($folder in $folders) {
            $folderNameLower = $folder.Name.ToLower()
            
            # Only match if folder name contains the primary keyword
            # Require it to be a meaningful match (not substring of something else)
            if ($folderNameLower -eq $primaryLower -or 
                $folderNameLower -like "$primaryLower*" -or 
                $folderNameLower -like "*$primaryLower") {
                
                # Calculate a score to prefer exact/closer matches
                $score = 0
                if ($folderNameLower -eq $primaryLower) { $score = 100 }
                elseif ($folderNameLower -like "$primaryLower*") { $score = 50 }
                else { $score = 10 }
                
                $matches += @{ 
                    Path = $folder.FullName
                    Name = $folder.Name
                    Score = $score
                    Location = $LocationName
                }
            }
        }
        
        # Return matches sorted by score (highest first)
        return $matches | Sort-Object -Property Score -Descending
    } catch {
        return @()
    }
}

# ===== HELPER FUNCTION: User selection from matches =====
function Select-FolderFromMatches {
    param(
        [string]$AppName,
        [array]$Matches
    )
    
    Write-Host "`n  ℹ Potential folders found for: $AppName" -ForegroundColor Cyan
    
    for ($i = 0; $i -lt $Matches.Count; $i++) {
        $m = $Matches[$i]
        Write-Host "    $($i + 1)) $($m.Name) [$($m.Location)]" -ForegroundColor White
    }
    
    Write-Host "    O) Enter a different folder name" -ForegroundColor White
    Write-Host "    N) None - Skip this app" -ForegroundColor White
    
    $selection = Read-Host "    Select option (1-$($Matches.Count), O, or N)"
    
    if ($selection -eq 'N') {
        Write-Host "    Skipping backup for $AppName" -ForegroundColor Yellow
        return $null
    }
    elseif ($selection -eq 'O') {
        $customName = Read-Host "    Enter the folder name to backup"
        if ([string]::IsNullOrWhiteSpace($customName)) {
            Write-Host "    Cancelled." -ForegroundColor Yellow
            return $null
        }
        return $customName
    }
    else {
        $index = [int]$selection - 1
        if ($index -ge 0 -and $index -lt $Matches.Count) {
            return $Matches[$index].Name
        }
        Write-Host "    Invalid selection." -ForegroundColor Red
        return $null
    }
}

# ===== HELPER FUNCTION: Prompt for manual entry =====
function Get-ManualFolderName {
    param(
        [string]$AppName
    )
    
    Write-Host "`n  ⚠ No matching folders found for: $AppName" -ForegroundColor Yellow
    Write-Host "    O) Enter the folder name manually" -ForegroundColor White
    Write-Host "    N) None - Skip this app" -ForegroundColor White
    
    $selection = Read-Host "    Select option (O or N)"
    
    if ($selection -eq 'N') {
        Write-Host "    Skipping backup for $AppName" -ForegroundColor Yellow
        return $null
    }
    elseif ($selection -eq 'O') {
        $customName = Read-Host "    Enter the folder name to backup"
        if ([string]::IsNullOrWhiteSpace($customName)) {
            Write-Host "    Cancelled." -ForegroundColor Yellow
            return $null
        }
        return $customName
    }
    else {
        Write-Host "    Invalid selection." -ForegroundColor Red
        return $null
    }
}

# ===== HELPER FUNCTION: Save folder mapping to JSON =====
function Save-FolderMapping {
    param(
        [hashtable]$Map,
        [string]$FilePath
    )
    
    if (Save-JsonFile -Data $Map -FilePath $FilePath) {
        return $true
    } else {
        Write-Host "⚠ Warning: Failed to save folder mapping" -ForegroundColor Yellow
        return $false
    }
}

# Load CSV
try {
    $inventory = Import-Csv -Path $csvPath -ErrorAction Stop
} catch {
    Write-Error "Failed to parse CSV file: $_"
    Write-Host "Please check the file format and ensure it's valid CSV." -ForegroundColor Yellow
    Stop-Transcript | Out-Null
    exit 1
}

if ($null -eq $inventory -or $inventory.Count -eq 0) {
    Write-Host "No entries found in inventory CSV. Nothing to backup." -ForegroundColor Yellow
    Stop-Transcript | Out-Null
    exit 0
}

$backupCount = 0
$errorCount = 0
$skippedCount = 0

Write-Host "`nScanning inventory for apps marked 'Backup Settings = TRUE'..." -ForegroundColor Yellow

foreach ($row in $inventory) {
    # Check if Backup Settings column exists and is TRUE
    if (-not $row.PSObject.Properties['Backup Settings (Y/N)']) {
        continue
    }
    
    if ($row.'Backup Settings (Y/N)' -match "TRUE|Yes|Y|1") {
        $appName = $row.'Application Name'
        
        # Skip Windows Store and WSL apps (only backup Windows user apps)
        if ($row.Environment -match "WSL" -or $row.Source -eq "Microsoft Store") {
            Write-Host "`n⊘ Skipping: $appName (Source: $($row.Source))" -ForegroundColor DarkGray
            Write-Host "  (Microsoft Store and WSL apps are not suitable for AppData backup)" -ForegroundColor DarkGray
            $skippedCount++
            continue
        }
        
        Write-Host "`n→ Processing: $appName" -ForegroundColor Yellow
        
        $folderName = $null
        
        # Check if we already have a mapping for this app
        if ($folderMap.ContainsKey($appName)) {
            $folderName = $folderMap[$appName]
            Write-Host "  ✓ Using stored mapping: $folderName" -ForegroundColor Green
        }
        else {
            # Search in both Roaming and Local AppData
            $roamingPath = $env:APPDATA
            $localPath = $env:LOCALAPPDATA
            
            $roamingMatches = Find-AppDataFolders -AppName $appName -SearchPath $roamingPath -LocationName "Roaming"
            $localMatches = Find-AppDataFolders -AppName $appName -SearchPath $localPath -LocationName "Local"
            
            $allMatches = @($roamingMatches) + @($localMatches)
            
            if ($allMatches.Count -eq 1) {
                # Single obvious match - use it automatically
                $folderName = $allMatches[0].Name
                Write-Host "  ✓ Found: $folderName [$($allMatches[0].Location)]" -ForegroundColor Green
            }
            elseif ($allMatches.Count -gt 1) {
                # Multiple matches - ask user
                $folderName = Select-FolderFromMatches -AppName $appName -Matches $allMatches
            }
            else {
                # No matches - ask for manual entry
                $folderName = Get-ManualFolderName -AppName $appName
            }
            
            # Save the mapping if we found one
            if (-not [string]::IsNullOrWhiteSpace($folderName)) {
                $folderMap[$appName] = $folderName
                Save-FolderMapping -Map $folderMap -FilePath $folderMapPath
            }
        }
        
        # If we have a folder name, try to backup
        if (-not [string]::IsNullOrWhiteSpace($folderName)) {
            # Find the full path (could be in Roaming or Local)
            $roamingPath = $env:APPDATA
            $localPath = $env:LOCALAPPDATA
            
            $folderPath = $null
            
            if (Test-Path "$roamingPath\$folderName") {
                $folderPath = "$roamingPath\$folderName"
            }
            elseif (Test-Path "$localPath\$folderName") {
                $folderPath = "$localPath\$folderName"
            }
            
            if ($folderPath -and (Test-Path $folderPath)) {
                $safeAppName = Get-SafeFilename -Filename $appName
                $zipFileName = "$safeAppName`_$(Get-Date -Format 'yyyyMMdd_HHmmss').zip"
                $zipPath = Join-Path $appDataBackupDir $zipFileName
                
                try {
                    Write-Host "  → Compressing: $folderPath" -ForegroundColor Cyan
                    Compress-Archive -Path $folderPath -DestinationPath $zipPath -Force -ErrorAction Stop
                    
                    # Verify file was created
                    if (-not (Test-Path $zipPath)) {
                        Write-Host "  ✗ Backup failed: Archive file was not created" -ForegroundColor Red
                        $errorCount++
                    } else {
                        $zipSize = (Get-Item $zipPath).Length
                        $zipSizeFormatted = Format-ByteSize -Bytes $zipSize
                        Write-Host "  ✓ Backup complete: $zipFileName ($zipSizeFormatted)" -ForegroundColor Green
                        $backupCount++
                    }
                } catch {
                    Write-Host "  ✗ Backup failed: $($_.Exception.Message)" -ForegroundColor Red
                    $errorCount++
                }
            }
            else {
                Write-Host "  ✗ Folder not found in AppData: $folderName" -ForegroundColor Red
                $errorCount++
            }
        }
        else {
            $skippedCount++
        }
    }
}

# Summary
Write-Host "`n========================================================" -ForegroundColor Cyan
Write-Host "BACKUP SUMMARY" -ForegroundColor Cyan
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host "Successful backups: $backupCount" -ForegroundColor Green
Write-Host "Skipped/No selection: $skippedCount" -ForegroundColor Yellow
Write-Host "Failed: $errorCount" -ForegroundColor Yellow
Write-Host "Backup destination: $appDataBackupDir" -ForegroundColor Cyan
Write-Host "Folder mappings saved to: $folderMapPath" -ForegroundColor Cyan
Write-Host "Log file: $logFile" -ForegroundColor DarkGray

Write-Host "`n⚠ IMPORTANT NOTES:" -ForegroundColor Magenta
Write-Host "  • Your folder selections are saved in AppData_Folder_Map.json" -ForegroundColor Yellow
Write-Host "  • Future backups will use these stored mappings automatically" -ForegroundColor Yellow
Write-Host "  • To reset a mapping, delete it from the JSON file and re-run backup" -ForegroundColor Yellow
Write-Host "  • Some apps may require re-authentication or reconfiguration after restore" -ForegroundColor Yellow

Stop-ScriptLogging

