# ==============================================================================
# SCRIPT: Get-Inventory.ps1
# Purpose: Scan Windows and WSL applications and generate inventory CSV
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
@('BackupRootDirectory', 'InventoryOutputCSV') | ForEach-Object {
    if ([string]::IsNullOrWhiteSpace($config.$_)) {
        Write-Error "Config missing required field: $_"
        exit 1
    }
}

# Create timestamped inventory directory structure
$timestampDir = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$invDir = Join-Path $config.BackupRootDirectory "Inventory\$timestampDir\Inventories"
$logDir = Join-Path $config.BackupRootDirectory "Inventory\$timestampDir\Logs"
$csvPath = Join-Path $invDir $config.InventoryOutputCSV
$wingetJsonPath = Join-Path $invDir "winget-apps.json"

# Ensure directories exist
if (-not (New-DirectoryIfNotExists -Path $invDir) -or -not (New-DirectoryIfNotExists -Path $logDir)) {
    Write-Error "Failed to create required directories"
    exit 1
}

# Start logging
$logTimestamp = Get-Date -Format "yyyyMMdd_HHmm"
$logFile = Start-ScriptLogging -LogDirectory $logDir -ScriptName "Inventory"

Write-Host "`n=== STARTING APP INVENTORY SCAN ===" -ForegroundColor Cyan

# STEP 0: SYSTEM INFO
Write-Host "0. Capturing System Identity..." -NoNewline -ForegroundColor Yellow
try {
    $info = Get-ComputerInfo | Select-Object CsName, WindowsProductName, WindowsVersion, OsArchitecture
    $info | Out-File -FilePath "$invDir\System_Info.txt" -Encoding UTF8
    Write-Host " Done." -ForegroundColor Green
} catch { Write-Host " Skipped." }

# FILTERS
$winSystemKeywords = @("Redistributable", "C\+\+", "\.NET", "Framework", "Runtime", "SDK", "Driver", "Intel", "NVIDIA", "AMD", "Realtek", "Update for", "KB[0-9]", "Service", "BIOS", "Firmware", "Chipset", "DirectX")
$linuxSystemKeywords = @("^lib", "^linux-", "^ubuntu-", "^python3-", "-minimal$", "-core$", "systemd", "udev", "init", "sudo", "bash", "coreutils", "grep", "sed", "tar", "gzip", "openssl", "netplan", "wsl", "snapd", "apt", "dpkg", "mount", "passwd", "tzdata")

function Get-AppCategory ($name, $env) {
    if ($env -eq "Windows") { foreach ($key in $winSystemKeywords) { if ($name -match $key) { return "System/Driver (Auto-Detected)" } } }
    if ($env -match "WSL") { foreach ($key in $linuxSystemKeywords) { if ($name -match $key) { return "System/Base (Linux)" } } }
    return "User-Installed Application"
}

$masterList = @(); $knownApps = @{}

# STEP 1: WINGET
Write-Host "1. Exporting Winget... " -NoNewline -ForegroundColor Yellow
try {
    winget export -o $wingetJsonPath --include-versions | Out-Null
    if (Test-Path $wingetJsonPath) {
        $json = Get-Content $wingetJsonPath -Raw | ConvertFrom-Json
        foreach ($source in $json.Sources) {
            foreach ($pkg in $source.Packages) {
                $cat = Get-AppCategory -name $pkg.PackageIdentifier -env "Windows"
                $masterList += [PSCustomObject]@{ 'Category' = $cat; 'Application Name' = $pkg.PackageIdentifier; 'Version' = $pkg.Version; 'Environment' = "Windows"; 'Source' = "Winget"; 'Restoration Command' = "winget install --id $($pkg.PackageIdentifier) -e" }
                $knownApps[$pkg.PackageIdentifier] = $true
            }
        }
    }
    Write-Host "Done." -ForegroundColor Green
} catch { Write-Host "Failed." -ForegroundColor Red }

# STEP 2: STORE
Write-Host "2. Scanning Store... " -NoNewline -ForegroundColor Yellow
try {
    $storeApps = Get-AppxPackage -ErrorAction Stop | Where-Object { $_.NonRemovable -eq $false -and $_.IsFramework -eq $false -and $_.SignatureKind -eq "Store" }
    foreach ($app in $storeApps) {
        if (-not $knownApps.ContainsKey($app.Name)) {
            $cat = Get-AppCategory -name $app.Name -env "Windows"
            $masterList += [PSCustomObject]@{ 'Category' = $cat; 'Application Name' = $app.Name; 'Version' = $app.Version; 'Environment' = "Windows"; 'Source' = "Microsoft Store"; 'Restoration Command' = "winget install --id $($app.Name) --source msstore" }
            $knownApps[$app.Name] = $true
        }
    }
    Write-Host "Done." -ForegroundColor Green
} catch { Write-Host "Failed." }

# STEP 3: REGISTRY
Write-Host "3. Scanning Registry... " -NoNewline -ForegroundColor Yellow
$registryLocations = @("HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*", "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*", "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*")
foreach ($loc in $registryLocations) {
    try {
        $entries = Get-ItemProperty $loc -ErrorAction Stop
        foreach ($app in $entries) {
            if (-not [string]::IsNullOrWhiteSpace($app.DisplayName) -and -not $knownApps.ContainsKey($app.DisplayName)) {
                # Skip system components and entries without uninstall string
                if ($app.PSObject.Properties['SystemComponent'] -and $app.SystemComponent -eq 1) {
                    continue
                }
                if ([string]::IsNullOrWhiteSpace($app.UninstallString)) {
                    continue
                }
                $cat = Get-AppCategory -name $app.DisplayName -env "Windows"
                $masterList += [PSCustomObject]@{ 'Category' = $cat; 'Application Name' = $app.DisplayName; 'Version' = $app.DisplayVersion; 'Environment' = "Windows"; 'Source' = "Registry (Manual)"; 'Restoration Command' = "winget search `"$($app.DisplayName)`"" }
            }
        }
    } catch {}
}
Write-Host "Done." -ForegroundColor Green

# STEP 4: WSL2 (App Inventory Only)
Write-Host "4. Inventorying WSL2 Packages... " -NoNewline -ForegroundColor Yellow
try {
    $wslOutput = wsl --exec apt-mark showmanual 2>&1
    if ($LASTEXITCODE -ne 0) { throw "WSL Error" }
    if ($null -ne $wslOutput) {
        foreach ($line in $wslOutput) {
            if (-not [string]::IsNullOrWhiteSpace($line) -and $line -notmatch "command not found") {
                $cat = Get-AppCategory -name $line -env "WSL"
                $masterList += [PSCustomObject]@{ 'Category' = $cat; 'Application Name' = $line; 'Version' = "Latest"; 'Environment' = "WSL2 (Ubuntu)"; 'Source' = "Apt (Linux)"; 'Restoration Command' = "sudo apt install $line -y" }
            }
        }
    }
    Write-Host "Done." -ForegroundColor Green
} catch { Write-Host "Failed." -ForegroundColor Red }

# EXPORT
Write-Host "5. Saving CSV... " -NoNewline -ForegroundColor Yellow
try {
    $masterList | Sort-Object Category, Environment, 'Application Name' | Select-Object 'Category', 'Application Name', 'Version', 'Environment', 'Source', 'Restoration Command', @{Name='Keep (Y/N)';Expression={"FALSE"}}, @{Name='Backup Settings (Y/N)';Expression={"FALSE"}} | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8 -Force
    if (-not (Test-Path $csvPath)) {
        Write-Error "CSV file was not created: $csvPath"
        exit 1
    }
    Write-Host "Done." -ForegroundColor Green
} catch {
    Write-Error "Failed to save CSV: $_"
    exit 1
}

if (Test-Path $wingetJsonPath) { Remove-Item $wingetJsonPath -Force -ErrorAction SilentlyContinue }
Stop-ScriptLogging
Write-Host "`nSUCCESS! Inventory saved to: $csvPath" -ForegroundColor Green
Write-Host "Log file: $logFile" -ForegroundColor DarkGray
