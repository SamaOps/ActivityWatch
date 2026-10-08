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
import uuid
import re

# In Windows pythonw, stdout and stderr are None. We dynamically redirect them to a log file to catch any future background errors.
if sys.stdout is None:
    sys.stdout = open(os.path.join(os.path.dirname(__file__), 'tracker.log'), 'a', encoding='utf-8')
if sys.stderr is None:
    sys.stderr = open(os.path.join(os.path.dirname(__file__), 'tracker_error.log'), 'a', encoding='utf-8')

BACKEND_API_URL = "https://aw-backend.thesama.in/api/track"

# Prevent double-execution if a sync takes longer than the scheduler interval
LOCK_FILE = os.path.join(os.path.dirname(__file__), 'sync.lock')
if os.path.exists(LOCK_FILE):
    try:
        # If lock is older than 2 hours (crashed run), clear it. Otherwise, exit.
        if time.time() - os.path.getmtime(LOCK_FILE) > 7200:
            os.remove(LOCK_FILE)
        else:
            print("Another instance is currently running. Exiting.")
            sys.exit(0)
    except Exception:
        sys.exit(0)

try:
    with open(LOCK_FILE, 'w') as f:
        f.write(str(os.getpid()))
except Exception:
    pass

def cleanup_lock():
    try:
        if os.path.exists(LOCK_FILE):
            os.remove(LOCK_FILE)
    except Exception:
        pass
        
import atexit
atexit.register(cleanup_lock)

def check_installer_updates():
    try:
        # Use raw github content to bypass the 60/hr API rate limit that gets schools banned
        api_url = "https://raw.githubusercontent.com/SamaOps/ActivityWatch/main/installer_version.txt"
        res = requests.get(api_url, timeout=10)
        if res.status_code == 200:
            new_version = res.text.strip()
            
            version_file = os.path.join(os.path.dirname(__file__), 'installer_version.txt')
            current_version = ""
            if os.path.exists(version_file):
                with open(version_file, 'r') as f:
                    current_version = f.read().strip()
                    
            if new_version != current_version and new_version != "":
                print("New installer version found! Running remote installer...")
                
                system = platform.system()
                if system == "Windows":
                    installer_url = "https://raw.githubusercontent.com/SamaOps/ActivityWatch/main/install_windows.bat"
                    ext = ".bat"
                    cmd = ["cmd.exe", "/c"]
                else:
                    installer_url = "https://raw.githubusercontent.com/SamaOps/ActivityWatch/main/install_ubuntu_mac.sh"
                    ext = ".sh"
                    cmd = ["bash"]
                
                inst_res = requests.get(f"{installer_url}?t={time.time()}", timeout=30)
                if inst_res.status_code == 200:
                    script_path = os.path.join(os.path.dirname(__file__), f"update_installer{ext}")
                    with open(script_path, 'w') as f:
                        f.write(inst_res.text)
                    
                    if system != "Windows":
                        os.chmod(script_path, 0o755)
                        
                    kwargs = {}
                    if os.name == 'nt':
                        kwargs['creationflags'] = 0x08000000
                    subprocess.Popen(cmd + [script_path], **kwargs)
                    
                    with open(version_file, 'w') as f:
                        f.write(new_version)
                    
                    # Exit immediately so the new installer can run cleanly without collision
                    sys.exit(0)
    except Exception:
        pass

def auto_update():
    try:
        # Fetch the master version of this script from GitHub, using a timestamp to bypass cache
        url = f"https://raw.githubusercontent.com/SamaOps/ActivityWatch/main/activity_tracker.py?t={time.time()}"
        res = requests.get(url, timeout=10)
        if res.status_code == 200:
            new_code = res.text
            
            # Validation: Ensure the downloaded code is actually our python script and not corrupted
            if "def main():" not in new_code or "import requests" not in new_code:
                print("Downloaded update is corrupted. Aborting update.")
                return
                
            with open(__file__, 'r') as f:
                current_code = f.read()
                
            # If the GitHub code is different, update the local file and restart
            if new_code.strip() != current_code.strip():
                print("New version found! Running safe compilation test...")
                temp_file = os.path.join(os.path.dirname(__file__), 'update_temp.py')
                with open(temp_file, 'w') as f:
                    f.write(new_code)
                
                # Verify syntax before applying (Bricked Laptop Safeguard)
                try:
                    compile(new_code, 'update_temp.py', 'exec')
                except SyntaxError:
                    print("Downloaded update contains syntax errors. Aborting to protect tracker.")
                    os.remove(temp_file)
                    return
                
                # Replace current file safely
                os.replace(temp_file, __file__)
                
                kwargs = {}
                if os.name == 'nt':
                    kwargs['creationflags'] = 0x08000000
                subprocess.Popen([sys.executable] + sys.argv, **kwargs)
                sys.exit(0)
    except Exception as e:
        pass # Ignore network errors and run normally

# Automatically get the laptop MAC address
def get_mac_address():
    try:
        mac_num = uuid.getnode()
        mac = ':'.join(re.findall('..', '%012x' % mac_num)).upper()
        return mac
    except Exception:
        return "Unknown-MAC"

def get_serial_number():
    # 1. Get mathematically unique UUID to prevent database collisions
    id_file = os.path.join(os.path.dirname(__file__), 'device_id.txt')
    device_uuid = ""
    try:
        if os.path.exists(id_file):
            with open(id_file, 'r') as f:
                device_uuid = f.read().strip()
        else:
            device_uuid = str(uuid.uuid4())
            with open(id_file, 'w') as f:
                f.write(device_uuid)
    except Exception:
        device_uuid = str(uuid.uuid4())
        
    # 2. Get real hardware serial number for the dashboard display
    real_serial = "Unknown-Serial"
    system = platform.system()
    try:
        if system == "Windows":
            try:
                real_serial = subprocess.check_output("wmic bios get serialnumber", shell=True, creationflags=0x08000000).decode().split('\n')[1].strip()
            except Exception:
                real_serial = subprocess.check_output('powershell -NoProfile -Command "(Get-WmiObject win32_bios).SerialNumber"', shell=True, creationflags=0x08000000).decode().strip()
        elif system == "Linux":
            try:
                with open("/etc/machine-id", "r") as f:
                    real_serial = f.read().strip()
            except Exception:
                pass
        elif system == "Darwin": # macOS
            mac_serial = subprocess.check_output("/usr/sbin/ioreg -l | grep IOPlatformSerialNumber | awk -F'\"' '{print $4}'", shell=True).decode().strip()
            if mac_serial:
                real_serial = mac_serial
    except Exception:
        pass
        
    # Combine them: "REAL_SERIAL | UUID". The React frontend will split this and only show the REAL_SERIAL.
    return f"{real_serial} | {device_uuid}"

def get_location():
    cache_file = os.path.join(os.path.dirname(__file__), 'location_cache.txt')
    # Check if we already fetched location today
    try:
        if os.path.exists(cache_file):
            mod_time = datetime.fromtimestamp(os.path.getmtime(cache_file))
            if mod_time.date() == datetime.now().date():
                with open(cache_file, 'r') as f:
                    return f.read().strip()
    except Exception:
        pass

    # Try multiple free APIs to bypass rate limits
    apis = [
        "http://ip-api.com/json",
        "https://ipwhois.app/json/",
        "https://ipapi.co/json/"
    ]
    
    for api in apis:
        try:
            # Use appropriate User-Agent to avoid blocks
            headers = {"User-Agent": "Mozilla/5.0"}
            res = requests.get(api, headers=headers, timeout=5)
            if res.status_code == 200:
                data = res.json()
                city = data.get("city", "")
                region = data.get("regionName", "") or data.get("region", "")
                country = data.get("country", "") or data.get("country_name", "")
                
                if city and country:
                    loc = f"{city}, {region}, {country}".strip(", ")
                    # Cache it for today
                    try:
                        with open(cache_file, 'w') as f:
                            f.write(loc)
                    except Exception:
                        pass
                    return loc
        except Exception:
            continue
            
    # If all fail, return cached value from yesterday if it exists
    try:
        if os.path.exists(cache_file):
            with open(cache_file, 'r') as f:
                return f.read().strip()
    except Exception:
        pass

    return "Unknown Location"



# Fetch data from ActivityWatch local server
AW_URL = "http://localhost:5600/api/0/buckets"

def format_duration(seconds):
    if seconds < 60:
        return f"{int(seconds)}s"
    minutes = int(seconds // 60)
    hours = int(minutes // 60)
    if hours > 0:
        return f"{hours}h {minutes % 60}m"
    return f"{minutes}m"

def get_daily_events(target_date):
    # Calculate local midnight for the target_date
    local_tz = datetime.now().astimezone().tzinfo
    start_local = target_date.replace(hour=0, minute=0, second=0, microsecond=0, tzinfo=local_tz)
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
        
        # Find the active buckets by picking the most recently updated one
        def get_latest_bucket(prefix):
            matching = [b for b in buckets.keys() if b.startswith(prefix)]
            if not matching: return None
            # Fresh installs return 'null' (None) for last_updated. We use 'or ""' to prevent sorting crashes.
            return sorted(matching, key=lambda x: buckets[x].get('last_updated') or "", reverse=True)[0]
            
        window_bucket = get_latest_bucket("aw-watcher-window")
        web_bucket = get_latest_bucket("aw-watcher-web")
        afk_bucket = get_latest_bucket("aw-watcher-afk")
                
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
                    
        # 2. Dynamic Mathematical Envelope: Calculate based on Working Hours (8:00 AM to current time)
        work_start = start_local # This is already set to 8:00 AM
        work_end = end_local     # This is already bound by "now" if it's today
        
        total_period_seconds = (work_end - work_start).total_seconds()
        if total_period_seconds < 0:
            total_period_seconds = 0
        
        # Prevent duplicate watcher glitches from creating impossible time
        if active_time > total_period_seconds:
            active_time = total_period_seconds
            
        if afk_time > (total_period_seconds - active_time):
            afk_time = total_period_seconds - active_time
                    
        # 2. Calculate top apps from window bucket (and provide robust fallback for times)
        if window_bucket:
            events_url = f"{AW_URL}/{window_bucket}/events?start={start_str}&end={end_str}"
            events = requests.get(events_url).json()
            inactive_apps = ['loginwindow', 'screensaverengine', 'window server', 'lockapp.exe', 'logonui.exe', 'idle']
            for e in events:
                app = e['data'].get('app', 'Unknown')
                if app.lower() in inactive_apps:
                    continue
                    
                duration = e.get('duration', 0)
                top_apps[app] = top_apps.get(app, 0) + duration
                
                # Robust Fallback: Track first and last active from Window events too
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
                        
            # If the AFK watcher crashed (active time is still 0 but apps were opened), use window duration as fallback
            if active_time == 0 and len(top_apps) > 0:
                active_time = sum(top_apps.values())
                
        # 3. Calculate top websites from web bucket
        if web_bucket:
            events_url = f"{AW_URL}/{web_bucket}/events?start={start_str}&end={end_str}"
            events = requests.get(events_url).json()
            for e in events:
                url = e['data'].get('url', '')
                duration = e.get('duration', 0)
                if url:
                    top_websites[url] = top_websites.get(url, 0) + duration
                    
                # Ultimate Fallback: Track first and last active from Web events too if others crashed
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
            
            # If BOTH AFK and Window watchers crashed (active time is still 0), use web duration
            if active_time == 0 and len(events) > 0:
                active_time = sum([e.get('duration', 0) for e in events])
                    
        # Off time is the "gaps" between First Active and Last Active (calculated after fallbacks)
        off_time = total_period_seconds - (active_time + afk_time)
        if off_time < 0:
            off_time = 0
        
        # Format all apps (only apps used for > 1 minute)
        sorted_apps = sorted(top_apps.items(), key=lambda x: x[1], reverse=True)
        top_apps_str = ", ".join([f"{app} ({format_duration(dur)})" for app, dur in sorted_apps if dur > 60])
        
        # Format all websites (only sites visited for > 1 minute)
        sorted_sites = sorted(top_websites.items(), key=lambda x: x[1], reverse=True)
        top_sites_str = ", ".join([f"{site} ({format_duration(dur)})" for site, dur in sorted_sites if dur > 60])
        
        first_active_str = first_active.strftime("%I:%M %p") if first_active else "None"
        last_active_str = last_active.strftime("%I:%M %p") if last_active else "None"
        
        return {
            "Date": start_local.strftime("%m/%d/%Y"),
            "Day_of_Week": start_local.strftime("%A"),
            "Total_Active_Time": str(int(active_time)),
            "AFK_Time": str(int(afk_time)),
            "Off_Time": str(int(off_time)),
            "First_Active": first_active_str,
            "Last_Active": last_active_str,
            "Times_Opened": str(times_opened),
            "Top_Apps": top_apps_str or "None",
            "Top_Websites": top_sites_str or "None"
        }
            
    except Exception as e:
        print(f"Error fetching AW data: {e}")
        return None

def check_and_start_engines():
    try:
        res = requests.get("http://localhost:5600/api/0/info", timeout=2)
        if res.status_code == 200:
            return # Engines are running fine
    except Exception:
        pass
        
    print("ActivityWatch engines are dead (likely due to reboot). Restarting them...")
    try:
        if platform.system() == "Windows":
            script = os.path.join(os.environ["USERPROFILE"], ".aw_tracker", "start_aw.vbs")
            if os.path.exists(script):
                subprocess.Popen(["wscript.exe", script], creationflags=0x08000000)
        else:
            script = os.path.expanduser("~/.aw_tracker/start_aw.sh")
            if os.path.exists(script):
                subprocess.Popen(["bash", script])
        # Give engines a few seconds to fully spin up
        time.sleep(5)
    except Exception as e:
        print(f"Failed to start engines: {e}")

def wait_for_internet(timeout=300):
    start_time = time.time()
    while time.time() - start_time < timeout:
        try:
            # Use standard HTTPS to a guaranteed unblocked site (Google) 
            # instead of DNS (1.1.1.1:53) which schools often block.
            requests.get("https://www.google.com", timeout=3)
            return True
        except Exception:
            time.sleep(5)
    return False

def main():
    # Global Jitter: Wait up to 5 minutes before doing ANYTHING to prevent DDoS on GitHub/Render.
    # We skip this if run interactively by a user in the terminal.
    is_interactive = getattr(sys, 'stdout', None) is not None and sys.stdout.isatty()
    if not is_interactive:
        delay = random.randint(1, 300)
        time.sleep(delay)

    # Block until internet is fully connected (solves the Wi-Fi race condition on wake)
    wait_for_internet(300)

    check_installer_updates()
    # Attempt to fetch and apply OTA updates before doing anything
    auto_update()
    
    # Watchdog: Ensure engines are actually running before we try to pull data
    check_and_start_engines()
    
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
                    start_date = last_sync
        except Exception:
            pass
            
    # Cap historical sync to last 30 days to avoid overloading
    if (today - start_date).days > 30:
        start_date = today - timedelta(days=30)
        
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
            "MAC_Address": get_mac_address(),
            "OS": "macOS" if platform.system() == "Darwin" else platform.system(),
            "Day_of_Week": aw_data["Day_of_Week"],
            "Total_Active_Time": aw_data["Total_Active_Time"],
            "AFK_Time": aw_data["AFK_Time"],
            "Off_Time": aw_data["Off_Time"],
            "First_Active": aw_data["First_Active"],
            "Last_Active": aw_data["Last_Active"],
            "Times_Opened": aw_data["Times_Opened"],
            "Top_Websites": aw_data["Top_Websites"],
            "Top_Apps": aw_data["Top_Apps"],
            "Location": get_location(),
            "Last_Sync_Time": datetime.now().strftime("%m/%d/%Y %I:%M %p")
        }
        
        print("Preparing to send to AWS rds Database...")
        try:
            headers = {"X-API-KEY": "aw-v2-enterprise-secret-key"}
            res = requests.post(BACKEND_API_URL, json=payload, headers=headers, timeout=90, allow_redirects=False)
            if res.status_code in [200, 201]:
                print(f"✅ Successfully sent data for {current_date.strftime('%Y-%m-%d')}!")
                # Save sync success for this date
                with open(sync_file, 'w') as f:
                    f.write(current_date.strftime("%Y-%m-%d"))
            elif res.status_code >= 400 and res.status_code < 500 and res.status_code != 429:
                print(f"⚠️ Unrecoverable Client Error ({res.status_code}). Skipping day to prevent infinite loop.")
                # Mark as synced so we don't get permanently stuck
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
