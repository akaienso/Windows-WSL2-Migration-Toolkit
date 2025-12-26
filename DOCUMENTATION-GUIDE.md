# v2025.12 Documentation Guide

**Quick reference for navigating the updated documentation.**

---

## 🎯 Where to Find What You Need

### For Users (Getting Started)
1. **[README.md](README.md)** - Start here for quick setup
2. **[docs/USER-GUIDE.md](docs/USER-GUIDE.md)** - Complete user manual
3. **[UPGRADE-GUIDE.md](UPGRADE-GUIDE.md)** - Upgrade from older version
4. **[docs/ERROR-HANDLING-QUICK-REFERENCE.md](docs/ERROR-HANDLING-QUICK-REFERENCE.md)** - Troubleshooting

### For Developers (Code & Architecture)
1. **[.github/copilot-instructions.md](.github/copilot-instructions.md)** - AI agent instructions
2. **[docs/DEVELOPER-GUIDE.md](docs/DEVELOPER-GUIDE.md)** - Architecture & patterns
3. **[docs/INDEX.md](docs/INDEX.md)** - Documentation index
4. **[Scripts/Utils.ps1](Scripts/Utils.ps1)** - Shared utilities module (400+ lines)

### For Release Information
1. **[RELEASE-NOTES-v2025.12.md](RELEASE-NOTES-v2025.12.md)** - Complete v2025.12 changes
2. **[DOCUMENTATION-UPDATE-SUMMARY.md](DOCUMENTATION-UPDATE-SUMMARY.md)** - What was updated

---

## 📚 Documentation Structure

```
Windows-WSL2-Migration-Toolkit/
│
├── README.md (Quick start)
│
├── .github/
│   └── copilot-instructions.md ⭐ AI agent guide
│
├── Scripts/
│   ├── Utils.ps1 ⭐ (400+ lines, 15 functions)
│   ├── ApplicationInventory/
│   ├── AppData/
│   └── WSL/
│
├── docs/
│   ├── INDEX.md ⭐ (Entry point)
│   ├── USER-GUIDE.md (Users)
│   ├── DEVELOPER-GUIDE.md ⭐ (Developers)
│   ├── ERROR-HANDLING-QUICK-REFERENCE.md (Troubleshooting)
│   ├── ERROR-HANDLING-AUDIT.md (Detailed)
│   └── [other docs]
│
├── RELEASE-NOTES-v2025.12.md ⭐ (What changed)
├── UPGRADE-GUIDE.md ⭐ (How to upgrade)
└── DOCUMENTATION-UPDATE-SUMMARY.md ⭐ (This update)
```

⭐ = Key files for v2025.12

---

## 🔍 Finding Specific Information

### Utils.ps1 Module Functions
**Location:** [docs/DEVELOPER-GUIDE.md](docs/DEVELOPER-GUIDE.md#utilsps1---shared-utilities-module-new)

Functions documented:
- `Load-Config` - Configuration management
- `ConvertTo-WslPath` - Path conversion
- `Invoke-WslCommand` - WSL execution
- `Find-LatestBackupDir` - Backup discovery
- `New-DirectoryIfNotExists` - Directory creation
- `Test-CsvFile` - CSV validation
- `Test-WslDistro` - Distro validation
- `Save-JsonFile` / `Load-JsonFile` - JSON operations
- `Format-ByteSize` - Byte formatting
- `Start-ScriptLogging` / `Stop-ScriptLogging` - Logging
- `Get-ToolkitRoot` - Root discovery
- `Get-SafeFilename` - Filename sanitization
- And more...

### Critical Bug Fixes
**Location:** [RELEASE-NOTES-v2025.12.md](RELEASE-NOTES-v2025.12.md#critical-bugs-fixed)

Fixes documented:
1. Timestamp variable shadowing (Get-Inventory)
2. Config reference bug (Generate-Restore-Scripts)
3. Function definition order (Restore-AppData)
4. Unsafe dot-sourcing (Restore-WSL)

### High-Priority Improvements
**Location:** [RELEASE-NOTES-v2025.12.md](RELEASE-NOTES-v2025.12.md#high-priority-improvements)

Improvements:
1. Enhanced registry filtering
2. CSV validation
3. Robust path conversion
4. Safe WSL execution
5. Unified logging

### Backward Compatibility Info
**Location:** [RELEASE-NOTES-v2025.12.md](RELEASE-NOTES-v2025.12.md#backward-compatibility)

- All existing backups work as-is
- No configuration changes needed
- 100% compatible with older versions

---

## 🚀 Quick Links

### Get Started Immediately
```
→ [README.md](README.md)
→ [docs/USER-GUIDE.md](docs/USER-GUIDE.md)
→ [UPGRADE-GUIDE.md](UPGRADE-GUIDE.md)
```

### Learn About Improvements
```
→ [RELEASE-NOTES-v2025.12.md](RELEASE-NOTES-v2025.12.md)
→ [docs/INDEX.md](docs/INDEX.md#-whats-new-v202512)
```

### Understand Architecture
```
→ [docs/DEVELOPER-GUIDE.md](docs/DEVELOPER-GUIDE.md)
→ [.github/copilot-instructions.md](.github/copilot-instructions.md)
```

### Fix Problems
```
→ [docs/ERROR-HANDLING-QUICK-REFERENCE.md](docs/ERROR-HANDLING-QUICK-REFERENCE.md)
→ [docs/ERROR-HANDLING-AUDIT.md](docs/ERROR-HANDLING-AUDIT.md)
```

---

## 📋 Content Summary

| Document | Audience | Purpose | Length |
|----------|----------|---------|--------|
| README.md | Everyone | Quick start | ~50 lines |
| RELEASE-NOTES-v2025.12.md | Users/Devs | What changed | 367 lines |
| UPGRADE-GUIDE.md | Users | How to upgrade | 263 lines |
| copilot-instructions.md | AI agents | Coding patterns | 400+ lines |
| DEVELOPER-GUIDE.md | Developers | Architecture | 900+ lines |
| USER-GUIDE.md | Users | How to use | 500+ lines |
| ERROR-HANDLING-QUICK-REFERENCE.md | Everyone | Troubleshooting | 200+ lines |
| DOCUMENTATION-UPDATE-SUMMARY.md | Auditors | What was updated | 336 lines |

---

## ✅ What You Should Know

### If You're a User
- ✅ Your backups are completely safe
- ✅ Upgrade is simple (just `git pull`)
- ✅ All improvements are transparent
- ✅ See [UPGRADE-GUIDE.md](UPGRADE-GUIDE.md) for help

### If You're a Developer
- ✅ New `Scripts/Utils.ps1` module (use it!)
- ✅ 4 critical bugs fixed
- ✅ All scripts import Utils
- ✅ See [docs/DEVELOPER-GUIDE.md](docs/DEVELOPER-GUIDE.md) for patterns

### If You're Contributing
- ✅ Use Utils.ps1 functions
- ✅ Follow documented patterns
- ✅ Import Utils in new scripts
- ✅ See [.github/copilot-instructions.md](.github/copilot-instructions.md)

---

## 🎓 Learning Path

### Level 1: Just Want to Use It
1. Read [README.md](README.md)
2. Follow [docs/USER-GUIDE.md](docs/USER-GUIDE.md)
3. Done! (refer to quick reference for issues)

### Level 2: Want to Understand It
1. Read [docs/INDEX.md](docs/INDEX.md)
2. Skim [RELEASE-NOTES-v2025.12.md](RELEASE-NOTES-v2025.12.md)
3. Check [docs/DEVELOPER-GUIDE.md](docs/DEVELOPER-GUIDE.md) as needed

### Level 3: Want to Extend It
1. Study [docs/DEVELOPER-GUIDE.md](docs/DEVELOPER-GUIDE.md) completely
2. Review [.github/copilot-instructions.md](.github/copilot-instructions.md)
3. Read [Scripts/Utils.ps1](Scripts/Utils.ps1) source code
4. Review existing scripts for patterns

---

## 🔗 Cross-References

### Main Entry Points
- **Users:** [README.md](README.md) → [docs/USER-GUIDE.md](docs/USER-GUIDE.md)
- **Developers:** [docs/INDEX.md](docs/INDEX.md) → [docs/DEVELOPER-GUIDE.md](docs/DEVELOPER-GUIDE.md)
- **New Version:** [RELEASE-NOTES-v2025.12.md](RELEASE-NOTES-v2025.12.md)
- **Upgrading:** [UPGRADE-GUIDE.md](UPGRADE-GUIDE.md)

### Technical References
- **Utils Module:** [Scripts/Utils.ps1](Scripts/Utils.ps1)
- **Architecture:** [docs/DEVELOPER-GUIDE.md](docs/DEVELOPER-GUIDE.md#architecture-overview)
- **Error Handling:** [docs/ERROR-HANDLING-AUDIT.md](docs/ERROR-HANDLING-AUDIT.md)
- **Patterns:** [.github/copilot-instructions.md](.github/copilot-instructions.md#project-conventions--patterns)

---

## 📞 Need Help?

- **Usage Questions:** See [docs/USER-GUIDE.md](docs/USER-GUIDE.md)
- **Architecture Questions:** See [docs/DEVELOPER-GUIDE.md](docs/DEVELOPER-GUIDE.md)
- **Errors/Issues:** See [docs/ERROR-HANDLING-QUICK-REFERENCE.md](docs/ERROR-HANDLING-QUICK-REFERENCE.md)
- **Bug Reports:** See [RELEASE-NOTES-v2025.12.md](RELEASE-NOTES-v2025.12.md#critical-bugs-fixed)
- **Upgrading:** See [UPGRADE-GUIDE.md](UPGRADE-GUIDE.md)

---

**Last Updated:** December 25, 2025  
**Version:** v2025.12  
**Status:** ✅ Complete and pushed to repository

