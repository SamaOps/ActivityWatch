# ActivityWatch Invisible Tracker (SamaOps Updates)

This document contains the custom, fully headless deployment scripts for tracking student laptop activity and automatically uploading the data directly to a Google Sheet.

## 🚀 Features

- **100% Invisible**: The trackers run completely in the background. There are no tray icons, visible windows, or desktop apps.
- **Automated Sync**: A hidden background timer (Windows Task Scheduler / Mac Cron) automatically uploads daily summaries to your Google Sheet every 30 minutes.
- **Offline Support**: If a laptop loses Wi-Fi connection, the script will safely pause. The moment they connect to Wi-Fi again, the script will automatically calculate the missing days and send a separate row for each missed day to the sheet!
- **Data Points Collected**:
  - Total Active Time
  - AFK Time
  - Off Time (Time the trackers were stopped/shutdown)
  - First Active Time & Last Active Time
  - Top 3 Websites Used (over 5 minutes)
  - Top 3 Apps Used (over 5 minutes)

---

## 💻 Installation Instructions

Instead of sending ZIP folders, you only need to send the student/tester **one single script file**. Everything else (including the tracking engines and the custom Python logic) is automatically downloaded and embedded inside these master installers.

### Windows Installation
1. Download **`install_windows.bat`**.
2. **Right-click** the file and select **"Run as Administrator"**.
3. A black command window will appear for a few seconds as it securely downloads the trackers and hides them.
4. Done! The background trackers will start silently, and a 30-minute timer is set forever.

### macOS & Ubuntu (Linux) Installation
1. Download **`install_ubuntu_mac.sh`**.
2. Open the **Terminal**.
3. Run the script with administrator privileges by typing:
   ```bash
   sudo bash /path/to/install_ubuntu_mac.sh
   ```
4. Done! The trackers are placed in the `Applications` folder and hidden.

---

## 🧪 Testing and Verification

You don't have to wait 30 minutes to see if the installation worked. You can force the laptop to instantly upload its current data to your Google Sheet at any time!

**On Windows:**
Open the Command Prompt (`cmd`) and run:
```cmd
python %USERPROFILE%\.aw_tracker\activity_tracker.py
```

**On Mac/Linux:**
Open the Terminal and run:
```bash
python3 ~/.aw_tracker/activity_tracker.py
```

If everything is working, you will see a green checkmark (`✅ Successfully sent data!`) and the new row will instantly appear in your Google Sheet.

---

## 🛑 How to Uninstall (Kill Switch)

Because the trackers are heavily embedded to run silently on boot, they cannot be closed from the Task Manager easily. 

If you are done testing on a Windows laptop and want to completely remove the trackers and the background timer, double-click the **`uninstall_windows.bat`** file. It will instantly force-kill all the hidden trackers and clean up the auto-start registry keys.
