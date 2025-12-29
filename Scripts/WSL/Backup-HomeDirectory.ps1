# ==============================================================================
# SCRIPT: Backup-HomeDirectory.ps1
# Purpose: Backup selected home directories from WSL with interactive selection
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

# Create timestamped backup directory
$timestampDir = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$homeBackupDir = Join-Path $config.BackupRootDirectory "HomeDirectory\$timestampDir"
$logDir = Join-Path $homeBackupDir "Logs"

if (-not (New-DirectoryIfNotExists -Path $homeBackupDir) -or -not (New-DirectoryIfNotExists -Path $logDir)) {
    Write-Error "Failed to create backup directories"
    exit 1
}

# Start logging
$logFile = Start-ScriptLogging -LogDirectory $logDir -ScriptName "HomeDirectory_Backup"

Write-Host "`n=== HOME DIRECTORY BACKUP ===" -ForegroundColor Cyan
Write-Host "Backup destination: $homeBackupDir" -ForegroundColor DarkGray

# Load current settings to check for existing profile
$settings = Load-JsonFile -FilePath (Join-Path $RootDir "settings.json")
$homeProfile = if ($settings -and $settings.HomeDirectoryProfile) { $settings.HomeDirectoryProfile } else { $null }
$existingSelections = if ($homeProfile -and $homeProfile.SelectedDirectories) { $homeProfile.SelectedDirectories } else { @() }

# ===== DISCOVER AVAILABLE DIRECTORIES =====
Write-Host "`n📁 Discovering home directories..." -ForegroundColor Yellow

try {
    # Simple command to list directories with sizes
    $dirCommand = @'
cd $HOME && for dir in * .*; do 
  [ -d "$dir" ] && [ "$dir" != "." ] && [ "$dir" != ".." ] && echo "$dir|$(du -sh "$dir" 2>/dev/null | cut -f1)"
done | sort
'@
    $dirOutput = Invoke-WslCommand -Distro $config.WslDistroName -Command $dirCommand -ErrorAction SilentlyContinue
    
    if ($null -ne $dirOutput) {
        $availableDirs = @($dirOutput | Where-Object { $_ -match '\|' })
    } else {
        Write-Host "⚠ Could not discover directories, using defaults" -ForegroundColor Yellow
        $availableDirs = @(
            ".ssh|0",
            ".bashrc|0",
            ".config|0",
            ".local|0",
            "Documents|0",
            "Pictures|0",
            "Downloads|0"
        )
    }
} catch {
    Write-Host "⚠ Error discovering directories: $_" -ForegroundColor Yellow
    $availableDirs = @()
}

if ($availableDirs.Count -eq 0) {
    Write-Host "No directories found in home directory" -ForegroundColor Yellow
    Stop-ScriptLogging
    exit 1
}

Write-Host "`n📊 Found $($availableDirs.Count) directories:" -ForegroundColor Cyan

# Parse directory info
$dirList = @()
foreach ($dirLine in $availableDirs) {
    if ($dirLine -match '^([^|]+)\|(.+)$') {
        $dirName = $matches[1]
        $dirSize = $matches[2]
        $dirList += [PSCustomObject]@{
            Name = $dirName
            Size = $dirSize
            Selected = $dirName -in $existingSelections
        }
    }
}

# ===== DISPLAY PRESET PROFILES =====
Write-Host "`n🎯 PRESET PROFILES:" -ForegroundColor Cyan

$presets = @{
    "Essential" = @(".ssh", ".bashrc", ".zshrc", ".profile", ".gitconfig", ".inputrc")
    "Standard" = @(".ssh", ".bashrc", ".zshrc", ".profile", ".gitconfig", ".config", ".local", "Documents", "Pictures")
    "Full" = @("*")  # Indicates all except excluded
    "Custom" = @()   # Custom selection
}

$selected = $null
Write-Host "Select a preset profile (or 'C' for custom):" -ForegroundColor Yellow
Write-Host "  E) Essential - Config files only" -ForegroundColor White
Write-Host "  S) Standard - Config + common directories" -ForegroundColor White
Write-Host "  F) Full - Everything except caches" -ForegroundColor White
Write-Host "  C) Custom - Select individual directories" -ForegroundColor White
Write-Host "Choice [E/S/F/C]: " -ForegroundColor Cyan -NoNewline
$profileChoice = Read-Host

$selectedDirs = @()

switch -Regex ($profileChoice) {
    "^(E|Essential)$" {
        $selectedDirs = $presets["Essential"]
        Write-Host "✓ Using Essential profile" -ForegroundColor Green
    }
    "^(S|Standard)$" {
        $selectedDirs = $presets["Standard"]
        Write-Host "✓ Using Standard profile" -ForegroundColor Green
    }
    "^(F|Full)$" {
        # Full = all except excluded
        $selectedDirs = @($dirList.Name)
        Write-Host "✓ Using Full profile (excluding caches)" -ForegroundColor Green
    }
    "^(C|Custom)$" {
        Write-Host "`n=== CUSTOM SELECTION ===" -ForegroundColor Cyan
        Write-Host "Select directories to backup (Y/N for each):" -ForegroundColor Yellow
        
        foreach ($dir in $dirList) {
            $defaultResponse = if ($dir.Selected) { "Y" } else { "N" }
            Write-Host "  • $($dir.Name) [$($dir.Size)]" -ForegroundColor White
            Write-Host "    Include? [Y/N] (default: $defaultResponse): " -ForegroundColor Cyan -NoNewline
            
            $response = Read-Host
            if ([string]::IsNullOrWhiteSpace($response)) {
                $response = $defaultResponse
            }
            
            if ($response -match "^(Y|Yes|1)$") {
                $selectedDirs += $dir.Name
                Write-Host "    ✓ Selected" -ForegroundColor Green
            } else {
                Write-Host "    ⊘ Skipped" -ForegroundColor DarkGray
            }
        }
    }
    default {
        Write-Host "Invalid choice. Using Essential profile." -ForegroundColor Yellow
        $selectedDirs = $presets["Essential"]
    }
}

if ($selectedDirs.Count -eq 0) {
    Write-Host "No directories selected for backup." -ForegroundColor Yellow
    Stop-ScriptLogging
    exit 0
}

# ===== SAVE PROFILE =====
Write-Host "`nSaving profile to settings.json..." -ForegroundColor Yellow

if ($null -eq $settings) {
    $settings = @{}
}

if (-not $settings.ContainsKey("HomeDirectoryProfile")) {
    $settings["HomeDirectoryProfile"] = @{}
}

$settings["HomeDirectoryProfile"]["Name"] = "Default"
$settings["HomeDirectoryProfile"]["LastUpdated"] = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ")
$settings["HomeDirectoryProfile"]["SelectedDirectories"] = $selectedDirs

if (-not (Save-JsonFile -Data $settings -FilePath (Join-Path $RootDir "settings.json"))) {
    Write-Host "⚠ Warning: Could not save profile" -ForegroundColor Yellow
}

# ===== CREATE BACKUP SCRIPT FOR WSL =====
Write-Host "`n📦 Creating home directory backup..." -ForegroundColor Yellow

# Build tar include patterns
$includePatterns = $selectedDirs | ForEach-Object { "./$_" }
$backupArchive = Join-Path $homeBackupDir "home-directories_$(Get-Date -Format 'yyyyMMdd_HHmmss').tar.gz"

# Convert to WSL path
$backupArchiveWsl = ConvertTo-WslPath -WindowsPath $backupArchive

# Create backup via WSL
$tarCmd = @"
cd `$HOME
tar --ignore-failed-read -czf '$backupArchiveWsl' $($includePatterns -join ' ')
echo `"Backup complete`"
"@

try {
    Write-Host "Running tar backup..." -ForegroundColor Cyan
    Invoke-WslCommand -Distro $config.WslDistroName -Command $tarCmd
    
    if (Test-Path $backupArchive) {
        $archiveSize = Format-ByteSize -Bytes (Get-Item $backupArchive).Length
        Write-Host "✓ Backup archive created: $(Split-Path -Leaf $backupArchive) ($archiveSize)" -ForegroundColor Green
    } else {
        Write-Error "Backup archive was not created"
        Stop-ScriptLogging
        exit 1
    }
} catch {
    Write-Error "Failed to create backup: $_"
    Stop-ScriptLogging
    exit 1
}

# ===== SUMMARY =====
Write-Host "`n════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "BACKUP SUMMARY" -ForegroundColor Cyan
Write-Host "════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "Directories backed up: $($selectedDirs.Count)" -ForegroundColor Green
foreach ($dir in $selectedDirs | Sort-Object) {
    Write-Host "  ✓ $dir" -ForegroundColor DarkGray
}
Write-Host "Archive location: $backupArchive" -ForegroundColor Cyan
Write-Host "Profile saved to: settings.json" -ForegroundColor Cyan
Write-Host "Log file: $logFile" -ForegroundColor DarkGray

Write-Host "`n✓ Home directory backup complete!" -ForegroundColor Green

Stop-ScriptLogging
exit 0
