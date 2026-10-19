#!/usr/bin/env python3
"""Tests for missions.py. No pytest here, so: python3 test_missions.py"""

import json
import os
import subprocess
import sys
import tempfile
import time
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
# Importing missions.py would write addons/missions/__pycache__/, and the shell
# watches the whole plugin folder: a new .pyc reads as "the plugin changed" and
# reloads the island mid-use. A test run isn't a plugin change.
sys.dont_write_bytecode = True
import missions  # noqa: E402

CLI = os.path.join(os.path.dirname(os.path.abspath(__file__)), "missions.py")


def make_store(folder, records):
    """Write one index pointer + one record per entry of `records`."""
    store = os.path.join(folder, "missions")
    os.makedirs(os.path.join(store, "index"))
    for index, record in enumerate(records):
        project_root = record.setdefault("cwd", "/home/tester/work/demo")
        record.setdefault("status", "active")
        record.setdefault("updatedAt", "2026-10-16T10:00:00.000Z")
        record.setdefault("decisions", [])
        record.setdefault("runs", [])
        project_dir = os.path.join(store, "projects", "%02x" % index)
        os.makedirs(project_dir)
        mission_id = record.setdefault("id", "mission-%d" % index)
        path = os.path.join(project_dir, mission_id + ".json")
        with open(path, "w", encoding="utf-8") as handle:
            handle.write(json.dumps(record))
        pointer = {
            "schemaVersion": 1,
            "missionId": mission_id,
            "projectRoot": project_root,
            "recordPath": path,
            "title": record.get("title", ""),
            "status": record["status"],
            "updatedAt": record["updatedAt"],
        }
        with open(os.path.join(store, "index", "ptr-%d.json" % index), "w",
                  encoding="utf-8") as handle:
            handle.write(json.dumps(pointer))
    return store


def write_state(store, project, mission_id, values):
    """A mission's durable state sits in a directory beside its record."""
    path = os.path.join(store, "projects", project, mission_id)
    os.makedirs(path, exist_ok=True)
    full = os.path.join(path, "state.json")
    with open(full, "w", encoding="utf-8") as handle:
        handle.write(json.dumps(values))
    return full


class Snapshot(unittest.TestCase):
    def test_readable_mission_gets_island_labels(self):
        with tempfile.TemporaryDirectory() as folder:
            store = make_store(folder, [{
                "title": "Ship auth refresh", "cwd": "/home/tester/work/api",
                "status": "needs_decision",
                "decisions": [{"id": "d1", "status": "open", "title": "用哪个刷新窗口"},
                              {"id": "d2", "status": "resolved", "title": "已定的那条"}],
                "runs": [{"usage": {"totalTokens": 1200}}, {"usage": {"totalTokens": 800}}],
                "labels": ["auth"],
            }])
            doc = missions.snapshot(store, done_days=7)
            self.assertEqual((doc["stale"], len(doc["missions"])), (0, 1))
            row = doc["missions"][0]
            self.assertEqual(row["title"], "Ship auth refresh")
            self.assertEqual(row["project"], "api")
            self.assertEqual((row["label"], row["tone"]), ("等你回答", "urgent"))
            self.assertEqual(row["openDecisions"], ["用哪个刷新窗口"])
            self.assertEqual((row["tokens"], row["runs"]), (2000, 2))

    def test_a_durable_state_is_previewed_not_dumped(self):
        with tempfile.TemporaryDirectory() as folder:
            store = make_store(folder, [{"id": "one", "title": "长跑"}])
            self.assertEqual(missions.snapshot(store, done_days=7)["missions"][0]["state"], {})
            write_state(store, "00", "one", {
                "zebra": "x" * 200, "alpha": "等 CI 跑完", "beta": [1, 2, 3],
                "gamma": {"k": 1}, "delta": 7})
            state = missions.snapshot(store, done_days=7)["missions"][0]["state"]
            self.assertEqual(state["count"], 5)
            self.assertGreater(state["bytes"], 0)
            self.assertTrue(state["updatedAt"].endswith("Z"))
            # Keyed order, a scalar shown as-is, a container counted, and the
            # island only ever gets the first few.
            self.assertEqual(state["entries"], [
                {"key": "alpha", "value": "等 CI 跑完"},
                {"key": "beta", "value": "3 项"},
                {"key": "delta", "value": "7"}])
            self.assertEqual(len(state["entries"]), missions.STATE_KEYS_SHOWN)

    def test_a_long_state_value_is_cut_to_one_line(self):
        shown = missions.state_preview("  a\n  " + "b" * 400)
        self.assertEqual(len(shown), missions.STATE_VALUE_CHARS)
        self.assertTrue(shown.endswith("…"))
        self.assertFalse("\n" in shown)

    def test_runs_are_named_from_the_last_ones(self):
        with tempfile.TemporaryDirectory() as folder:
            runs = [{"runId": "r%d" % n, "agent": "worker", "status": "complete",
                     "usage": {"totalTokens": 100 * n}} for n in range(1, 6)]
            store = make_store(folder, [{"id": "one", "runs": runs}])
            row = missions.snapshot(store, done_days=7)["missions"][0]
            self.assertEqual((row["runs"], row["tokens"]), (5, 1500))
            self.assertEqual([r["id"] for r in row["runList"]], ["r3", "r4", "r5"])
            self.assertEqual(row["runList"][-1], {
                "id": "r5", "agent": "worker", "status": "complete",
                "tokens": 500, "completedAt": ""})

    def test_an_open_decision_carries_the_id_the_agent_needs(self):
        with tempfile.TemporaryDirectory() as folder:
            store = make_store(folder, [{
                "id": "one",
                "ownerSessionId": "/home/tester/.pi/agent/sessions/x/y.jsonl",
                "decisions": [{"id": "d1", "status": "open", "title": "开不开 goal"},
                              {"id": "d2", "status": "resolved"}]}])
            row = missions.snapshot(store, done_days=7)["missions"][0]
            self.assertEqual(row["openDecisionIds"], ["d1"])
            self.assertEqual(row["ownerSessionId"],
                             "/home/tester/.pi/agent/sessions/x/y.jsonl")

    def test_index_pointing_at_a_removed_record_is_reported(self):
        with tempfile.TemporaryDirectory() as folder:
            store = make_store(folder, [{"title": "kept", "status": "active"}])
            pointer = os.path.join(store, "index", "ptr-0.json")
            with open(pointer, encoding="utf-8") as handle:
                doc = json.load(handle)
            os.remove(doc["recordPath"])
            doc["missionId"] = "gone"
            with open(pointer, "w", encoding="utf-8") as handle:
                handle.write(json.dumps(doc))
            out = missions.snapshot(store, done_days=7)
            self.assertEqual(out["stale"], 1)
            self.assertTrue(out["missions"][0]["stale"])
            self.assertEqual(out["missions"][0]["id"], "gone")

    def test_finished_missions_age_out_unless_asked_to_stay(self):
        with tempfile.TemporaryDirectory() as folder:
            old = time.strftime("%Y-%m-%dT%H:%M:%S.000Z",
                                time.gmtime(time.time() - 40 * 86400))
            store = make_store(folder, [{"title": "old", "status": "completed",
                                         "updatedAt": old}])
            self.assertEqual(missions.snapshot(store, done_days=7)["missions"], [])
            self.assertEqual(missions.snapshot(store, done_days=7)["skipped"], 1)
            self.assertEqual(len(missions.snapshot(store, done_days=None)["missions"]), 1)

    def test_unknown_status_passes_through(self):
        with tempfile.TemporaryDirectory() as folder:
            store = make_store(folder, [{"title": "newer pi", "status": "queued"}])
            row = missions.snapshot(store, done_days=7)["missions"][0]
            self.assertEqual(row["label"], "queued")
            self.assertEqual(row["tone"], "")
            self.assertFalse(row["terminal"])

    def test_newest_first_and_limit(self):
        with tempfile.TemporaryDirectory() as folder:
            store = make_store(folder, [
                {"id": "old", "updatedAt": "2026-10-01T00:00:00.000Z"},
                {"id": "new", "updatedAt": "2026-10-16T00:00:00.000Z"}])
            doc = missions.snapshot(store, done_days=7, limit=1)
            self.assertEqual([m["id"] for m in doc["missions"]], ["new"])

    def test_unreadable_index_entry_is_skipped(self):
        with tempfile.TemporaryDirectory() as folder:
            store = make_store(folder, [{"title": "fine"}])
            with open(os.path.join(store, "index", "junk.json"), "w",
                      encoding="utf-8") as handle:
                handle.write("{ not json")
            self.assertEqual(len(missions.snapshot(store, done_days=7)["missions"]), 1)


class Names(unittest.TestCase):
    def test_project_name(self):
        self.assertEqual(missions.project_name(os.path.expanduser("~")), "~")
        self.assertEqual(missions.project_name("/a/b/c/"), "c")
        self.assertEqual(missions.project_name(""), "?")

    def test_missing_store_is_an_empty_list(self):
        with tempfile.TemporaryDirectory() as folder:
            doc = missions.snapshot(os.path.join(folder, "nothing"), done_days=7)
            self.assertEqual(doc["missions"], [])


class Cli(unittest.TestCase):
    def test_list_prints_one_line_of_json(self):
        with tempfile.TemporaryDirectory() as folder:
            store = make_store(folder, [{"title": "one"}])
            out = subprocess.run([sys.executable, CLI, "--dir", store, "list"],
                                 capture_output=True, text=True, check=True)
            self.assertEqual(len(out.stdout.strip().splitlines()), 1)
            doc = json.loads(out.stdout)
            self.assertEqual([m["title"] for m in doc["missions"]], ["one"])

    def test_missing_store_is_not_an_error(self):
        with tempfile.TemporaryDirectory() as folder:
            out = subprocess.run([sys.executable, CLI,
                                  "--dir", os.path.join(folder, "none"), "list"],
                                 capture_output=True, text=True, check=True)
            self.assertTrue(json.loads(out.stdout)["missing"])

    def test_watch_reprints_when_a_record_changes(self):
        with tempfile.TemporaryDirectory() as folder:
            store = make_store(folder, [{"id": "one", "title": "第一版"}])
            watch = subprocess.Popen([sys.executable, CLI, "--dir", store,
                                      "watch", "--interval", "0.2"],
                                     stdout=subprocess.PIPE, text=True)
            self.addCleanup(watch.kill)
            first = json.loads(watch.stdout.readline())
            self.assertEqual([m["title"] for m in first["missions"]], ["第一版"])
            path = os.path.join(store, "projects", "00", "one.json")
            with open(path, encoding="utf-8") as handle:
                doc = json.load(handle)
            self.assertEqual(doc["id"], "one")
            doc["title"] = "第二版"
            doc["status"] = "needs_decision"
            with open(path, "w", encoding="utf-8") as handle:
                handle.write(json.dumps(doc))
            second = json.loads(watch.stdout.readline())
            self.assertEqual([m["title"] for m in second["missions"]], ["第二版"])
            self.assertEqual(second["missions"][0]["label"], "等你回答")

    def test_watch_is_quiet_while_nothing_changes(self):
        import select
        with tempfile.TemporaryDirectory() as folder:
            store = make_store(folder, [{"id": "one"}])
            watch = subprocess.Popen([sys.executable, CLI, "--dir", store,
                                      "watch", "--interval", "0.1"],
                                     stdout=subprocess.PIPE, text=True)
            self.addCleanup(watch.kill)
            json.loads(watch.stdout.readline())
            # Nothing written since, so the pipe must still be empty.
            ready, _, _ = select.select([watch.stdout], [], [], 1.0)
            self.assertEqual(ready, [])

    def test_watch_wakes_on_a_state_write(self):
        """`mission.state.set` rewrites only state.json, and the panel must follow."""
        with tempfile.TemporaryDirectory() as folder:
            store = make_store(folder, [{"id": "one"}])
            before = missions.fingerprint(store)
            write_state(store, "00", "one", {"phase": "implement"})
            self.assertNotEqual(missions.fingerprint(store), before)
            watch = subprocess.Popen([sys.executable, CLI, "--dir", store,
                                      "watch", "--interval", "0.2"],
                                     stdout=subprocess.PIPE, text=True)
            self.addCleanup(watch.kill)
            json.loads(watch.stdout.readline())
            write_state(store, "00", "one", {"phase": "verify"})
            second = json.loads(watch.stdout.readline())
            self.assertEqual(second["missions"][0]["state"]["entries"],
                             [{"key": "phase", "value": "verify"}])

    def test_list_carries_the_state_and_the_handoff_handles(self):
        with tempfile.TemporaryDirectory() as folder:
            store = make_store(folder, [{"id": "one", "title": "长跑",
                                         "ownerSessionId": "/s/y.jsonl"}])
            write_state(store, "00", "one", {"next": "跑集成测试"})
            out = subprocess.run([sys.executable, CLI, "--dir", store, "list"],
                                 capture_output=True, text=True, check=True)
            row = json.loads(out.stdout)["missions"][0]
            self.assertEqual(row["state"]["entries"],
                             [{"key": "next", "value": "跑集成测试"}])
            self.assertEqual(row["ownerSessionId"], "/s/y.jsonl")


if __name__ == "__main__":
    unittest.main(verbosity=2)
