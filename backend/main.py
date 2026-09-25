from fastapi import FastAPI, Depends, Query
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy.orm import Session
from sqlalchemy import desc
from pydantic import BaseModel
from typing import List, Optional
from database import SessionLocal, DailyActivity

app = FastAPI(title="ActivityWatch Tracker Backend")

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

# ----------------- INGESTION ENDPOINT -----------------
@app.post("/api/track")
def track_activity(payload: ActivityPayload, db: Session = Depends(get_db)):
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
            top_apps=payload.Top_Apps
        )
        db.add(new_record)
        db.commit()
        return {"status": "success", "message": "Created new row in database!"}

# ----------------- DASHBOARD / DATA ENDPOINTS -----------------
@app.get("/api/data")
def get_all_data(
    date: Optional[str] = None, 
    serial_no: Optional[str] = None, 
    db: Session = Depends(get_db)
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
def get_unique_devices(db: Session = Depends(get_db)):
    """Retrieve a list of all unique laptop serial numbers tracked so far."""
    devices = db.query(DailyActivity.serial_no).distinct().all()
    # Flatten the result list
    return {"devices": [d[0] for d in devices]}

@app.get("/")
def read_root():
    return {"status": "Online", "message": "ActivityWatch Backend is fully operational!"}
