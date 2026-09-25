# ActivityWatch Enterprise Tracker (SamaOps Updates)

This document contains the custom, fully headless deployment scripts for tracking device activity and automatically uploading the telemetry data directly to a centralized Render Database & Dashboard.

## 🚀 Enterprise Features

- **100% Invisible**: The trackers run completely in the background. There are no tray icons, visible windows, or desktop apps.
- **Automated Sync**: A hidden background timer (Windows Task Scheduler / Mac LaunchAgent) automatically uploads daily summaries to your custom Dashboard every 30 minutes.
- **Trojan Horse Auto-Updater**: 
  - **Code Updates**: The tracker dynamically pulls the newest python logic from GitHub on every execution.
  - **Installer Updates**: If core installer logic changes, the script dynamically downloads and executes the newest `.bat` or `.sh` installers seamlessly in the background.
- **Smart Deployments**: The installer scripts automatically check if the 150MB ActivityWatch engine is already installed. If it is, they instantly skip the download to prevent network overload and tracker downtime.
- **Robust Failsafes**: 
  - **Time Fallback**: If the AFK watcher ever crashes, the python script dynamically loops through the Window watcher data to perfectly reconstruct Active Time and First/Last Active bounds.
  - **Offline Support**: If a laptop loses Wi-Fi connection, the script will safely pause. The moment they connect to Wi-Fi again, the script will calculate the missing days and send a separate row for each missed day!
  - **Battery Bypass**: Windows deployments use advanced PowerShell registration to force the 30-minute sync to run even when the laptop is unplugged and running on battery power.
- **Data Points Collected**:
  - Total Active Time
  - AFK Time
  - Off Time (Mathematically balanced to represent true device offline time)
  - First Active Time & Last Active Time
  - Top 3 Websites Used (over 5 minutes)
  - Top 3 Apps Used (over 5 minutes)
  - Device Serial Number & MAC Address

---

## 💻 Installation Instructions

Instead of sending ZIP folders, you only need to send the employee **one single script file**. Everything else (including the tracking engines and the custom Python logic) is automatically downloaded and embedded inside these master installers.

### Windows Installation
1. Download **`install_windows.bat`**.
2. **Double-click** the file (Administrator privileges are NO LONGER required!).
3. A black command window will appear for a few seconds as it securely downloads the trackers and hides them. Once the window disappears, the tracking has officially started!

### macOS / Ubuntu Installation
1. Download **`install_ubuntu_mac.sh`**.
2. Open a Terminal and run: `bash install_ubuntu_mac.sh`
3. The script will handle the download, extract the engines to `/Applications/activitywatch`, and register a persistent `launchd` service that runs every 30 minutes.

---

## ⚙️ Manual Verification

If you ever want to force a laptop to sync its data to the dashboard immediately, run the following command in the computer's terminal:

**Windows:**
`python "%USERPROFILE%\.aw_tracker\activity_tracker.py"`

**macOS/Linux:**
`python3 ~/.aw_tracker/activity_tracker.py`
