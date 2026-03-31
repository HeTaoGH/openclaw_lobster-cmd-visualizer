import argparse
import json
import shutil
from datetime import datetime
from pathlib import Path


MAIN_KEY = "agent:main:main"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--mode", choices=["reset", "archive"], required=True)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    sessions_dir = Path.home() / ".openclaw/agents/main/sessions"
    index_path = sessions_dir / "sessions.json"
    backup_dir = sessions_dir / "backup-main-session"
    timestamp = datetime.now().strftime("%Y%m%d-%H%M%S")

    data = json.loads(index_path.read_text(encoding="utf-8"))
    main_entry = data.get(MAIN_KEY, {})
    session_id = main_entry.get("sessionId") if isinstance(main_entry, dict) else None

    print(f"mode={args.mode}")
    print(f"scope=local-default-main-only")
    print(f"main_key={MAIN_KEY}")
    print(f"session_id={session_id or 'NONE'}")
    print(f"dry_run={args.dry_run}")

    if args.dry_run:
        return 0

    backup_dir.mkdir(parents=True, exist_ok=True)
    shutil.copy2(index_path, backup_dir / f"sessions.json.{timestamp}.bak")

    if args.mode == "archive" and session_id:
        for suffix in [".jsonl", ".jsonl.lock"]:
            source = sessions_dir / f"{session_id}{suffix}"
            if source.exists():
                shutil.move(str(source), backup_dir / f"{source.name}.{timestamp}")

    data.pop(MAIN_KEY, None)
    if "sessions" not in data or not isinstance(data["sessions"], list):
        data["sessions"] = []

    index_path.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")

    print(f"backup_dir={backup_dir}")
    print("result=main_session_removed_from_index")
    if args.mode == "archive":
        print("result_detail=main_session_files_archived_when_present")
    else:
        print("result_detail=main_session_files_kept_on_disk")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
