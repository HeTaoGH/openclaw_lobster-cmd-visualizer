import json
from pathlib import Path

path = Path.home() / ".openclaw/agents/main/sessions/sessions.json"
backup = path.with_suffix(".json.bak")
backup.write_text(path.read_text(encoding="utf-8"), encoding="utf-8")

data = json.loads(path.read_text(encoding="utf-8"))
main_key = "agent:main:main"
data = {
    key: value
    for key, value in data.items()
    if key in {main_key, "sessions"}
}
data["sessions"] = []
path.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")

print("keys=", list(data.keys()))
if main_key in data:
    print(f"sessionId={data[main_key].get('sessionId')}")
