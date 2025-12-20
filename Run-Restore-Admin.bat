@echo off
:: ============================================================
:: BOOTSTRAP LOADER
:: Automatically elevates to Admin and runs the Windows Restore Script
:: ============================================================

NET SESSION >nul 2>&1
IF %ERRORLEVEL% NEQ 0 (
    echo Requesting Administrator privileges...
    powershell -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

cd /d "%~dp0"

IF EXIST "Installers\Restore_Windows.ps1" (
    echo Found Restore Script. Launching PowerShell...
    powershell -NoProfile -ExecutionPolicy Bypass -File "Installers\Restore_Windows.ps1"
) ELSE (
    color 0C
    echo ERROR: Could not find "Installers\Restore_Windows.ps1"
    echo.
    echo Please ensure you have run the Generator script first!
    pause
)
