import os

# Update Windows .bat
with open('tracker_base64.txt', 'r') as f:
    b64_content = f.read().strip()

bat_file = 'install_windows.bat'
with open(bat_file, 'r') as f:
    bat_lines = f.readlines()

new_bat_lines = []
skip = False
for line in bat_lines:
    if line.startswith('echo -----BEGIN CERTIFICATE-----'):
        new_bat_lines.append(line)
        for b64_line in b64_content.split('\n'):
            new_bat_lines.append(f'echo {b64_line} >> "%B64_FILE%"\n')
        skip = True
    elif line.startswith('echo -----END CERTIFICATE-----'):
        skip = False
        new_bat_lines.append(line)
    elif not skip:
        new_bat_lines.append(line)

with open(bat_file, 'w') as f:
    f.writelines(new_bat_lines)

# Update Mac/Linux .sh
py_file = 'activity_tracker.py'
with open(py_file, 'r') as f:
    py_content = f.read()

sh_file = 'install_ubuntu_mac.sh'
with open(sh_file, 'r') as f:
    sh_lines = f.readlines()

new_sh_lines = []
skip = False
for line in sh_lines:
    if line.startswith("cat > ~/.aw_tracker/activity_tracker.py << 'EOF_PYTHON'"):
        new_sh_lines.append(line)
        new_sh_lines.append(py_content)
        if not py_content.endswith('\n'):
            new_sh_lines.append('\n')
        skip = True
    elif line.startswith('EOF_PYTHON'):
        skip = False
        new_sh_lines.append(line)
    elif not skip:
        new_sh_lines.append(line)

with open(sh_file, 'w') as f:
    f.writelines(new_sh_lines)

print("Install scripts updated!")
