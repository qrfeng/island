#!/usr/bin/env python3
"""Missions: the island's read-only window onto pi-subagents' durable records.

pi-subagents stores one JSON record per mission under
`~/.pi/agent/missions/projects/<sha256(projectRoot)>/<missionId>.json`, plus a
thin pointer index under `~/.pi/agent/missions/index/<sha>.json` holding
`{schemaVersion, missionId, projectRoot, recordPath, title, status, updatedAt}`.

This script never writes anything. It reads the index (one small file per
mission, so the common case stays cheap), joins in each record for the parts the
index lacks - open decisions, run/token totals, labels, the mission's durable
state - and prints the whole list as a single line of JSON, which is what
`watch` reprints whenever any file under the store changes (the state file lives
in the store too, so a `mission.state.set` wakes it like any other change). One line per snapshot keeps the QML side to a single
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


def run_tokens(run):
    """One run's token total, whichever key the record happened to use."""
    usage = run.get("usage")
    if not isinstance(usage, dict):
        return 0
    for key in ("totalTokens", "tokens", "total"):
        value = usage.get(key)
        if isinstance(value, (int, float)):
            return int(value)
    return 0


def token_total(record):
    """Sum of the per-run token totals, when the record carries them."""
    return sum(run_tokens(run) for run in (record.get("runs") or [])
               if isinstance(run, dict))


def run_list(record, keep=3):
    """The last few runs, oldest first: what the card wants to name out loud.

    A mission can carry dozens of runs after a long goal-mode stretch, and the
    card is a glance, not a log - `mission.show` in pi is the full one.
    """
    out = []
    for run in (record.get("runs") or [])[-keep:]:
        if not isinstance(run, dict):
            continue
        out.append({
            "id": str(run.get("runId") or ""),
            "agent": str(run.get("agent") or ""),
            "status": str(run.get("status") or ""),
            "tokens": run_tokens(run),
            "completedAt": str(run.get("completedAt") or ""),
        })
    return out


# A mission's durable state is the flat {key: value} map the child agents write
# with `mission.state.set`, capped at 256 KiB (MISSION_STATE_MAX_BYTES in
# pi-subagents' src/missions/workflow-state.js). The island previews a few keys;
# the whole map stays one `mission.show` away.
STATE_KEYS_SHOWN = 3
STATE_VALUE_CHARS = 80


def state_path(record_path):
    """`projects/<hash>/<id>.json` -> `projects/<hash>/<id>/state.json`.

    Derived from the record path the index hands us rather than re-derived from
    the project root: pi-subagents keeps the state directory beside the record
    (`missionStatePath`), and hashing the root again would only add a way to
    disagree with it.
    """
    if not record_path:
        return ""
    return os.path.join(os.path.splitext(str(record_path))[0], "state.json")


def state_preview(value):
    """One scannable line; a nested value is counted, not dumped onto the island."""
    if isinstance(value, str):
        text = " ".join(value.split())
    elif value is None or isinstance(value, (bool, int, float)):
        text = json.dumps(value)
    elif isinstance(value, (list, dict, tuple)):
        text = "%d 项" % len(value)
    else:
        text = ""
    if len(text) > STATE_VALUE_CHARS:
        text = text[: STATE_VALUE_CHARS - 1].rstrip() + "…"
    return text


def state_summary(path):
    """{count, bytes, updatedAt, entries:[{key,value}]}, or {} when there is none.

    Most missions never write state at all, so "no state" is the normal answer
    rather than a problem - hence an empty dict instead of a zero count.
    """
    doc = read_json(path) if path else None
    if not isinstance(doc, dict) or not doc:
        return {}
    try:
        info = os.stat(path)
        size, stamp = info.st_size, time.strftime(
            "%Y-%m-%dT%H:%M:%SZ", time.gmtime(info.st_mtime))
    except OSError:
        size, stamp = 0, ""
    entries = []
    for key in sorted(str(k) for k in doc):
        text = state_preview(doc[key])
        if text != "":
            entries.append({"key": key, "value": text})
    return {"count": len(doc), "bytes": size, "updatedAt": stamp,
            "entries": entries[:STATE_KEYS_SHOWN]}


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
        open_questions, open_ids = [], []
        for item in (record.get("decisions") or []):
            if not isinstance(item, dict):
                continue
            if str(item.get("status") or "open") != "open":
                continue
            open_questions.append(str(item.get("title") or item.get("id") or ""))
            # The id is the only handle that survives a redacted title, and it is
            # what `mission.resolve-decision` asks for.
            open_ids.append(str(item.get("id") or ""))
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
            "runList": run_list(record),
            "state": state_summary(state_path(path)),
            # A pi session file path - the same string `herdr agent list` reports
            # as that pane's `agent_session.value`, which is how the view offers a
            # jump without parsing session logs.
            "ownerSessionId": str(record.get("ownerSessionId") or ""),
            "openDecisionIds": open_ids,
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
