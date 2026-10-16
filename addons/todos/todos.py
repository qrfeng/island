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
  todos.py move    --file PATH --line N --to M [--raw LINE]
  todos.py archive --file PATH [--archive-days N] [--archive PATH]
  todos.py watch   --file PATH [--done-days N] [--archive-days N] [--interval SECONDS]

`--done-days` says how far back finished tasks are listed: 0 hides them, a
negative number hides nothing, and 7 is the default (what the addon's "Last 7
days" setting sends). A mutation answers with every task, none hidden, so the
screen that asked sees the line it wrote either way.

`move` puts one open task where another line was, pushing that line and
everything between them along; `--to -1` means the end of the open tasks. Only
open tasks have an order to keep, so a finished line refuses to move - and since
the file holds both kinds at once, moving is said in terms of the line to land
on rather than a position in a filtered list.

`archive` moves finished lines older than `--archive-days` out of the file and
into a `done.txt` beside it (`--archive` says elsewhere), appending them as they
stand. The copy into the archive happens before the line leaves `todo.txt`, so
the worst a crash in between does is leave a line written twice.

Its document:

  {"path", "doneDays", "stamp", "exists", "error", "today",
   "archiveDays", "archivePath", "counts": {"open", "done", "archive"},
   "tasks": [...]}

and a task:

  {"line", "raw", "done", "priority", "body", "projects", "contexts", "tags",
   "createdAt", "doneAt"}

`line` is the line's 0-based place in the file, which is how a task is named
back to `toggle`, `remove`, and `move`; `--raw` says what that line read when it
was drawn on screen, so a task edited in another window in the meantime is
refused rather than aimed at. `counts.archive` is how many finished lines are old
enough to archive, and the archive command adds how many it just moved:

  {"archived": N} Open tasks come back in the order they were written down, which
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

# Where finished tasks go when they stop being a list and become a record.
ARCHIVE_NAME = "done.txt"


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


def append_lines(path, lines):
    """Add lines to the end of another file, as they stand, leaving what it
    already holds alone. Used for the archive, where a finished line keeps the
    exact text it had in the list."""
    if not lines:
        return
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    before = ""
    if os.path.exists(path):
        with open(path, encoding="utf-8") as handle:
            before = handle.read()
    with open(path, "a", encoding="utf-8") as handle:
        if before and not before.endswith("\n"):
            handle.write("\n")
        handle.write("\n".join(lines) + "\n")


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


def stale(task, now, days):
    """A finished task this many days old is a record rather than a reminder, so
    it can leave for the archive. Undated - finished by hand in an editor - stays
    where it is, because there is nothing to say how old it is."""
    if days <= 0 or not task["done"]:
        return False
    done_on = as_date(task["doneAt"])
    return done_on is not None and (now - done_on).days > days


def archive_path_for(path):
    """The done.txt that belongs to a todo.txt: beside it, named for what it is."""
    full = os.path.abspath(os.path.expanduser(path))
    return os.path.join(os.path.dirname(full), ARCHIVE_NAME)


def document(path, now, done_days, error=None, archive_days=0, archive_path=""):
    lines = read_lines(path)
    open_ = []
    done = []
    archivable = 0
    for number, line in enumerate(lines):
        if not line.strip():
            continue
        task = parse_line(number, line)
        if not task["done"]:
            open_.append(task)
            continue
        if stale(task, now, archive_days):
            archivable += 1
        if shown(task, now, done_days):
            done.append(task)
    # Down the page: what's still to do in the order it was written, and the
    # finished ones newest first under them.
    done.sort(key=lambda t: (_flipped(t["doneAt"]), t["line"]))
    tasks = open_ + done
    for task in tasks:
        task.pop("tail", None)
    return {"path": os.path.abspath(os.path.expanduser(path)), "doneDays": done_days,
            "stamp": stamp_of(path), "exists": os.path.exists(path), "error": error,
            "today": iso(now), "archiveDays": archive_days,
            "archivePath": archive_path or archive_path_for(path),
            "counts": {"open": len(open_), "done": len(done), "archive": archivable},
            "tasks": tasks}


def _flipped(text):
    """A date string turned into one that sorts newest first."""
    if not as_date(text):
        return ""
    return "%04d-%02d-%02d" % tuple(9999 - int(part) for part in text.split("-"))


def mutate(path, change, done_days=-1, archive_days=0, archive_path="", rescue=None):
    """Change one line (or add one, or move one) and hand back the list as it now
    reads.

    The stamp is checked again before writing: this addon and a terminal editor
    both own the file, and a write that would land on top of a change it never
    read is refused instead of quietly losing that change.

    `rescue(change)` runs between that check and the write, for the changes that
    take lines out of the file and should copy them somewhere first.
    """
    now = today()
    try:
        before = stamp_of(path)
        lines = read_lines(path)
        changed = change(lines)
        if stamp_of(path) != before:
            return document(path, now, done_days, archive_days=archive_days,
                            archive_path=archive_path,
                            error="\u6587\u4ef6\u521a\u624d\u88ab\u6539\u8fc7\uff0c\u8bf7\u518d\u8bd5\u4e00\u6b21")
        if rescue:
            rescue(change)
        save_lines(path, changed)
        return document(path, now, done_days, archive_days=archive_days,
                        archive_path=archive_path)
    except (OSError, IndexError, ValueError) as error:
        return document(path, now, done_days, error=str(error),
                        archive_days=archive_days, archive_path=archive_path)


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


def change_move(number, to, raw=None):
    """Move an open task to where line `to` was; -1 is after the last open one.

    Done tasks and blank lines keep their places, so the task lands among the
    open ones either way: the line it is aimed at is always an open task from the
    same reading, or -1.
    """
    def change(lines):
        task = parse_line(number, lines[number])
        if raw is not None and task["raw"] != raw:
            raise IndexError("line %d has changed since it was read" % number)
        if task["done"]:
            raise ValueError("a finished task keeps its place")
        open_at = [n for n, line in enumerate(lines)
                   if line.strip() and not parse_line(n, line)["done"]]
        if to == -1:
            at = open_at[-1] + 1
        elif to == number:
            return lines
        else:
            at = to
        line = lines.pop(number)
        if at > number:
            at -= 1
        lines.insert(max(0, min(at, len(lines))), line)
        return lines
    return change


def change_archive(days):
    """Take out every finished line older than `days`, and leave it in
    `change.moved` for whoever is keeping the archive."""
    def change(lines):
        now = today()
        keep = []
        moved = []
        for number, line in enumerate(lines):
            task = parse_line(number, line) if line.strip() else None
            if task is not None and stale(task, now, days):
                moved.append(line)
            else:
                keep.append(line)
        change.moved = moved
        return keep
    change.moved = []
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


def command_watch(args, path, archive_days, archive):
    now = today()
    last = None
    while True:
        # A new day can change what's listed even when the file hasn't - the
        # finished ones age out and the archivable count grows - so it's worth
        # printing again.
        if today() != now:
            now, last = today(), None
        stamp = stamp_of(path)
        if stamp != last:
            last = stamp
            emit(document(path, now, args.done_days, archive_days=archive_days,
                          archive_path=archive))
        time.sleep(max(0.2, args.interval))


def command_archive(path, archive, days, done_days):
    """Finished lines older than `days` go into the archive file. Copy first,
    then delete, so nothing is only ever in one place by an accident."""
    box = {}

    def rescue(change):
        box["n"] = len(change.moved)
        append_lines(archive, change.moved)

    if days <= 0:
        return document(path, today(), done_days, archive_days=days, archive_path=archive,
                        error="\u5f52\u6863\u6ca1\u6709\u6253\u5f00")
    doc = mutate(path, change_archive(days), done_days, archive_days=days,
                 archive_path=archive, rescue=rescue)
    if "n" in box:
        doc["archived"] = box["n"]
    return doc


def main(argv=None):
    parser = argparse.ArgumentParser(prog="todos.py",
                                     description="todo.txt for Island's Task list addon")
    parser.add_argument("--file", default="~/.local/share/todos/todo.txt")
    parser.add_argument("--done-days", type=int, default=7)
    parser.add_argument("--archive-days", type=int, default=0,
                        help="finished tasks older than this are worth archiving; 0 is off")
    parser.add_argument("--archive", default="",
                        help="where finished tasks are filed away; a done.txt beside --file")
    every = parser.add_subparsers(dest="command", required=True)

    every.add_parser("list")
    add = every.add_parser("add")
    add.add_argument("--text", required=True)
    for name in ("toggle", "remove"):
        one = every.add_parser(name)
        one.add_argument("--line", type=int, required=True)
        one.add_argument("--raw", help="only act if that line still reads this")
    mover = every.add_parser("move")
    mover.add_argument("--line", type=int, required=True)
    mover.add_argument("--to", type=int, required=True,
                       help="line to land on, or -1 for the end of the open tasks")
    mover.add_argument("--raw")
    every.add_parser("archive")
    watch = every.add_parser("watch")
    watch.add_argument("--interval", type=float, default=1.0)

    args = parser.parse_args(argv)
    path = os.path.expanduser(args.file)
    archive = os.path.expanduser(args.archive) if args.archive else archive_path_for(path)

    if args.command == "list":
        emit(document(path, today(), args.done_days, archive_days=args.archive_days,
                      archive_path=archive))
    elif args.command == "add":
        emit(mutate(path, change_add(args.text), archive_days=args.archive_days,
                    archive_path=archive))
    elif args.command == "toggle":
        emit(mutate(path, change_toggle(args.line, args.raw),
                    archive_days=args.archive_days, archive_path=archive))
    elif args.command == "remove":
        emit(mutate(path, change_remove(args.line, args.raw),
                    archive_days=args.archive_days, archive_path=archive))
    elif args.command == "move":
        emit(mutate(path, change_move(args.line, args.to, args.raw),
                    archive_days=args.archive_days, archive_path=archive))
    elif args.command == "archive":
        emit(command_archive(path, archive, args.archive_days, args.done_days))
    else:
        command_watch(args, path, args.archive_days, archive)
    return 0


if __name__ == "__main__":
    sys.exit(main())
