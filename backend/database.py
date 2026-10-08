import os
from sqlalchemy import create_engine, Column, Integer, String, text
from sqlalchemy.orm import declarative_base, sessionmaker
from dotenv import load_dotenv

load_dotenv()

# Production AWS PostgreSQL Database
PROD_DB = "postgresql+psycopg://activity_watch:ActivityWatch*898&8@db-pg.cosodeda78lq.ap-south-1.rds.amazonaws.com:5432/activity_watch"
DATABASE_URL = os.getenv("POSTGRES_URL", PROD_DB)

engine = create_engine(
    DATABASE_URL, 
    connect_args={"check_same_thread": False} if "sqlite" in DATABASE_URL else {}
)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

Base = declarative_base()

class DailyActivity(Base):
    __tablename__ = "daily_activity"

    id = Column(Integer, primary_key=True, index=True)
    date = Column(String, index=True)
    serial_no = Column(String, index=True)
    mac_address = Column(String, index=True)
    os = Column(String)
    day_of_week = Column(String)
    total_active_time = Column(String)
    afk_time = Column(String)
    off_time = Column(String)
    first_active = Column(String)
    last_active = Column(String)
    times_opened = Column(String)
    top_websites = Column(String)
    top_apps = Column(String)
    location = Column(String)
    last_sync_time = Column(String)
    tracker_version = Column(String)

# Automatically create the database tables if they don't exist
Base.metadata.create_all(bind=engine)

# Super simple auto-migration for the new Location and Last_Sync_Time fields
try:
    with engine.connect() as conn:
        conn.execute(text("ALTER TABLE daily_activity ADD COLUMN location VARCHAR;"))
        conn.execute(text("ALTER TABLE daily_activity ADD COLUMN last_sync_time VARCHAR;"))
        conn.execute(text("ALTER TABLE daily_activity ADD COLUMN tracker_version VARCHAR;"))
        conn.commit()
except Exception:
    pass # Columns likely already exist
