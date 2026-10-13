import QtQuick
import Quickshell.Io
import ".."

// Agent usage: how many tokens the coding agents on this machine have spent.
//
// Pi keeps its figures nowhere but its session files, and Omarchy's own usage
// collectors only count a Pi session that ran on an Anthropic provider (they
// answer "did this spend my Claude subscription"), so a Pi session on any
// other endpoint counted as nothing. The collector beside this file reads the
// sessions themselves and writes an Omarchy usage record for Pi alongside the
// ones `omarchy agent usage update` writes, which is what feeds this addon and
// Omarchy's own Agents panel alike; here it also prints what the view draws.
//
// One root for every screen, so the reading is shared: the view is only a
// picture of `list`.
Addon {
  id: agentUsage
  views: [{ name: "agents", component: agentsView }]
  tiles: [{ key: "usage", title: "Agent usage", component: agentsTile }]

  Component {
    id: agentsView
    AgentsView { host: agentUsage.host; usage: agentUsage; active: agentUsage.host.view === "agents" }
  }
  Component {
    id: agentsTile
    AgentsTile { usage: agentUsage; center: parent.center }
  }

  // How often to re-read while the view is on screen (Settings > Addons >
  // Agent usage); "5 minutes" and friends, so take the number off the front.
  readonly property int refreshMs: {
    var text = String(addon.option("refresh") || "15 minutes")
    var mins = parseInt(text, 10)
    return Math.max(1, isNaN(mins) ? 15 : mins) * 60 * 1000
  }
  // Whether to run Omarchy's collectors too, which ask Anthropic and Codex for
  // their rate limits over the network. Off: their records then only move when
  // something else refreshes them, which is fine when neither is signed in.
  readonly property bool withOthers: addon.option("others") === true
  // Dollars to yuan, for the money the panel shows: the endpoints bill in
  // dollars, so one figure carries the whole panel.
  readonly property real rate: {
    var value = Number(addon.option("rate"))
    return value > 0 ? value : 6.69
  }

  // Every agent with a record, heaviest first (see collector.py), and which
  // one the view shows.
  property var list: []
  property int selected: 0
  property bool loading: false
  property string error: ""
  property real fetchedAt: 0

  readonly property bool hasData: list.length > 0
  readonly property var current: list.length ? (list[selected] || list[0]) : null
  // Tokens today across every agent, for the control center tile.
  readonly property int todayTokens: list.reduce(function(sum, own) {
    return sum + (Number(own.todayTotalTokens) || 0)
  }, 0)

  function pick(index) {
    if (!list.length) return
    selected = (index + list.length) % list.length
  }
  function timeText(iso) {
    var date = new Date(String(iso || ""))
    return isNaN(date.getTime()) ? "" : Qt.formatDateTime(date, "HH:mm")
  }

  // Read the records. `force` ignores how recent the current reading is;
  // without it a view that opens again within the refresh interval keeps what
  // it already has. Python reads only what the agents already wrote, so a scan
  // is a fraction of a second; the timeout only covers --others, which waits
  // on two network round trips.
  function refresh(force) {
    if (reader.running) return
    if (!force && fetchedAt > 0 && Date.now() - fetchedAt < refreshMs) return
    loading = true
    error = ""
    reader.command = ["timeout", "-k", "5", "45", "python3", scriptPath, "--print",
      "--rate", String(rate || 6.69)].concat(withOthers ? ["--others"] : [])
    reader.running = true
  }

  function take(line) {
    var data
    try { data = JSON.parse(line) } catch (e) { return }
    list = (data && Array.isArray(data.agents)) ? data.agents : []
    if (selected >= list.length) selected = 0
    fetchedAt = Date.now()
    loading = false
  }

  readonly property string scriptPath:
    decodeURIComponent(String(Qt.resolvedUrl("collector.py")).replace("file://", ""))

  Process {
    id: reader
    stdout: SplitParser { onRead: function(line) { agentUsage.take(line) } }
    stderr: StdioCollector { id: readerErr; waitForEnd: true }
    onExited: function(code) {
      agentUsage.loading = false
      if (code === 0) return
      agentUsage.error = code === 124 ? "Reading the agents took too long"
        : String(readerErr.text || "").trim().split("\n").filter(function(l) { return l !== "" })
          .slice(-1)[0] || "Couldn't read the agent usage"
    }
  }

  // Once the island is up: the tile has figures before the view is ever open.
  // A one-shot Timer rather than Qt.callLater, which cannot call back into a
  // QML object's own methods ("attempted to evaluate a function in an invalid
  // context").
  Timer {
    running: true
    interval: 400
    onTriggered: agentUsage.refresh(false)
  }

  // And again while its view is on screen, so a long session's count climbs
  // without asking.
  Timer {
    interval: agentUsage.refreshMs
    repeat: true
    running: agentUsage.host.view === "agents" && !agentUsage.loading
    triggeredOnStart: false
    onTriggered: agentUsage.refresh(true)
  }
}
