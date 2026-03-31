import argparse
import json
import shutil
from datetime import datetime
from pathlib import Path


MARKERS = [
    "feishu",
    "open_id",
    "chat_id",
    "message_id",
    "receive_id_type",
    "tenant",
    "my.feishu.cn",
    "open.feishu.cn",
    "feishu_chat",
    "feishu_",
]


def detect_candidates(sessions_dir: Path) -> list[dict]:
    results = []
    for path in sessions_dir.glob("*.jsonl"):
        try:
            text = path.read_text(encoding="utf-8", errors="ignore").lower()
        except Exception:
            continue
        found = [marker for marker in MARKERS if marker in text]
        if not found:
            continue
        stat = path.stat()
        results.append(
            {
                "path": path,
                "sessionId": path.stem,
                "score": len(found),
                "markers": found,
                "mtime": int(stat.st_mtime),
                "size": stat.st_size,
            }
        )
    results.sort(key=lambda item: (item["score"], item["mtime"], item["size"]), reverse=True)
    return results


def remove_session_from_index(data: dict, session_id: str) -> list[str]:
    removed_keys = []
    for key in list(data.keys()):
        value = data[key]
        if isinstance(value, dict) and value.get("sessionId") == session_id:
            removed_keys.append(key)
            del data[key]
    sessions = data.get("sessions")
    if isinstance(sessions, list):
        filtered = [item for item in sessions if not (isinstance(item, dict) and item.get("sessionId") == session_id)]
        data["sessions"] = filtered
    return removed_keys


def load_excluded_ids(path_str: str) -> list[str]:
    if not path_str:
        return []
    path = Path(path_str)
    if not path.exists():
        return []
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return []
    if isinstance(data, dict) and isinstance(data.get("excludedSessionIds"), list):
        return [str(item) for item in data["excludedSessionIds"]]
    return []


def save_excluded_ids(path_str: str, values: list[str]) -> None:
    if not path_str:
        return
    path = Path(path_str)
    path.parent.mkdir(parents=True, exist_ok=True)
    payload = {"excludedSessionIds": sorted(set(str(item) for item in values))}
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--mode", choices=["archive-top", "archive-session", "close-top", "close-session"], required=True)
    parser.add_argument("--session-id")
    parser.add_argument("--exclude-file")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    sessions_dir = Path.home() / ".openclaw/agents/main/sessions"
    index_path = sessions_dir / "sessions.json"
    backup_dir = sessions_dir / "backup-feishu-candidate"
    candidates = detect_candidates(sessions_dir)

    print(f"candidate_count={len(candidates)}")
    if not candidates:
      print("result=none")
      return 0

    top = candidates[0]
    session_id = args.session_id or top["sessionId"]
    selected = next((item for item in candidates if item["sessionId"] == session_id), None)
    if selected is None:
        print("result=session_not_found")
        return 1

    print(f"selected_session={session_id}")
    print(f"score={selected['score']}")
    print(f"markers={','.join(selected['markers'])}")
    print(f"dry_run={args.dry_run}")

    if args.dry_run:
      print("result=dry_run_only")
      return 0

    data = json.loads(index_path.read_text(encoding="utf-8"))
    timestamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    backup_dir.mkdir(parents=True, exist_ok=True)
    shutil.copy2(index_path, backup_dir / f"sessions.json.{timestamp}.bak")

    removed_keys = remove_session_from_index(data, session_id)
    index_path.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")

    if args.mode.startswith("close"):
      excluded = load_excluded_ids(args.exclude_file)
      excluded.append(session_id)
      save_excluded_ids(args.exclude_file, excluded)
      print("result=closed_feishu_candidate")
      print(f"removed_keys={','.join(removed_keys) if removed_keys else 'none'}")
      print("moved_files=none")
      print(f"backup_dir={backup_dir}")
      return 0

    moved = []
    for suffix in [".jsonl", ".jsonl.lock"]:
      source = sessions_dir / f"{session_id}{suffix}"
      if source.exists():
        target = backup_dir / f"{source.name}.{timestamp}"
        shutil.move(str(source), target)
        moved.append(target.name)

    if args.exclude_file:
      excluded = [item for item in load_excluded_ids(args.exclude_file) if item != session_id]
      save_excluded_ids(args.exclude_file, excluded)

    print("result=archived_feishu_candidate")
    print(f"removed_keys={','.join(removed_keys) if removed_keys else 'none'}")
    print(f"moved_files={','.join(moved) if moved else 'none'}")
    print(f"backup_dir={backup_dir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
