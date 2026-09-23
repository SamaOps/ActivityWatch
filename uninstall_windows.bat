@echo off
echo Stopping ActivityWatch trackers...

:: Kill the processes
taskkill /F /IM aw-server.exe >nul 2>&1
taskkill /F /IM aw-watcher-afk.exe >nul 2>&1
taskkill /F /IM aw-watcher-window.exe >nul 2>&1
taskkill /F /IM aw-qt.exe >nul 2>&1

:: Remove auto-start registry keys
reg delete "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" /v "AW-Server" /f >nul 2>&1
reg delete "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" /v "AW-Watcher-AFK" /f >nul 2>&1
reg delete "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" /v "AW-Watcher-Window" /f >nul 2>&1
reg delete "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" /v "ActivityWatch" /f >nul 2>&1

:: Remove the scheduled python task
schtasks /delete /tn "ActivityWatchTracker" /f >nul 2>&1

echo Trackers stopped and timers removed!
pause
