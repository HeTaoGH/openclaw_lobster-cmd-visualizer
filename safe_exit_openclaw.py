import argparse
import json
import shutil
import subprocess
from datetime import datetime
from pathlib import Path


def run_shell(command: str) -> str:
    result = subprocess.run(
        ["bash", "-lc", command],
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="ignore",
        check=False,
    )
    return ((result.stdout or "") + "\n" + (result.stderr or "")).strip()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    base_dir = Path.home() / ".openclaw" / "agents" / "main"
    sessions_dir = base_dir / "sessions"
    state_dir = base_dir / "safe-exit"
    timestamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    snapshot_dir = state_dir / timestamp
    snapshot_dir.mkdir(parents=True, exist_ok=True)

    sessions_index = sessions_dir / "sessions.json"
    session_data = {}
    if sessions_index.exists():
        session_data = json.loads(sessions_index.read_text(encoding="utf-8"))
        shutil.copy2(sessions_index, snapshot_dir / "sessions.json")

    session_ids = set()
    for key, value in session_data.items():
        if isinstance(value, dict) and value.get("sessionId"):
            session_ids.add(str(value["sessionId"]))
    sessions_list = session_data.get("sessions")
    if isinstance(sessions_list, list):
        for item in sessions_list:
            if isinstance(item, dict) and item.get("sessionId"):
                session_ids.add(str(item["sessionId"]))

    copied_files = []
    for session_id in sorted(session_ids):
        for suffix in [".jsonl", ".jsonl.lock"]:
            path = sessions_dir / f"{session_id}{suffix}"
            if path.exists():
                shutil.copy2(path, snapshot_dir / path.name)
                copied_files.append(path.name)

    status_text = run_shell("timeout 12 openclaw status || openclaw health || true")
    stop_text = "dry-run"
    if not args.dry_run:
        stop_text = run_shell("openclaw gateway stop || pkill -f clawdbot || pkill -f openclaw || true")

    main_session = session_data.get("agent:main:main", {}) if isinstance(session_data, dict) else {}
    payload = {
        "timestamp": timestamp,
        "snapshotDir": str(snapshot_dir),
        "mainSessionId": main_session.get("sessionId"),
        "sessionFileCount": len(copied_files),
        "sessionIds": sorted(session_ids),
        "statusText": status_text,
        "stopText": stop_text,
        "gatewayStopped": not args.dry_run,
        "dryRun": args.dry_run,
        "resumeHint": "next_start_can_continue_from_saved_sessions",
    }
    (snapshot_dir / "summary.json").write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
    (state_dir / "latest.json").write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")

    print(f"result=safe_exit_completed")
    print(f"snapshot_dir={snapshot_dir}")
    print(f"main_session_id={main_session.get('sessionId') or 'unknown'}")
    print(f"copied_session_files={len(copied_files)}")
    print(f"gateway_stopped={'false' if args.dry_run else 'true'}")
    print(f"dry_run={args.dry_run}")
    print("resume_hint=next_start_can_continue_from_saved_sessions")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
