# ActivityWatch V2 Enterprise Architecture & System Documentation

## 📖 Introduction
This document serves as the official architectural reference for the ActivityWatch V2 Telemetry System. It details the technical implementation, data flow, and scaling strategies used to manage telemetry for 20,000+ endpoint devices, ensuring guaranteed data integrity and zero manual maintenance.

---

## 🎯 Architectural Strategies & Implementation

### 1. The "OTA Updater" (Over-The-Air) Pattern
**Concept:** The primary Python tracker (`activity_tracker.py`) contains a self-updating function `check_installer_updates()`. Upon execution, it bypasses strict GitHub API rate limits by querying a raw text file (`raw.githubusercontent.com/.../installer_version.txt`). If a newer version is detected, it automatically downloads and executes the latest OS-specific installer.
**Technical Value:** This establishes a decentralized, self-healing deployment pipeline capable of bypassing school IP bans (which normally limit GitHub API to 60/hr). Any bug fixes or payload modifications pushed to the main repository are immediately propagated to all 20,000 devices upon their next execution cycle.

### 2. Hourly Sync & Asynchronous "Catch-Up" Logic
**Concept:** OS-level task schedulers (Windows Task Scheduler, macOS launchd, Linux cron) trigger the telemetry extraction every single hour (at the top of the hour).
**Technical Value:** 
- **Ideal State:** Devices consistently transmit hourly heartbeats, maintaining real-time data accuracy on the dashboard without relying on a single end-of-day sync.
- **Offline State:** If a device is powered off or disconnected, the script safely catches up. Upon the next successful internet connection (verified via a firewall-proof HTTPS ping to Google), the script iterates chronologically from the last successful sync date to the current date, guaranteeing **zero data loss**.

### 3. Traffic Throttling via "Global Jitter"
**Concept:** Before transmitting the JSON payload via HTTP POST, the script initiates a `time.sleep()` using a randomized integer between 1 and 300 seconds (5 minutes).
**Technical Value:** A synchronized 11:59 PM execution across 20,000 devices would result in a massive traffic spike, effectively executing a self-inflicted DDoS attack on the backend infrastructure. The introduction of global jitter evenly distributes the HTTP requests across a 5-minute window, allowing a standard, cost-effective server to ingest the payloads without requiring highly scaled AWS SQS or Redis queues.

### 4. Resilient Multi-API Geolocation Caching
**Concept:** The tracker executes a non-blocking HTTP GET request to resolve the external IP address to a City, State, and Country. It uses an array of three fallback free APIs (ip-api.com, ipwhois.app, ipapi.co) and caches the successful result to the hard drive for 24 hours.
**Technical Value:** This completely circumvents API rate-limiting blocks caused by 20,000 laptops sharing a single school/corporate public IP address. By caching the location locally for the day, it drastically reduces network overhead while guaranteeing location accuracy.

### 5. Invisible Execution & Dynamic Logging ("Black Box")
**Concept:** The script runs completely invisibly using `pythonw.exe` on Windows. All standard output and errors are dynamically caught and redirected to local hidden text files (`tracker.log` and `tracker_error.log`).
**Technical Value:** Without a terminal window, standard `print()` statements cause fatal Python crashes. The dynamic logging system prevents these silent crashes and serves as a local "Black Box" flight recorder, allowing RMS admins to instantly diagnose any endpoint failures directly from the hard drive.

### 6. Enterprise Data Integrity Protocols
**Concept:** The system utilizes multiple hard-coded safeguards to maintain database integrity across 20k+ endpoints.
**Technical Value:**
- **UUID Fingerprinting:** Instead of relying on unreliable Windows `wmic` OEM serials (which cause database collisions), the script mathematically generates and saves a permanent UUID (`device_id.txt`) upon first execution.
- **Integer Payloads:** Telemetry durations are sent as pure integers (e.g., `5400`) rather than strings (`"1h 30m"`). This allows the AWS PostgreSQL database to dynamically sum and sort millions of rows instantly, while the React frontend seamlessly renders the integers back into human-readable text.
- **Network Failure Safeguard:** Server errors (like `404 Not Found`) explicitly fail the sync process, ensuring the laptop retains its local data and retries tomorrow, rather than assuming success and deleting the data.

---

## 📂 Core System Components & File Breakdown

### 1. `activity_tracker.py` (The Core Engine)
**Role:** The primary Python execution script running on all endpoint laptops.
**Architecture & Responsibilities:**
- **ActivityWatch API Interfacing:** Queries `localhost:5600` to extract raw AFK and Window event buckets.
- **Data Processing:** Calculates precise Active Time, AFK Time, and Off Time based on a dynamic envelope (Midnight to current execution time), gracefully handling completely empty databases on fresh installs.
- **Multi-Layer Fallback:** If the primary AFK watcher is blocked (e.g. macOS Privacy Firewalls), it rescues the Active Time calculation by falling back to Window durations, and ultimately to Chrome Web Extension durations.
- **State Management:** Reads and writes to `last_sync.txt` to manage the offline catch-up loop.
- **Network Transmission:** Packages the calculated data, System OS, Geolocation, and MAC/Serial identifiers into a JSON payload and POSTs it to the remote FastAPI backend.

### 2. `install_windows.bat` (Windows Deployment)
**Role:** The zero-interaction installation payload for Windows endpoints.
**Architecture & Responsibilities:**
- Downloads and installs the ActivityWatch binaries silently via PowerShell.
- Decodes the Base64-encoded `activity_tracker.py` script directly into the `%USERPROFILE%\.aw_tracker` directory.
- Registers a hidden `wscript.exe` VBScript to execute the Python tracker without flashing a command prompt window to the user.
- **Task Scheduler:** Interfaces with Windows Task Scheduler to register the background trigger:
  1. An hourly run explicitly executing silently in the background.

### 3. `install_ubuntu_mac.sh` (Unix Deployment)
**Role:** The zero-interaction installation payload for macOS and Linux endpoints.
**Architecture & Responsibilities:**
- Identifies the host OS and downloads the appropriate ActivityWatch binaries (DMG for Mac, ZIP for Linux) natively using `curl`.
- Installs ActivityWatch to `/Applications` (Mac) or `/opt` (Linux) silently.
- **macOS Scheduler (LaunchAgent):** Generates a `com.activitywatch.sync.plist` file in `~/Library/LaunchAgents`. Configures a `StartCalendarInterval` (Minute 0) to trigger an hourly sync in the background.
- **Linux Scheduler (Crontab):** Injects an hourly CRON expression (`0 * * * *`) into the user's crontab.

### 4. `update_scripts.py` (The Compiler)
**Role:** A developer-side utility used to build the final installers.
**Architecture & Responsibilities:**
- Reads the raw `activity_tracker.py` file, converts it into a Base64 string, and automatically injects it into `install_windows.bat`.
- Injects the raw python code into the heredoc block of `install_ubuntu_mac.sh`.
- Ensures that when the installers are distributed, they contain the absolute latest tracking logic natively.

### 5. Backend Components (`backend/main.py` & `backend/database.py`)
**Role:** The centralized cloud ingestion server (FastAPI) and storage layer (SQLAlchemy / PostgreSQL).
**Architecture & Responsibilities:**
- Defines the strict expected JSON schema (`ActivityPayload`).
- Receives the payload and searches the DB for an existing `Serial_No + Date` composite key.
- Performs an UPSERT (Update if exists, Insert if new) to ensure multiple heartbeats throughout the day safely overwrite old data rather than creating duplicate rows.
- **Authentication:** Enforces security by requiring a hardcoded secret `X-API-KEY` header on the `/api/track` endpoint, rejecting unauthorized spam/bot traffic with a `403 Forbidden`.
- Hosts the REST API endpoints (`/api/data`, `/api/devices`) that feed the React frontend.

### 6. Frontend Dashboard (`frontend/src/App.jsx`)
**Role:** The React/Vite web application for data visualization.
**Architecture & Responsibilities:**
- Fetches the telemetry payload from the backend.
- Provides real-time filtering, date-range selections, and dynamic search (by Serial, MAC, or Date).
- Renders analytical charts (Activity Trends, OS Distributions) using Recharts.
