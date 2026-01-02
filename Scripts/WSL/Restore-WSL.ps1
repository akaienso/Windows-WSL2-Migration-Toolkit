# ==============================================================================
# SCRIPT: Restore-WSL.ps1
# PURPOSE: Imports Full WSL Distro from External Drive
# ==============================================================================
$ErrorActionPreference = 'Stop'

# ===== HELPER FUNCTIONS: Define before main execution =====

# Find backup directory with user selection
function Find-BackupDirectory {
    param(
        [Parameter(Mandatory=$true)]
        [string]$BackupTypeDir,
        
        [string]$BackupType = "Backup"
    )
    
    if (-not (Test-Path $BackupTypeDir)) {
        Write-Error "Backup directory not found: $BackupTypeDir"
        return $null
    }
    
    # Get all backup directories
    $backupDirs = @(Get-ChildItem -Path $BackupTypeDir -Directory -ErrorAction SilentlyContinue | 
                    Sort-Object LastWriteTime -Descending)
    
    if ($backupDirs.Count -eq 0) {
        Write-Error "No $BackupType directories found in: $BackupTypeDir"
        return $null
    }
    
    # If only one, use it
    if ($backupDirs.Count -eq 1) {
        return $backupDirs[0]
    }
    
    # Multiple backups - let user choose
    Write-Host "`nFound multiple $BackupType backups:" -ForegroundColor Yellow
    for ($i = 0; $i -lt $backupDirs.Count; $i++) {
        $size = (Get-ChildItem $backupDirs[$i].FullName -Recurse | Measure-Object -Property Length -Sum).Sum
        $sizeGB = [Math]::Round($size / 1GB, 2)
        Write-Host "  $($i + 1). $($backupDirs[$i].Name) (~$sizeGB GB)" -ForegroundColor Cyan
    }
    
    $selection = Read-Host "`nSelect backup (1-$($backupDirs.Count))"
    $index = [int]$selection - 1
    
    if ($index -ge 0 -and $index -lt $backupDirs.Count) {
        return $backupDirs[$index]
    }
    
    Write-Error "Invalid selection"
    return $null
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

# ===== VERSION VALIDATION =====
Write-Host "`n=== VERSION VALIDATION ===" -ForegroundColor Cyan
Write-Host "Checking system requirements..." -ForegroundColor Yellow

if (-not (Test-PowerShellVersion)) {
    exit 1
}

if (-not (Test-WslVersion)) {
    exit 1
}

Write-Host "✓ All version requirements met" -ForegroundColor Green

$config = Load-Config -RootDirectory $RootDir

# Validate required config fields
@('WslDistroName', 'BackupRootDirectory') | ForEach-Object {
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

$Distro = $config.WslDistroName
$WslScriptsDir = Join-Path $RootDir "Scripts\WSL"

# Find the WSL backup directory
Write-Host "`n=== WSL SYSTEM RESTORE ===" -ForegroundColor Cyan
$WslBackupDir = Join-Path $config.BackupRootDirectory "WSL"
$BackupDir = Find-BackupDirectory -BackupTypeDir $WslBackupDir -BackupType "WSL"

if (-not $BackupDir -or -not (Test-Path $BackupDir)) {
    Write-Error "Unable to locate WSL backup directory. Restore cancelled."
    exit 1
}

$InstallLocation = "C:\WSL\$Distro"

Write-Host "Source: $($BackupDir.FullName)" -ForegroundColor Yellow
Write-Host "Distro: $Distro" -ForegroundColor Yellow
Write-Host "Destination: $InstallLocation" -ForegroundColor Yellow

# ===== CRITICAL SAFETY CHECK =====
Write-Host "`n╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Red
Write-Host "║                    ⚠️  CRITICAL WARNING  ⚠️                     ║" -ForegroundColor Red
Write-Host "║                                                              ║" -ForegroundColor Red
Write-Host "║  This will OVERWRITE your existing WSL distro: $Distro" -ForegroundColor Red
Write-Host "║  Any unsaved data in your current distro will be LOST.      ║" -ForegroundColor Red
Write-Host "║                                                              ║" -ForegroundColor Red
Write-Host "║  OPTIONS:                                                    ║" -ForegroundColor Red
Write-Host "║    1. Restore to ORIGINAL distro (overwrites current)       ║" -ForegroundColor Red
Write-Host "║    2. TEST restore to temporary distro (RECOMMENDED)        ║" -ForegroundColor Red
Write-Host "║    3. CANCEL (do nothing)                                   ║" -ForegroundColor Red
Write-Host "║                                                              ║" -ForegroundColor Red
Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Red

$choice = Read-Host "`nSelect option (1/2/3)"

if ($choice -eq "3") {
    Write-Host "`n✓ Restore cancelled." -ForegroundColor Green
    exit 0
}

if ($choice -eq "2") {
    # Test restore to temporary distro
    $TestDistro = "$($Distro)-TEST-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    $TestInstallLocation = "C:\WSL\$TestDistro"
    
    Write-Host "`n⚠️  Testing restore to temporary distro: $TestDistro" -ForegroundColor Yellow
    Write-Host "If successful, you can then safely restore to the original distro." -ForegroundColor Cyan
    Write-Host "This temporary distro can be deleted afterward with:" -ForegroundColor Cyan
    Write-Host "  wsl --unregister $TestDistro" -ForegroundColor DarkGray
    
    # Use test names for the restore
    $Distro = $TestDistro
    $InstallLocation = $TestInstallLocation
    
    Write-Host "`nProceeding with TEST restore..." -ForegroundColor Yellow
} elseif ($choice -eq "1") {
    # Confirm overwrite of original
    Write-Host "`n⚠️  You selected DIRECT OVERWRITE of your existing distro." -ForegroundColor Red
    Write-Host "`nType the distro name exactly to confirm: " -ForegroundColor Red -NoNewline
    $confirm = Read-Host
    
    if ($confirm -ne $config.WslDistroName) {
        Write-Host "`n✗ Confirmation failed. Restore cancelled." -ForegroundColor Red
        exit 1
    }
    
    Write-Host "`nProceeding with direct overwrite..." -ForegroundColor Yellow
} else {
    Write-Error "Invalid selection. Restore cancelled."
    exit 1
}

# 1. Find Backups
Write-Host "`nSearching for backup files..." -ForegroundColor Yellow
$FullBackup = Get-ChildItem "$($BackupDir.FullName)\WslBackup_*.tar" -ErrorAction SilentlyContinue | 
              Sort-Object LastWriteTime -Descending | 
              Select-Object -First 1
$DotBackup = Get-ChildItem "$($BackupDir.FullName)\WslDotfiles_*.tar.gz" -ErrorAction SilentlyContinue | 
             Sort-Object LastWriteTime -Descending | 
             Select-Object -First 1

if (-not $FullBackup) { 
    Write-Error "No distro backup found in $($BackupDir.FullName)"
    exit 1
}

Write-Host "Found distro backup: $($FullBackup.Name)" -ForegroundColor Green
if ($DotBackup) {
    Write-Host "Found dotfiles backup: $($DotBackup.Name)" -ForegroundColor Green
} else {
    Write-Host "⚠ No dotfiles backup found (continuing without dotfiles)" -ForegroundColor Yellow
}

# 2. Unregister existing distro if it exists (always try, ignore error if doesn't exist)
Write-Host "`nChecking for existing distro..." -ForegroundColor Yellow
$distroExists = Test-WslDistro -Distro $Distro
if ($distroExists) {
    Write-Host "Unregistering existing distro: $Distro..." -ForegroundColor Yellow
    & wsl.exe --unregister $Distro
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to unregister existing distro: $Distro. Make sure all WSL terminals are closed."
        exit 1
    }
    Write-Host "✓ Existing distro unregistered" -ForegroundColor Green
} else {
    Write-Host "No existing distro found (proceeding with import)" -ForegroundColor DarkGray
}

# 3. Import
Write-Host "`n1. Importing Distro (this may take a few minutes)..." -ForegroundColor Magenta
if (-not (New-DirectoryIfNotExists -Path $InstallLocation)) {
    Write-Error "Failed to create install directory: $InstallLocation"
    exit 1
}

# Use wsl.exe explicitly with call operator for proper path handling
$importArgs = @(
    "--import",
    $Distro,
    $InstallLocation,
    $FullBackup.FullName
)

& wsl.exe $importArgs
if ($LASTEXITCODE -ne 0) {
    Write-Error "WSL import failed with exit code $LASTEXITCODE. Ensure WSL is properly installed and the backup file exists."
    exit 1
}

# 4. Inject Scripts
Write-Host "`n2. Starting WSL and injecting helper scripts..." -ForegroundColor Cyan
$bootCmd = "echo 'WSL distro booted successfully'"
if (-not (Invoke-WslCommand -Distro $Distro -Command $bootCmd -Quiet)) {
    Write-Error "Failed to start WSL distro"
    exit 1
}

$wslPath = ConvertTo-WslPath -WindowsPath $WslScriptsDir
if (-not $wslPath) {
    Write-Error "Failed to convert script path to WSL format"
    exit 1
}

$deployCmd = "mkdir -p ~/.wsl-toolkit && cp $wslPath/*.sh ~/.wsl-toolkit/ && chmod +x ~/.wsl-toolkit/*.sh"
if (-not (Invoke-WslCommand -Distro $Distro -Command $deployCmd)) {
    Write-Error "Failed to inject toolkit scripts"
    exit 1
}

# 5. Restore Dotfiles
if ($DotBackup) {
    Write-Host "`n3. Restoring Dotfiles..." -ForegroundColor Cyan
    $wslBackupPath = ConvertTo-WslPath -WindowsPath $BackupDir.FullName
    if (-not $wslBackupPath) {
        Write-Error "Failed to convert backup path to WSL format"
        exit 1
    }
    
    $restoreCmd = "mkdir -p ~/restore && cp '$wslBackupPath/$($DotBackup.Name)' ~/restore/"
    if (-not (Invoke-WslCommand -Distro $Distro -Command $restoreCmd)) {
        Write-Warning "Failed to copy dotfile backup to WSL"
    } else {
        $extractCmd = "~/.wsl-toolkit/restore-dotfiles.sh ~/restore/$($DotBackup.Name)"
        if (-not (Invoke-WslCommand -Distro $Distro -Command $extractCmd)) {
            Write-Warning "Dotfile restore script had errors (continuing anyway)"
        }
    }
} else {
    Write-Host "`n3. Skipping dotfiles (not available)" -ForegroundColor Yellow
}

# 6. Post Install
Write-Host "`n4. Running Post-Install Setup..." -ForegroundColor Cyan
$postCmd = "~/.wsl-toolkit/post-restore-install.sh"
if (-not (Invoke-WslCommand -Distro $Distro -Command $postCmd)) {
    Write-Warning "Post-install script had warnings (but distro should be functional)"
}

Write-Host "`n✓ RESTORE COMPLETE!" -ForegroundColor Green
Write-Host "You can now run: wsl -d $Distro" -ForegroundColor Cyan
Write-Host "`nNext Steps:" -ForegroundColor Yellow
Write-Host "  1. Launch WSL: wsl -d $Distro" -ForegroundColor White
Write-Host "  2. Verify distro is functional" -ForegroundColor White
Write-Host "  3. Check dotfiles and settings restored correctly" -ForegroundColor White
