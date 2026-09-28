# ActivityWatch V2 Enterprise Architecture & System Documentation

## 📖 Introduction
This document serves as the official architectural reference for the ActivityWatch V2 Telemetry System. It details the technical implementation, data flow, and scaling strategies used to manage telemetry for 20,000+ endpoint devices, ensuring guaranteed data integrity and zero manual maintenance.

---

## 🎯 Architectural Strategies & Implementation

### 1. The "OTA Updater" (Over-The-Air) Pattern
**Concept:** The primary Python tracker (`activity_tracker.py`) contains a self-updating function `check_installer_updates()`. Upon execution, it checks the raw `installer_version.txt` file on the central GitHub repository. If a newer version is detected, it automatically downloads and executes the latest OS-specific installer (`install_windows.bat` or `install_ubuntu_mac.sh`), which in turn updates the Python script.
**Technical Value:** This establishes a decentralized, self-healing deployment pipeline. Any bug fixes, feature additions (e.g., Geolocation tracking), or payload modifications pushed to the main repository are immediately propagated to all 20,000 devices upon their next execution cycle, completely eliminating the need for endpoint management software (MDM) redeployments.

### 2. 24-Hour Sync & Asynchronous "Catch-Up" Logic
**Concept:** OS-level task schedulers trigger the telemetry extraction at 11:59 PM daily, enforcing a strict 12:00 AM to 11:59 PM calculation envelope.
**Technical Value:** 
- **Ideal State:** Devices online at 11:59 PM transmit a mathematically perfect 24-hour block of telemetry.
- **Offline State:** If a device is powered off at 11:59 PM, the sync fails silently. The script utilizes a local state file (`last_sync.txt`). Upon the next successful network connection (e.g., 9:00 AM the following morning), the script iterates chronologically from the last successful sync date to the current date, retroactively building and transmitting the missing 24-hour JSON payloads. This guarantees **zero data loss**.

### 3. Traffic Throttling via "Global Jitter"
**Concept:** Before transmitting the JSON payload via HTTP POST, the script initiates a `time.sleep()` using a randomized integer between 1 and 300 seconds (5 minutes).
**Technical Value:** A synchronized 11:59 PM execution across 20,000 devices would result in a massive traffic spike, effectively executing a self-inflicted DDoS attack on the backend infrastructure. The introduction of global jitter evenly distributes the HTTP requests across a 5-minute window, allowing a standard, cost-effective server to ingest the payloads without requiring highly scaled AWS SQS or Redis queues.

### 4. IP-Based Geolocation Integration
**Concept:** The tracker executes a non-blocking, rate-limited HTTP GET request to `ip-api.com` to resolve the external IP address to a City, State, and Country.
**Technical Value:** This negates the need to request OS-level location permissions, avoiding intrusive prompts to the end user. Network exceptions (e.g., firewall blocks, API rate limits) are caught gracefully, defaulting the payload to "Unknown Location" to ensure the core telemetry transmission is never interrupted.

---

## 📂 Core System Components & File Breakdown

### 1. `activity_tracker.py` (The Core Engine)
**Role:** The primary Python execution script running on all endpoint laptops.
**Architecture & Responsibilities:**
- **ActivityWatch API Interfacing:** Queries `localhost:5600` to extract raw AFK and Window event buckets.
- **Data Processing:** Calculates precise Active Time, AFK Time, and Off Time based on a dynamic envelope (Midnight to current execution time).
- **Fallback Mechanisms:** If the AFK watcher fails, it intelligently recalculates Active Time strictly from the Window event durations.
- **State Management:** Reads and writes to `last_sync.txt` to manage the offline catch-up loop.
- **Network Transmission:** Packages the calculated data, System OS, Geolocation, and MAC/Serial identifiers into a JSON payload and POSTs it to the remote FastAPI backend.

### 2. `install_windows.bat` (Windows Deployment)
**Role:** The zero-interaction installation payload for Windows endpoints.
**Architecture & Responsibilities:**
- Downloads and installs the ActivityWatch binaries silently via PowerShell.
- Decodes the Base64-encoded `activity_tracker.py` script directly into the `%USERPROFILE%\.aw_tracker` directory.
- Registers a hidden `wscript.exe` VBScript to execute the Python tracker without flashing a command prompt window to the user.
- **Task Scheduler:** Interfaces with Windows Task Scheduler to register two execution triggers:
  1. A daily run explicitly at `23:59:00` for the full day telemetry dump.
  2. A repeating 3-hour interval to act as a micro-heartbeat failsafe.

### 3. `install_ubuntu_mac.sh` (Unix Deployment)
**Role:** The zero-interaction installation payload for macOS and Linux endpoints.
**Architecture & Responsibilities:**
- Identifies the host OS and downloads the appropriate ActivityWatch binaries (DMG for Mac, ZIP for Linux) natively using `curl`.
- Installs ActivityWatch to `/Applications` (Mac) or `/opt` (Linux) silently.
- **macOS Scheduler (LaunchAgent):** Generates a `com.activitywatch.sync.plist` file in `~/Library/LaunchAgents`. Configures a `StartCalendarInterval` (23:59) and a `StartInterval` (10800 seconds / 3 hours).
- **Linux Scheduler (Crontab):** Injects specific CRON expressions (`59 23 * * *` and `0 */3 * * *`) into the user's crontab.

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
- Hosts the REST API endpoints (`/api/data`, `/api/devices`) that feed the React frontend.

### 6. Frontend Dashboard (`frontend/src/App.jsx`)
**Role:** The React/Vite web application for data visualization.
**Architecture & Responsibilities:**
- Fetches the telemetry payload from the backend.
- Provides real-time filtering, date-range selections, and dynamic search (by Serial, MAC, or Date).
- Renders analytical charts (Activity Trends, OS Distributions) using Recharts.
