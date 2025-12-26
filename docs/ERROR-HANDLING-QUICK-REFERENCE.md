# Quick Reference: Error Handling in Windows-WSL2-Migration-Toolkit

## What's Protected

### Configuration Layer
✅ All config fields validated before use
✅ Missing config files caught immediately with helpful messages
✅ Settings persisted to toolkit root (not in backups)

### Backup Operations
✅ WSL distro existence verified
✅ Export file creation verified
✅ Archive extraction validated
✅ File sync delays handled (30-second wait)

### Restore Operations
✅ Backup files checked for existence
✅ CSV data validated before parsing
✅ Archive integrity verified
✅ Permission errors reported clearly

### Bash Script Layer
✅ All directory operations error-checked
✅ Archive operations validated
✅ Exit codes propagated properly
✅ Non-fatal warnings don't stop execution

---

## Common Error Scenarios & Fixes

### "BackupRootDirectory not configured"
**Cause:** First run, no settings.json  
**Fix:** Run `Start.ps1`, select option to configure backup path

### "WSL Distro 'Ubuntu' not found"
**Cause:** WSL distro not installed or name mismatch  
**Fix:** Run `wsl --list --verbose` to see installed distros, update Start.ps1

### "Backup directory does not exist"
**Cause:** Path doesn't exist or WSL mount path issues  
**Fix:** Check path in settings.json, ensure backup drive is connected

### "No dotfile backup created"
**Cause:** Timeout waiting for WSL filesystem sync  
**Fix:** Check `~/.wsl-dotfile-backups/` inside WSL distro manually

### "Failed to extract archive"
**Cause:** Corrupted zip file or insufficient permissions  
**Fix:** Check file integrity, verify AppData folder access permissions

### "Backup directory not found"
**Cause:** Running Restore before Backup  
**Fix:** Run Backup-WSL.ps1 or Backup-AppData.ps1 first

---

## Testing Error Handling

### Test 1: Missing WSL Distro
```powershell
# Edit config.json: set WslDistroName = "NonExistent"
. .\Scripts\WSL\Backup-WSL.ps1
# Expected: "WSL Distro 'NonExistent' not found" + available distros listed
```

### Test 2: Corrupted CSV
```powershell
# Edit SOFTWARE-INSTALLATION-INVENTORY.csv - add invalid characters
. .\Scripts\ApplicationInventory\Generate-Restore-Scripts.ps1
# Expected: "Failed to parse CSV file" + error details
```

### Test 3: Missing Archive
```powershell
# Delete or move backup.tar before running restore
. .\Scripts\WSL\Restore-WSL.ps1
# Expected: "No Backup Tar found in {path}"
```

### Test 4: Permission Denied
```powershell
# Make backup directory read-only
# Run backup operation
# Expected: Directory creation error with specific path
```

---

## Log Files

All operations log to timestamped files:

### Backup Logs
- `$BackupRootDirectory/AppData/yyyy-MM-dd_HH-mm-ss/Logs/AppData_Backup_*.txt`
- `$BackupRootDirectory/WSL/yyyy-MM-dd_HH-mm-ss/HashReport_*.txt`

### Inventory Logs
- `$BackupRootDirectory/AppData/yyyy-MM-dd_HH-mm-ss/Logs/Inventory_Log_*.txt`

### Restore Logs
- `$BackupRootDirectory/AppData/yyyy-MM-dd_HH-mm-ss/Logs/AppData_Restore_*.txt`

**Location:** Check the timestamp directory created during operation

---

## Before Reporting an Issue

1. **Check the error message** - Most issues have clear actionable guidance
2. **Review relevant log file** - Full details of what failed
3. **Verify prerequisites**:
   - WSL2 installed and distro exists: `wsl --list --verbose`
   - Backup directory exists and accessible
   - config.json or settings.json properly configured
   - Required PowerShell version (5.1+)
4. **Try the suggested fix** in the error message

---

## Design Philosophy

The toolkit follows these error handling principles:

1. **Fail Fast** - Validate all prerequisites before long-running operations
2. **Fail Clearly** - Provide actionable error messages, not stack traces
3. **Fail Safely** - Clean up temporary files on error, never corrupt existing data
4. **Fail Gracefully** - Non-critical operations warn but continue (apt install, chmod)

---

## Exit Codes

- **0** = Success
- **1** = Fatal error (validation failed, operation failed)
- External tools (wsl, winget, tar) return their own codes (checked by toolkit)

---

## For Developers

### Adding New Validation
```powershell
# Pattern: Check → Error → Exit
if (-not (Validate-Something)) {
    Write-Error "Clear message: what was wrong, what to do next"
    exit 1
}
```

### Adding New File Operations
```powershell
# Pattern: Try-Catch → Log → Continue or Exit
try {
    Copy-Item -Path $source -Destination $dest -ErrorAction Stop
} catch {
    Write-Error "Failed to copy file: $_"
    # Exit if critical, continue if optional
    exit 1
}
```

### Adding New External Commands
```powershell
# Pattern: Run → Check Exit Code → Error or Continue
wsl --shutdown
if ($LASTEXITCODE -ne 0) {
    Write-Error "WSL shutdown failed"
    exit 1
}
```

---

**Last Updated:** December 21, 2025  
**Audit Status:** ✅ Complete and verified
