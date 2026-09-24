import os
from sqlalchemy import create_engine, Column, Integer, String
from sqlalchemy.orm import declarative_base, sessionmaker
from dotenv import load_dotenv

load_dotenv()

# We use SQLite by default for easy local testing so you don't have to install PostgreSQL immediately.
# When you are ready for production, just add POSTGRES_URL=postgresql://user:pass@host/db to a .env file!
DATABASE_URL = os.getenv("POSTGRES_URL", "sqlite:///./activitywatch.db")

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

# Automatically create the database tables if they don't exist
Base.metadata.create_all(bind=engine)
