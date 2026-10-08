from fastapi import FastAPI, Depends, Query, HTTPException, Security, status
from fastapi.responses import PlainTextResponse
from fastapi.security import APIKeyHeader
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy.orm import Session
from sqlalchemy import desc
from pydantic import BaseModel
from typing import List, Optional
from database import SessionLocal, DailyActivity
import os
import threading
import requests

app = FastAPI(title="ActivityWatch Tracker Backend")

# Write key is baked into the widely-distributed tracker; read key stays only
# in the dashboard. A leaked write key can POST data but cannot read the fleet.
WRITE_KEY = os.getenv("TRACKER_WRITE_KEY", "aw-write-key-change-me")
READ_KEY = os.getenv("DASHBOARD_READ_KEY", "aw-read-key-change-me")
api_key_header = APIKeyHeader(name="X-API-KEY", auto_error=False)

# ---- Tracker distribution: the server is the single hub between GitHub and
# the devices. It pulls the clean placeholder tracker from the latest GitHub
# release, injects the real backend URL + write key (kept only in server env),
# caches it per version, and serves it to devices. Devices never touch GitHub,
# so there is no 60/hr GitHub rate-limit exposure across the fleet.
GITHUB_REPO = os.getenv("GITHUB_REPO", "prakash-dey/activitywatch")
# The public URL devices use to reach THIS server (injected into the tracker).
BACKEND_BASE_URL = os.getenv("BACKEND_BASE_URL", "http://16.171.17.163:8000")
# Shared token the release workflow sends to trigger a refresh (event-driven,
# no polling). Must match the REFRESH_TOKEN GitHub secret.
REFRESH_TOKEN = os.getenv("REFRESH_TOKEN", "aw-refresh-token-change-me")

_tracker_lock = threading.Lock()
_tracker_cache = {"version": None, "code": None}

def _fetch_latest_tag():
    # Follow the /releases/latest redirect (no GitHub API rate limit).
    res = requests.get(
        f"https://github.com/{GITHUB_REPO}/releases/latest",
        allow_redirects=True, timeout=10
    )
    if "/tag/" in res.url:
        return res.url.split("/tag/")[-1].strip()
    return None

def refresh_tracker():
    """Pull the latest release tracker from GitHub, inject secrets, cache it.
    Called once at startup and on each /tracker/refresh webhook — never polled."""
    with _tracker_lock:
        try:
            tag = _fetch_latest_tag()
            if not tag or tag == _tracker_cache["version"]:
                return
            code = requests.get(
                f"https://github.com/{GITHUB_REPO}/releases/latest/download/activity_tracker.py",
                timeout=30
            ).text
            if "def main():" not in code:
                return  # bad download, keep previous cache
            code = code.replace("__INJECT_TRACKER_WRITE_KEY__", WRITE_KEY)
            code = code.replace("__INJECT_BACKEND_URL__", BACKEND_BASE_URL)
            _tracker_cache["version"] = tag
            _tracker_cache["code"] = code
        except Exception:
            pass  # network hiccup: keep serving the previous cached version

@app.on_event("startup")
def _start_refresh():
    refresh_tracker()  # populate cache once at boot; after that it's event-driven

def require_write_key(api_key_header: str = Security(api_key_header)):
    if api_key_header == WRITE_KEY:
        return api_key_header
    raise HTTPException(
        status_code=status.HTTP_403_FORBIDDEN,
        detail="Could not validate API key",
    )

def require_read_key(api_key_header: str = Security(api_key_header)):
    if api_key_header == READ_KEY:
        return api_key_header
    raise HTTPException(
        status_code=status.HTTP_403_FORBIDDEN,
        detail="Could not validate API key",
    )

# Allow dashboards from any domain to fetch data
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Dependency to get DB sessionw
def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()

# The exact JSON structure your Python script currently sends
class ActivityPayload(BaseModel):
    Date: str   
    Serial_No: str
    MAC_Address: str
    OS: str
    Day_of_Week: str
    Total_Active_Time: str
    AFK_Time: str
    Off_Time: str
    First_Active: str
    Last_Active: str
    Times_Opened: str
    Top_Websites: str
    Top_Apps: str
    Location: str = "Unknown Location"
    Last_Sync_Time: str = "N/A"
    Tracker_Version: str = "Unknown"

# ----------------- INGESTION ENDPOINT -----------------
@app.post("/api/track")
def track_activity(payload: ActivityPayload, db: Session = Depends(get_db), api_key: str = Depends(require_write_key)):
    from sqlalchemy import or_
    
    # 1. Search the database to see if this exact laptop already has a row for this Date
    # We check BOTH Serial_No and MAC_Address because macOS randomizes MAC addresses on Wi-Fi
    existing_record = db.query(DailyActivity).filter(
        DailyActivity.date == payload.Date,
        or_(
            DailyActivity.serial_no == payload.Serial_No,
            DailyActivity.mac_address == payload.MAC_Address
        )
    ).first()

    if existing_record:
        # 2. If it already exists, UPDATE the row with the new, larger totals
        existing_record.serial_no = payload.Serial_No
        existing_record.mac_address = payload.MAC_Address
        existing_record.total_active_time = payload.Total_Active_Time
        existing_record.afk_time = payload.AFK_Time
        existing_record.off_time = payload.Off_Time
        existing_record.first_active = payload.First_Active
        existing_record.last_active = payload.Last_Active
        existing_record.times_opened = payload.Times_Opened
        existing_record.top_websites = payload.Top_Websites
        existing_record.top_apps = payload.Top_Apps
        existing_record.location = payload.Location
        existing_record.last_sync_time = payload.Last_Sync_Time
        existing_record.tracker_version = payload.Tracker_Version
        db.commit()
        return {"status": "success", "message": "Updated existing row in database!"}
    
    else:
        # 3. If it does not exist, CREATE a brand new row
        new_record = DailyActivity(
            date=payload.Date,
            serial_no=payload.Serial_No,
            mac_address=payload.MAC_Address,
            os=payload.OS,
            day_of_week=payload.Day_of_Week,
            total_active_time=payload.Total_Active_Time,
            afk_time=payload.AFK_Time,
            off_time=payload.Off_Time,
            first_active=payload.First_Active,
            last_active=payload.Last_Active,
            times_opened=payload.Times_Opened,
            top_websites=payload.Top_Websites,
            top_apps=payload.Top_Apps,
            location=payload.Location,
            last_sync_time=payload.Last_Sync_Time,
            tracker_version=payload.Tracker_Version
        )
        db.add(new_record)
        db.commit()
        return {"status": "success", "message": "Created new row in database!"}

# ----------------- DASHBOARD / DATA ENDPOINTS -----------------
@app.get("/api/data")
def get_all_data(
    date: Optional[str] = None,
    serial_no: Optional[str] = None,
    db: Session = Depends(get_db),
    api_key: str = Depends(require_read_key)
):
    """Retrieve all student tracking data. Optionally filter by date or serial_no."""
    query = db.query(DailyActivity)
    if date:
        query = query.filter(DailyActivity.date == date)
    if serial_no:
        query = query.filter(DailyActivity.serial_no == serial_no)

    # Return newest records first
    return query.order_by(desc(DailyActivity.id)).all()

@app.get("/api/devices")
def get_unique_devices(db: Session = Depends(get_db), api_key: str = Depends(require_read_key)):
    """Retrieve a list of all unique laptop serial numbers tracked so far."""
    devices = db.query(DailyActivity.serial_no).distinct().all()
    # Flatten the result list
    return {"devices": [d[0] for d in devices]}

@app.get("/")
def read_root():
    return {"status": "Online", "message": "ActivityWatch Backend is fully operational!"}

# ----------------- TRACKER DISTRIBUTION (devices pull from here) -----------------
@app.get("/tracker/version")
def tracker_version():
    """Latest tracker version the server is serving. Devices compare this to their own.
    Serves the cache only — no GitHub fetch here (refresh is event-driven)."""
    return {"version": _tracker_cache["version"]}

@app.get("/tracker/activity_tracker.py", response_class=PlainTextResponse)
def tracker_file():
    """The latest tracker with backend URL + write key injected. Devices self-update from this."""
    if not _tracker_cache["code"]:
        raise HTTPException(status_code=503, detail="Tracker not ready yet")
    return _tracker_cache["code"]

@app.post("/tracker/refresh")
def tracker_refresh(x_refresh_token: str = Security(APIKeyHeader(name="X-Refresh-Token", auto_error=False))):
    """Webhook the release workflow calls after publishing a release. Pulls the
    new version from GitHub immediately instead of waiting for a poll."""
    if x_refresh_token != REFRESH_TOKEN:
        raise HTTPException(status_code=403, detail="Invalid refresh token")
    refresh_tracker()
    return {"status": "refreshed", "version": _tracker_cache["version"]}

@app.post("/api/delete_test")
def delete_test_data(db: Session = Depends(get_db), api_key: str = Depends(require_read_key)):
    """Delete all TEST device records. Requires API key. POST to prevent accidental triggering."""
    deleted_count = db.query(DailyActivity).filter(DailyActivity.serial_no == "TEST").delete()
    db.commit()
    return {"status": "success", "message": f"Deleted {deleted_count} TEST records!"}
