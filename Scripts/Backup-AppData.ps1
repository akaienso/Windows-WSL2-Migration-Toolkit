# ==============================================================================
# SCRIPT: Backup-AppData.ps1
# Purpose: Selectively backup Application Data folders for chosen apps
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

$invDir = "$($config.BackupRootDirectory)\AppData\Inventories"
$logDir = "$RootDir\$($config.LogDirectory)"
$backupRootDirectory = $config.BackupRootDirectory
$timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$appDataBackupBaseDir = Join-Path $backupRootDirectory "AppData\$timestamp\Backups"
$appDataBackupDir = $appDataBackupBaseDir
$csvPath = "$invDir\$($config.InventoryInputCSV)"
$folderMapPath = "$invDir\AppData_Folder_Map.json"

# Ensure directories exist
if (-not (Test-Path $invDir)) { 
    Write-Error "Inventory directory not found: $invDir"
    exit 1
}
if (-not (Test-Path $logDir)) { 
    New-Item -ItemType Directory -Force -Path $logDir | Out-Null 
}

# Setup logging
$logTimestamp = Get-Date -Format "yyyyMMdd_HHmm"
$logFile = "$logDir\AppData_Backup_$logTimestamp.txt"
Start-Transcript -Path $logFile -Append | Out-Null

Write-Host "`n=== STARTING APPDATA BACKUP ===" -ForegroundColor Cyan
Write-Host "CSV: $csvPath" -ForegroundColor DarkGray
Write-Host "Backup destination: $appDataBackupDir" -ForegroundColor DarkGray
Write-Host "Folder map: $folderMapPath" -ForegroundColor DarkGray

# --- CHECK FOR EXISTING APPDATA BACKUPS ---
$appDataTimestampBaseDir = Join-Path $backupRootDirectory "AppData"
$existingBackups = @(Get-ChildItem -Path $appDataTimestampBaseDir -Directory -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)

if ($existingBackups.Count -gt 0) {
    Write-Host "`n⚠ Found $($existingBackups.Count) existing AppData backup(s):" -ForegroundColor Yellow
    foreach ($backup in $existingBackups | Select-Object -First 5) {
        Write-Host "   • $($backup.Name)" -ForegroundColor DarkGray
    }
    if ($existingBackups.Count -gt 5) {
        Write-Host "   ... and $($existingBackups.Count - 5) more" -ForegroundColor DarkGray
    }
    
    Write-Host "`n❓ Replace existing AppData backups with new ones?" -ForegroundColor Cyan
    Write-Host "   Note: This will DELETE all existing AppData backups and create fresh backups with current timestamp." -ForegroundColor DarkGray
    Write-Host "   Yes (Y) / No (N): " -ForegroundColor Cyan -NoNewline
    $response = Read-Host
    
    if ($response -match "^(Y|Yes)$") {
        Write-Host "`nRemoving existing AppData backups..." -ForegroundColor Yellow
        foreach ($backup in $existingBackups) {
            Remove-Item -Path $backup.FullName -Recurse -Force -ErrorAction SilentlyContinue
            Write-Host "   ✓ Deleted: $($backup.Name)" -ForegroundColor DarkGray
        }
        Write-Host "Existing AppData backups removed." -ForegroundColor Green
    } else {
        Write-Host "Keeping existing AppData backups. Creating new backup in separate directory." -ForegroundColor Cyan
    }
}

if (-not (Test-Path $appDataBackupDir)) { 
    New-Item -ItemType Directory -Force -Path $appDataBackupDir | Out-Null 
}

# Load or create folder mapping
$folderMap = @{}
if (Test-Path $folderMapPath) {
    $folderMap = Get-Content $folderMapPath -Raw | ConvertFrom-Json | ConvertTo-Hashtable
}

# Validate CSV exists
if (-not (Test-Path $csvPath)) {
    Write-Error "Input CSV not found: $csvPath"
    Write-Host "Please run Option 1 to generate inventory, then set Backup Settings to TRUE in the CSV." -ForegroundColor Yellow
    Stop-Transcript | Out-Null
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
    
    $Map | ConvertTo-Json | Out-File -FilePath $FilePath -Encoding UTF8 -Force
}

# Load CSV
$inventory = Import-Csv -Path $csvPath
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
                $safeAppName = $appName -replace '[\\/:*?"<>|]', '_'
                $zipFileName = "$safeAppName`_$(Get-Date -Format 'yyyyMMdd_HHmmss').zip"
                $zipPath = "$appDataBackupDir\$zipFileName"
                
                try {
                    Write-Host "  → Compressing: $folderPath" -ForegroundColor Cyan
                    Compress-Archive -Path $folderPath -DestinationPath $zipPath -Force -ErrorAction Stop
                    $zipSize = (Get-Item $zipPath).Length / 1MB
                    Write-Host "  ✓ Backup complete: $zipFileName ($([Math]::Round($zipSize, 2)) MB)" -ForegroundColor Green
                    $backupCount++
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

Stop-Transcript | Out-Null

