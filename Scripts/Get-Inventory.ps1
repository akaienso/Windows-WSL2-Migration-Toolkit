# ==============================================================================
# SCRIPT: Get-Inventory.ps1
# ==============================================================================
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$RootDir = Split-Path -Parent $ScriptDir 
$configPath = "$RootDir\config.json"

if (Test-Path $configPath) { $config = Get-Content $configPath -Raw | ConvertFrom-Json } 
else { Write-Error "Config missing."; exit }

$invDir = "$($config.BackupRootDirectory)\AppData\Inventories"
$logDir = "$RootDir\$($config.LogDirectory)"
$csvPath = "$invDir\$($config.InventoryOutputCSV)"
$wingetJsonPath = "$invDir\winget-apps.json"

if (-not (Test-Path $invDir)) { New-Item -ItemType Directory -Force -Path $invDir | Out-Null }
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Force -Path $logDir | Out-Null }

$timestamp = Get-Date -Format "yyyyMMdd_HHmm"
Start-Transcript -Path "$logDir\Inventory_Log_$timestamp.txt" -Append | Out-Null

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
$masterList | Sort-Object Category, Environment, 'Application Name' | Select-Object 'Category', 'Application Name', 'Version', 'Environment', 'Source', 'Restoration Command', @{Name='Keep (Y/N)';Expression={"FALSE"}}, @{Name='Backup Settings (Y/N)';Expression={"FALSE"}} | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8 -Force
Write-Host "Done." -ForegroundColor Green

if (Test-Path $wingetJsonPath) { Remove-Item $wingetJsonPath -Force -ErrorAction SilentlyContinue }
Stop-Transcript | Out-Null
Write-Host "`nSUCCESS! Inventory saved to: $csvPath" -ForegroundColor Green
