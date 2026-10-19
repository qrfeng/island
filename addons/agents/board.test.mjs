// node board.test.mjs — exercises board.js without a running shell.
//
// board.js is a plain QML script (no module wrapper), so it is read and
// evaluated into an object here. Keep this file next to it: the reducer is the
// part of the board that can be wrong without anyone seeing it.
import fs from "node:fs"
import assert from "node:assert/strict"
import { execFileSync } from "node:child_process"

const src = fs.readFileSync(new URL("./board.js", import.meta.url), "utf8")
const board = new Function(`${src}
; return { parseList, rows, counts, summary, cwdTail, statusLabel, statusTone, rowOf,
    annotate, items, seenUpdate, markSeen, parseStatus }`)()

const agent = (over = {}) => ({
  agent: "pi", agent_status: "idle", cwd: "/home/q/me/work/api", display_agent: "",
  focused: false, pane_id: "w1:p1", terminal_title: "", workspace_id: "w1",
  agent_session: { value: "" }, state_change_seq: 0, ...over
})

// ---------- parseList ----------
assert.deepEqual(board.parseList(""), [])
assert.deepEqual(board.parseList("not json"), [])
assert.deepEqual(board.parseList(JSON.stringify({ hi: 1 })), [])
assert.equal(board.parseList(JSON.stringify([{ pane_id: "a" }])).length, 1)
assert.equal(board.parseList(JSON.stringify({ agents: [agent()] })).length, 1)
// The real herdr envelope nests one level deeper than the docs suggest.
assert.equal(board.parseList(JSON.stringify({
  id: "cli:agent:list", result: { type: "agent_list", agents: [agent(), agent({ pane_id: "b" })] }
})).length, 2)

// ---------- cwdTail ----------
assert.equal(board.cwdTail("/home/q/me/work/api"), "api")
assert.equal(board.cwdTail("/home/q/me/work/api/"), "api")
assert.equal(board.cwdTail("/"), "")
assert.equal(board.cwdTail(""), "")
assert.equal(board.cwdTail("/home/q", "/home/q"), "~")
assert.equal(board.cwdTail("/home/q/", "/home/q"), "~")
assert.equal(board.cwdTail("/home/q/me", "/home/q"), "me")
assert.equal(board.cwdTail("/home/q/me"), "me") // no home given -> plain tail

// ---------- rows: order, tie-breaks ----------
const mixed = [
  agent({ pane_id: "p-idle", agent_status: "idle", display_agent: "z" }),
  agent({ pane_id: "p-work", agent_status: "working", display_agent: "b" }),
  agent({ pane_id: "p-block", agent_status: "blocked", display_agent: "a" }),
  agent({ pane_id: "p-what", agent_status: "weird", display_agent: "c" }),
  agent({ pane_id: "p-done", agent_status: "done", display_agent: "d" })
]
assert.deepEqual(board.rows(mixed).map(r => r.pane),
  ["p-block", "p-work", "p-done", "p-idle", "p-what"])
// Same rank: the focused one first, then the most recent state change.
const same = [
  agent({ pane_id: "x1", agent_status: "working", state_change_seq: 5 }),
  agent({ pane_id: "x2", agent_status: "working", state_change_seq: 9, focused: true }),
  agent({ pane_id: "x3", agent_status: "working", state_change_seq: 7 })
]
assert.deepEqual(board.rows(same).map(r => r.pane), ["x2", "x3", "x1"])
// Alphabetical only when nothing else separates them.
const tie = [agent({ pane_id: "t2", display_agent: "beta" }), agent({ pane_id: "t1", display_agent: "alpha" })]
assert.deepEqual(board.rows(tie).map(r => r.title), ["alpha", "beta"])

// ---------- rows: fields ----------
const one = board.rows([agent({
  agent_status: "blocked", display_agent: "修登录", cwd: "/home/q", terminal_title: "π - q",
  agent_session: { value: "/home/q/.pi/agent/sessions/x.jsonl" }
})], "", "/home/q")[0]
assert.equal(one.status, "blocked")
assert.equal(one.statusLabel, "等你")
assert.equal(one.tone, "urgent")
assert.equal(one.title, "修登录")
assert.equal(one.folder, "~")
assert.equal(one.detail, "π - q")
assert.equal(one.pane, "w1:p1")
assert.equal(one.focused, false)
assert.equal(one.session, "/home/q/.pi/agent/sessions/x.jsonl")
// No display name, no terminal title: the harness name, then the pane, then a word.
assert.equal(board.rows([agent({ display_agent: "", terminal_title: "" })])[0].title, "pi")
assert.equal(board.rows([agent({ display_agent: "", terminal_title: "", agent: "" })])[0].title, "w1:p1")
assert.equal(board.rows([{ agent_status: "idle", pane_id: "", display_agent: "" }])
  .map(r => r.title).join(), "会话")
// A record with no pane still gets a stable key rather than `undefined`.
assert.equal(board.rows([{ agent_status: "idle", pane_id: "" }])[0].key, "会话|")

// ---------- rows: query ----------
assert.equal(board.rows(mixed, "").length, 5)
assert.equal(board.rows(mixed, "  ").length, 5)
assert.deepEqual(board.rows(mixed, "BLOCK").map(r => r.pane), ["p-block"])
assert.deepEqual(board.rows(mixed, "api").map(r => r.pane),
  ["p-block", "p-work", "p-done", "p-idle", "p-what"]) // every row runs in api/
assert.deepEqual(board.rows(mixed, "p-work").map(r => r.pane), ["p-work"])
assert.equal(board.rows(mixed, "pi").length, 5) // the harness name matches too
// The folder tail is searchable even though the full path is not shown.
assert.deepEqual(board.rows([agent({ cwd: "/home/q/x/keepme", pane_id: "k1" }),
  agent({ cwd: "/home/q/x/other", pane_id: "k2" })], "keepme").map(r => r.pane), ["k1"])
assert.deepEqual(board.rows(mixed, "nothing-matches"), [])

// ---------- counts / summary ----------
assert.deepEqual(board.counts([]), { blocked: 0, working: 0, done: 0, idle: 0, unknown: 0, total: 0 })
assert.deepEqual(board.counts(mixed), { blocked: 1, working: 1, done: 1, idle: 1, unknown: 1, total: 5 })
assert.equal(board.summary([]), "")
// 等你 > 等你看 > 在跑；"完成" 不再单列（它一定同时是「等你看」）。
assert.equal(board.summary(mixed), "1 等你 · 1 在跑")
assert.equal(board.summary([agent(), agent()]), "2 个空闲")
assert.equal(board.summary([agent({ agent_status: "working", agent_status_: 0 })]), "1 在跑")

// ---------- labels and tones ----------
assert.deepEqual(["blocked", "working", "done", "idle", "unknown", "", "bogus"].map(board.statusLabel),
  ["等你", "在跑", "完成", "空闲", "未知", "未知", "未知"])
assert.deepEqual(["blocked", "working", "done", "idle", "x"].map(board.statusTone),
  ["urgent", "accent", "done", "muted", "muted"])

// ---------- against the machine, when herdr is here ----------
let live = null
try { live = execFileSync("herdr", ["agent", "list"], { encoding: "utf8", timeout: 4000 }) } catch (e) { live = null }
if (live === null) {
  console.log("– herdr not reachable, live check skipped")
} else {
  const parsed = board.parseList(live)
  assert.ok(Array.isArray(parsed), "herdr output must parse to an array")
  for (const row of board.rows(parsed, "", "/home/qrfeng")) {
    assert.ok(row.pane !== "", "every herdr agent carries a pane target")
    assert.ok(row.title !== "", "every row needs a name to show")
    assert.ok(["idle", "working", "blocked", "done", "unknown"].indexOf(row.status) >= 0,
      `status herdr invented: ${row.status}`)
  }
  console.log(`– live: ${parsed.length} agent(s), summary "${board.summary(parsed)}"`)
}

// ---------- 「等你看」标记 ----------
const R = (o) => board.rows([agent(o)])[0]
const solo = (o) => board.rows([agent(o)])   // seenUpdate 吃的是 rowOf 之后的行
// 刚跑完 = done = 等你看
let up = board.seenUpdate(solo({ agent_status: "done" }), {}, 1000, 0)
assert.equal(up.flags["w1:p1"], "unseen")
// 之后 herdr 把 done 收回 idle，标记必须活下来
up = board.seenUpdate(solo({ agent_status: "idle" }), up.seen, 2000, 0)
assert.equal(up.flags["w1:p1"], "unseen")
// 跳过去看过（focused）就松手
up = board.seenUpdate(solo({ agent_status: "idle", focused: true }), up.seen, 3000, 0)
assert.equal(up.flags["w1:p1"], "")
// 再跑一轮 -> 回到 idle，又是一次「等你看」
up = board.seenUpdate(solo({ agent_status: "working" }), up.seen, 4000, 0)
assert.equal(up.flags["w1:p1"], "")
up = board.seenUpdate(solo({ agent_status: "idle" }), up.seen, 5000, 0)
assert.equal(up.flags["w1:p1"], "unseen")
// 钉过 ttl 自己松手（ttl 从第一次钉住那刻算）
up = board.seenUpdate(solo({ agent_status: "idle" }), up.seen, 5000 + 3 * 60 * 60 * 1000, 2 * 60 * 60 * 1000)
assert.equal(up.flags["w1:p1"], "")
// blocked 永远算等你，不需要历史
assert.equal(board.seenUpdate(solo({ agent_status: "blocked" }), {}, 1, 0).flags["w1:p1"], "waiting")
// blocked 是活状态：批准完继续跑，红色必须当场退掉（不钉）
let bl = board.seenUpdate(solo({ agent_status: "blocked" }), {}, 1, 0)
assert.equal(bl.flags["w1:p1"], "waiting")
assert.equal(board.seenUpdate(solo({ agent_status: "working" }), bl.seen, 2, 0).flags["w1:p1"], "")
// 空闲的、从没动过的不该凭空长记号
assert.equal(board.seenUpdate(solo({ agent_status: "idle" }), {}, 1, 0).flags["w1:p1"], "")
// 跳过去之后本地立刻抹掉，不用等下一次采样
let seen = board.seenUpdate(solo({ agent_status: "done" }), {}, 10, 0).seen
assert.equal(board.markSeen(seen, "w1:p1")["w1:p1"].flag, "")
assert.equal(board.markSeen(seen, "w1:p9")["w1:p1"].flag, "unseen")

// ---------- annotate：全量 + 标记 + 顺序 ----------
// 同一个项目下的三行（分组另有一组测试）
const many = [
  agent({ pane_id: "w1:p1", agent_status: "idle", cwd: "/srv/app" }),
  agent({ pane_id: "w1:p2", agent_status: "blocked", cwd: "/srv/app" }),
  agent({ pane_id: "w1:p3", agent_status: "working", cwd: "/srv/app" }),
]
let an = board.annotate(many, { home: "/home/u", seen: { "w1:p1": { status: "working", flag: "", since: 1 } }, now: 5 })
// 顺序：等你处理(blocked) > 等你看(跑完没回来看) > 在跑 > 空闲
assert.deepEqual(an.rows.map(r => r.key), ["w1:p2", "w1:p1", "w1:p3"])
assert.equal(an.rows[0].attentionLabel, "等你")
assert.equal(an.rows[1].attention, "unseen")
assert.equal(an.rows[1].attentionLabel, "等你看")
assert.equal(board.summary(many, an.flags), "1 等你 · 1 等你看 · 1 在跑")

// ---------- items：分组标题 ----------
assert.equal(board.items(an.rows, "").filter(r => r.header).length, 0)   // 一个项目 => 不插标题
const grouped = board.annotate([
  agent({ pane_id: "w1:p1", cwd: "/srv/alpha" }),
  agent({ pane_id: "w1:p2", cwd: "/srv/alpha" }),
  agent({ pane_id: "w1:p3", cwd: "/srv/beta", agent_status: "blocked" }),
], { home: "/home/u", seen: {}, now: 1 }).rows
const g = board.items(grouped, "")
assert.deepEqual(g.map(r => (r.header ? "#" : r.key)), ["#", "w1:p3", "#", "w1:p1", "w1:p2"])
assert.equal(g[0].label, "beta")          // 最急的组排前面
assert.equal(g[0].count, 1)
assert.equal(g[2].count, 2)
assert.equal(g[0].disabled, true)         // 标题行不可选（ListPicker 会跳过）
// 搜索搜到只剩一个项目时，标题也跟着消失（规则只有一条：多于一个项目才分组长）
const filtered = board.items(grouped, "alpha")
assert.deepEqual(filtered.map(r => (r.header ? "#" : r.key)), ["w1:p1", "w1:p2"])
// 只剩一个项目时不该有标题
assert.deepEqual(board.items(grouped, "beta").map(r => r.key), ["w1:p3"])

// ---------- parseStatus：盘上的 herdr 比在跑的 server 新 ----------
const status = (over = {}) => JSON.stringify({
  client: { version: "0.9.3" },
  server: { running: true, version: "0.9.1", server_binary_stale: false },
  update: { restart_needed: false, server_binary_stale: false }, ...over
})
assert.deepEqual(board.parseStatus(""), { stale: false, client: "", server: "" })
assert.deepEqual(board.parseStatus("not json"), { stale: false, client: "", server: "" })
assert.deepEqual(board.parseStatus("null"), { stale: false, client: "", server: "" })
assert.deepEqual(board.parseStatus(status()), { stale: false, client: "0.9.3", server: "0.9.1" })
// 两处都得认：`update.server_binary_stale` 与 `server.server_binary_stale`
assert.equal(board.parseStatus(status({ update: { server_binary_stale: true } })).stale, true)
assert.equal(board.parseStatus(status({
  server: { running: true, version: "0.9.1", server_binary_stale: true } })).stale, true)
// server 没在跑 ⇒ 没有旧进程卡着，不该说「需重启」（但版本要报得出来）
assert.deepEqual(board.parseStatus(status({ server: { running: false } })),
  { stale: false, client: "0.9.3", server: "" })
// 字段缺了也不抛
assert.deepEqual(board.parseStatus('{"client":{}}'), { stale: false, client: "", server: "" })

console.log("board.js ok")
