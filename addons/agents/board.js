// Agent 会话看板的归约逻辑，写成普通 JS 有两个原因：QML 里只留绑定，
// 以及 `node board.test.mjs` 能不带图形界面把规则全测一遍。
// 数据来源只有 `herdr agent list`，所以这里的字段名就是 herdr 的字段名。

// `herdr agent list` 的答案是一行 JSON：可能是裸数组，也可能是
// {agents:[…]} 或 {result:{agents:[…]}}（CLI 和 socket 两种壳）。
// 读不到就当没有，别把上一次的好数据擦掉 —— 调用方负责判空。
function parseList(text) {
  var raw = String(text === undefined || text === null ? "" : text).trim()
  if (raw === "") return []
  var data = null
  try { data = JSON.parse(raw) } catch (e) { return [] }
  if (Array.isArray(data)) return data
  if (data && Array.isArray(data.agents)) return data.agents
  if (data && data.result && Array.isArray(data.result.agents)) return data.result.agents
  return []
}

// herdr 的状态顺序就是"谁该先打断你"的顺序；blocked 永远在最上面。
var order = { blocked: 0, working: 1, done: 2, idle: 3 }

function rank(row) {
  var at = order[String((row && row.status) || "")]
  return at === undefined ? 4 : at
}

function statusLabel(status) {
  var s = String(status || "")
  if (s === "blocked") return "等你"
  if (s === "working") return "在跑"
  if (s === "done") return "完成"
  if (s === "idle") return "空闲"
  return "未知"
}

// 颜色只出"这一行该不该扎眼"，具体色值由 theme 决定（见 AgentsAddon.toneColor）。
function statusTone(status) {
  var s = String(status || "")
  if (s === "blocked") return "urgent"
  if (s === "working") return "accent"
  if (s === "done") return "done"
  return "muted"
}

// 标题栏只露目录末段：`~/code/api` 比 `/home/qrfeng/code/api` 好认。
function cwdTail(cwd, home) {
  var path = String(cwd || "")
  if (path === "") return ""
  var h = String(home || "")
  while (path.length > 1 && path.charAt(path.length - 1) === "/") path = path.slice(0, -1)
  if (h !== "" && path === h) return "~"
  if (h !== "" && path.indexOf(h + "/") === 0) return path.slice(h.length + 1)
  if (path === "/") return ""
  var parts = path.split("/")
  var last = parts[parts.length - 1]
  return last || path
}

// 一个 agent -> 一行。key 用窗格（跳过去、读输出、记「等你看」都靠它），
// 没有窗格的记录（比如刚创建还没落位）退回 名称+会话 的组合。
function rowOf(agent, home) {
  var a = agent || {}
  var pane = String(a.pane_id || "")
  var session = String((a.agent_session && a.agent_session.value) || "")
  var kind = String(a.agent || "")
  var cwd = String(a.cwd || a.foreground_cwd || "")
  var status = String(a.agent_status || "") || "unknown"
  var title = String(a.display_agent || a.terminal_title || a.agent || pane || "会话")
  return {
    // 有窗格就用窗格：跳过去、读输出、记「等你看」都拿它当句柄。
    key: pane !== "" ? pane : title + "|" + session,
    pane: pane,
    status: status,
    statusLabel: statusLabel(status),
    tone: statusTone(status),
    rank: order[status] === undefined ? 4 : order[status],
    title: title,
    kind: kind,
    folder: cwdTail(cwd, home),
    cwd: cwd,
    detail: String(a.terminal_title || pane),
    workspace: String(a.workspace_id || ""),
    focused: a.focused === true,
    session: session,
    seq: Number(a.state_change_seq || 0),
    attention: "",
    attentionLabel: ""
  }
}

function match(row, query) {
  var q = String(query || "").trim().toLowerCase()
  if (q === "") return true
  var fields = ["title", "folder", "pane", "kind", "detail"]
  for (var i = 0; i < fields.length; i++) {
    if (String(row[fields[i]] || "").toLowerCase().indexOf(q) !== -1) return true
  }
  return false
}

function byUrgency(a, b) {
  var ka = a.atKey, kb = b.atKey
  if (ka !== kb) return ka - kb
  if (a.rank !== b.rank) return a.rank - b.rank
  if (a.focused !== b.focused) return a.focused ? -1 : 1
  if (a.seq !== b.seq) return b.seq - a.seq
  return String(a.title).localeCompare(String(b.title))
}

// 过滤 + 排序，不带「等你看」标记（测试和旧调用方用这个）。
function rows(agents, query, home) {
  var list = agents || []
  var out = []
  for (var i = 0; i < list.length; i++) {
    var row = rowOf(list[i], home)
    if (!match(row, query)) continue
    row.atKey = 9
    out.push(row)
  }
  out.sort(byUrgency)
  return out
}

/* ---------- 「等你看」：done 会被 herdr 收回去，标记得岛自己钉住 ---------- */
// herdr 的 done 只表示"刚刚跑完"，几秒就落回 idle；所以"跑完了但你没回去看"
// 这个最有用的信号在 `agent list` 里是丢掉的。这里拿上一帧的采样 + 这一帧的
// focused 自己钉住它（语义和 herdr-radar 的勾对齐）：
//   blocked                          -> waiting（不需要历史，永远算）
//   这一帧 done                      -> unseen
//   上一帧 working/done，这一帧 idle  -> unseen（herdr 已经把 done 收回去了）
//   已经钉着的                       -> 继续钉，直到那个窗格真的被 focus 过
//   这一帧 focused                   -> 你正看着它，立刻松手
//   钉过 ttl                         -> 自己松手，别在磁贴上面留一颗长红点
var attentionLabel = { waiting: "等你", unseen: "等你看" }
var attentionRank = { waiting: 0, unseen: 1 }

function seenUpdate(rowsIn, prev, now, ttl) {
  var seen = {}, flags = {}
  var old = prev || {}
  var life = ttl > 0 ? ttl : 2 * 60 * 60 * 1000
  for (var i = 0; i < rowsIn.length; i++) {
    var r = rowsIn[i]
    var key = String(r.key)
    var was = old[key] || null
    var since = was && was.since > 0 ? was.since : 0
    var flag = ""
    if (r.status === "blocked") flag = "waiting"
    else if (r.status === "done") flag = "unseen"
    else if (r.status === "idle" && was && (was.status === "working" || was.status === "done")) flag = "unseen"
    // 只有「等你看」需要钉住（done 会被 herdr 收回 idle）；blocked 是活状态，
    // 每一帧重算，批准完继续跑就该立刻不红了。
    else if (was && was.flag === "unseen") flag = "unseen"
    if (flag !== "" && since > 0 && now > 0 && now - since > life) flag = ""
    if (r.focused === true) flag = ""
    // 钉住的时间取第一次，这样 ttl 才是"从跑完那刻算起"。
    if (flag !== "" && was && was.flag === flag && since > 0) since = was.since
    else if (flag !== "") since = now
    flags[key] = flag
    seen[key] = { status: String(r.status || ""), flag: flag, since: since }
  }
  return { seen: seen, flags: flags }
}

// 跳过去之后别等下一次采样：本地先把这个窗格的记号抹掉。
function markSeen(prev, key) {
  var next = {}
  for (var k in (prev || {})) {
    var entry = prev[k] || {}
    next[k] = String(k) === String(key)
      ? { status: String(entry.status || ""), flag: "", since: 0 }
      : entry
  }
  return next
}

// 全量会话 + 「等你看」标记。分组和过滤都不再碰 seen，
// 所以搜索时不会把没显示出来的窗格的记号弄丢。
function annotate(agents, opts) {
  var o = opts || {}
  var list = rows(agents, "", o.home)
  var up = seenUpdate(list, o.seen, o.now || 0, o.ttl || 0)
  for (var i = 0; i < list.length; i++) {
    var r = list[i]
    r.attention = up.flags[String(r.key)] || ""
    r.attentionLabel = attentionLabel[r.attention] || ""
    r.atKey = attentionLabel[r.attention] === undefined ? 9 : attentionRank[r.attention]
  }
  list.sort(byUrgency)
  return { rows: list, seen: up.seen, flags: up.flags }
}

// ListPicker 的行：按 query 过滤，出现两个以上项目时才插分组标题行
// （一个项目时标题纯属噪音）。分组顺序 = 组内最急那一行的顺序。
function items(rowsIn, query) {
  var list = rowsIn || []
  var kept = []
  for (var i = 0; i < list.length; i++) if (match(list[i], query)) kept.push(list[i])
  var order2 = [], groups = {}
  for (i = 0; i < kept.length; i++) {
    var r = kept[i]
    var id = String(r.cwd || "") !== "" ? String(r.cwd) : "其它"
    if (!groups[id]) { groups[id] = []; order2.push({ id: id, label: r.folder !== "" ? r.folder : id, cwd: id }) }
    groups[id].push(r)
  }
  if (order2.length <= 1) return kept
  var out = []
  for (i = 0; i < order2.length; i++) {
    var g = order2[i]
    out.push({ header: true, disabled: true, key: "group:" + g.id, label: g.label, cwd: g.cwd, count: groups[g.id].length })
    out = out.concat(groups[g.id])
  }
  return out
}

function counts(agents) {
  var at = { blocked: 0, working: 0, done: 0, idle: 0, unknown: 0, total: 0 }
  var list = agents || []
  for (var i = 0; i < list.length; i++) {
    var status = String((list[i] || {}).agent_status || "") || "unknown"
    if (at[status] === undefined) status = "unknown"
    at[status] += 1
    at.total += 1
  }
  return at
}

// 磁贴和视图顶部那一行字："1 等你 · 2 等你看 · 1 在跑"。
// 什么都没发生就只说有几个空闲，再没有就空串（磁贴副标题不占地方）。
function summary(agents, flags) {
  var at = counts(agents)
  var unseen = 0
  for (var k in (flags || {})) if (flags[k] === "unseen") unseen += 1
  var parts = []
  if (at.blocked) parts.push(at.blocked + " 等你")
  if (unseen) parts.push(unseen + " 等你看")
  if (at.working) parts.push(at.working + " 在跑")
  if (!parts.length && at.total) parts.push(at.total + " 个空闲")
  return parts.join(" · ")
}

// `herdr status --json` 里那句 `server_binary_stale`：盘上的二进制比在跑的
// server 新。pacman/AUR 升完 herdr 时 herdr 自己不发一声，而插件各自按
// min_herdr_version 被挡下（岛的事件戳 companion 就是这么瞎的），所以这里替它
// 说出来。server 没在跑时不算「需重启」——那时根本没有旧进程卡着。
function parseStatus(text) {
  var none = { stale: false, client: "", server: "" }
  var data
  try { data = JSON.parse(String(text || "")) } catch (e) { return none }
  if (!data || typeof data !== "object") return none
  var client = data.client ? String(data.client.version || "") : ""
  var server = data.server
  if (!server || server.running !== true) return { stale: false, client: client, server: "" }
  var upd = data.update || {}
  return {
    stale: upd.server_binary_stale === true || server.server_binary_stale === true,
    client: client,
    server: String(server.version || "")
  }
}
