# ==============================================================================
# SCRIPT: Get-Inventory.ps1
# AUTHOR: Rob Moore <io@rmoore.dev>
# LOCATION: /Scripts/
# ==============================================================================

# --- LOAD CONFIGURATION (From Parent Root) ---
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$RootDir = Split-Path -Parent $ScriptDir # Go up one level
$configPath = "$RootDir\config.json"

if (Test-Path $configPath) {
    $config = Get-Content $configPath -Raw | ConvertFrom-Json
} else {
    Write-Error "Config file missing in root. Run Start.ps1 first."
    exit
}

# --- RESOLVE PATHS ---
$invDir = "$RootDir\$($config.InventoryDirectory)"
$logDir = "$RootDir\$($config.LogDirectory)"
$csvPath = "$invDir\$($config.InventoryOutputCSV)"
$wingetJsonPath = "$invDir\winget-apps.json"

# --- INIT ---
if (-not (Test-Path $invDir)) { New-Item -ItemType Directory -Force -Path $invDir | Out-Null }
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Force -Path $logDir | Out-Null }

# --- LOGGING ---
$timestamp = Get-Date -Format "yyyyMMdd_HHmm"
$logPath = "$logDir\Inventory_Log_$timestamp.txt"
Start-Transcript -Path $logPath -Append | Out-Null
$errorCount = 0

Write-Host "`n========================================================" -ForegroundColor Cyan
Write-Host " STARTING INVENTORY SCAN..." -ForegroundColor Cyan
Write-Host " OUTPUT: $csvPath" -ForegroundColor Cyan
Write-Host "========================================================" -ForegroundColor Cyan

# --- FILTER KEYWORDS ---
$winSystemKeywords = @(
    "Redistributable", "C\+\+", "\.NET", "Framework", "Runtime", "SDK", 
    "Driver", "Intel", "NVIDIA", "AMD", "Realtek", "Qualcomm", "Ethernet", "Wireless",
    "Update for", "KB[0-9]", "Service", "BIOS", "Firmware", "Chipset",
    "Experience", "Control Panel", "Support Assistant", "Helper", "Client", "DirectX"
)
$linuxSystemKeywords = @(
    "^lib", "^linux-", "^ubuntu-", "^python3-", "-minimal$", "-core$",
    "systemd", "udev", "init", "sudo", "bash", "zsh", "dash", 
    "coreutils", "grep", "sed", "tar", "gzip", "openssl", 
    "netplan", "wsl", "snapd", "adduser", "apt", "dpkg", 
    "mount", "lsb-release", "passwd", "tzdata"
)

function Get-AppCategory ($name, $env) {
    if ($env -eq "Windows") {
        foreach ($key in $winSystemKeywords) { if ($name -match $key) { return "System/Driver (Auto-Detected)" } }
    }
    if ($env -match "WSL") {
        foreach ($key in $linuxSystemKeywords) { if ($name -match $key) { return "System/Base (Linux)" } }
    }
    return "User-Installed Application"
}

$masterList = @()
$knownApps = @{} 

# --- STEP 1: WINGET ---
Write-Host "1. Exporting Winget... " -NoNewline -ForegroundColor Yellow
$stepCount = 0
try {
    winget export -o $wingetJsonPath --include-versions | Out-Null
    if (Test-Path $wingetJsonPath) {
        $json = Get-Content $wingetJsonPath -Raw | ConvertFrom-Json
        foreach ($source in $json.Sources) {
            foreach ($pkg in $source.Packages) {
                $cat = Get-AppCategory -name $pkg.PackageIdentifier -env "Windows"
                $masterList += [PSCustomObject]@{
                    'Category' = $cat; 'Application Name' = $pkg.PackageIdentifier; 'Version' = $pkg.Version;
                    'Environment' = "Windows"; 'Source' = "Winget"; 
                    'Restoration Command' = "winget install --id $($pkg.PackageIdentifier) -e"
                }
                $knownApps[$pkg.PackageIdentifier] = $true
                $stepCount++
            }
        }
    }
    Write-Host "$stepCount applications found" -ForegroundColor Green
} catch {
    $errorCount++
    Write-Host "FAILED" -ForegroundColor Red
    Write-Error "Winget failed: $_"
}

# --- STEP 2: STORE ---
Write-Host "2. Scanning Store... " -NoNewline -ForegroundColor Yellow
$stepCount = 0
try {
    $storeApps = Get-AppxPackage -ErrorAction Stop | Where-Object { $_.NonRemovable -eq $false -and $_.IsFramework -eq $false -and $_.SignatureKind -eq "Store" }
    foreach ($app in $storeApps) {
        $isDuplicate = $false
        foreach ($key in $knownApps.Keys) { if ($app.Name -like "*$key*") { $isDuplicate = $true; break } }
        if (-not $isDuplicate) {
            $cat = Get-AppCategory -name $app.Name -env "Windows"
            $masterList += [PSCustomObject]@{
                'Category' = $cat; 'Application Name' = $app.Name; 'Version' = $app.Version;
                'Environment' = "Windows"; 'Source' = "Microsoft Store"; 
                'Restoration Command' = "winget install --id $($app.Name) --source msstore"
            }
            $knownApps[$app.Name] = $true
            $stepCount++
        }
    }
    Write-Host "$stepCount applications found" -ForegroundColor Green
} catch {
    $errorCount++
    Write-Host "FAILED" -ForegroundColor Red; Write-Warning $_
}

# --- STEP 3: REGISTRY ---
Write-Host "3. Scanning Registry... " -NoNewline -ForegroundColor Yellow
$stepCount = 0
$registryLocations = @("HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*", "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*", "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*")
foreach ($loc in $registryLocations) {
    try {
        $entries = Get-ItemProperty $loc -ErrorAction Stop
        foreach ($app in $entries) {
            if (-not [string]::IsNullOrWhiteSpace($app.DisplayName)) {
                $isDuplicate = $false
                foreach ($key in $knownApps.Keys) { if ($app.DisplayName -like "*$key*") { $isDuplicate = $true; break } }
                if (-not $isDuplicate) {
                    $cat = Get-AppCategory -name $app.DisplayName -env "Windows"
                    $masterList += [PSCustomObject]@{
                        'Category' = $cat; 'Application Name' = $app.DisplayName; 'Version' = $app.DisplayVersion;
                        'Environment' = "Windows"; 'Source' = "Registry (Manual)"; 
                        'Restoration Command' = "winget search `"$($app.DisplayName)`""
                    }
                    $stepCount++
                }
            }
        }
    } catch {}
}
Write-Host "$stepCount applications found" -ForegroundColor Green

# --- STEP 4: WSL2 ---
Write-Host "4. Connecting to WSL2... " -NoNewline -ForegroundColor Yellow
$stepCount = 0
try {
    $wslOutput = wsl --exec apt-mark showmanual 2>&1
    if ($LASTEXITCODE -ne 0) { throw "WSL Error" }
    if ($null -ne $wslOutput) {
        foreach ($line in $wslOutput) {
            if (-not [string]::IsNullOrWhiteSpace($line) -and $line -notmatch "command not found") {
                $cat = Get-AppCategory -name $line -env "WSL"
                $masterList += [PSCustomObject]@{
                    'Category' = $cat; 'Application Name' = $line; 'Version' = "Latest";
                    'Environment' = "WSL2 (Ubuntu)"; 'Source' = "Apt (Linux)"; 
                    'Restoration Command' = "sudo apt install $line -y"
                }
                $stepCount++
            }
        }
    }
    Write-Host "$stepCount applications found" -ForegroundColor Green
} catch {
    $errorCount++
    Write-Host "FAILED" -ForegroundColor Red; Write-Error $_
}

# --- EXPORT ---
Write-Host "5. Exporting $($masterList.Count) applications to CSV..." -ForegroundColor Yellow
try {
    $masterList | 
        Sort-Object Category, Environment, 'Application Name' | 
        Select-Object 'Category', 'Application Name', 'Version', 'Environment', 'Source', 'Restoration Command', @{Name='Keep (Y/N)';Expression={"FALSE"}} | 
        Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8 -Force
} catch {
    $errorCount++
    Write-Error "Save failed: $_"
}

# --- CLEANUP (Delete Temp Files) ---
if (Test-Path $wingetJsonPath) {
    Remove-Item $wingetJsonPath -Force -ErrorAction SilentlyContinue
}

# --- SUMMARY ---
$stats = $masterList | Group-Object Category
function Print-Stat($catName) { $c = ($stats | Where-Object Name -eq $catName).Count; if ($null -eq $c) {0} else {$c} }

Write-Host "`nFound:" -ForegroundColor Cyan
Write-Host "1. $(Print-Stat 'System/Driver (Auto-Detected)') Windows System/Driver Applications" -ForegroundColor White
Write-Host "2. $(Print-Stat 'System/Base (Linux)') Linux System/Base Applications" -ForegroundColor White
Write-Host "3. $(Print-Stat 'User-Installed Application') User-Installed Applications" -ForegroundColor White

Write-Host "`n------------------------------------------------" -ForegroundColor Green
Write-Host " SUCCESS! Inventory saved to:" -ForegroundColor Green
Write-Host " $csvPath" -ForegroundColor Green
Write-Host "------------------------------------------------" -ForegroundColor Green

if ($errorCount -gt 0) { Write-Host "`n! $errorCount errors detected. See log: $logPath" -ForegroundColor Red }
Stop-Transcript | Out-Null