import QtQuick
import Quickshell
import Quickshell.Io
import ".."

// Task list: a plain todo.txt file, on the island.
//
// The file is the whole point. Everything shown is what the format holds - an
// (A)-(D) priority, the (x) marker and its dates, +projects, @contexts and
// key:value tags - and the same file stays open in an editor, a `todo.sh`, or a
// phone app without this addon having anything to say about it. Nothing is
// mirrored anywhere else, and a line this script isn't asked to change is
// written back byte for byte. todos.py beside this file does the reading and the
// writing (see it for the document these views are drawn from).
//
// One root for every screen, so a task ticked on one screen is ticked on the
// rest: a `watch` process prints the list whenever the file changes, and the
// field, the tile, and the launcher's row all read the same `doc`.
Addon {
  id: taskList
  views: [{ name: "todos", width: 440, padding: 22, component: todosView }]
  tiles: [{ key: "tasks", title: "Tasks", component: todosTile }]

  Component {
    id: todosView
    TodosView { host: taskList.host; todos: taskList; active: taskList.host.view === "todos" }
  }
  Component {
    id: todosTile
    TodosTile { todos: taskList; center: parent.center }
  }

  // ---------- settings (Settings > Addons > Task list) ----------

  readonly property string defaultFile: "~/.local/share/todos/todo.txt"
  readonly property string file: {
    var own = String(addon.option("path") || "").trim()
    return own !== "" ? own : defaultFile
  }
  // How far back finished tasks are listed; "Last 7 days" and friends, so take
  // the number out of the middle, with 0 and -1 at the ends of the range.
  readonly property var doneChoices: ({ "Hide": 0, "Last 3 days": 3, "Last 7 days": 7,
    "Last 30 days": 30, "Always": -1 })
  readonly property int doneDays: {
    var own = doneChoices[String(addon.option("done"))]
    return own === undefined ? 7 : own
  }

  readonly property string script:
    decodeURIComponent(String(Qt.resolvedUrl("todos.py")).replace("file://", ""))

  // ---------- the list ----------

  readonly property var empty: ({ path: file, doneDays: doneDays, stamp: "", exists: false,
    error: "", today: "", counts: ({ open: 0, done: 0 }), tasks: [] })
  property var doc: empty
  readonly property var tasks: doc.tasks || []
  readonly property var counts: doc.counts || empty.counts
  readonly property int open: counts.open || 0
  readonly property int finished: counts.done || 0
  readonly property string path: doc.path || file
  readonly property bool exists: doc.exists === true
  readonly property bool loading: doc.stamp === "" && !failed
  readonly property string error: failed ? "\u8bfb\u4e0d\u4e86\u8fd9\u4e2a\u6587\u4ef6:" + script : String(doc.error || "")

  // A reading replaces the one on screen only when it says something new: the
  // watcher prints again after our own writes, and that would otherwise redraw
  // the list under the keyboard.
  function apply(line) {
    var text = String(line || "").trim()
    if (text === "" || text.charAt(0) !== "{") return
    var own
    try { own = JSON.parse(text) } catch (e) { return }
    if (own.stamp === doc.stamp && own.doneDays === doc.doneDays) return
    doc = own
  }

  // ---------- reading it ----------

  // One long-lived watcher, so a task added in a terminal reaches the island a
  // moment later with nothing polling from QML.
  property bool reading: true
  property bool failed: false
  property int failures: 0
  readonly property string readKey: file + "\u0000" + doneDays
  onReadKeyChanged: restart()
  function restart() {
    failures = 0
    failed = false
    reading = false
    Qt.callLater(function() { reading = true })
  }
  Timer {
    id: retry
    interval: 3000
    onTriggered: { taskList.failed = false; taskList.reading = true }
  }
  Process {
    id: watcher
    running: taskList.reading
    command: ["python3", taskList.script, "--file", taskList.file,
      "--done-days", String(taskList.doneDays), "watch", "--interval", "1"]
    stdout: SplitParser { onRead: function(line) { taskList.apply(line) } }
    onExited: {
      if (!taskList.reading) return
      taskList.reading = false
      if (++taskList.failures >= 3) { taskList.failed = true; return }
      retry.restart()
    }
  }

  // ---------- changing it ----------

  // Writes run one at a time: two at once could each read the file before the
  // other had written it. Each answers with the whole list, so the screen
  // changes the moment its own write lands rather than a second later.
  property var queue: []
  function enqueue(args) {
    queue = queue.concat([args])
    pump()
  }
  function pump() {
    if (writer.running || queue.length === 0) return
    var next = queue[0]
    queue = queue.slice(1)
    writer.command = ["python3", taskList.script, "--file", taskList.file,
      "--done-days", String(taskList.doneDays)].concat(next)
    writer.running = true
  }
  Process {
    id: writer
    stdout: SplitParser { onRead: function(line) { taskList.apply(line) } }
    onExited: taskList.pump()
  }

  function add(text) {
    var what = String(text || "").trim()
    if (what === "") return
    enqueue(["add", "--text", what])
  }
  // A task is named by its line in the file and by what that line read when it
  // was drawn, so one edited in another window in the meantime is refused
  // rather than aimed at.
  function toggle(task) {
    if (task) enqueue(["toggle", "--line", String(task.line), "--raw=" + task.raw])
  }
  function remove(task) {
    if (task) enqueue(["remove", "--line", String(task.line), "--raw=" + task.raw])
  }
  function openFile() {
    Quickshell.execDetached(["xdg-open", path.substring(0, path.lastIndexOf("/"))])
  }

  // The launcher's rows: `todo buy milk` writes the line without opening
  // anything.
  readonly property var prefixes: [/^\s*todos?\b[:\s]/i, /^\s*td\s+/i, /^\u5f85\u529e/]
  function launcherRow(text) {
    var typed = String(text || "")
    for (var i = 0; i < prefixes.length; i++) {
      if (!prefixes[i].test(typed)) continue
      var what = typed.replace(/^\s*(todos?|td)\s*[:\s]*/i, "")
        .replace(/^\u5f85\u529e\s*[:\s]?/, "").trim()
      if (what === "") return null
      return {
        glyph: "\udb80\udd2c", tile: "#34c759", ink: "#ffffff",
        label: "\u6dfb\u52a0\u4efb\u52a1", detail: what, first: true,
        run: function() { taskList.add(what) }
      }
    }
    return null
  }
}
