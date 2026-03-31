import argparse
import json
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


def score_text(text: str) -> tuple[int, list[str]]:
    found = []
    lowered = text.lower()
    for marker in MARKERS:
        if marker in lowered:
            found.append(marker)
    return len(found), found


def extract_preview(text: str) -> str:
    preview = ""
    for line in reversed(text.splitlines()):
        cleaned = " ".join(line.strip().split())
        if len(cleaned) < 12:
            continue
        lowered = cleaned.lower()
        if "message_id" in lowered or "feishu" in lowered or "content" in lowered or "text" in lowered:
            preview = cleaned
            break
    if not preview:
        preview = " ".join(text.strip().split())[:240]
    preview = compact_text(preview.replace('"', "'"), 120)
    return preview[:120]


def compact_text(value: str, limit: int = 80) -> str:
    raw = "".join(ch if (ch >= " " or ch in "\t\r\n") else " " for ch in (value or ""))
    text = " ".join(raw.strip().split())
    return text[:limit]


def extract_content_text(content) -> str:
    if isinstance(content, list):
        parts = []
        for item in content:
            if isinstance(item, dict):
                if item.get("type") == "text" and item.get("text"):
                    parts.append(str(item.get("text")))
                elif item.get("type") == "toolCall":
                    name = item.get("name") or "tool"
                    parts.append(f"[tool:{name}]")
        return compact_text(" ".join(parts), 120)
    if isinstance(content, str):
        return compact_text(content, 120)
    return ""


def build_event_line(role: str, text: str, tool_name: str = "") -> str:
    if not text:
        return ""
    if role == "toolResult":
        label = f"工具[{tool_name or 'tool'}]"
    elif role == "assistant":
        label = "助手"
    elif role == "user":
        label = "用户"
    else:
        label = role or "事件"
    return f"{label}: {compact_text(text, 120)}"


def extract_human_summary(text: str) -> dict:
    latest_user = ""
    latest_assistant = ""
    latest_tool = ""
    latest_tool_name = ""
    latest_type = ""
    recent_events: list[str] = []

    for line in text.splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            obj = json.loads(line)
        except Exception:
            continue
        if not isinstance(obj, dict) or obj.get("type") != "message":
            continue
        message = obj.get("message", {})
        if not isinstance(message, dict):
            continue
        role = message.get("role")
        latest_type = role or latest_type
        if role == "user":
            latest_user = extract_content_text(message.get("content"))
            event_line = build_event_line("user", latest_user)
        elif role == "assistant":
            latest_assistant = extract_content_text(message.get("content"))
            event_line = build_event_line("assistant", latest_assistant)
        elif role == "toolResult":
            latest_tool_name = str(message.get("toolName") or latest_tool_name)
            latest_tool = extract_content_text(message.get("content"))
            event_line = build_event_line("toolResult", latest_tool, latest_tool_name)
        else:
            event_line = ""

        if event_line:
            recent_events.append(event_line)

    summary_parts = []
    if latest_user:
        summary_parts.append(f"用户: {latest_user}")
    if latest_assistant:
        summary_parts.append(f"助手: {latest_assistant}")
    if latest_tool_name or latest_tool:
        tail = latest_tool or "无文本结果"
        tool_title = latest_tool_name or "tool"
        summary_parts.append(f"工具[{tool_title}]: {tail}")

    recent_events = recent_events[-6:]

    return {
        "latestRole": latest_type or "unknown",
        "latestUserText": latest_user,
        "latestAssistantText": latest_assistant,
        "latestToolName": latest_tool_name,
        "latestToolText": latest_tool,
        "humanSummary": " | ".join(summary_parts)[:220] if summary_parts else "",
        "recentEvents": recent_events,
    }


def extract_last_ts(text: str, fallback_mtime: int) -> int:
    last_ts = 0
    for line in text.splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            obj = json.loads(line)
        except Exception:
            continue
        if isinstance(obj, dict):
            for key in ("timestamp", "ts", "createdAt", "updatedAt"):
                value = obj.get(key)
                if isinstance(value, (int, float)):
                    if value > 10_000_000_000:
                        value = int(value / 1000)
                    last_ts = max(last_ts, int(value))
    return last_ts or fallback_mtime


def load_excluded_ids(path_str: str) -> set[str]:
    if not path_str:
        return set()
    path = Path(path_str)
    if not path.exists():
        return set()
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return set()
    if isinstance(data, dict):
        values = data.get("excludedSessionIds")
        if isinstance(values, list):
            return {str(item) for item in values}
    return set()


def collect_results(excluded_ids: set[str] | None = None, include_excluded: bool = False) -> list[dict]:
    sessions_dir = Path.home() / ".openclaw/agents/main/sessions"
    excluded_ids = excluded_ids or set()
    results = []
    for path in sessions_dir.glob("*.jsonl"):
        is_excluded = path.stem in excluded_ids
        if is_excluded and not include_excluded:
            continue
        try:
            text = path.read_text(encoding="utf-8", errors="ignore")
        except Exception:
            continue
        score, found = score_text(text)
        if score <= 0:
            continue
        mtime = int(path.stat().st_mtime)
        last_activity_ts = extract_last_ts(text, mtime)
        summary = extract_human_summary(text)
        results.append(
            {
                "file": path.name,
                "sessionId": path.stem,
                "score": score,
                "markers": found,
                "mtime": mtime,
                "size": path.stat().st_size,
                "lastActivityTs": last_activity_ts,
                "lastActivityText": datetime.fromtimestamp(last_activity_ts).strftime("%Y-%m-%d %H:%M:%S"),
                "preview": extract_preview(text),
                "excluded": is_excluded,
                **summary,
            }
        )

    results.sort(key=lambda item: (item["score"], item["lastActivityTs"], item["size"]), reverse=True)
    return results


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--json", action="store_true")
    parser.add_argument("--exclude-file")
    parser.add_argument("--include-excluded", action="store_true")
    args = parser.parse_args()

    excluded_ids = load_excluded_ids(args.exclude_file)
    results = collect_results(excluded_ids=excluded_ids, include_excluded=args.include_excluded)
    top = results[:8]

    if args.json:
        print(json.dumps({"candidate_count": len(results), "candidates": top}, ensure_ascii=True, indent=2))
        return 0

    print(f"candidate_count={len(results)}")
    if not top:
        print("result=none")
        return 0

    print("result=ok")
    for idx, item in enumerate(top, 1):
        markers = ",".join(item["markers"][:8])
        print(
            f"{idx}. sessionId={item['sessionId']} | score={item['score']} | "
            f"lastActivity={item['lastActivityText']} | size={item['size']} | markers={markers} | excluded={item['excluded']}"
        )
        if item.get("humanSummary"):
            print(f"   summary={item['humanSummary']}")
        print(f"   preview={item['preview']}")
    print("note=heuristic_only")
    print("note=these_are_candidates_not_guaranteed_active_feishu_thread")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
