# ==============================================================================
# SCRIPT: Select-Apps-Interactive.ps1
# Purpose: Interactive app selection replacing CSV workflow
#          Reads from AppSelectionProfile.json, retains previous selections,
#          uses quick [Y/N] prompts to build selections
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
@('BackupRootDirectory') | ForEach-Object {
    if ([string]::IsNullOrWhiteSpace($config.$_)) {
        Write-Error "Config missing required field: $_"
        exit 1
    }
}

# Find the most recent timestamped Inventory directory
$invBaseDir = Join-Path $config.BackupRootDirectory "Inventory"
$latestInvDir = Find-LatestBackupDir -BackupBaseDir $invBaseDir -BackupType "Inventory"
if (-not $latestInvDir) {
    Write-Error "No inventory found. Run Option 1 (Get-Inventory) first."
    exit 1
}

$invTimestamp = $latestInvDir.Name
$invDir = Join-Path $latestInvDir.FullName "Inventories"
$csvPath = Join-Path $invDir $config.InventoryOutputCSV

# Validate CSV exists
if (-not (Test-Path $csvPath)) {
    Write-Error "Inventory CSV not found: $csvPath"
    Write-Host "Run Option 1 (Get-Inventory) to generate the inventory." -ForegroundColor Yellow
    exit 1
}

Write-Host "`n=== INTERACTIVE APP SELECTION ===" -ForegroundColor Cyan
Write-Host "Loading discovered applications from inventory..." -ForegroundColor Yellow

# Load inventory CSV
try {
    $inventory = Import-Csv -Path $csvPath -ErrorAction Stop
} catch {
    Write-Error "Failed to parse inventory CSV: $_"
    exit 1
}

if ($null -eq $inventory -or $inventory.Count -eq 0) {
    Write-Error "No applications found in inventory CSV"
    exit 1
}

# Separate Windows and WSL apps
$windowsApps = @($inventory | Where-Object { $_.Environment -eq "Windows" })
$wslApps = @($inventory | Where-Object { $_.Environment -match "WSL|Linux" })

Write-Host "`n📊 Inventory Summary:" -ForegroundColor Cyan
Write-Host "   Windows apps found: $($windowsApps.Count)" -ForegroundColor White
Write-Host "   WSL/Linux apps found: $($wslApps.Count)" -ForegroundColor White

# Check for existing selections in CSV (backward compatibility)
$previousWindowsSelections = @()
$previousWslSelections = @()

foreach ($row in $inventory) {
    if ($row.PSObject.Properties['Keep (Y/N)'] -and $row.'Keep (Y/N)' -match "TRUE|Yes|Y|1") {
        if ($row.Environment -eq "Windows") {
            $previousWindowsSelections += $row.'Application Name'
        } else {
            $previousWslSelections += $row.'Application Name'
        }
    }
}

# Prompt to restore previous selections or start fresh
if ($previousWindowsSelections.Count -gt 0 -or $previousWslSelections.Count -gt 0) {
    Write-Host "`n✓ Found $($previousWindowsSelections.Count + $previousWslSelections.Count) previously selected apps." -ForegroundColor Green
    Write-Host "Restore previous selections? (Y/N): " -ForegroundColor Cyan -NoNewline
    $restore = Read-Host
    
    if ($restore -match "^(Y|Yes)$") {
        Write-Host "Restoring previous selections..." -ForegroundColor Green
    } else {
        $previousWindowsSelections = @()
        $previousWslSelections = @()
        Write-Host "Starting fresh selection..." -ForegroundColor Yellow
    }
}

# ===== HELPER FUNCTION: Categorize apps =====
function Get-AppsByCategory {
    param([array]$Apps)
    
    $categories = @{}
    foreach ($app in $Apps) {
        $cat = $app.Category
        if (-not $categories.ContainsKey($cat)) {
            $categories[$cat] = @()
        }
        $categories[$cat] += $app
    }
    return $categories
}

# ===== INTERACTIVE SELECTION FUNCTION =====
function Select-AppsInteractive {
    param(
        [array]$Apps,
        [string]$Environment,
        [array]$PreviousSelections
    )
    
    if ($Apps.Count -eq 0) {
        Write-Host "No $Environment applications to select." -ForegroundColor Yellow
        return @()
    }
    
    Write-Host "`n════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host "SELECT $Environment APPLICATIONS" -ForegroundColor Cyan
    Write-Host "════════════════════════════════════════" -ForegroundColor Cyan
    
    $categories = Get-AppsByCategory -Apps $Apps
    $selectedApps = @()
    
    foreach ($category in $categories.Keys | Sort-Object) {
        $appsInCat = $categories[$category]
        $categorySelected = @()
        
        Write-Host "`n[$category] - $($appsInCat.Count) apps" -ForegroundColor Yellow
        
        foreach ($app in $appsInCat | Sort-Object -Property 'Application Name') {
            $appName = $app.'Application Name'
            $version = $app.Version
            $source = $app.Source
            
            # Check if previously selected
            $wasSelected = $appName -in $PreviousSelections
            $defaultResponse = if ($wasSelected) { "Y" } else { "N" }
            
            Write-Host "  • $appName [$version] (from: $source)" -ForegroundColor White
            Write-Host "    Keep this app? [Y/N] (default: $defaultResponse): " -ForegroundColor Cyan -NoNewline
            
            $response = Read-Host
            if ([string]::IsNullOrWhiteSpace($response)) {
                $response = $defaultResponse
            }
            
            if ($response -match "^(Y|Yes|1)$") {
                $selectedApps += $appName
                $categorySelected += $appName
                Write-Host "    ✓ Selected" -ForegroundColor Green
            } else {
                Write-Host "    ⊘ Skipped" -ForegroundColor DarkGray
            }
        }
        
        Write-Host "   [$($categorySelected.Count)/$($appsInCat.Count) selected in this category]" -ForegroundColor Cyan
    }
    
    return $selectedApps
}

# ===== RUN INTERACTIVE SELECTION =====
$selectedWindows = Select-AppsInteractive -Apps $windowsApps -Environment "WINDOWS" -PreviousSelections $previousWindowsSelections
$selectedWSL = Select-AppsInteractive -Apps $wslApps -Environment "WSL" -PreviousSelections $previousWslSelections

# ===== SAVE PROFILE TO CONFIG =====
Write-Host "`n=== SAVING PROFILE ===" -ForegroundColor Cyan

# Load current config and update profile
$settings = Load-JsonFile -FilePath (Join-Path $RootDir "settings.json")
if ($null -eq $settings) {
    $settings = @{}
}

# Initialize AppSelectionProfile if not exists
if (-not $settings.ContainsKey("AppSelectionProfile")) {
    $settings["AppSelectionProfile"] = @{}
}

$settings["AppSelectionProfile"]["Name"] = "Default"
$settings["AppSelectionProfile"]["LastUpdated"] = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ")
$settings["AppSelectionProfile"]["SelectedApps"] = @{
    "Windows" = $selectedWindows
    "WSL" = $selectedWSL
}

# Save updated settings
if (Save-JsonFile -Data $settings -FilePath (Join-Path $RootDir "settings.json")) {
    Write-Host "✓ Profile saved to settings.json" -ForegroundColor Green
} else {
    Write-Error "Failed to save profile"
    exit 1
}

# ===== SUMMARY =====
Write-Host "`n════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "SELECTION SUMMARY" -ForegroundColor Cyan
Write-Host "════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "Windows apps selected: $($selectedWindows.Count)" -ForegroundColor Green
foreach ($app in $selectedWindows | Sort-Object) {
    Write-Host "  ✓ $app" -ForegroundColor DarkGray
}

Write-Host "`nWSL apps selected: $($selectedWSL.Count)" -ForegroundColor Green
foreach ($app in $selectedWSL | Sort-Object) {
    Write-Host "  ✓ $app" -ForegroundColor DarkGray
}

Write-Host "`n✓ Selection saved! Run Option 3 (Generate Restore Scripts) to create installation scripts." -ForegroundColor Green

exit 0
