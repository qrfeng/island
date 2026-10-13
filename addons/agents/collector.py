#!/usr/bin/env python3
"""Agent usage: Pi's token figures, plus everything else Omarchy records.

Pi writes no usage record anywhere but its session transcripts, and Omarchy's
own collectors only count a Pi session when it ran on an Anthropic provider
(their point is "did this burn my Claude subscription"). This reads the same
session files and counts all of them.

It plays both roles Omarchy's Agents panel is built around:

  collector  it writes one usage record, in Omarchy's own contract, to
             ~/.local/state/omarchy/agents/usage/pi.json, so Omarchy's panel
             gains a "Pi" tab without either side knowing about the other.
  display    with --print it merges every record in that directory - Pi's and
             the ones `omarchy agent usage update` writes for Claude, Codex,
             and Fireworks - into one line of JSON on stdout, reduced to what
             the island draws. That line is the addon's whole data contract.

Costs in the transcripts are US dollars, what the endpoints bill in; --rate
carries a USD->CNY figure into the `costCny` fields the island draws, so the
panel can show the money in yuan.

With --others it also runs `omarchy agent usage update` and keeps its records:
that asks Anthropic
and Codex for their rate limits over the network; off by default because those
round trips are slow and this machine has neither signed in.

Every figure here comes from what the CLIs already wrote to disk; nothing is
posted anywhere. Session format: one JSON object per line, and the ones that
carry usage are
{"type":"message","timestamp":"...","message":{"role":"assistant",
 "provider":"...","model":"...","usage":{"input":N,"output":N,
 "cacheRead":N,"cacheWrite":N,"totalTokens":N,"cost":{"total":N}}}}
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import subprocess
import sys
from pathlib import Path
from typing import Any

# Session roots: Pi's, and omp's, which writes the same format (Omarchy's own
# collectors read these two together).
SESSION_ROOTS = ["~/.pi/agent/sessions", "~/.omp/agent/sessions"]
RECENT_DAYS = 7


def home() -> Path:
  return Path(os.path.expanduser("~"))


def usage_dir() -> Path:
  root = Path(os.environ.get("XDG_STATE_HOME") or home() / ".local" / "state")
  path = root / "omarchy" / "agents" / "usage"
  path.mkdir(parents=True, exist_ok=True)
  return path


def day_string(day: dt.date) -> str:
  return day.strftime("%Y-%m-%d")


def local_day_of(raw: Any) -> str:
  """Local calendar day of a transcript timestamp ("...Z" is UTC)."""
  text = str(raw or "").strip()
  if not text:
    return day_string(dt.datetime.now().date())
  try:
    if text.endswith("Z"):
      text = text[:-1] + "+00:00"
    moment = dt.datetime.fromisoformat(text)
    if moment.tzinfo is not None:
      moment = moment.astimezone().replace(tzinfo=None)
    return day_string(moment.date())
  except ValueError:
    return day_string(dt.datetime.now().date())


def number(value: Any) -> int:
  try:
    return int(float(value))
  except (TypeError, ValueError):
    return 0


def money(value: Any) -> float:
  try:
    return float(value)
  except (TypeError, ValueError):
    return 0.0


def project_label(cwd: str, path: Path) -> str:
  """Where a session ran, short: its folder name, or the directory itself."""
  cwd = str(cwd or "").rstrip("/")
  if cwd:
    return cwd.rsplit("/", 1)[-1] or cwd
  # "--home-user-projects-app--" decodes back to a path.
  folder = path.parent.name.strip("-")
  return folder.replace("--", "/").rsplit("/", 1)[-1] or folder or "other"


def scan_sessions(roots: list[str]) -> dict[str, Any]:
  """Every assistant turn with a usage block in Pi's and omp's sessions."""
  today = day_string(dt.datetime.now().date())
  recent_dates = [
    day_string(dt.datetime.now().date() - dt.timedelta(days=offset))
    for offset in range(RECENT_DAYS - 1, -1, -1)
  ]
  recent = {day: {"date": day, "messageCount": 0} for day in recent_dates}
  models: dict[str, dict[str, int]] = {}
  today_models: dict[str, int] = {}
  costs: dict[str, float] = {}
  providers: dict[str, dict[str, Any]] = {}
  projects: dict[str, dict[str, Any]] = {}
  seen: set[str] = set()
  sessions: set[str] = set()
  today_sessions: set[str] = set()
  active_days: set[str] = set()
  prompts = 0
  today_prompts = 0
  today_tokens = 0
  cost_total = 0.0
  today_cost = 0.0
  files = 0

  for raw_root in roots:
    root = Path(os.path.expanduser(raw_root))
    if not root.is_dir():
      continue
    for path in sorted(root.rglob("*.jsonl")):
      files += 1
      cwd = ""
      try:
        handle = path.open("r", encoding="utf-8", errors="replace")
      except OSError:
        continue
      with handle:
        for line_number, line in enumerate(handle, 1):
          if line.lstrip().startswith('{"type":"session"'):
            try:
              cwd = str(json.loads(line).get("cwd") or "")
            except ValueError:
              pass
            continue
          if '"usage"' not in line or '"assistant"' not in line:
            continue
          try:
            entry = json.loads(line)
          except ValueError:
            continue
          message = entry.get("message") if isinstance(entry.get("message"), dict) else {}
          if entry.get("type") != "message" or message.get("role") != "assistant":
            continue
          usage = message.get("usage") if isinstance(message.get("usage"), dict) else {}
          key = "%s:%s" % (path, entry.get("id") or line_number)
          if key in seen:
            continue
          input_tokens = number(usage.get("input", usage.get("inputTokens")))
          output_tokens = number(usage.get("output", usage.get("outputTokens")))
          cache_read = number(usage.get("cacheRead", usage.get("cache_read_input_tokens")))
          cache_write = number(usage.get("cacheWrite", usage.get("cache_creation_input_tokens")))
          total = input_tokens + output_tokens + cache_read + cache_write
          if total <= 0:
            total = number(usage.get("totalTokens"))
            if total <= 0:
              continue
            input_tokens = total
          seen.add(key)
          model = str(message.get("model") or "unknown")
          provider = str(message.get("provider") or "unknown")
          day = local_day_of(entry.get("timestamp") or message.get("timestamp"))
          cost = money((usage.get("cost") or {}).get("total"))

          bucket = models.setdefault(
            model,
            {
              "inputTokens": 0,
              "outputTokens": 0,
              "cacheReadInputTokens": 0,
              "cacheCreationInputTokens": 0,
            },
          )
          bucket["inputTokens"] += input_tokens
          bucket["outputTokens"] += output_tokens
          bucket["cacheReadInputTokens"] += cache_read
          bucket["cacheCreationInputTokens"] += cache_write
          costs[model] = costs.get(model, 0.0) + cost

          for table, name in ((providers, provider), (projects, project_label(cwd, path))):
            row = table.setdefault(
              name, {"tokens": 0, "prompts": 0, "cost": 0.0, "sessions": set()}
            )
            row["tokens"] += total
            row["prompts"] += 1
            row["cost"] += cost
            row["sessions"].add(str(path))

          sessions.add(str(path))
          active_days.add(day)
          prompts += 1
          cost_total += cost
          if day in recent:
            # recentDays.messageCount is a token total despite the legacy
            # name, the same way Omarchy's own records spell it.
            recent[day]["messageCount"] += total
          if day == today:
            today_prompts += 1
            today_tokens += total
            today_cost += cost
            today_sessions.add(str(path))
            today_models[model] = today_models.get(model, 0) + total

  return {
    "todayPrompts": today_prompts,
    "todaySessions": len(today_sessions),
    "todayTotalTokens": today_tokens,
    "todayTokensByModel": today_models,
    "recentDays": [recent[day] for day in recent_dates],
    "modelUsage": models,
    "totalPrompts": prompts,
    "totalSessions": len(sessions),
    "activeDays": len(active_days),
    "activeDates": sorted(active_days),
    "todayCostUsd": round(today_cost, 6),
    "totalCostUsd": round(cost_total, 6),
    "costByModel": {model: round(value, 6) for model, value in costs.items()},
    "byProvider": sorted(
      (
        {
          "name": name,
          "tokens": row["tokens"],
          "prompts": row["prompts"],
          "sessions": len(row["sessions"]),
          "costUsd": round(row["cost"], 6),
        }
        for name, row in providers.items()
      ),
      key=lambda row: -row["tokens"],
    ),
    "byProject": sorted(
      (
        {
          "name": name,
          "tokens": row["tokens"],
          "prompts": row["prompts"],
          "sessions": len(row["sessions"]),
          "costUsd": round(row["cost"], 6),
        }
        for name, row in projects.items()
      ),
      key=lambda row: -row["tokens"],
    )[:12],
    "sessionFiles": files,
  }


def main() -> int:
  parser = argparse.ArgumentParser()
  parser.add_argument("--print", dest="print_merged", action="store_true")
  parser.add_argument("--others", action="store_true")
  parser.add_argument("--rate", type=float, default=6.69)
  args = parser.parse_args()
  rate = args.rate if args.rate > 0 else 6.69

  stats = scan_sessions(SESSION_ROOTS)
  record = {
    "schemaVersion": 1,
    "id": "pi",
    "name": "Pi",
    "updatedAt": dt.datetime.now(dt.timezone.utc).isoformat(),
    "ready": stats["totalPrompts"] > 0,
    "hasLocalStats": True,
    "scope": "cli",
    "tierLabel": "local sessions",
    "limits": [],
    "usageStatusText": "" if stats["totalPrompts"] else "No Pi sessions yet",
    "authHelpText": "",
  }
  record.update(stats)
  # Yuan, for the island: the transcripts speak dollars because that is what
  # the endpoints bill in, and one rate converts the lot (--rate, adjustable in
  # Settings > Addons > Agent usage).
  record["todayCostCny"] = round(stats["todayCostUsd"] * rate, 4)
  record["totalCostCny"] = round(stats["totalCostUsd"] * rate, 4)
  record["costByModelCny"] = {
    model: round(value * rate, 4) for model, value in (stats.get("costByModel") or {}).items()
  }
  for table in ("byProvider", "byProject"):
    for row in stats.get(table) or []:
      row["costCny"] = round(row["costUsd"] * rate, 4)

  target = usage_dir() / "pi.json"
  tmp = target.with_suffix(".json.tmp")
  tmp.write_text(json.dumps(record, separators=(",", ":")), encoding="utf-8")
  tmp.replace(target)

  if not args.print_merged:
    print(json.dumps(record, separators=(",", ":")))
    return 0

  if args.others:
    # Omarchy's own collectors, so Claude, Codex, and Fireworks show up too.
    # Their limits come over the network, so this is off unless asked for, and
    # never gets to hang the view.
    try:
      subprocess.run(
        ["omarchy", "agent", "usage", "update"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        timeout=25,
        check=False,
      )
    except (OSError, subprocess.SubprocessError):
      pass

  records = []
  for path in sorted(usage_dir().glob("*.json")):
    try:
      data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
      continue
    if not isinstance(data, dict) or not data.get("id"):
      continue
    usage = data.get("modelUsage") or {}
    all_time = 0
    for bucket in usage.values():
      if not isinstance(bucket, dict):
        continue
      total = sum(number(bucket.get(key)) for key in (
        "inputTokens", "outputTokens", "cacheReadInputTokens", "cacheCreationInputTokens"))
      all_time += total or number(bucket.get("totalTokens"))
    if not all_time:
      all_time = sum(number(day.get("messageCount")) for day in data.get("recentDays") or [])
    records.append(
      {
        "id": str(data.get("id")),
        "name": str(data.get("name") or data.get("id")),
        "ready": bool(data.get("ready")),
        "tierLabel": str(data.get("tierLabel") or ""),
        "usageStatusText": str(data.get("usageStatusText") or ""),
        "authHelpText": str(data.get("authHelpText") or ""),
        "updatedAt": str(data.get("updatedAt") or ""),
        "todayPrompts": number(data.get("todayPrompts")),
        "todaySessions": number(data.get("todaySessions")),
        "todayTotalTokens": number(data.get("todayTotalTokens")),
        "todayCostUsd": money(data.get("todayCostUsd")),
        "totalCostUsd": money(data.get("totalCostUsd")),
        "todayCostCny": money(data.get("todayCostCny")),
        "totalCostCny": money(data.get("totalCostCny")),
        "recentDays": [
          {"date": str(day.get("date") or ""), "tokens": number(day.get("messageCount"))}
          for day in data.get("recentDays") or []
          if isinstance(day, dict)
        ],
        "models": sorted(
          (
            {
              "name": str(model),
              "tokens": sum(number(bucket.get(key)) for key in (
                "inputTokens", "outputTokens", "cacheReadInputTokens",
                "cacheCreationInputTokens")) or number(bucket.get("totalTokens")),
              "inputTokens": number(bucket.get("inputTokens")),
              "outputTokens": number(bucket.get("outputTokens")),
              "cacheReadTokens": number(bucket.get("cacheReadInputTokens")),
              "cacheWriteTokens": number(bucket.get("cacheCreationInputTokens")),
              "costUsd": money((data.get("costByModel") or {}).get(model)),
              "costCny": money((data.get("costByModelCny") or {}).get(model)),
            }
            for model, bucket in usage.items()
            if isinstance(bucket, dict)
          ),
          key=lambda row: -row["tokens"],
        )[:10],
        "byProvider": data.get("byProvider") or [],
        "byProject": data.get("byProject") or [],
        "limits": [
          {
            "label": str(limit.get("label") or "Limit"),
            "percent": money(limit.get("percent")),
            "resetsAt": str(limit.get("resetsAt") or ""),
          }
          for limit in data.get("limits") or []
          if isinstance(limit, dict)
        ],
        "totalPrompts": number(data.get("totalPrompts")),
        "totalSessions": number(data.get("totalSessions")),
        "activeDays": number(data.get("activeDays")),
        "allTimeTokens": all_time,
      }
    )
  if not args.others:
    # Everything but Pi is another tool's subscription, and its collector only
    # speaks for itself: with no Claude or Codex signed in, those tabs are
    # empty noise. --others brings them back.
    records = [own for own in records if own["id"] == "pi"]
  records.sort(key=lambda row: (-row["allTimeTokens"], row["name"]))
  print(json.dumps({"generatedAt": dt.datetime.now().isoformat(), "agents": records},
                   separators=(",", ":")))
  return 0


if __name__ == "__main__":
  sys.exit(main())
