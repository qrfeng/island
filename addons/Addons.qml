import QtQuick
import Quickshell.Io

// Addons: niche features kept out of the core, each switched on in Settings →
// Addons and kept in its own folder here. An addon's files are only read
// while it's enabled: its root (an Addon) is loaded from its file then, and
// everything it adds to the island is declared inside that root.
Item {
  id: addons
  required property var host
  required property var settings

  // Each addon: id, name, icon (and its color, and optionally iconLayers drawn
  // in its place, see PaneIcon), description, whether it starts enabled, its
  // root file (relative to this folder), and its options
  // ({ key, label, detail, type: "switch" | "popup" | "text", default, choices,
  // placeholder }). Its views' keybindings are tagged with its id in
  // companion/bindings.sh.
  readonly property var entries: [
    { id: "weather", name: "天气", icon: "󰖐", color: "#1f8ef1", default: false, source: "weather/WeatherAddon.qml",
      iconLayers: [
        { circle: true, color: "#ffd60a", x: 0.65, y: 0.37, size: 0.36 },
        { glyph: "󰅟", color: "#ffffff", opacity: 0.9, x: 0.45, y: 0.57, size: 0.74 }
      ],
      description: "你所在城市的实时天气",
      options: [
        { key: "city", label: "城市", detail: "通过 Open-Meteo 查询", type: "text", default: "", placeholder: "例如：上海" },
        { key: "fahrenheit", label: "华氏度", detail: "以 °F 代替 °C", type: "switch", default: false }
      ] },
    { id: "calendar", name: "日历", icon: "󰃭", color: "#f7f7f7", default: false, source: "calendar/CalendarAddon.qml",
      iconLayers: [
        { rect: true, color: "#f2564f", x: 0.5, y: 0.13, width: 1, height: 0.36 },
        { date: "month", color: "#ffffff", weight: Font.Bold, x: 0.5, y: 0.17, size: 0.2 },
        { date: "day", color: "#2c2c2e", weight: Font.Light, x: 0.5, y: 0.63, size: 0.56 }
      ],
      description: "本月日历与当日日程",
      options: [
        { key: "urls", label: "订阅日历", detail: "ICS 链接，用空格分隔", type: "text", default: "", placeholder: "https://…/basic.ics" }
      ] },
    { id: "timer", name: "计时器", icon: "󰔛", color: "#1c1c1e", default: false, source: "timer/TimerAddon.qml",
      iconLayers: [
        { rect: true, color: "#ff9f0a", x: 0.5, y: 0.13, width: 0.2, height: 0.08, radius: 0.5 },
        { circle: true, color: "#ff9f0a", x: 0.5, y: 0.56, size: 0.68 },
        { circle: true, color: "#1c1c1e", x: 0.5, y: 0.56, size: 0.52 },
        { rect: true, color: "#ffffff", x: 0.5, y: 0.47, width: 0.07, height: 0.2, radius: 0.5 },
        { circle: true, color: "#ffffff", x: 0.5, y: 0.56, size: 0.1 }
      ],
      description: "在胶囊上显示倒计时" },
    { id: "stats", name: "资源监控", icon: "󰓅", color: "#232325", default: true, source: "stats/StatsAddon.qml",
      // Activity Monitor's: a red and a blue wave either side of a line,
      // over a faint grid.
      iconLayers: [1, 2, 3, 4, 5, 6, 7].reduce(function(grid, n) {
        return grid.concat([
          { rect: true, color: "#ffffff", opacity: 0.07, x: 0.5, y: n / 8, width: 1, height: 0.01 },
          { rect: true, color: "#ffffff", opacity: 0.07, x: n / 8, y: 0.5, width: 0.01, height: 1 }
        ])
      }, []).concat([
        { line: wave(-1, [0.22, 0.34, 0.49, 0.63, 0.76], [0.07, 0.15, 0.25, 0.12, 0.15]), color: "#ff6b5e", fill: true },
        { line: wave(1, [0.3, 0.42, 0.55, 0.67, 0.77], [0.08, 0.17, 0.27, 0.15, 0.08]), color: "#3d8bff", fill: true },
        { rect: true, color: "#ff6b5e", x: 0.5, y: 0.492, width: 1, height: 0.03 },
        { rect: true, color: "#3d8bff", x: 0.5, y: 0.518, width: 1, height: 0.025 }
      ]),
      description: "CPU、内存、GPU、磁盘实时用量" },
    { id: "tray", name: "系统托盘", icon: "󰀻", color: "#5e5ce6", default: false, source: "tray/TrayAddon.qml",
      iconLayers: [
        { rect: true, color: "#ffffff", opacity: 0.95, x: 0.5, y: 0.26, width: 0.8, height: 0.14, radius: 0.5 },
        { circle: true, color: "#34c759", x: 0.56, y: 0.26, size: 0.07 },
        { circle: true, color: "#ff9f0a", x: 0.68, y: 0.26, size: 0.07 },
        { circle: true, color: "#5e5ce6", x: 0.8, y: 0.26, size: 0.07 },
        { rect: true, color: "#ffffff", opacity: 0.95, x: 0.66, y: 0.61, width: 0.52, height: 0.46, radius: 0.16 },
        { rect: true, color: "#c7c7cc", x: 0.66, y: 0.47, width: 0.34, height: 0.05, radius: 0.5 },
        { rect: true, color: "#5e5ce6", x: 0.66, y: 0.61, width: 0.44, height: 0.12, radius: 0.3 },
        { rect: true, color: "#ffffff", x: 0.66, y: 0.61, width: 0.34, height: 0.05, radius: 0.5 },
        { rect: true, color: "#c7c7cc", x: 0.66, y: 0.75, width: 0.34, height: 0.05, radius: 0.5 }
      ],
      description: "应用托盘图标与菜单" },
    { id: "plugins", name: "插件", icon: "󰐱", color: "#ff9f0a", default: false, source: "plugins/PluginsAddon.qml",
      iconLayers: [
        { rect: true, color: "#ffffff", x: 0.33, y: 0.33, width: 0.3, height: 0.3, radius: 0.28 },
        { rect: true, color: "#ffffff", x: 0.67, y: 0.33, width: 0.3, height: 0.3, radius: 0.28 },
        { rect: true, color: "#ffffff", x: 0.33, y: 0.67, width: 0.3, height: 0.3, radius: 0.28 },
        { rect: true, color: "#ffffff", opacity: 0.4, x: 0.67, y: 0.67, width: 0.3, height: 0.3, radius: 0.28 },
        { glyph: "󰐕", color: "#ffffff", x: 0.67, y: 0.67, size: 0.28 }
      ],
      description: "打开与切换 Omarchy 插件" },
    { id: "keyboard", name: "键盘布局", icon: "󰌌", color: "#30b0c7", default: false, source: "keyboard/KeyboardAddon.qml",
      iconLayers: [{ rect: true, color: "#ffffff", x: 0.5, y: 0.55, width: 0.8, height: 0.5, radius: 0.16 }]
        .concat([0.41, 0.55].reduce(function(keys, y) {
          return keys.concat([0.23, 0.365, 0.5, 0.635, 0.77].map(function(x) {
            return { rect: true, color: "#a9bcc2", x: x, y: y, width: 0.1, height: 0.09, radius: 0.25 }
          }))
        }, []))
        .concat([{ rect: true, color: "#a9bcc2", x: 0.5, y: 0.69, width: 0.5, height: 0.09, radius: 0.4 }]),
      description: "切换布局时在胶囊上提示" },
    { id: "calculator", name: "计算器", icon: "=", color: "#ff9f0a", default: true,
      source: "calculator/CalculatorAddon.qml",
      // The macOS calculator: a dark key with its screen, and the equals bar.
      iconLayers: [
        { rect: true, color: "#1c1c1e", x: 0.5, y: 0.5, width: 0.94, height: 0.94, radius: 0.26 },
        { rect: true, color: "#ffffff", opacity: 0.85, x: 0.5, y: 0.3, width: 0.62, height: 0.15, radius: 0.3 },
        { rect: true, color: "#ff9f0a", x: 0.5, y: 0.6, width: 0.44, height: 0.085, radius: 0.4 },
        { rect: true, color: "#ff9f0a", x: 0.5, y: 0.75, width: 0.44, height: 0.085, radius: 0.4 }
      ],
      description: "启动器里输算式，回车复制结果" },
    { id: "ask", name: "问 AI", icon: "󰚩", color: "#000000", default: true, source: "ask/AskAddon.qml",
      // Siri's: a glass sphere on black, with a ribbon of light across it,
      // white in the middle and tinted orange and blue at its edges.
      iconLayers: [
        { circle: true, color: "#e5e5ea", opacity: 0.9, x: 0.5, y: 0.5, size: 0.78 },
        { circle: true, color: "#7c7c82", x: 0.5, y: 0.5, size: 0.75 },
        { circle: true, color: "#2c2c2e", opacity: 0.75, x: 0.5, y: 0.47, size: 0.62 },
        { circle: true, color: "#ffffff", opacity: 0.12, x: 0.42, y: 0.32, size: 0.3 },
        siriWave(0.2, 0.8, 0.012, "#ff9f0a", 0.45, 0.035),
        siriWave(0.2, 0.8, -0.012, "#64d2ff", 0.45, 0.035),
        siriWave(0.16, 0.84, 0, "#ffffff", 0.3, 0.09),
        siriWave(0.24, 0.76, 0, "#ffffff", 0.55, 0.045),
        siriWave(0.34, 0.66, 0, "#ffffff", 0.95, 0.03)
      ],
      description: "启动器的问题由 Pi 在 island 内回答",
      options: [
        { key: "web", label: "联网搜索", detail: "可联网查证：更慢，只搜索和阅读网页", type: "switch", default: true }
      ] },
    { id: "agents", name: "Agent", icon: "\uf201", color: "#30d158", default: true,
      source: "agents/AgentsAddon.qml",
      description: "编程 agent 的会话看板与已用 tokens（herdr 在跑时看板才有内容）",
      options: [
        { key: "refresh", label: "刷新", detail: "视图打开时重新读取数据的频率",
          type: "popup", default: "15 minutes", choices: [
            { label: "5分钟", value: "5 minutes" }, { label: "15分钟", value: "15 minutes" },
            { label: "30分钟", value: "30 minutes" }, { label: "1小时", value: "1 hour" }] },
        { key: "rate", label: "美元兑人民币", detail: "把接口的美元金额折算成人民币",
          type: "text", default: "6.69", placeholder: "例如：6.69" },
        { key: "others", label: "显示 Codex 和 Fireworks", detail: "也列出这两个工具并联网查询限额；Pi 和 Claude Code 始终读各自会话",
          type: "switch", default: false }
      ] },
    { id: "todos", name: "待办", icon: "󰝖", color: "#34c759", default: true,
      source: "todos/TodosAddon.qml",
      // Apple Reminders' tile: a dark card, one green tick, and the list under
      // it fading away as it goes down.
      iconLayers: [
        { rect: true, color: "#1c1c1e", x: 0.5, y: 0.5, width: 0.94, height: 0.94, radius: 0.26 },
        { glyph: "󰄬", color: "#34c759", x: 0.26, y: 0.3, size: 0.34 },
        { rect: true, color: "#ffffff", opacity: 0.9, x: 0.66, y: 0.3, width: 0.5, height: 0.075, radius: 0.5 },
        { glyph: "󰄰", color: "#8e8e93", x: 0.26, y: 0.52, size: 0.26 },
        { rect: true, color: "#ffffff", opacity: 0.55, x: 0.66, y: 0.52, width: 0.5, height: 0.075, radius: 0.5 },
        { glyph: "󰄰", color: "#8e8e93", x: 0.26, y: 0.73, size: 0.26 },
        { rect: true, color: "#ffffff", opacity: 0.3, x: 0.66, y: 0.73, width: 0.4, height: 0.075, radius: 0.5 }
      ],
      description: "todo.txt 文件，在 island 内勾选",
      options: [
        { key: "path", label: "文件", detail: "纯文本 todo.txt，任何编辑器都能改",
          type: "text", default: "~/.local/share/todos/todo.txt", placeholder: "~/.local/share/todos/todo.txt" },
        { key: "done", label: "已完成任务", detail: "继续列出多久以内的完成项",
          type: "popup", default: "Last 7 days", choices: [
            { label: "不显示", value: "Hide" }, { label: "最近3天", value: "Last 3 days" },
            { label: "最近7天", value: "Last 7 days" }, { label: "最近30天", value: "Last 30 days" },
            { label: "一直显示", value: "Always" }] },
        { key: "group", label: "按项目分组", detail: "未完成项按 +project 归类（列表内按 g 切换）",
          type: "popup", default: "By project", choices: [{ label: "关闭", value: "Off" }, { label: "按项目", value: "By project" }] },
        { key: "archive", label: "归档已完成任务", detail: "完成项超过这个天数就移到同目录 done.txt",
          type: "popup", default: "After 30 days", choices: [
            { label: "关闭", value: "Off" }, { label: "7天后", value: "After 7 days" },
            { label: "30天后", value: "After 30 days" }, { label: "90天后", value: "After 90 days" }] }
      ] },
    { id: "missions", name: "Mission", icon: "\u25ce", color: "#ff9f0a", default: false,
      source: "missions/MissionsAddon.qml",
      // A target with a ring around it: work that outlives the session that started it.
      iconLayers: [
        { rect: true, color: "#1c1c1e", x: 0.5, y: 0.5, width: 0.94, height: 0.94, radius: 0.26 },
        { glyph: "◎", color: "#ff9f0a", x: 0.5, y: 0.5, size: 0.46 },
        { glyph: "󰄬", color: "#ffffff", opacity: 0.85, x: 0.74, y: 0.72, size: 0.26 }
      ],
      description: "pi-subagents 的 durable 记录：状态、等回答、token（只读）",
      options: [
        { key: "path", label: "记录目录", detail: "pi-subagents 写 mission 的地方",
          type: "text", default: "~/.pi/agent/missions", placeholder: "~/.pi/agent/missions" },
        { key: "done", label: "已收口的", detail: "继续列多久以内的完成/失败项",
          type: "popup", default: "Last 7 days", choices: [
            { label: "不显示", value: "Hide" }, { label: "最近7天", value: "Last 7 days" },
            { label: "最近30天", value: "Last 30 days" }, { label: "一直显示", value: "Always" }] }
      ] },
    { id: "inputmethod", name: "输入法", icon: "󰍛", color: "#5ac8fa", default: true,
      source: "inputmethod/InputMethodAddon.qml",
      // The key the user is actually pressing: a keycap, and the letter on it.
      iconLayers: [
        { rect: true, color: "#1c1c1e", x: 0.5, y: 0.5, width: 0.94, height: 0.94, radius: 0.26 },
        { glyph: "󰌌", color: "#5ac8fa", x: 0.34, y: 0.64, size: 0.44 },
        { glyph: "A", color: "#ffffff", x: 0.68, y: 0.36, size: 0.32 }
      ],
      description: "fcitx5 的中英文：控制中心一键切换，要的话切换时提示",
      options: [
        { key: "labels", label: "输入法名称", detail: "把 fcitx5 的内部名改成你看得懂的词，逗号分隔",
          type: "text", default: "", placeholder: "例如：rime=雾凇拼音,keyboard-us=英文" },
        // 胶囊只能长在岛顶部（layer panel 跟不到光标，也到不了另一块屏），而他按快捷键切的是
        // 会话：位置对不上就变成误导，所以默认不弹，状态看控制中心那块磁贴。
        { key: "popup", label: "切换时弹提示", detail: "胶囊只出现在岛顶部，不在你正在打字的会话旁边；关掉后看「输入法」磁贴",
          type: "switch", default: false }
      ] }
  ]

  // A smooth wave off the icon's middle line, rising (sign -1) or falling,
  // with a bump of each height at each x; for the System Stats icon.
  function wave(sign, centers, heights) {
    var points = [[0, 0.5]]
    for (var x = 0; x <= 1.0001; x += 0.0125) {
      var y = 0
      for (var i = 0; i < centers.length; i++) y += heights[i] * Math.exp(-Math.pow((x - centers[i]) / 0.042, 2))
      points.push([x, 0.5 + sign * Math.min(0.34, y)])
    }
    points.push([1, 0.5])
    return points
  }
  // Part of Siri's ribbon of light, from x `from` to `to`, shifted down by
  // `dy`: an S across the sphere, for the Ask AI icon.
  function siriWave(from, to, dy, color, opacity, width) {
    var points = []
    for (var x = from; x <= to + 0.0001; x += 0.01)
      points.push([x, 0.54 + dy - 0.045 * Math.sin((x - 0.2) / 0.6 * 2 * Math.PI)])
    return { line: points, color: color, opacity: opacity, width: width }
  }
  function entry(id) {
    for (var i = 0; i < entries.length; i++) if (entries[i].id === id) return entries[i]
    return null
  }
  function isEnabled(id) {
    var saved = settings.addons || {}
    if (saved[id] !== undefined) return !!saved[id]
    var e = entry(id)
    return !!(e && e.default)
  }
  function setEnabled(id, on) {
    var next = Object.assign({}, settings.addons || {})
    next[id] = !!on
    settings.addons = next
  }
  function option(id, key) {
    var saved = (settings.addonOptions || {})[id] || {}
    if (saved[key] !== undefined) return saved[key]
    var e = entry(id)
    var options = e && e.options || []
    for (var i = 0; i < options.length; i++) if (options[i].key === key) return options[i].default
    return undefined
  }
  function setOption(id, key, value) {
    var next = Object.assign({}, settings.addonOptions || {})
    next[id] = Object.assign({}, next[id] || {})
    next[id][key] = value
    settings.addonOptions = next
  }

  // Ask AI was core, set by `askAi` ("claude", "chatgpt" for Codex, or
  // "none" for off): carried over once to its addon, then cleared. Late,
  // so the addon settings it fills in are loaded first.
  Connections {
    target: addons.settings
    function onAskAiChanged() { Qt.callLater(addons.migrateAsk) }
  }
  function migrateAsk() {
    var old = settings.askAi
    if (!old) return
    if ((settings.addons || {}).ask === undefined) setEnabled("ask", old !== "none")
    settings.askAi = ""
  }

  // A disabled addon's keybindings are switched off in island-bindings.lua,
  // their keys kept (see companion/bindings.sh). Synced on start and on
  // each change; the script does nothing when the list is unchanged.
  readonly property string enabledIds: entries.filter(function(e) { return addons.isEnabled(e.id) })
    .map(function(e) { return e.id }).join(",")
  onEnabledIdsChanged: syncBindings()
  Component.onCompleted: { syncBindings(); Qt.callLater(migrateAsk) }
  property bool bindingsStale: false
  Process {
    id: bindingSync
    onExited: if (addons.bindingsStale) addons.syncBindings()
  }
  function syncBindings() {
    if (bindingSync.running) { bindingsStale = true; return }
    bindingsStale = false
    bindingSync.command = ["bash", host.setup.companionDir + "/bindings.sh", "addons", enabledIds]
    bindingSync.running = true
  }

  // The enabled addons' roots, in registry order.
  property var loaded: []
  function collect() {
    var roots = []
    for (var i = 0; i < slots.count; i++) {
      var slot = slots.itemAt(i)
      if (slot && slot.item) roots.push(slot.item)
    }
    loaded = roots
  }
  Repeater {
    id: slots
    model: addons.entries
    delegate: Loader {
      id: slot
      required property var modelData
      readonly property bool wanted: addons.isEnabled(modelData.id)
      onWantedChanged: load()
      Component.onCompleted: load()
      function load() {
        if (!wanted) { source = ""; return }
        var e = modelData
        slot.setSource(addons.url(Qt.resolvedUrl(e.source)), {
          host: addons.host,
          addon: {
            id: e.id, name: e.name,
            option: function(key) { return addons.option(e.id, key) },
            setOption: function(key, value) { addons.setOption(e.id, key, value) }
          }
        })
      }
      onItemChanged: addons.collect()
    }
  }

  // Quickshell 0.3.2 serves this plugin's tree through its own `qs:` VFS, and a
  // file *loaded at runtime* with such a URL compiles with its own file name
  // taken as its directory: every relative import inside it then misses, and
  // the addon loads as an empty item ("WeatherView is not a type"). Compiling
  // the same file from a plain `file:` URL resolves them normally, so the URLs
  // handed to Loader.setSource are normalized here.
  function url(u) {
    var s = String(u)
    return s.indexOf("qs:") === 0 ? "file:" + s.replace(/^qs:\/\/?/, "") : s
  }

  // A `qs:`/`file:` URL as the path on disk it names, for spawning processes.
  function path(u) {
    var s = String(u)
    var m = s.match(/^[a-zA-Z][a-zA-Z0-9+.\-]*:\/\/?/)
    if (m) s = s.slice(m[0].length)
    return decodeURIComponent(s)
  }

  // An enabled addon's root by id, or null.
  function root(id) {
    for (var i = 0; i < loaded.length; i++) if (loaded[i].addon.id === id) return loaded[i]
    return null
  }

  // The enabled addons' launcher rows for the typed text (see Addon.qml),
  // and what they add to its placeholder.
  function launcherRows(text) {
    var rows = []
    for (var i = 0; i < loaded.length; i++) {
      var row = loaded[i].launcherRow(text)
      if (row) rows.push(Object.assign({ addonRow: true }, row))
    }
    return rows
  }
  readonly property var launcherHints: loaded.map(function(own) { return own.launcherHint })
    .filter(function(hint) { return hint !== "" })

  // The live activity on the island now, if an addon's: the feedback kind
  // "addon:<id>" names it.
  function pillFor(kind) {
    if (String(kind).indexOf("addon:") !== 0) return null
    var id = String(kind).slice(6)
    for (var i = 0; i < loaded.length; i++)
      if (loaded[i].addon.id === id && loaded[i].pill) return loaded[i]
    return null
  }

  // The addon whose ongoing activity holds the resting island, if any: the
  // first in registry order with `ongoing` set.
  readonly property var ongoing: {
    for (var i = 0; i < loaded.length; i++)
      if (loaded[i].ongoing && loaded[i].pill) return loaded[i]
    return null
  }

  // Every enabled addon's views, and its control center tiles keyed
  // "<addon id>.<tile key>".
  readonly property var views: {
    var result = []
    for (var i = 0; i < loaded.length; i++) result = result.concat(loaded[i].views || [])
    return result
  }
  readonly property var tiles: {
    var result = []
    for (var i = 0; i < loaded.length; i++) {
      var own = loaded[i].tiles || []
      for (var j = 0; j < own.length; j++)
        result.push(Object.assign({}, own[j], { key: loaded[i].addon.id + "." + own[j].key }))
    }
    return result
  }
  // Every enabled addon's Settings panes, in registry order.
  readonly property var settingsPages: {
    var result = []
    for (var i = 0; i < loaded.length; i++) {
      // Drawn with its addon's icon unless it has its own.
      var own = entry(loaded[i].addon.id)
      result = result.concat((loaded[i].settingsPages || []).map(function(page) {
        return Object.assign({ icon: own.icon, color: own.color, iconLayers: own.iconLayers }, page)
      }))
    }
    return result
  }
  function settingsPage(title) {
    for (var i = 0; i < settingsPages.length; i++) if (settingsPages[i].title === title) return settingsPages[i]
    return null
  }
  function tileFor(key) {
    for (var i = 0; i < tiles.length; i++) if (tiles[i].key === key) return tiles[i]
    return null
  }
}
