#!/usr/bin/env python3
"""Missions: the island's read-only window onto pi-subagents' durable records.

pi-subagents stores one JSON record per mission under
`~/.pi/agent/missions/projects/<sha256(projectRoot)>/<missionId>.json`, plus a
thin pointer index under `~/.pi/agent/missions/index/<sha>.json` holding
`{schemaVersion, missionId, projectRoot, recordPath, title, status, updatedAt}`.

This script never writes anything. It reads the index (one small file per
mission, so the common case stays cheap), joins in each record for the parts the
index lacks - open decisions, run/token totals, labels - and prints the whole
list as a single line of JSON, which is what `watch` reprints whenever any file
under the store changes. One line per snapshot keeps the QML side to a single
`JSON.parse`.

A record that the index still points at but that no longer exists is reported as
`stale` instead of being dropped: a missing record is exactly the thing worth
showing after a retention sweep.

    missions.py [--dir DIR] list
    missions.py [--dir DIR] watch [--interval SECONDS]
"""

import argparse
import json
import os
import sys
import time

TERMINAL = ("completed", "failed", "cancelled", "closed")

# Statuses pi-subagents writes, mapped to what the island shows. Unknown ones
# pass through verbatim, so a newer pi keeps working (just unlabelled) instead
# of silently disappearing or lying about what it means.
LABELS = {
    "planned": "待启动",
    "active": "进行中",
    "needs_decision": "等你回答",
    "needs-attention": "需要你",
    "budget-exhausted": "预算用尽",
    "completed": "已完成",
    "failed": "失败",
    "cancelled": "已取消",
    "closed": "已关闭",
}

# The same tone words the island uses for its pills: accent, urgent, or "" (muted).
TONES = {
    "active": "accent",
    "needs_decision": "urgent",
    "needs-attention": "urgent",
    "budget-exhausted": "urgent",
    "failed": "urgent",
}


def read_json(path):
    try:
        with open(path, encoding="utf-8") as handle:
            return json.load(handle)
    except (OSError, ValueError):
        return None


def index_entries(store):
    """Every pointer in the index, newest first; unreadable ones are skipped."""
    entries = []
    for name in sorted(os.listdir(os.path.join(store, "index"))) if os.path.isdir(
        os.path.join(store, "index")
    ) else []:
        if not name.endswith(".json"):
            continue
        doc = read_json(os.path.join(store, "index", name))
        if isinstance(doc, dict) and doc.get("missionId"):
            entries.append(doc)
    entries.sort(key=lambda d: str(d.get("updatedAt") or ""), reverse=True)
    return entries


def token_total(record):
    """Sum of the per-run token totals, when the record carries them."""
    total = 0
    for run in record.get("runs") or []:
        usage = run.get("usage")
        if isinstance(usage, dict):
            for key in ("totalTokens", "tokens", "total"):
                value = usage.get(key)
                if isinstance(value, (int, float)):
                    total += int(value)
                    break
    return total


def project_name(project_root):
    """The directory name, since a record's title can be `[prompt redacted]`."""
    if not project_root:
        return "?"
    tail = os.path.basename(os.path.normpath(str(project_root)))
    # A home directory normalises to itself; show it as ~ like the island does.
    home = os.path.expanduser("~")
    if project_root == home:
        return "~"
    return tail or str(project_root)


def snapshot(store, done_days=7, limit=40):
    """The whole list as one JSON-ready dict."""
    now = time.time()
    horizon = None if done_days is None or done_days < 0 else now - done_days * 86400
    missions, stale, skipped = [], 0, 0
    for entry in index_entries(store):
        path = str(entry.get("recordPath") or "")
        record = read_json(path) if path else None
        if record is None:
            # The index outlived the record (terminal retention). Say so.
            stale += 1
            record = {}
        # The project record is the source of truth; the index is a pointer that
        # can lag a beat behind, so prefer it and fall back for a missing record.
        status = str(record.get("status") or entry.get("status") or "")
        updated = str(record.get("updatedAt") or entry.get("updatedAt") or "")
        open_questions = [
            str(item.get("title") or item.get("id") or "")
            for item in (record.get("decisions") or [])
            if str(item.get("status") or "open") == "open"
        ]
        if status in TERMINAL and horizon is not None:
            try:
                seen = time.mktime(time.strptime(updated[:19], "%Y-%m-%dT%H:%M:%S"))
            except ValueError:
                seen = None
            if seen is not None and seen < horizon:
                skipped += 1
                continue
        missions.append({
            "id": str(record.get("id") or entry.get("missionId") or ""),
            "title": str(record.get("title") or entry.get("title") or ""),
            "project": project_name(record.get("cwd") or entry.get("projectRoot")),
            "projectRoot": str(record.get("cwd") or entry.get("projectRoot") or ""),
            "status": status,
            "label": LABELS.get(status, status or "未知"),
            "tone": TONES.get(status, ""),
            "terminal": status in TERMINAL,
            "updatedAt": updated,
            "openDecisions": open_questions,
            "runs": len(record.get("runs") or []),
            "children": len(record.get("workflowChildren") or []),
            "tokens": token_total(record),
            "labels": [str(x) for x in (record.get("labels") or [])],
            "summary": str(record.get("summary") or ""),
            "stale": not record,
        })
        if limit > 0 and len(missions) >= limit:
            break
    return {"generatedAt": now, "missions": missions, "stale": stale,
            "skipped": skipped, "store": store}


def emit(store, done_days, limit):
    print(json.dumps(snapshot(store, done_days, limit), ensure_ascii=False), flush=True)


def fingerprint(store):
    """(mtime, size) of every json in the store - cheap enough to poll."""
    stamp = []
    for root, _dirs, files in os.walk(store):
        for name in files:
            if name.endswith(".json"):
                try:
                    info = os.stat(os.path.join(root, name))
                    stamp.append((name, int(info.st_mtime), info.st_size))
                except OSError:
                    pass
    return hash(tuple(sorted(stamp)))


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--dir", default="~/.pi/agent/missions")
    parser.add_argument("--done-days", type=int, default=7,
                        help="已完成/失败的还列多久以内；0 或负数 = 一直列")
    parser.add_argument("--limit", type=int, default=40)
    parser.add_argument("command", choices=["list", "watch"], nargs="?", default="list")
    parser.add_argument("--interval", type=float, default=1.0)
    args = parser.parse_args(argv)

    store = os.path.expanduser(args.dir)
    done_days = args.done_days if args.done_days > 0 else None
    if not os.path.isdir(store):
        # Not an error to have none yet: the island shows the empty state.
        print(json.dumps({"generatedAt": time.time(), "missions": [], "stale": 0,
                          "skipped": 0, "store": store, "missing": True},
                         ensure_ascii=False), flush=True)
        return 0
    if args.command == "list":
        emit(store, done_days, args.limit)
        return 0
    seen = None
    while True:
        stamp = fingerprint(store)
        if stamp != seen:
            seen = stamp
            emit(store, done_days, args.limit)
        time.sleep(args.interval)


if __name__ == "__main__":
    sys.exit(main())
