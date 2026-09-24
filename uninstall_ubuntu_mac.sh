#!/bin/bash
echo "Starting ActivityWatch Uninstallation..."

if [ "$(uname)" == "Darwin" ]; then
    echo "macOS detected. Removing files..."
    
    # 1. Stop background trackers
    killall aw-server > /dev/null 2>&1
    killall aw-watcher-afk > /dev/null 2>&1
    killall aw-watcher-window > /dev/null 2>&1
    
    # 2. Remove Chrome Policy
    sudo rm -f "/Library/Managed Preferences/com.google.Chrome.plist"
    
    # 3. Remove LaunchAgent
    sudo rm -f /Library/LaunchAgents/com.activitywatch.plist
    
    # 4. Remove Cron Job
    crontab -l | grep -v 'activity_tracker.py' | crontab -
    
    # 5. Delete Application and Tracker folders
    rm -rf /Applications/activitywatch
    rm -rf ~/.aw_tracker
    
else
    echo "Ubuntu/Linux detected. Removing files..."
    
    # 1. Stop background trackers
    killall aw-server > /dev/null 2>&1
    killall aw-watcher-afk > /dev/null 2>&1
    killall aw-watcher-window > /dev/null 2>&1
    
    # 2. Remove Chrome Policy
    sudo rm -f /etc/opt/chrome/policies/managed/activitywatch.json
    
    # 3. Remove Autostart files
    rm -f /etc/xdg/autostart/activitywatch-server.desktop
    rm -f /etc/xdg/autostart/activitywatch-afk.desktop
    rm -f /etc/xdg/autostart/activitywatch-window.desktop
    
    # 4. Remove Cron Job
    crontab -l | grep -v 'activity_tracker.py' | crontab -
    
    # 5. Delete Application and Tracker folders
    sudo rm -rf /opt/activitywatch
    rm -rf ~/.aw_tracker
fi

echo "Uninstallation Complete! ActivityWatch has been fully removed."
