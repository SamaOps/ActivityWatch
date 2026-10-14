// ActivityWatch Windows installer — Rust replacement for install_windows.bat.
//
// Built with the Windows GUI subsystem so running it never flashes a console
// window. Progress is written to ~/.aw_tracker/install.log instead of stdout.
//
// Two modes:
//   aw-installer.exe              -> full installation
//   aw-installer.exe run-engine   -> start the three AW executables hidden
//                                    (what the logon auto-start calls).
//
// We also still write start_aw.vbs / start_aw.ps1 into ~/.aw_tracker, matching
// the old batch installer, because activity_tracker.py's check_and_start_engines()
// looks for those files when it finds the engine dead and uses them to revive it.
// Keeping them lets the unmodified tracker self-heal on Rust-installed machines.
#![windows_subsystem = "windows"]

use std::fs;
use std::io::Write as _;
use std::os::windows::process::CommandExt;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

/// Spawn child processes without a console window (equivalent to the VBScript
/// `WScript.Shell.Run ..., 0` trick, but native).
const CREATE_NO_WINDOW: u32 = 0x0800_0000;

// --- Pinned download sources (kept identical to install_windows.bat) ---
const AW_ZIP_URL: &str = "https://github.com/ActivityWatch/activitywatch/releases/download/v0.13.2/activitywatch-v0.13.2-windows-x86_64.zip";
const VC_REDIST_URL: &str = "https://aka.ms/vs/17/release/vc_redist.x64.exe";
const TRACKER_URL: &str = "https://aw-backend.thesama.in/tracker/activity_tracker.py";
const PYTHON_URL: &str = "https://www.python.org/ftp/python/3.11.8/python-3.11.8-amd64.exe";
const CHROME_FORCELIST: &str =
    "nglaklhklhcoonedhgnpgddginnjdadi;https://clients2.google.com/service/update2/crx";

fn main() {
    let home = env_path("USERPROFILE").expect("USERPROFILE not set");
    let aw_dir = home.join(".aw_tracker");
    let _ = fs::create_dir_all(&aw_dir);

    let mode = std::env::args().nth(1).unwrap_or_default();
    match mode.as_str() {
        "run-engine" => run_engine(&aw_dir),
        _ => install(&aw_dir),
    }
}

// ---------------------------------------------------------------------------
// Full installation
// ---------------------------------------------------------------------------
fn install(aw_dir: &Path) {
    log(aw_dir, "Starting ActivityWatch installation...");

    defender_exclusion(aw_dir);
    chrome_policy(aw_dir);
    install_engine(aw_dir);
    install_vc_redist(aw_dir);
    write_launcher_scripts(aw_dir);
    start_engine(aw_dir);
    set_autostart(aw_dir);
    install_tracker(aw_dir);

    log(aw_dir, "Installation complete.");
}

/// Exclude the tracker folder from Defender scanning (needs admin; ignored if not).
fn defender_exclusion(aw_dir: &Path) {
    log(aw_dir, "Configuring Windows Defender exclusion...");
    let arg = format!("Add-MpPreference -ExclusionPath '{}'", aw_dir.display());
    silent("powershell", &["-Command", &arg]);
}

/// Force-install the Chrome extension via HKLM policy (needs admin).
fn chrome_policy(aw_dir: &Path) {
    log(aw_dir, "Setting up Chrome extension policy...");
    silent(
        "reg",
        &[
            "add",
            r"HKLM\SOFTWARE\Policies\Google\Chrome\ExtensionInstallForcelist",
            "/v", "1", "/t", "REG_SZ", "/d", CHROME_FORCELIST, "/f",
        ],
    );
}

/// Download + extract the ActivityWatch engine if not already present.
fn install_engine(aw_dir: &Path) {
    let marker = aw_dir
        .join("activitywatch")
        .join("aw-server")
        .join("aw-server.exe");
    if marker.exists() {
        log(aw_dir, "ActivityWatch engine already installed. Skipping download.");
        return;
    }
    log(aw_dir, "Downloading ActivityWatch engine...");
    let zip = temp_file("aw-win.zip");
    if download(&zip, AW_ZIP_URL, aw_dir) {
        log(aw_dir, "Extracting ActivityWatch engine...");
        silent(
            "tar.exe",
            &["-xf", &zip.to_string_lossy(), "-C", &aw_dir.to_string_lossy()],
        );
    }
    let _ = fs::remove_file(&zip);
}

/// Install the Visual C++ runtime (needed by aw-server-rust) if missing.
fn install_vc_redist(aw_dir: &Path) {
    let vcruntime = PathBuf::from(r"C:\Windows\System32\vcruntime140.dll");
    if vcruntime.exists() {
        return;
    }
    log(aw_dir, "Installing Visual C++ Redistributable...");
    let installer = temp_file("vc_redist.x64.exe");
    if download(&installer, VC_REDIST_URL, aw_dir) {
        silent(
            &installer.to_string_lossy(),
            &["/install", "/quiet", "/norestart"],
        );
    }
    let _ = fs::remove_file(&installer);
}

/// Write start_aw.vbs + start_aw.ps1 into ~/.aw_tracker. These are NOT used by
/// the Rust auto-start (the Run key points at `aw-installer.exe run-engine`),
/// but activity_tracker.py's check_and_start_engines() looks for them when the
/// engine dies and uses them to revive it. Keep them so the unmodified tracker
/// stays self-healing on Rust-installed machines.
fn write_launcher_scripts(aw_dir: &Path) {
    log(aw_dir, "Writing legacy launcher scripts (start_aw.vbs / .ps1)...");
    let base = aw_dir.join("activitywatch");
    let server = base.join("aw-server-rust").join("aw-server-rust.exe");
    let afk = base.join("aw-watcher-afk").join("aw-watcher-afk.exe");
    let window = base.join("aw-watcher-window").join("aw-watcher-window.exe");

    // VBScript — the primary path the tracker tries. The `, 0` on each Run
    // tells WScript to launch hidden (same as install_windows.bat produced).
    let vbs = format!(
        "Set WshShell = CreateObject(\"WScript.Shell\")\r\n\
         WshShell.Run chr(34) & \"{server}\" & Chr(34), 0\r\n\
         WshShell.Run chr(34) & \"{afk}\" & Chr(34), 0\r\n\
         WshShell.Run chr(34) & \"{window}\" & Chr(34), 0\r\n\
         Set WshShell = Nothing\r\n",
        server = server.display(),
        afk = afk.display(),
        window = window.display(),
    );
    let _ = fs::write(aw_dir.join("start_aw.vbs"), vbs);

    // PowerShell fallback — used only if wscript.exe is unavailable.
    let ps1 = format!(
        "Start-Process \"{server}\" -WindowStyle Hidden\r\n\
         Start-Process \"{afk}\" -WindowStyle Hidden\r\n\
         Start-Process \"{window}\" -WindowStyle Hidden\r\n",
        server = server.display(),
        afk = afk.display(),
        window = window.display(),
    );
    let _ = fs::write(aw_dir.join("start_aw.ps1"), ps1);
}

/// Start the three ActivityWatch executables now, hidden.
fn start_engine(aw_dir: &Path) {
    log(aw_dir, "Starting ActivityWatch engine...");
    run_engine(aw_dir);
}

fn run_engine(aw_dir: &Path) {
    let base = aw_dir.join("activitywatch");
    for (sub, exe) in [
        ("aw-server-rust", "aw-server-rust.exe"),
        ("aw-watcher-afk", "aw-watcher-afk.exe"),
        ("aw-watcher-window", "aw-watcher-window.exe"),
    ] {
        let path = base.join(sub).join(exe);
        if path.exists() {
            let _ = Command::new(&path)
                .creation_flags(CREATE_NO_WINDOW)
                .stdin(Stdio::null())
                .stdout(Stdio::null())
                .stderr(Stdio::null())
                .spawn();
        }
    }
}

/// Register logon auto-start pointing back at this exe (`run-engine` mode),
/// replacing the old VBScript/PowerShell launchers and Run keys.
fn set_autostart(aw_dir: &Path) {
    log(aw_dir, "Registering logon auto-start...");
    let self_exe = std::env::current_exe()
        .unwrap_or_else(|_| aw_dir.join("aw-installer.exe"));

    // Remove legacy visible Run entries left by older installers.
    for v in ["AW-Server", "AW-Watcher-AFK", "AW-Watcher-Window"] {
        silent(
            "reg",
            &[
                "delete",
                r"HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Run",
                "/v", v, "/f",
            ],
        ); 
    }

    let cmd = format!("\"{}\" run-engine", self_exe.display());
    silent(
        "reg",
        &[
            "add",
            r"HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Run",
            "/v", "ActivityWatchHidden", "/t", "REG_SZ", "/d", &cmd, "/f",
        ],
    );
}

/// Download the Python tracker, ensure Python + requests, schedule hourly runs,
/// and fire the first sync immediately.
fn install_tracker(aw_dir: &Path) {
    log(aw_dir, "Setting up Python tracker...");
    let tracker = aw_dir.join("activity_tracker.py");
    download(&tracker, TRACKER_URL, aw_dir);

    ensure_python(aw_dir);

    // Ensure the `requests` library is available (try both the PATH python and
    // the default all-users install location).
    silent("python", &["-m", "pip", "install", "requests"]);
    let py311 = PathBuf::from(r"C:\Program Files\Python311\python.exe");
    if py311.exists() {
        silent(&py311.to_string_lossy(), &["-m", "pip", "install", "requests"]);
    }

    schedule_hourly(aw_dir, &tracker);
    first_sync(aw_dir, &tracker);
}

/// Install Python 3.11 silently if no `python` is on PATH.
fn ensure_python(aw_dir: &Path) {
    if command_ok("python", &["--version"]) {
        return;
    }
    log(aw_dir, "Python not found. Installing Python 3.11 silently...");
    let installer = temp_file("python_installer.exe");
    if download(&installer, PYTHON_URL, aw_dir) {
        // start /wait equivalent: run and block until it exits.
        let _ = Command::new(&installer)
            .args([
                "/quiet",
                "InstallAllUsers=1",
                "PrependPath=1",
                "Include_test=0",
                "Include_doc=0",
            ])
            .creation_flags(CREATE_NO_WINDOW)
            .status();
    }
    let _ = fs::remove_file(&installer);
}

/// Register the hourly + at-logon scheduled task that runs the tracker via
/// pythonw (no console). pythonw gives us a hidden window without any VBScript.
fn schedule_hourly(aw_dir: &Path, tracker: &Path) {
    log(aw_dir, "Scheduling hourly tracker task...");
    let ps = format!(
        "$action = New-ScheduledTaskAction -Execute 'pythonw.exe' -Argument '\"{}\"'; \
         $t1 = New-ScheduledTaskTrigger -AtLogOn; \
         $t2 = New-ScheduledTaskTrigger -Once -At '00:00' \
               -RepetitionInterval (New-TimeSpan -Hours 1) \
               -RepetitionDuration (New-TimeSpan -Days 3650); \
         $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries \
               -DontStopIfGoingOnBatteries -StartWhenAvailable -Hidden; \
         Register-ScheduledTask -Action $action -Trigger @($t1, $t2) \
               -Settings $settings -TaskName 'ActivityWatchTracker' -Force",
        tracker.display()
    );
    silent("powershell", &["-Command", &ps]);
}

/// Fire the first tracker run now (scheduled task may not see the new PATH
/// until reboot), preferring the absolute pythonw path.
fn first_sync(aw_dir: &Path, tracker: &Path) {
    log(aw_dir, "Triggering first background sync...");
    let pyw = PathBuf::from(r"C:\Program Files\Python311\pythonw.exe");
    let exe = if pyw.exists() {
        pyw.to_string_lossy().into_owned()
    } else {
        "pythonw".to_string()
    };
    let _ = Command::new(exe)
        .arg(tracker)
        .creation_flags(CREATE_NO_WINDOW)
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn();
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

fn env_path(key: &str) -> Option<PathBuf> {
    std::env::var_os(key).map(PathBuf::from)
}

fn temp_file(name: &str) -> PathBuf {
    env_path("TEMP")
        .unwrap_or_else(|| PathBuf::from("."))
        .join(name)
}

/// Download `url` to `dest` using curl.exe. Returns true on success.
fn download(dest: &Path, url: &str, aw_dir: &Path) -> bool {
    let ok = command_ok(
        "curl.exe",
        &["-sSL", "-o", &dest.to_string_lossy(), url],
    );
    if !ok {
        log(aw_dir, &format!("Download failed: {url}"));
    }
    ok
}

/// Run a command hidden, ignoring its output; errors are swallowed (best effort).
fn silent(program: &str, args: &[&str]) {
    let _ = Command::new(program)
        .args(args)
        .creation_flags(CREATE_NO_WINDOW)
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status();
}

/// Run a command hidden and report whether it exited with success.
fn command_ok(program: &str, args: &[&str]) -> bool {
    Command::new(program)
        .args(args)
        .creation_flags(CREATE_NO_WINDOW)
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()
        .map(|s| s.success())
        .unwrap_or(false)
}

/// Append a timestamped line to ~/.aw_tracker/install.log.
fn log(aw_dir: &Path, msg: &str) {
    if let Ok(mut f) = fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(aw_dir.join("install.log"))
    {
        let _ = writeln!(f, "{msg}");
    }
}
