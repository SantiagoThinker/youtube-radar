"""scripts/utils.py — shared Python helpers.

Used by gen_status.py and any future Python scripts the orchestrator might call.
Stdlib only. No external dependencies.
"""
import json
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SEEN = ROOT / "seen.json"
LOGS_DIR = ROOT / "logs"


def prune_seen(max_per_channel: int = 30) -> dict:
    """Trim seen.json[handle] to last N entries per channel.

    Watcher only checks the last 10 videos per channel; anything older than
    position 10 is dead weight. 30 = 3× watcher window for safety.

    Returns the pruned dict (also writes to disk).
    """
    if not SEEN.exists():
        return {}
    seen = json.loads(SEEN.read_text())
    for handle, ids in list(seen.items()):
        if isinstance(ids, list) and len(ids) > max_per_channel:
            seen[handle] = ids[-max_per_channel:]
    SEEN.write_text(json.dumps(seen, indent=2) + "\n")
    return seen


def current_log_file() -> Path:
    """Return path to the current month's runs-YYYY-MM.jsonl."""
    ym = datetime.now(timezone.utc).strftime("%Y-%m")
    return LOGS_DIR / f"runs-{ym}.jsonl"


def all_log_files() -> list[Path]:
    """Return sorted list of all runs-*.jsonl files (chronological by name).

    gen_status.py uses this to aggregate across months.
    """
    if not LOGS_DIR.exists():
        return []
    files = sorted(LOGS_DIR.glob("runs-*.jsonl"))
    # Backward compatibility: include legacy runs.jsonl if it exists
    legacy = LOGS_DIR / "runs.jsonl"
    if legacy.exists():
        files = [legacy, *files]
    return files
