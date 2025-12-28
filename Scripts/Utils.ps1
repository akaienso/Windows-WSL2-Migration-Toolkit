# ==============================================================================
# SCRIPT: Utils.ps1
# Purpose: Shared utility functions for all toolkit scripts
# ==============================================================================

# ===== FUNCTION: Load Configuration =====
# Unified configuration loading with proper precedence
function Load-Config {
    param(
        [string]$RootDirectory = (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $MyInvocation.PSCommandPath)))
    )
    
    $settingsPath = Join-Path $RootDirectory "settings.json"
    $configPath = Join-Path $RootDirectory "config.json"
    
    # Try settings.json first (user-persisted settings)
    if (Test-Path $settingsPath) {
        try {
            return Get-Content $settingsPath -Raw | ConvertFrom-Json
        } catch {
            Write-Warning "Failed to parse settings.json: $_. Falling back to config.json"
        }
    }
    
    # Fall back to config.json
    if (Test-Path $configPath) {
        try {
            return Get-Content $configPath -Raw | ConvertFrom-Json
        } catch {
            Write-Error "Failed to parse config.json: $_"
            exit 1
        }
    }
    
    Write-Error "Configuration files not found. Expected: $settingsPath or $configPath"
    exit 1
}

# ===== FUNCTION: Convert Windows Path to WSL Mount Path =====
# Safely converts Windows paths like C:\path\to\dir to /mnt/c/path/to/dir
function ConvertTo-WslPath {
    param(
        [Parameter(Mandatory=$true)]
        [string]$WindowsPath
    )
    
    # Validate input
    if ([string]::IsNullOrWhiteSpace($WindowsPath)) {
        Write-Error "Path cannot be empty"
        return $null
    }
    
    # Resolve full path
    try {
        $resolvedPath = (Resolve-Path $WindowsPath -ErrorAction Stop).Path
    } catch {
        Write-Warning "Could not resolve path: $WindowsPath"
        $resolvedPath = $WindowsPath
    }
    
    # Extract drive letter and path
    if ($resolvedPath -match '^([a-zA-Z]):(.*)$') {
        $driveLetter = $matches[1].ToLower()
        $rest = $matches[2].Replace("\", "/").ToLower()
        return "/mnt/$driveLetter$rest"
    }
    
    Write-Error "Invalid Windows path format: $WindowsPath"
    return $null
}

# ===== FUNCTION: Execute WSL Command with Error Handling =====
# Safely executes commands in WSL with proper error checking
function Invoke-WslCommand {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Distro,
        
        [Parameter(Mandatory=$true)]
        [string]$Command,
        
        [switch]$Quiet = $false
    )
    
    # Validate distro exists
    $availableDistros = wsl --list --quiet 2>$null | ForEach-Object { $_.Trim() } | Where-Object { $_ }
    if ($availableDistros -notcontains $Distro) {
        Write-Error "WSL distro '$Distro' not found. Available: $($availableDistros -join ', ')"
        return $false
    }
    
    # Execute command
    if ($Quiet) {
        wsl -d $Distro -- bash -lc $Command 2>$null
    } else {
        wsl -d $Distro -- bash -lc $Command
    }
    
    if ($LASTEXITCODE -ne 0) {
        Write-Error "WSL command failed with exit code ${LASTEXITCODE}: $Command"
        return $false
    }
    
    return $true
}

# ===== FUNCTION: Find Latest Backup Directory =====
# Locates the most recent timestamped backup directory
function Find-LatestBackupDir {
    param(
        [Parameter(Mandatory=$true)]
        [string]$BackupBaseDir,
        
        [string]$BackupType = "Backup"
    )
    
    # Validate directory exists
    if (-not (Test-Path $BackupBaseDir)) {
        Write-Error "Backup directory not found: $BackupBaseDir"
        return $null
    }
    
    # Get directories sorted by modification time (newest first)
    $latestDir = Get-ChildItem -Path $BackupBaseDir -Directory -ErrorAction SilentlyContinue | 
                 Sort-Object LastWriteTime -Descending | 
                 Select-Object -First 1
    
    if (-not $latestDir) {
        Write-Error "No $BackupType directories found in: $BackupBaseDir"
        return $null
    }
    
    return $latestDir
}

# ===== FUNCTION: Ensure Directory Exists =====
# Safely creates directory with comprehensive error handling
function New-DirectoryIfNotExists {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Path
    )
    
    if (Test-Path $Path) {
        return $true
    }
    
    try {
        New-Item -ItemType Directory -Force -Path $Path -ErrorAction Stop | Out-Null
        return $true
    } catch {
        Write-Error "Failed to create directory '$Path': $_"
        return $false
    }
}

# ===== FUNCTION: Validate CSV File =====
# Checks CSV format and required columns
function Test-CsvFile {
    param(
        [Parameter(Mandatory=$true)]
        [string]$CsvPath,
        
        [string[]]$RequiredColumns = @()
    )
    
    if (-not (Test-Path $CsvPath)) {
        Write-Error "CSV file not found: $CsvPath"
        return $false
    }
    
    try {
        $csv = Import-Csv -Path $CsvPath -ErrorAction Stop
        
        if ($null -eq $csv) {
            Write-Error "CSV file is empty: $CsvPath"
            return $false
        }
        
        # Check for required columns
        if ($RequiredColumns.Count -gt 0) {
            $firstRow = $csv | Select-Object -First 1
            foreach ($col in $RequiredColumns) {
                if (-not $firstRow.PSObject.Properties[$col]) {
                    Write-Error "CSV missing required column: $col"
                    return $false
                }
            }
        }
        
        return $true
    } catch {
        Write-Error "Invalid CSV file: $_"
        return $false
    }
}

# ===== FUNCTION: Convert PSObject to Hashtable =====
# Safe conversion for JSON compatibility
function ConvertTo-Hashtable {
    param(
        [Parameter(ValueFromPipeline=$true)]
        $InputObject
    )
    
    if ($null -eq $InputObject) { return @{} }
    
    $hash = @{}
    $InputObject.PSObject.Properties | ForEach-Object {
        $hash[$_.Name] = $_.Value
    }
    return $hash
}

# ===== FUNCTION: Save JSON File =====
# Safely saves hashtable to JSON with error handling
function Save-JsonFile {
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$Data,
        
        [Parameter(Mandatory=$true)]
        [string]$FilePath
    )
    
    try {
        $parentDir = Split-Path -Parent $FilePath
        if (-not (New-DirectoryIfNotExists -Path $parentDir)) {
            return $false
        }
        
        $Data | ConvertTo-Json | Out-File -FilePath $FilePath -Encoding UTF8 -Force -ErrorAction Stop
        return $true
    } catch {
        Write-Error "Failed to save JSON file '$FilePath': $_"
        return $false
    }
}

# ===== FUNCTION: Load JSON File =====
# Safely loads JSON with error handling
function Load-JsonFile {
    param(
        [Parameter(Mandatory=$true)]
        [string]$FilePath
    )
    
    if (-not (Test-Path $FilePath)) {
        Write-Warning "JSON file not found: $FilePath"
        return @{}
    }
    
    try {
        $json = Get-Content $FilePath -Raw | ConvertFrom-Json
        return ConvertTo-Hashtable -InputObject $json
    } catch {
        Write-Warning "Failed to load JSON file '$FilePath': $_. Starting fresh."
        return @{}
    }
}

# ===== FUNCTION: Test WSL Distro Exists =====
# Validates a WSL distro is installed and running
function Test-WslDistro {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Distro
    )
    
    try {
        $availableDistros = wsl --list --quiet 2>$null | ForEach-Object { $_.Trim() } | Where-Object { $_ }
        return $availableDistros -contains $Distro
    } catch {
        Write-Error "Failed to list WSL distros: $_"
        return $false
    }
}

# ===== FUNCTION: Get Safe Filename =====
# Removes invalid filename characters
function Get-SafeFilename {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Filename
    )
    
    return $Filename -replace '[\\/:*?"<>|]', '_'
}

# ===== FUNCTION: Format Byte Size to Human Readable =====
# Converts bytes to MB/GB format
function Format-ByteSize {
    param(
        [Parameter(Mandatory=$true)]
        [long]$Bytes
    )
    
    $units = @('B', 'KB', 'MB', 'GB', 'TB')
    $size = [double]$Bytes
    $unitIndex = 0
    
    while ($size -ge 1024 -and $unitIndex -lt $units.Length - 1) {
        $size /= 1024
        $unitIndex++
    }
    
    return "{0:N2} {1}" -f $size, $units[$unitIndex]
}

# ===== FUNCTION: Start Logging =====
# Unified logging setup
function Start-ScriptLogging {
    param(
        [Parameter(Mandatory=$true)]
        [string]$LogDirectory,
        
        [Parameter(Mandatory=$true)]
        [string]$ScriptName
    )
    
    if (-not (New-DirectoryIfNotExists -Path $LogDirectory)) {
        Write-Warning "Failed to create log directory, continuing without logging"
        return $null
    }
    
    $timestamp = Get-Date -Format "yyyyMMdd_HHmm"
    $logFile = Join-Path $LogDirectory "${ScriptName}_Log_$timestamp.txt"
    
    try {
        Start-Transcript -Path $logFile -Append | Out-Null
        return $logFile
    } catch {
        Write-Warning "Failed to start transcript logging: $_"
        return $null
    }
}

# ===== FUNCTION: Stop Logging =====
# Unified logging cleanup
function Stop-ScriptLogging {
    try {
        Stop-Transcript | Out-Null
    } catch {
        # Silently continue if not actively transcribing
    }
}

# ===== FUNCTION: Get Configuration Root =====
# Helper to find toolkit root directory
function Get-ToolkitRoot {
    param(
        [string]$FromPath = $PSScriptRoot
    )
    
    # Walk up directory tree to find Start.ps1
    $current = $FromPath
    $maxDepth = 5
    $depth = 0
    
    while ($depth -lt $maxDepth) {
        if (Test-Path (Join-Path $current "Start.ps1")) {
            return $current
        }
        $parent = Split-Path -Parent $current
        if ($parent -eq $current) { break }
        $current = $parent
        $depth++
    }
    
    Write-Error "Could not locate toolkit root directory"
    return $null
}

# Export all functions (make them available to calling scripts)
# Note: In a .ps1 script, these are automatically available after dot-sourcing
