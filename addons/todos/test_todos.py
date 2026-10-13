#!/usr/bin/env python3
"""Tests for todos.py. No pytest here, so: python3 test_todos.py"""

import json
import os
import subprocess
import sys
import tempfile
import unittest
from datetime import date

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import todos  # noqa: E402

NOW = date(2026, 10, 13)
HERE = os.path.dirname(os.path.abspath(__file__))
CLI = os.path.join(HERE, "todos.py")


def parse(line, number=0):
    return todos.parse_line(number, line)


class Parse(unittest.TestCase):
    def test_plain(self):
        task = parse("Buy milk")
        self.assertEqual((task["body"], task["done"], task["priority"]), ("Buy milk", False, ""))
        self.assertEqual((task["projects"], task["contexts"], task["tags"]), ([], [], {}))

    def test_priority_dates_and_word_lists(self):
        task = parse("(A) 2026-09-01 Fix the sink +Kitchen @plumbing due:2026-10-11")
        self.assertEqual(task["priority"], "A")
        self.assertEqual(task["createdAt"], "2026-09-01")
        self.assertEqual(task["projects"], ["Kitchen"])
        self.assertEqual(task["contexts"], ["plumbing"])
        # A tag this addon has no use for is still read and left alone.
        self.assertEqual(task["tags"]["due"], "2026-10-11")
        self.assertEqual(task["body"], "Fix the sink")

    def test_done_keeps_both_dates(self):
        task = parse("(x) 2026-10-12 2026-09-01 Ship it")
        self.assertTrue(task["done"])
        self.assertEqual(task["doneAt"], "2026-10-12")
        self.assertEqual(task["createdAt"], "2026-09-01")
        self.assertEqual(task["body"], "Ship it")

    def test_a_url_is_not_a_tag(self):
        task = parse("Read https://todotxt.org tonight")
        self.assertEqual(task["tags"], {})
        self.assertIn("https://todotxt.org", task["body"])

    def test_rubbish_dates_are_dropped_but_the_line_is_kept(self):
        task = parse("(A) not-a-date Fix")
        self.assertEqual(task["createdAt"], "")
        self.assertEqual(task["tail"], "not-a-date Fix")

    def test_priority_from_a_tag_only(self):
        self.assertEqual(parse("Tidy p:2")["priority"], "B")


class Normalize(unittest.TestCase):
    def test_spaces_are_tidied(self):
        self.assertEqual(todos.normalize("  fix\n\tthis   now "), "fix this now")
        self.assertEqual(todos.normalize("   "), "")

    def test_p_becomes_a_priority_mark(self):
        self.assertEqual(todos.normalize("p:1 Fix the sink"), "(A) Fix the sink")
        self.assertEqual(todos.normalize("Fix p:3 due:2026-10-20"),
                         "(C) Fix due:2026-10-20")
        # Already a priority mark: it wins and the redundant tag goes.
        self.assertEqual(todos.normalize("(C) p:1 Fix"), "(C) Fix")

    def test_a_line_is_written_once(self):
        self.assertEqual(todos.normalize("Buy milk +Shop @errands"), "Buy milk +Shop @errands")


class RoundTrip(unittest.TestCase):
    def setUp(self):
        self.folder = tempfile.TemporaryDirectory()
        self.path = os.path.join(self.folder.name, "todo.txt")
        self.addCleanup(self.folder.cleanup)

    def write(self, line):
        with open(self.path, "w", encoding="utf-8") as handle:
            handle.write(line + "\n")

    def read(self):
        return todos.read_lines(self.path)

    def save(self, change):
        todos.save_lines(self.path, change(self.read()))

    def check(self, line):
        """Finish an open line and open it up again: it comes back as it was."""
        self.write(line)
        self.save(todos.change_toggle(0, line))
        self.assertTrue(parse(self.read()[0])["done"], self.read()[0])
        self.save(todos.change_toggle(0, self.read()[0]))
        self.assertEqual(self.read()[0], line)

    def test_plain_round_trip(self):
        self.check("Buy milk +Shop")

    def test_priority_and_creation_round_trip(self):
        self.check("(A) 2026-09-01 Fix the sink +Kitchen due:2026-10-11")

    def test_odd_spacing_round_trip(self):
        self.check("Keep\tthis   exactly  +as@it  is")

    def test_finishing_keeps_a_priority_as_a_tag(self):
        self.write("(B) 2026-09-01 Fix the sink")
        self.save(todos.change_toggle(0))
        line = self.read()[0]
        self.assertTrue(line.startswith("(x) %s 2026-09-01 Fix the sink" % todos.iso(todos.today())), line)
        self.assertIn("p:2", line)

    def test_opening_a_finished_line(self):
        """Opened up and finished again: its day changes, its history doesn't."""
        self.write("(x) 2026-10-12 2026-09-01 Ship it p:1")
        self.save(todos.change_toggle(0))
        self.assertEqual(self.read()[0], "(A) 2026-09-01 Ship it")
        self.save(todos.change_toggle(0))
        self.assertEqual(self.read()[0],
                         "(x) %s 2026-09-01 Ship it p:1" % todos.iso(todos.today()))


class Document(unittest.TestCase):
    def setUp(self):
        self.folder = tempfile.TemporaryDirectory()
        self.path = os.path.join(self.folder.name, "todo.txt")
        self.addCleanup(self.folder.cleanup)

    def write(self, *lines):
        with open(self.path, "w", encoding="utf-8") as handle:
            handle.write("\n".join(lines) + "\n")

    def doc(self, done_days=7):
        return todos.document(self.path, NOW, done_days)

    def test_open_tasks_keep_the_order_they_were_written(self):
        self.write("(C) third", "(A) first", "no priority",
                   "(x) 2026-10-12 done", "second")
        self.assertEqual([t["body"] for t in self.doc()["tasks"]],
                         ["third", "first", "no priority", "second", "done"])
        self.assertEqual(self.doc()["counts"], {"open": 4, "done": 1})

    def test_finished_tasks_come_newest_first(self):
        self.write("(x) 2026-10-08 older", "(x) 2026-10-12 newer", "open one")
        self.assertEqual([t["body"] for t in self.doc()["tasks"]],
                         ["open one", "newer", "older"])

    def test_done_window(self):
        self.write("(x) 2026-10-12 recent", "(x) 2026-08-01 ancient", "(x) no date")
        # A finished line with no date reads as the freshest of them.
        self.assertEqual([t["body"] for t in self.doc(7)["tasks"]], ["no date", "recent"])
        self.assertEqual(self.doc(0)["tasks"], [])
        self.assertEqual(len(self.doc(-1)["tasks"]), 3)

    def test_missing_file(self):
        doc = todos.document(self.path, NOW, 7)
        self.assertFalse(doc["exists"])
        self.assertEqual(doc["tasks"], [])
        self.assertEqual(doc["stamp"], "missing")
        self.assertEqual(doc["counts"], {"open": 0, "done": 0})

    def test_add_lands_after_the_last_line(self):
        todos.save_lines(self.path, todos.change_add("Buy milk")(todos.read_lines(self.path)))
        self.assertEqual(todos.read_lines(self.path), ["Buy milk"])
        with open(self.path, "w", encoding="utf-8") as handle:
            handle.write("first\n\n\n")
        todos.save_lines(self.path, todos.change_add("second")(todos.read_lines(self.path)))
        self.assertEqual(todos.read_lines(self.path), ["first", "second"])

    def test_a_stale_line_is_refused(self):
        self.write("Buy milk")
        with self.assertRaises(IndexError):
            todos.change_remove(0, "Something else")(todos.read_lines(self.path))

    def test_a_write_is_refused_if_the_file_moved(self):
        """A change made elsewhere in between is not written over."""
        self.write("Buy milk")
        real = todos.stamp_of
        seen = {"n": 0}

        def moving(path):
            seen["n"] += 1
            return "someone else wrote" if seen["n"] == 2 else real(path)

        todos.stamp_of = moving
        try:
            doc = todos.mutate(self.path, todos.change_add("later"))
        finally:
            todos.stamp_of = real
        self.assertTrue(doc["error"])
        self.assertEqual(todos.read_lines(self.path), ["Buy milk"])

    def test_an_empty_add_says_so(self):
        with self.assertRaises(ValueError):
            todos.change_add("   ")(todos.read_lines(self.path))


class Cli(unittest.TestCase):
    """The real thing, run as the addon runs it."""

    def run_cli(self, *args):
        out = subprocess.run([sys.executable, CLI] + list(args),
                             capture_output=True, text=True, check=True)
        return json.loads(out.stdout.strip().splitlines()[-1])

    def test_add_toggle_remove(self):
        with tempfile.TemporaryDirectory() as folder:
            path = os.path.join(folder, "todo.txt")
            args = ["--file", path]
            doc = self.run_cli(*args, "add", "--text", "Fix the sink   p:1")
            self.assertEqual(doc["tasks"][0]["body"], "Fix the sink")
            self.assertEqual(doc["tasks"][0]["priority"], "A")
            self.assertEqual(doc["counts"], {"open": 1, "done": 0})

            doc = self.run_cli(*args, "toggle", "--line", "0")
            self.assertEqual(doc["counts"], {"open": 0, "done": 1})

            doc = self.run_cli(*args, "toggle", "--line", "0")
            self.assertEqual(doc["counts"], {"open": 1, "done": 0})

            doc = self.run_cli(*args, "remove", "--line", "0")
            self.assertEqual(doc["tasks"], [])
            with open(path, encoding="utf-8") as handle:
                self.assertEqual(handle.read(), "")

    def test_watch_prints_once_per_change(self):
        with tempfile.TemporaryDirectory() as folder:
            path = os.path.join(folder, "todo.txt")
            with open(path, "w", encoding="utf-8") as handle:
                handle.write("first\n")
            watch = subprocess.Popen([sys.executable, CLI, "--file", path,
                                      "watch", "--interval", "0.2"],
                                     stdout=subprocess.PIPE, text=True)
            self.addCleanup(watch.kill)
            self.assertEqual([t["body"] for t in json.loads(watch.stdout.readline())["tasks"]],
                             ["first"])
            with open(path, "w", encoding="utf-8") as handle:
                handle.write("first\nsecond\n")
            self.assertEqual([t["body"] for t in json.loads(watch.stdout.readline())["tasks"]],
                             ["first", "second"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
