# Upgrade Guide: v2025.12

This guide walks through upgrading to Windows-WSL2-Migration-Toolkit v2025.12.

**Good news:** Upgrading is simple and completely safe. All improvements are transparent and fully backward compatible.

---

## Quick Start

### For Users
```powershell
cd D:\Windows-WSL2-Migration-Toolkit
git pull origin main
```

Done! No configuration changes or other steps needed.

### For Developers
1. Pull latest code: `git pull origin main`
2. Review `RELEASE-NOTES-v2025.12.md` for what changed
3. See `docs/DEVELOPER-GUIDE.md` for new Utils.ps1 patterns
4. Use `Load-Config` and other Utils functions in new code

---

## What Gets Updated?

### Scripts (7 PowerShell + 3 Bash)
- All scripts improved with better error handling
- New `Scripts/Utils.ps1` module added
- All scripts now import Utils.ps1 for centralized utilities

### Documentation (5 files)
- `.github/copilot-instructions.md` - Updated with Utils.ps1 details
- `docs/DEVELOPER-GUIDE.md` - New Utils.ps1 section
- `docs/USER-GUIDE.md` - Added improvements section
- `docs/INDEX.md` - Added what's new highlights
- `RELEASE-NOTES-v2025.12.md` - Comprehensive change documentation

### New Files
- `RELEASE-NOTES-v2025.12.md` - Detailed release notes
- `UPGRADE-GUIDE.md` - This file

---

## What Doesn't Change?

✅ **Your backups are completely safe:**
- Backup file formats unchanged
- CSV schema unchanged
- Configuration format unchanged
- All existing backups remain fully functional

✅ **Your workflows:**
- All command syntax unchanged
- Menu options unchanged
- User experience unchanged
- All documented procedures work as before

---

## Backward Compatibility

**100% Backward Compatible** - No breaking changes whatsoever.

### Existing Backups
- All existing backups work with v2025.12 scripts
- Restore operations work on any backup (old or new)
- No migration needed

### Configuration
- `config.json` format unchanged
- `settings.json` format unchanged
- Existing configurations work as-is

### Scripts
- All public script behaviors unchanged
- All command outputs compatible
- All file paths and locations unchanged

---

## What If I'm Running an Older Version?

Don't worry! You can safely upgrade:

1. **Your backups won't be affected** - Scripts read existing backups without modification
2. **Settings are compatible** - Your current config.json and settings.json work as-is
3. **Zero data loss risk** - This is a code-only update

### Steps:
```powershell
# Backup current settings (optional but safe)
Copy-Item settings.json settings.json.backup

# Pull latest code
git pull origin main

# Continue using normally
. .\Start.ps1
```

---

## New Features (Transparent to Users)

### For Everyone
- Better error messages if something goes wrong
- More detailed logging for troubleshooting
- More robust handling of edge cases
- All improvements are automatic

### For Developers
- New `Scripts/Utils.ps1` module with 15 functions
- Centralized patterns for all new code
- Easier to extend and maintain
- See `docs/DEVELOPER-GUIDE.md` for details

---

## Important: Review These

### New Users
- See `docs/USER-GUIDE.md` for getting started
- See `RELEASE-NOTES-v2025.12.md` for what's new
- See `docs/ERROR-HANDLING-QUICK-REFERENCE.md` for troubleshooting

### Developers
- See `docs/DEVELOPER-GUIDE.md` for architecture overview
- New section: "Utils.ps1 - Shared Utilities Module"
- New section: "Recent Improvements & Changes (v2025.12)"
- See `.github/copilot-instructions.md` for updated patterns

---

## Testing After Upgrade

### Quick Verification
```powershell
# Verify all scripts load correctly
cd D:\Windows-WSL2-Migration-Toolkit

# Test Utils.ps1 module
. .\Scripts\Utils.ps1
$config = Load-Config
Write-Host "Config loaded: $($config.WslDistroName)"

# Verify scripts can load (don't run them yet)
. .\Scripts\ApplicationInventory\Get-Inventory.ps1 -Verbose:$false
Write-Host "Get-Inventory.ps1 loaded successfully"
```

### Test Existing Backup Restore
If you have an existing backup:
```powershell
# Try to list backups (non-destructive test)
. .\Start.ps1
# Choose option 4 (Restore WSL) or 6 (Restore AppData)
# Just browse available backups, don't execute restore
```

---

## Troubleshooting After Upgrade

### Issue: "Scripts\Utils.ps1 not found"
**Cause:** Git pull incomplete or network issue  
**Solution:** 
```powershell
git pull origin main --force
git status  # Should show all files up to date
```

### Issue: Script shows old behavior
**Cause:** PowerShell session cached old version  
**Solution:**
```powershell
# Close current PowerShell window
# Open new PowerShell window
# Try again
```

### Issue: Path issues or "command not found"
**Cause:** Distro or path issue  
**Solution:** See `docs/ERROR-HANDLING-QUICK-REFERENCE.md`

### Issue: Confused about new Utils module
**Cause:** Natural - it's new!  
**Solution:** See `docs/DEVELOPER-GUIDE.md` for detailed explanation

---

## Rollback Instructions (If Needed)

If for any reason you need to rollback:

```powershell
cd D:\Windows-WSL2-Migration-Toolkit

# Go back to previous version
git checkout HEAD~1

# Or go back to a specific commit
git log --oneline | head -20  # Find commit hash
git checkout <commit-hash>
```

**But remember:** All changes are improvements with no breaking changes. Rollback is unlikely to be necessary.

---

## What's Different?

### Code Quality
- 4 critical bugs fixed
- 5 high-priority improvements
- 6 medium-level enhancements
- Better error handling throughout
- Robust path conversion for all drives A-Z

### User Experience
- Clearer error messages
- Better logging for troubleshooting
- Consistent behavior across scripts
- More reliable backup/restore operations

### Developer Experience
- Centralized `Scripts/Utils.ps1` module
- No more code duplication
- Easier to add new features
- Better tested, proven patterns

---

## Need Help?

### Before Upgrading
- Read `RELEASE-NOTES-v2025.12.md` for what changes
- See `.github/copilot-instructions.md` for architecture overview

### After Upgrading
- See `docs/USER-GUIDE.md` for usage
- See `docs/ERROR-HANDLING-QUICK-REFERENCE.md` if issues
- Check GitHub Issues for known problems
- See `docs/DEVELOPER-GUIDE.md` if you want to contribute

---

## Summary

✅ **Upgrade is safe:** Zero breaking changes  
✅ **Upgrade is automatic:** Just `git pull`  
✅ **Your backups are safe:** Fully compatible  
✅ **New features are transparent:** Automatic improvements  
✅ **Rollback is easy:** Just `git checkout` if needed  

**You're all set!** Enjoy the improved reliability and robustness of v2025.12.

---

**Questions?** See the main [README.md](README.md) or documentation in `docs/` folder.

