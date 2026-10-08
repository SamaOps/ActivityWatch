@echo off
echo Starting ActivityWatch Uninstallation...

:: 1. Remove scheduled task and startup registry (stop it re-launching)
echo Removing auto-start entries...
schtasks /delete /tn "ActivityWatchTracker" /F >nul 2>&1
reg delete "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" /v "ActivityWatchHidden" /f >nul 2>&1

:: 2. Stop all running processes
echo Stopping background trackers...
taskkill /F /IM wscript.exe >nul 2>&1
taskkill /F /IM aw-server-rust.exe >nul 2>&1
taskkill /F /IM aw-watcher-afk.exe >nul 2>&1
taskkill /F /IM aw-watcher-window.exe >nul 2>&1
taskkill /F /IM pythonw.exe >nul 2>&1
:: Brief wait so file handles are released before we delete
timeout /t 2 /nobreak >nul

:: 3. Remove Chrome Extension Force-Install Policy
echo Removing Chrome extension policy...
reg delete "HKLM\SOFTWARE\Policies\Google\Chrome\ExtensionInstallForcelist" /v 1 /f >nul 2>&1

:: 4. Remove Windows Defender exclusion added during install
echo Removing Windows Defender exclusion...
powershell -Command "Remove-MpPreference -ExclusionPath '%USERPROFILE%\.aw_tracker'" >nul 2>&1

:: 5. Delete all application files (covers activitywatch engine, scripts, tracker, launchers)
echo Deleting application files...
rmdir /s /q "%USERPROFILE%\.aw_tracker" >nul 2>&1

echo.
echo Uninstallation complete. ActivityWatch has been fully removed from this system.
pause
