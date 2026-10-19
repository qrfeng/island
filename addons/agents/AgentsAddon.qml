import QtQuick
import Quickshell
import Quickshell.Io
import ".."
import "board.js" as Board

// Agent usage: how many tokens the coding agents on this machine have spent.
//
// Pi keeps its figures nowhere but its session files, and Omarchy's own usage
// collectors only count a Pi session that ran on an Anthropic provider (they
// answer "did this spend my Claude subscription"), so a Pi session on any
// other endpoint counted as nothing. The collector beside this file reads the
// sessions themselves - Pi's and Claude Code's, both of which write their turn
// usage to disk - and writes an Omarchy usage record for Pi alongside the
// ones `omarchy agent usage update` writes, which is what feeds this addon and
// Omarchy's own Agents panel alike; here it also prints what the view draws.
//
// One root for every screen, so the reading is shared: the view is only a
// picture of `list`.
Addon {
  id: agentUsage
  // width/padding/radius here are the shape the island uses before the view
  // exists (its Loader is only made when the view first opens), so they match
  // AgentsView's own surfaceWidth / surfacePadding / surfaceRadius.
  views: [
    { name: "agents", width: 620, padding: 22, radius: 36, component: agentsView },
    // The board is the same shape on purpose: crossing between two screens of
    // the same subject should not resize the island.
    { name: "sessions", width: 620, padding: 22, radius: 36, component: sessionsView }
  ]
  tiles: [{ key: "usage", title: "Agent 用量", component: agentsTile },
    { key: "sessions", title: "Agent 会话", component: sessionsTile }]

  Component {
    id: agentsView
    AgentsView { host: agentUsage.host; usage: agentUsage; active: agentUsage.host.view === "agents" }
  }
  Component {
    id: agentsTile
    AgentsTile { usage: agentUsage; center: parent.center }
  }
  Component {
    id: sessionsView
    SessionsView { host: agentUsage.host; usage: agentUsage; active: agentUsage.host.view === "sessions" }
  }
  Component {
    id: sessionsTile
    SessionsTile { usage: agentUsage; center: parent.center }
  }

  // How often to re-read while the view is on screen (Settings > Addons >
  // Agent usage); "5 minutes" and friends, so take the number off the front.
  readonly property int refreshMs: {
    var text = String(addon.option("refresh") || "15 minutes")
    var mins = parseInt(text, 10)
    return Math.max(1, isNaN(mins) ? 15 : mins) * 60 * 1000
  }
  // Whether to run Omarchy's collectors too, which ask Codex and Fireworks for
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
    host.addons.path(Qt.resolvedUrl("collector.py"))

  Process {
    id: reader
    stdout: SplitParser { onRead: function(line) { agentUsage.take(line) } }
    stderr: StdioCollector { id: readerErr; waitForEnd: true }
    onExited: function(code) {
      agentUsage.loading = false
      if (code === 0) return
      agentUsage.error = code === 124 ? "读取 agent 用量超时"
        : String(readerErr.text || "").trim().split("\n").filter(function(l) { return l !== "" })
          .slice(-1)[0] || "读不到 agent 用量"
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
  // ---------- 会话：what herdr is watching ----------
  //
  // Which agent sessions are live, and which of them are waiting for a person.
  // `herdr agent list` answers in about 4ms, so this can ask often; board.js
  // turns its answer into rows, and board.test.mjs covers that reducer without a
  // running shell.
  property var boardList: []
  property var boardRows: []
  // 视图直接画这个：分组标题行也在里面（多于一个项目时才有标题）。
  property var boardItems: []
  property string boardError: ""
  property bool boardLoading: false
  property real boardFetchedAt: 0
  // The tail of one session's terminal, for the view's side pane.
  property string readFor: ""
  property string readText: ""
  property bool readRunning: false
  // Filled in once by `command -v`: an island on a machine without herdr says
  // so instead of showing an empty board. Probed by shell because this Qt has
  // no Qt.file (same reason as InputMethodAddon).
  property string herdr: ""
  // 盘上的 herdr 二进制比在跑的 server 新时的一句话（空串 = 没事）。herdr 升完
  // 自己不提示，而插件会按各自的 min_herdr_version 静默被闸（岛的事件戳 companion
  // 首当其冲），所以得有人说出来。见 board.js 的 parseStatus。
  property string herdrStale: ""
  readonly property bool boardReady: herdr !== "" && boardFetchedAt > 0
  readonly property string boardSummary: Board.summary(boardList, boardFlags)
  // 磁贴上的红点：等你处理的 + 跑完了你还没回去看的。
  readonly property int boardWaiting: {
    var n = Board.counts(agentUsage.boardList).blocked
    for (var k in agentUsage.boardFlags) if (agentUsage.boardFlags[k] === "unseen") n += 1
    return n
  }
  // 每个项目目录当前在哪个分支（`git -C <目录> branch --show-current`）。
  // 一次批量问完、只在板子开着时问、结果整块换新，所以它不会变成每秒的子进程雨。
  property var branches: ({})
  property string branchKey: ""
  // 「等你看」的记性（{ 窗格: {status, flag, since} }）。每帧采样整块换新，
  // 所以它只是个快照；真正钉住它的是 herdr 的事件戳（见下面 stampView）。
  property var boardSeen: ({})
  property var boardFlags: ({})

  // board.js tags a row "urgent" / "accent" / "muted"; only the theme owns
  // colours, so the board cannot invent a palette of its own.
  function toneColor(tone) {
    var theme = agentUsage.host ? agentUsage.host.theme : null
    if (!theme) return "#ffffff"
    if (tone === "urgent") return theme.urgent
    if (tone === "accent") return theme.accent
    return theme.muted
  }

  // Where herdr lives, resolved once by the shell: this Qt has no Qt.file, so
  // `command -v` is how the island learns a binary exists at all.
  Process {
    id: herdrFinder
    command: ["sh", "-c", "command -v herdr 2>/dev/null || true"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var path = String(text).trim()
        agentUsage.herdr = path.indexOf("/") === 0 ? path : ""
      }
    }
    Component.onCompleted: running = true
  }

  // Its answer is one JSON line, so a line parser is enough; `command` binds to
  // `herdr` and re-evaluates as soon as the finder above has named it.
  Process {
    id: boardRead
    command: [agentUsage.herdr, "agent", "list"]
    stdout: SplitParser { onRead: function(line) { agentUsage.takeBoard(line) } }
    onExited: agentUsage.boardLoading = false
  }

  function refreshBoard(force) {
    if (agentUsage.herdr === "" || boardRead.running) return
    // While the board is on screen it tracks herdr; every other time a five
    // second glance is plenty for a 4ms command.
    var every = agentUsage.host && agentUsage.host.view === "sessions" ? 1500 : 5000
    if (!force && agentUsage.boardFetchedAt > 0
      && Date.now() - agentUsage.boardFetchedAt < every) return
    agentUsage.boardError = ""
    agentUsage.boardLoading = true
    boardRead.running = true
  }

  function takeBoard(line) {
    var list = Board.parseList(line)
    agentUsage.boardList = list
    // 一次算完：全量行 + 「等你看」标记。标记只在这里推进，视图搜索不碰它。
    var out = Board.annotate(list, {
      home: String(Quickshell.env("HOME") || ""),
      seen: agentUsage.boardSeen, now: Date.now(), ttl: 2 * 60 * 60 * 1000
    })
    agentUsage.boardSeen = out.seen
    agentUsage.boardFlags = out.flags
    agentUsage.boardRows = out.rows
    agentUsage.boardItems = Board.items(out.rows, "")
    agentUsage.boardFetchedAt = Date.now()
    agentUsage.refreshBranches()
  }

  // 视图的搜索走这里：过滤发生在已经带标记的行上，所以搜一下不会把
  // 没显示出来的那些窗格的记号弄丢。
  function itemsFor(query) { return Board.items(agentUsage.boardRows, String(query || "")) }

  // Jump to that pane and get out of the way: the point is the agent, not the
  // island. No focus handoff needed - herdr answers over its own socket, so the
  // pane comes forward even though the island had the keyboard.
  function focusRow(row) {
    if (!row || String(row.pane || "") === "" || agentUsage.herdr === "") return
    agentUsage.host.view = "rest"
    agentUsage.boardSeen = Board.markSeen(agentUsage.boardSeen, String(row.key))
    focusProc.command = [agentUsage.herdr, "agent", "focus", String(row.pane)]
    focusProc.running = true
  }
  Process { id: focusProc }

  // What one session is sitting on, read off herdr's own snapshot of its pane:
  // that works for any harness and needs no session-file parsing. `--source
  // visible` is the one read that always answers - measured here, a *working*
  // pane replies `{"error":{"code":"agent_not_idle"}}` (exit 1) to a scrollback
  // read, because herdr can only scroll an alternate screen once the agent has
  // stopped, while the current screen is available either way. The current
  // screen is also the useful one on a board: it shows the prompt waiting.
  function readRow(row) {
    if (!row || String(row.pane || "") === "" || agentUsage.herdr === "" || readProc.running) return
    agentUsage.readFor = String(row.key)
    agentUsage.readText = ""
    agentUsage.readRunning = true
    readProc.command = [agentUsage.herdr, "agent", "read", String(row.pane),
      "--source", "visible", "--format", "text"]
    readProc.running = true
  }

  Process {
    id: readProc
    stdout: StdioCollector { id: readOut; waitForEnd: true }
    onExited: function(code) {
      agentUsage.readRunning = false
      var text = String(readOut.text || "").replace(/\s+$/, "")
      agentUsage.readText = code === 0 ? text : "读不到那个窗格的输出"
    }
  }

  // 事件驱动：companion/herdr-agent-stamp 那个 herdr 插件在 agent 状态变化、
  // 窗格增删、焦点切换时写一个戳文件，我们看到它变了就去问一次 —— 常态下
  // 一次轮询都不用。底下两个 Timer 只是保险（戳文件丢了/插件被禁用时仍会更新）。
  readonly property string stampFile: (String(Quickshell.env("XDG_STATE_HOME")
    || (String(Quickshell.env("HOME") || "") + "/.local/state")))
    + "/omarchy/island-agent-stamp/changed"
  FileView {
    id: stampView
    path: agentUsage.stampFile
    watchChanges: true
    onFileChanged: reload()
    onTextChanged: agentUsage.refreshBoard(true)
  }

  // 一次 `herdr status --json` 问出两件事：server 在跑什么版本、盘上装的是什么
  // 版本。版本只在升级那天会变，所以一分钟一次足够（它只走一次 socket）。
  function refreshStatus() {
    if (agentUsage.herdr === "" || statusProc.running) return
    statusProc.command = [agentUsage.herdr, "status", "--json"]
    statusProc.running = true
  }
  Process {
    id: statusProc
    stdout: StdioCollector { id: statusOut; waitForEnd: true }
    onExited: function(code) {
      // 问不成就算没事：看板上不该多出一条说不清的错。
      if (code !== 0) { agentUsage.herdrStale = ""; return }
      var s = Board.parseStatus(String(statusOut.text || ""))
      agentUsage.herdrStale = s.stale
        ? "herdr 需重启：server " + s.server + " → 盘上 " + s.client : ""
    }
  }

  // 分支：把板子上出现的目录一次性交给一个 shell 循环问完（不是每个目录起一个进程），
  // 并且只在目录集合真的变了那天再问一次——所以板子开着还是关着都无所谓。
  function refreshBranches() {
    if (agentUsage.boardRows.length === 0) return
    var dirs = [], i, cwd
    for (i = 0; i < agentUsage.boardRows.length && dirs.length < 8; i++) {
      cwd = String(agentUsage.boardRows[i].cwd || "")
      if (cwd !== "" && dirs.indexOf(cwd) === -1) dirs.push(cwd)
    }
    dirs.sort() // 顺序会随行排序抖，key 只该认「集合变没变」
    var key = dirs.join("\u0001")
    if (key === "" || key === agentUsage.branchKey || branchProc.running) return
    agentUsage.branchKey = key
    var body = ""
    for (i = 0; i < dirs.length; i++) {
      body += 'printf "%s\\t%s\\n" ' + JSON.stringify(dirs[i])
        + ' "$(git -C ' + JSON.stringify(dirs[i]) + ' branch --show-current 2>/dev/null)"\n'
    }
    branchProc.command = ["sh", "-c", body]
    branchProc.running = true
  }
  Process {
    id: branchProc
    stdout: StdioCollector { id: branchOut; waitForEnd: true }
    onExited: function(code) {
      if (code !== 0) return
      var next = {}
      var lines = String(branchOut.text || "").split("\n")
      for (var i = 0; i < lines.length; i++) {
        var tab = lines[i].indexOf("\t")
        if (tab <= 0) continue
        var name = lines[i].slice(tab + 1)
        if (name !== "") next[lines[i].slice(0, tab)] = name
      }
      agentUsage.branches = next
    }
  }

  // 保险：20 秒一次（herdr 挂了、或者事件插件被关掉时看板不至于冻住）。
  Timer {
    interval: 20000
    repeat: true
    running: agentUsage.herdr !== ""
    triggeredOnStart: true
    onTriggered: agentUsage.refreshBoard(false)
  }
  // 看板在眼前时勤一点：跳来跳去的时候延迟最难受，3 秒够跟手了。
  Timer {
    interval: 3000
    repeat: true
    running: agentUsage.herdr !== "" && agentUsage.host.view === "sessions"
    triggeredOnStart: false
    onTriggered: agentUsage.refreshBoard(true)
  }
  // herdr 自身的版本差：一分钟一次，启动时立刻问一次（`herdr` 路径到位就开始了）。
  Timer {
    interval: 60000
    repeat: true
    running: agentUsage.herdr !== ""
    triggeredOnStart: true
    onTriggered: agentUsage.refreshStatus()
  }
}
