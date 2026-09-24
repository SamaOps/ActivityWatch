@echo off
echo Starting ActivityWatch Uninstallation...

:: 1. Remove Chrome Extension Force-Install Policy
echo Removing Chrome Extension Policy...
reg delete "HKLM\SOFTWARE\Policies\Google\Chrome\ExtensionInstallForcelist" /v 1 /f >nul 2>&1

:: 2. Stop any running ActivityWatch processes
echo Stopping Background Trackers...
taskkill /F /IM aw-server.exe >nul 2>&1
taskkill /F /IM aw-watcher-afk.exe >nul 2>&1
taskkill /F /IM aw-watcher-window.exe >nul 2>&1
taskkill /F /IM pythonw.exe >nul 2>&1

:: 3. Remove Scheduled Task and Startup Registry
echo Removing Scheduled Tasks...
schtasks /delete /tn "ActivityWatchTracker" /F >nul 2>&1
reg delete "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" /v "ActivityWatchHidden" /f >nul 2>&1

:: 4. Delete Application Files
echo Deleting Application Files...
rmdir /s /q "C:\Program Files\activitywatch" >nul 2>&1
rmdir /s /q "%USERPROFILE%\.aw_tracker" >nul 2>&1

echo Uninstallation Complete! ActivityWatch has been fully removed from this system.
pause
