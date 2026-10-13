#!/usr/bin/env python3
"""todo.txt for Island's Task list addon.

The file is the whole point. Everything shown is what the format holds - an
(A)-(D) priority, the (x) marker and its dates, +projects, @contexts and
key:value tags - and the same file stays open in an editor, a `todo.sh`, or a
phone app without this addon having anything to say about it. Nothing is stored
anywhere else, and a line this script isn't asked to change is written back byte
for byte.

One command per run, printing one JSON document on stdout (watch: one per
change), so the QML side only has to JSON.parse a line:

  todos.py list    --file PATH [--done-days N]
  todos.py add     --file PATH --text TEXT
  todos.py toggle  --file PATH --line N [--raw LINE]
  todos.py remove  --file PATH --line N [--raw LINE]
  todos.py watch   --file PATH [--done-days N] [--interval SECONDS]

`--done-days` says how far back finished tasks are listed: 0 hides them, a
negative number hides nothing, and 7 is the default (what the addon's "Last 7
days" setting sends). A mutation answers with every task, none hidden, so the
screen that asked sees the line it wrote either way.

Its document:

  {"path", "doneDays", "stamp", "exists", "error", "today",
   "counts": {"open", "done"}, "tasks": [...]}

and a task:

  {"line", "raw", "done", "priority", "body", "projects", "contexts", "tags",
   "createdAt", "doneAt"}

`line` is the line's 0-based place in the file, which is how a task is named
back to `toggle` and `remove`; `--raw` says what that line read when it was drawn
on screen, so a task edited in another window in the meantime is refused rather
than aimed at. Open tasks come back in the order they were written down, which
is the order someone means when they jot a list.
"""

import argparse
import json
import os
import re
import sys
import time
from datetime import date

# The format's pieces. (x) is completion, so a priority letter is only ever A-D.
PRIORITY_MARK = re.compile(r"^\(([A-Da-d])\)\s+")
DONE_MARK = re.compile(r"^\([xX]\)\s+")
DATE = r"\d{4}-\d{2}-\d{2}"
LEAD_DATES = re.compile(r"^(%s)(?:\s+(%s))?\s+" % (DATE, DATE))
PROJECT = re.compile(r"(?:^|\s)\+(\S+)")
CONTEXT = re.compile(r"(?:^|\s)@(\S+)")
# key:value, but not a URL: a value may not start with a slash.
TAG = re.compile(r"(?:^|\s)([A-Za-z][\w-]*):([^\s/][^\s:]*)")

# A (D) is todo.txt's lowest; the letters come first because the format says so.
PRIORITY_OF = {"1": "A", "2": "B", "3": "C", "4": "D"}
LETTER_OF = {v: k for k, v in PRIORITY_OF.items()}


def today():
    return date.today()


def iso(day):
    return day.isoformat() if day else ""


def as_date(text):
    """A `2026-10-13` string as a date, or None."""
    try:
        return date.fromisoformat(str(text))
    except ValueError:
        return None


def parse_line(number, line):
    """A line of the file as a task, keeping `raw` for the round trip."""
    raw = line.rstrip("\n").rstrip("\r")
    rest = raw
    priority = ""
    mark = PRIORITY_MARK.match(rest)
    if mark:
        priority = mark.group(1).upper()
        rest = rest[mark.end():]
    done = False
    mark = DONE_MARK.match(rest)
    if mark:
        done = True
        rest = rest[mark.end():]
    created = done_at = ""
    dates = LEAD_DATES.match(rest)
    if dates:
        first, second = dates.group(1), dates.group(2)
        if done:
            done_at, created = first, second or ""
        else:
            created = first
        rest = rest[dates.end():]
    tags = {k.lower(): v for k, v in TAG.findall(rest)}
    body = TAG.sub(" ", rest)
    body = re.sub(r"(?:^|\s)(?:\+\S+|@\S+)", " ", body)
    body = re.sub(r"\s+", " ", body).strip()
    if not priority:
        priority = PRIORITY_OF.get(tags.get("p", ""), "")
    return {"line": number, "raw": raw, "done": done, "priority": priority,
            "body": body, "projects": PROJECT.findall(rest),
            "contexts": CONTEXT.findall(rest), "tags": tags,
            "createdAt": created if as_date(created) else "",
            "doneAt": done_at if as_date(done_at) else "",
            # What is left after the marker and the dates: the round trip writes
            # this back untouched, so spacing and any tag this script doesn't
            # know about survive a finish-and-reopen.
            "tail": rest}


def rebuild(task, done):
    """A task's line again, as the format wants it ordered.

    Finishing one keeps a priority by moving it into a `p:` tag - the format
    lets a line carry the (x) mark or an (A) priority, not both - and opening one
    up puts the letter back and drops the tag, which is how a line finished
    earlier was left without one.
    """
    tail = task["tail"]
    if done:
        parts = ["(x)"]
        dates = [iso(today()), task["createdAt"]]
        if task["priority"] and "p" not in task["tags"]:
            tail = (tail + " p:" + LETTER_OF[task["priority"]]).strip()
    else:
        if PRIORITY_OF.get(task["tags"].get("p", "")) == task["priority"]:
            tail = re.sub(r"(^|\s)p:[1-4](?=\s|$)", " ", tail)
            tail = re.sub(r"\s+", " ", tail).strip()
        parts = ["(%s)" % task["priority"]] if task["priority"] else []
        dates = [task["createdAt"]]
    return " ".join([p for p in parts + dates + [tail] if p])


def normalize(text):
    """New task text as a line: tidied, and a `p:1` made into an (A) mark."""
    text = re.sub(r"\s+", " ", str(text).strip())
    if not text:
        return ""
    # Where a priority mark is already written it wins, and the tag - which
    # would only be a second say - goes.
    box = {"priority": ""}

    def take_priority(match):
        box["priority"] = PRIORITY_OF.get(match.group(2), "")
        return "" if box["priority"] else match.group(0)

    text = re.sub(r"(?i)(^|\s)p\s*[:=]\s*([1-4])(?=\s|$)", take_priority, text)
    text = re.sub(r"\s+", " ", text).strip()
    if box["priority"] and not PRIORITY_MARK.match(text):
        text = "(%s) %s" % (box["priority"], text)
    return text


# ---------- the file ----------

def stamp_of(path):
    try:
        stat = os.stat(path)
    except OSError:
        return "missing"
    return "%d:%d" % (stat.st_mtime_ns, stat.st_size)


def read_lines(path):
    """The file's lines; no file yet is an empty list."""
    try:
        with open(path, encoding="utf-8") as handle:
            return handle.read().splitlines()
    except FileNotFoundError:
        return []


def save_lines(path, lines):
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    body = "\n".join(lines).rstrip("\n")
    tmp = os.path.abspath(path) + ".tmp"
    with open(tmp, "w", encoding="utf-8") as handle:
        handle.write(body + "\n" if body else "")
    os.replace(tmp, path)


def shown(task, now, done_days):
    """Whether a finished task is still worth a place in the list. A finished
    line with no completion date - closed by hand in an editor - counts as
    recent."""
    if not task["done"]:
        return True
    if done_days < 0:
        return True
    if done_days == 0:
        return False
    done_on = as_date(task["doneAt"])
    return done_on is None or (now - done_on).days <= done_days


def document(path, now, done_days, error=None):
    lines = read_lines(path)
    open_ = []
    done = []
    for number, line in enumerate(lines):
        if not line.strip():
            continue
        task = parse_line(number, line)
        if not task["done"]:
            open_.append(task)
        elif shown(task, now, done_days):
            done.append(task)
    # Down the page: what's still to do in the order it was written, and the
    # finished ones newest first under them.
    done.sort(key=lambda t: (_flipped(t["doneAt"]), t["line"]))
    tasks = open_ + done
    for task in tasks:
        task.pop("tail", None)
    return {"path": os.path.abspath(os.path.expanduser(path)), "doneDays": done_days,
            "stamp": stamp_of(path), "exists": os.path.exists(path), "error": error,
            "today": iso(now), "counts": {"open": len(open_), "done": len(done)},
            "tasks": tasks}


def _flipped(text):
    """A date string turned into one that sorts newest first."""
    if not as_date(text):
        return ""
    return "%04d-%02d-%02d" % tuple(9999 - int(part) for part in text.split("-"))


def mutate(path, change, done_days=-1):
    """Change one line (or add one) and hand back the list as it now reads.

    The stamp is checked again before writing: this addon and a terminal editor
    both own the file, and a write that would land on top of a change it never
    read is refused instead of quietly losing that change.
    """
    now = today()
    try:
        before = stamp_of(path)
        lines = read_lines(path)
        changed = change(lines)
        if stamp_of(path) != before:
            return document(path, now, done_days,
                            error="\u6587\u4ef6\u521a\u624d\u88ab\u6539\u8fc7\uff0c\u8bf7\u518d\u8bd5\u4e00\u6b21")
        save_lines(path, changed)
        return document(path, now, done_days)
    except (OSError, IndexError, ValueError) as error:
        return document(path, now, done_days, error=str(error))


def change_toggle(number, raw=None):
    def change(lines):
        task = parse_line(number, lines[number])
        if raw is not None and task["raw"] != raw:
            raise IndexError("line %d has changed since it was read" % number)
        lines[number] = rebuild(task, not task["done"])
        return lines
    return change


def change_remove(number, raw=None):
    def change(lines):
        if raw is not None and lines[number].rstrip("\n") != raw:
            raise IndexError("line %d has changed since it was read" % number)
        del lines[number]
        return lines
    return change


def change_add(text):
    def change(lines):
        line = normalize(text)
        if not line:
            raise ValueError("nothing to add")
        at = 0
        for index, own in enumerate(lines):
            if own.strip():
                at = index + 1
        lines.insert(at, line)
        return lines
    return change


def emit(doc):
    sys.stdout.write(json.dumps(doc, ensure_ascii=False, separators=(",", ":")) + "\n")
    sys.stdout.flush()


def command_watch(args, path):
    now = today()
    last = None
    while True:
        # A new day can change what's listed even when the file hasn't, so it's
        # worth printing again.
        if today() != now:
            now, last = today(), None
        stamp = stamp_of(path)
        if stamp != last:
            last = stamp
            emit(document(path, now, args.done_days))
        time.sleep(max(0.2, args.interval))


def main(argv=None):
    parser = argparse.ArgumentParser(prog="todos.py",
                                     description="todo.txt for Island's Task list addon")
    parser.add_argument("--file", default="~/.local/share/todos/todo.txt")
    parser.add_argument("--done-days", type=int, default=7)
    every = parser.add_subparsers(dest="command", required=True)

    every.add_parser("list")
    add = every.add_parser("add")
    add.add_argument("--text", required=True)
    for name in ("toggle", "remove"):
        one = every.add_parser(name)
        one.add_argument("--line", type=int, required=True)
        one.add_argument("--raw", help="only act if that line still reads this")
    watch = every.add_parser("watch")
    watch.add_argument("--interval", type=float, default=1.0)

    args = parser.parse_args(argv)
    path = os.path.expanduser(args.file)

    if args.command == "list":
        emit(document(path, today(), args.done_days))
    elif args.command == "add":
        emit(mutate(path, change_add(args.text)))
    elif args.command == "toggle":
        emit(mutate(path, change_toggle(args.line, args.raw)))
    elif args.command == "remove":
        emit(mutate(path, change_remove(args.line, args.raw)))
    else:
        command_watch(args, path)
    return 0


if __name__ == "__main__":
    sys.exit(main())
