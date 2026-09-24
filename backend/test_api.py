import requests
import json

url = "http://localhost:8000/api/track"

payload = {
    "Date": "09/23/2026",
    "Serial_No": "TEST-LAPTOP-123",
    "OS": "Windows",
    "Day_of_Week": "Wednesday",
    "Total_Active_Time": "5h 30m",
    "AFK_Time": "30m",
    "Off_Time": "1h 15m",
    "First_Active": "9:05 AM",
    "Last_Active": "3:45 PM",
    "Times_Opened": "4",
    "Top_Websites": "google.com (1h), github.com (45m)",
    "Top_Apps": "VS Code (2h), Chrome (1.5h)"
}

print("Sending POST request to:", url)
response = requests.post(url, json=payload)

print("Status Code:", response.status_code)
print("Response JSON:", response.json())
