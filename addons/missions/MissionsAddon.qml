import QtQuick
import Quickshell
import Quickshell.Io
import ".."

// Missions: pi-subagents' durable records, on the island, read-only.
//
// A mission is the record pi-subagents keeps for delegated work under
// `~/.pi/agent/missions/` - objective, lifecycle status, linked runs and their
// token totals, open decisions, receipts. It survives compaction and restarts,
// which is the whole reason to look at it here: the island is where you notice
// that something is still waiting for you.
//
// Nothing in this addon writes. Starting, pausing and closing missions belongs
// to the agent (`mission.create` / `mission.update` / `mission.close`), and the
// records are that extension's store - the island reads it the same way the Task
// list reads a todo.txt another program also edits. missions.py beside this file
// does the reading; one `watch` process prints the whole list as one line of
// JSON whenever anything under the store changes, so the tile and the view always
// show the same numbers.
//
// Two things the records force on us: a mission auto-created from a prompt keeps
// `[prompt redacted]` as its title (only an explicit `mission: {title: ...}` is
// stored), so rows lead with the project directory; and the index can lag its
// record by a beat, so missions.py reads the record as the source of truth.
Addon {
  id: missionBoard
  views: [{ name: "missions", width: 440, padding: 22, component: missionsView }]
  tiles: [{ key: "missions", title: "任务", component: missionsTile }]

  Component {
    id: missionsView
    MissionsView { host: missionBoard.host; board: missionBoard; active: missionBoard.host.view === "missions" }
  }
  Component {
    id: missionsTile
    MissionsTile { board: missionBoard; center: parent.center }
  }

  // ---------- settings (Settings > Addons > Missions) ----------

  readonly property string defaultDir: "~/.pi/agent/missions"
  readonly property string dir: {
    var own = String(addon.option("path") || "").trim()
    return own !== "" ? own : defaultDir
  }
  // How far back finished (or failed) missions stay listed.
  readonly property var doneChoices: ({ "Hide": 0, "Last 7 days": 7, "Last 30 days": 30,
    "Always": -1 })
  readonly property int doneDays: {
    var own = doneChoices[String(addon.option("done"))]
    return own === undefined ? 7 : own
  }
  readonly property string script:
    host.addons.path(Qt.resolvedUrl("missions.py"))

  // ---------- the list ----------

  readonly property var empty: ({ store: "", generatedAt: 0, missions: [], stale: 0,
    skipped: 0, missing: false })
  property var doc: empty
  // The watcher's list before this addon's own filter. `--done-days` cannot
  // express "hide the finished ones": 0 means "no window" over in missions.py,
  // so the settings option "不显示" is applied here instead.
  readonly property var raw: doc.missions || []
  readonly property var missions: {
    var list = missionBoard.doneDays === 0
      ? raw.filter(function (m) { return m.terminal !== true }) : raw.slice()
    // The index is newest-first, which buries the one mission you owe an answer
    // to under the finished experiments you cannot even read. Owe-you comes first.
    return list.sort(function (a, b) {
      var w = (missionBoard.isWaiting(b) ? 1 : 0) - (missionBoard.isWaiting(a) ? 1 : 0)
      if (w !== 0) return w
      var t = (a.terminal === true ? 1 : 0) - (b.terminal === true ? 1 : 0)
      if (t !== 0) return t
      return String(b.updatedAt || "").localeCompare(String(a.updatedAt || ""))
    })
  }
  // Finished ones this option keeps off the list (the time window's own
  // dropouts are the script's `skipped`).
  readonly property int hidden: raw.length - missions.length
  readonly property bool missing: doc.missing === true
  // Missions the index still lists but whose record is gone (terminal retention).
  readonly property int stale: Number(doc.stale) || 0
  readonly property int skipped: Number(doc.skipped) || 0

  readonly property int running: countWhere(function (m) { return m.status === "active" })
  // An open decision gates the mission even while pi-subagents keeps its
  // lifecycle status (only active/completed ones flip to needs_decision), so the
  // tile and the card both judge by the decision, not by the status label.
  function isWaiting(m) {
    return m.status === "needs_decision" || m.status === "needs-attention"
      || m.status === "budget-exhausted" || (m.openDecisions || []).length > 0
  }
  readonly property int waiting: countWhere(isWaiting)
  readonly property int open: countWhere(function (m) { return m.terminal !== true })
  readonly property int tokens: {
    var sum = 0
    for (var i = 0; i < missions.length; ++i) sum += Number(missions[i].tokens) || 0
    return sum
  }
  readonly property bool loading: doc.generatedAt === 0 && !failed
  readonly property string error: failed ? "读不了 " + script : ""

  property bool failed: false
  property int failures: 0
  property bool reading: true

  function countWhere(test) {
    var n = 0
    for (var i = 0; i < missions.length; ++i) if (test(missions[i])) ++n
    return n
  }

  function apply(line) {
    var text = String(line || "").trim()
    if (text === "" || text.charAt(0) !== "{") return
    var next
    try { next = JSON.parse(text) } catch (e) { return }
    if (!next || !Array.isArray(next.missions)) return
    doc = next
    failures = 0
  }

  // The watcher died three times in a row: stop retrying and say so, rather than
  // spinning against a store we cannot read.
  Timer {
    id: retry
    interval: 2000
    onTriggered: missionBoard.reading = true
  }

  Process {
    id: watcher
    running: missionBoard.reading
    command: ["python3", missionBoard.script, "--dir", missionBoard.dir,
      "--done-days", String(missionBoard.doneDays), "watch", "--interval", "1"]
    stdout: SplitParser { onRead: function (line) { missionBoard.apply(line) } }
    onExited: {
      if (!missionBoard.reading) return
      missionBoard.reading = false
      if (++missionBoard.failures >= 3) { missionBoard.failed = true; return }
      retry.restart()
    }
  }

  // A settings change is a new document, so re-read rather than show the old one.
  function reread() {
    missionBoard.failed = false
    missionBoard.failures = 0
    missionBoard.doc = missionBoard.empty
    if (watcher.running) watcher.restart()
    else missionBoard.reading = true
  }
  onDirChanged: reread()
  onDoneDaysChanged: reread()
}
