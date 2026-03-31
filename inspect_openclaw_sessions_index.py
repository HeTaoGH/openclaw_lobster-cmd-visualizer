import json
from pathlib import Path

path = Path.home() / ".openclaw" / "agents" / "main" / "sessions" / "sessions.json"
text = path.read_text(encoding="utf-8")
print("size=", len(text))
data = json.loads(text)
print("type=", type(data).__name__)
if isinstance(data, dict):
    print("keys=", list(data.keys())[:20])
    sessions = data.get("sessions")
    print("sessions_type=", type(sessions).__name__ if sessions is not None else None)
    if isinstance(sessions, list):
      print("sessions_len=", len(sessions))
      for item in sessions[:5]:
        if isinstance(item, dict):
          print("session_key=", item.get("key"), "session_id=", item.get("sessionId"))
