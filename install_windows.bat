@echo off
echo Starting ActivityWatch Master Installation...

:: Add Windows Defender Exclusion automatically (Requires Admin)
echo Configuring Windows Defender...
powershell -Command "Add-MpPreference -ExclusionPath '%USERPROFILE%\.aw_tracker'" >nul 2>&1

:: Windows Chrome Policy
echo Setting up Chrome Extension...
reg add "HKLM\SOFTWARE\Policies\Google\Chrome\ExtensionInstallForcelist" /v 1 /t REG_SZ /d "nglaklhklhcoonedhgnpgddginnjdadi;https://clients2.google.com/service/update2/crx" /f

:: Download and extract ActivityWatch for Windows
echo Downloading ActivityWatch...
mkdir "%USERPROFILE%\.aw_tracker" 2>nul
if not exist "%USERPROFILE%\.aw_tracker\activitywatch\aw-server\aw-server.exe" (
    curl.exe -L -o "%TEMP%\aw-win.zip" "https://github.com/ActivityWatch/activitywatch/releases/download/v0.13.2/activitywatch-v0.13.2-windows-x86_64.zip"
    tar.exe -xf "%TEMP%\aw-win.zip" -C "%USERPROFILE%\.aw_tracker"
) else (
    echo ActivityWatch engine already installed. Skipping download.
)

:: Install Visual C++ Redistributable silently (Required for aw-server-rust)
if not exist "C:\Windows\System32\vcruntime140.dll" (
    echo Checking/Installing Visual C++ Redistributable...
    curl.exe -sSL -o "%TEMP%\vc_redist.x64.exe" "https://aka.ms/vs/17/release/vc_redist.x64.exe"
    "%TEMP%\vc_redist.x64.exe" /install /quiet /norestart
    del "%TEMP%\vc_redist.x64.exe"
)

:: Create VBScript launcher (primary - zero flash, Win 98 to Win 11 current)
echo Set WshShell = CreateObject("WScript.Shell") > "%USERPROFILE%\.aw_tracker\start_aw.vbs"
echo WshShell.Run chr(34) ^& "%USERPROFILE%\.aw_tracker\activitywatch\aw-server-rust\aw-server-rust.exe" ^& Chr(34), 0 >> "%USERPROFILE%\.aw_tracker\start_aw.vbs"
echo WshShell.Run chr(34) ^& "%USERPROFILE%\.aw_tracker\activitywatch\aw-watcher-afk\aw-watcher-afk.exe" ^& Chr(34), 0 >> "%USERPROFILE%\.aw_tracker\start_aw.vbs"
echo WshShell.Run chr(34) ^& "%USERPROFILE%\.aw_tracker\activitywatch\aw-watcher-window\aw-watcher-window.exe" ^& Chr(34), 0 >> "%USERPROFILE%\.aw_tracker\start_aw.vbs"
echo Set WshShell = Nothing >> "%USERPROFILE%\.aw_tracker\start_aw.vbs"

:: Create PowerShell launcher (backup - used only if VBScript is removed in a future Win 11 build)
echo Start-Process "%USERPROFILE%\.aw_tracker\activitywatch\aw-server-rust\aw-server-rust.exe" -WindowStyle Hidden > "%USERPROFILE%\.aw_tracker\start_aw.ps1"
echo Start-Process "%USERPROFILE%\.aw_tracker\activitywatch\aw-watcher-afk\aw-watcher-afk.exe" -WindowStyle Hidden >> "%USERPROFILE%\.aw_tracker\start_aw.ps1"
echo Start-Process "%USERPROFILE%\.aw_tracker\activitywatch\aw-watcher-window\aw-watcher-window.exe" -WindowStyle Hidden >> "%USERPROFILE%\.aw_tracker\start_aw.ps1"

:: Run engines now - VBScript primary, PowerShell fallback
where wscript.exe >nul 2>&1
if %errorlevel% == 0 (
    wscript.exe "%USERPROFILE%\.aw_tracker\start_aw.vbs"
) else (
    echo VBScript unavailable. Using PowerShell fallback...
    powershell -WindowStyle Hidden -ExecutionPolicy Bypass -File "%USERPROFILE%\.aw_tracker\start_aw.ps1"
)

:: Clean up any old visible registry keys so they don't pop up on boot
reg delete "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" /v "AW-Server" /f >nul 2>&1
reg delete "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" /v "AW-Watcher-AFK" /f >nul 2>&1
reg delete "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" /v "AW-Watcher-Window" /f >nul 2>&1

:: Set auto-start on boot - VBScript primary, PowerShell fallback
where wscript.exe >nul 2>&1
if %errorlevel% == 0 (
    reg add "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" /v "ActivityWatchHidden" /t REG_EXPAND_SZ /d "wscript.exe \"%USERPROFILE%\.aw_tracker\start_aw.vbs\"" /f
) else (
    reg add "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" /v "ActivityWatchHidden" /t REG_EXPAND_SZ /d "powershell -WindowStyle Hidden -ExecutionPolicy Bypass -File \"%USERPROFILE%\.aw_tracker\start_aw.ps1\"" /f
)

:: Set up Tracker (self-contained exe - no Python needed, runs silently)
echo Setting up Tracker...
mkdir "%USERPROFILE%\.aw_tracker" 2>nul
curl.exe -sSL -o "%USERPROFILE%\.aw_tracker\activity_tracker.exe" "https://github.com/prakash-dey/activitywatch/releases/latest/download/activity_tracker.exe"

:: Schedule the tracker to run silently every hour, even on battery power.
:: The exe is built with --noconsole, so it runs hidden with no window flash.
powershell -Command "$action = New-ScheduledTaskAction -Execute '%USERPROFILE%\.aw_tracker\activity_tracker.exe'; $t1 = New-ScheduledTaskTrigger -AtLogOn; $t2 = New-ScheduledTaskTrigger -Once -At '00:00' -RepetitionInterval (New-TimeSpan -Hours 1) -RepetitionDuration (New-TimeSpan -Days 3650); $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -Hidden; Register-ScheduledTask -Action $action -Trigger @($t1, $t2) -Settings $settings -TaskName 'ActivityWatchTracker' -Force" >nul

echo Installation Complete! Chrome extension and ActivityWatch are now running silently.
echo Triggering first background sync (will execute within 0-5 minutes)...
start "" /B "%USERPROFILE%\.aw_tracker\activity_tracker.exe"

