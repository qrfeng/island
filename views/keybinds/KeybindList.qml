import QtQuick
import Quickshell
import Quickshell.Io
import "../../components"

// Keybindings: the shared list view over every layer that gets a say in what a
// keystroke does.
//
// A key is offered to three owners, outermost first: Hyprland (it sees the
// SUPER chords first), then ghostty (its own `keybind` entries), then herdr
// running inside that window. Omarchy's own list only describes the first
// layer, which is why this view reads two sources:
//
//   * omarchy-menu-keybindings - the Hyprland bindings. They stay the only
//     rows this view can *run*, because dispatch_binding needs the dispatcher
//     and the argument this source provides.
//   * `omarchy-keybinds list` (the meviusisback.keybinds plugin) - the two
//     read-only layers inside the terminal window, and which of their chords
//     never reach the layer that declared them (`shadowed_by`, shown DEAD).
//     Parsing ghostty's CLI and herdr's [keys] table here would mean a second,
//     worse copy of rules that plugin already owns; its rows also carry
//     `managed_by`, which is exactly the "another file owns this" flag. If that
//     plugin is not installed the command finds nothing and this view is
//     exactly what it has always been.
//
// Type to search by description or keys ("super t", "alt esc", "herdr",
// "ghostty", "dead", "解绑"), Enter or a click to run a Hyprland binding. The
// terminal rows are reference only - they live in another config file - so
// they are listed dimmed and the cursor steps over them.
ListPicker {
  id: keybinds
  // A blank panel with no clue is what made this view impossible to debug
  // remotely, so state the two source counts where they are impossible to miss.
  placeholder: "搜索快捷键（名称或键位，直接打字）"
  emptyText: "这个分组里没有匹配的快捷键"
  rowHeight: 44
  visibleRows: 9
  disabledOpacity: 0.62
  tabs: tabList
  tabIndex: tab
  onTabChosen: function(index) { tab = index }

  property var hyprland: []
  property var terminal: []
  // `all` is this view's own unfiltered list; the rendered model is the
  // INHERITED ListPicker `items`, which must never be redeclared here. A
  // `property var items` (even a readonly binding) in a derived QML type
  // shadows the base property instead of overriding it: ListPicker's GridView
  // keeps binding `model: picker.items` to the base slot, so the view renders
  // nothing and shows its empty state while this file's own `items` happily
  // counts 280+ rows - the "no keybindings, and I searched nothing" report.
  // (views/menu/OmarchyMenu.qml had already dodged the same trap via `items_`.)
  property var all: []
  // Group tabs. Labels and order come from the keybinds plugin (`groups`); the
  // counts are recomputed here so a tab can never advertise a row it does not
  // show. Without that plugin the list stays one flat 全部 tab.
  property var groupOrder: []
  property var groupLabel: ({})
  property int tab: 0
  readonly property var tabList: {
    var out = [{ label: "全部", count: all.length }]
    groupOrder.forEach(function(cat) {
      var n = 0
      all.forEach(function(b) { if (b.category === cat) n += 1 })
      if (n) out.push({ id: cat, label: String(groupLabel[cat] || cat), count: n })
    })
    return out
  }
  // Hyprland rows come from Omarchy's script, which says nothing about
  // categories, so the plugin's own Hyprland rows are indexed by chord (and,
  // failing that, by description) to label them. `#` chords win over `@`
  // descriptions because three bindings share a label with their island twin.
  property var catOf: ({})
  // Same index, but to the plugin's Chinese label: Omarchy's own list only
  // speaks English ("Focus on left window"), and he reads this view to learn.
  property var zhOf: ({})
  // Chords the plugin reports as unbound. Omarchy's own reader is a union of
  // `hyprctl binds` and a scan of the upstream Lua (omarchy-menu-keybindings:
  // dynamic_bindings | static_bindings), so a chord disabled in
  // ~/.config/hypr/bindings.lua still comes back through the static half -
  // the ten `SUPER + SHIFT + ALT + <n>` "Move window silently to workspace N"
  // lines kept showing up after they were cut. This view is read to learn what
  // a key does, so a chord that does nothing must not be listed.
  property var deadChords: ({})
  // Two rows Omarchy does not derive from anything: they are echoed verbatim by
  // `static_bindings()` in omarchy-menu-keybindings (a `sendshortcut` hint for a
  // binding the user has to create himself). They are never in `hyprctl binds`
  // and the keybinds plugin does not report them, so the index above has nothing
  // to match them against. Cut 2026-10-15 on request.
  readonly property var staticHints: ({"SHIFT + ALT + D": true, "SHIFT + ALT + L": true})
  // Fallback bucket, identical to the plugin's CATEGORY_SYSTEM.
  readonly property string fallbackCategory: "\u2699\ufe0f System"
  // Identical to the plugin's CATEGORY_ISLAND (U+1F9CA, written as a surrogate
  // pair because QML has no \U escape). An island row IS a Hyprland binding - the
  // island writes island-bindings.lua - so it arrives through Omarchy's reader and
  // only learns its owner from the chord index below. The badge is what tells the
  // two apart in the 全部 tab, where the group tab cannot say it.
  readonly property string islandCategory: "\ud83e\uddca Island"

  // "SUPER SHIFT + RETURN" and "SUPER + SHIFT + RETURN" are the same chord to
  // two different sources; canonicalise both to the plugin's spacing.

  function normChord(chord) {
    var out = []
    String(chord || "").split("+").forEach(function(part) {
      part.trim().split(/\s+/).forEach(function(token) { if (token) out.push(token) })
    })
    return out.join(" + ").toUpperCase()
  }
  function categoryFor(entry) {
    var map = keybinds.catOf
    var hit = map["#" + entry.chord]
    if (hit) return hit
    hit = map["@" + String(entry.english || entry.name || "").toLowerCase()]
    return hit || keybinds.fallbackCategory
  }

  // Two lines exist only in Omarchy's own list (the plugin never reports them),
  // so they would be the only English rows left in a learning view.
  function labelFor(entry) {
    var map = keybinds.zhOf
    var hit = String(map["#" + entry.chord] || map["@" + String(entry.english || "").toLowerCase()] || "")
    if (hit) return hit
    var local = {
      "download video from web app": "从网页应用下载视频",
      "copy url from web app": "复制网页应用链接",
    }
    return String(local[String(entry.english || "").toLowerCase()] || "")
  }

  function rebuildAll() {
    // Category is resolved here, not while parsing: the two readers race, and
    // whichever arrives second is the one that knows the categories.
    // Only when the plugin answered (deadChords non-empty): without it this view
    // has no idea what is unbound, and hiding rows on a guess is worse than
    // showing a stale one.
    var dead = keybinds.deadChords
    var hints = keybinds.staticHints
    keybinds.all = keybinds.hyprland.filter(function(b) { return !dead[b.chord] && !hints[b.chord] }).map(function(b) {
      b.category = keybinds.categoryFor(b)
      // Owner badge for the island's own chords (see islandCategory).
      if (b.category === keybinds.islandCategory) b.layerName = "island"
      // The plugin's Chinese label wins; the English line stays in `english` so
      // the lookup above still hits on a re-read and search keeps matching both.
      var zh = keybinds.labelFor(b)
      if (zh) b.name = zh
      b.search = (b.name + " " + b.english + " " + b.caps.join(" ")).toLowerCase()
      return b
    }).concat(keybinds.terminal)
    keybinds.applyFilter()
  }
  // Every row is in the model from the first frame: components/ListPicker.qml
  // renders it through a GridView, which already instantiates only the visible
  // cells, so slicing the model here would only hide rows from the wheel and
  // the cursor. Measured: slicing changed nothing (the cost is elsewhere).
  function applyFilter() {
    var list = keybinds.all
    // Tab 0 is 全部; any other tab keeps one category. A tab whose rows all
    // disappeared on the last reload falls back to 全部 instead of an empty pane.
    if (keybinds.tab >= keybinds.tabList.length) keybinds.tab = 0
    var id = String(keybinds.tabList[keybinds.tab].id || "")
    if (id) list = list.filter(function(b) { return b.category === id })
    var q = query.trim().toLowerCase()
    if (!q) { keybinds.items = list; return }
    var terms = q.split(/\s+/)
    keybinds.items = list.filter(function(b) {
      // The summary row only makes sense as a map of the unfiltered list.
      if (b.hint) return false
      return terms.every(function(t) { return String(b.search || "").indexOf(t) !== -1 })
    })
  }
  onQueryChanged: applyFilter()
  onTabChanged: applyFilter()
  onChosen: function(entry) { run(entry) }
  // Both layers are read fresh on every open, because bindings change while the
  // island is closed (a ghostty reload, a herdr config edit). Reading them the
  // instant the panel opens is what made opening this view the slowest one:
  // the two scripts finish while the morph is running and all ~400 rows are
  // rebuilt on the animation's worst frame. So the first read happens when the
  // view is built (off any animation) and a re-read waits for the rows already
  // on screen to be revealed.
  Component.onCompleted: { rebuildAll(); readLayers() }
  onActiveChanged: {
    if (!active) return
    if (all.length) refreshTimer.restart()
    else readLayers()
  }
  function readLayers() {
    if (!loader.running) loader.running = true
    if (!layerLoader.running) layerLoader.running = true
  }
  // An empty list is never a supported state for this view: both readers either
  // produce rows or fail, and a blank panel gave no clue which one. Log it and
  // retry a few times, since the usual cause is a reader whose process lost the
  // race against a slow CLI (the terminal layer takes ~1s).
  property int emptyReads: 0
  function noteRead() {
    if (hyprland.length || terminal.length) { emptyReads = 0; return }
    emptyReads += 1
    console.warn("island: keybinding list came back empty (read " + emptyReads + ")")
    if (emptyReads <= 3 && !retryTimer.running) retryTimer.restart()
  }
  Timer {
    id: retryTimer
    interval: 1500
    onTriggered: keybinds.readLayers()
  }
  Timer {
    id: refreshTimer
    interval: 260
    onTriggered: keybinds.readLayers()
  }

  // Omarchy's keybindings script, loaded for its functions: its records give
  // each binding's label plus the dispatcher and argument to run it, and
  // dispatch_binding runs one exactly the way its own list does.
  readonly property string script: 'set -- --print; source "$(command -v omarchy-menu-keybindings)" >/dev/null; '

  Process {
    id: loader
    command: ["bash", "-c", keybinds.script + "output_binding_records"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        keybinds.hyprland = keybinds.parse(text)
        keybinds.rebuildAll()
        keybinds.noteRead()
      }
    }
  }

  // The terminal layers. Best-effort by design: no keybinds plugin, no ghostty
  // installed, or herdr without a config all end here with an empty list.
  Process {
    id: layerLoader
    command: ["bash", "-c", "command -v omarchy-keybinds >/dev/null 2>&1 && omarchy-keybinds list 2>/dev/null || true"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        keybinds.terminal = keybinds.parseLayers(text)
        keybinds.rebuildAll()
        keybinds.noteRead()
      }
    }
  }

  // "SUPER SHIFT + RETURN   → Browser\texec\tomarchy-launch-browser"
  function parse(raw) {
    var list = []
    String(raw || "").split("\n").forEach(function(line) {
      var cols = line.split("\t")
      var label = cols[0] || ""
      var arrow = label.indexOf("→")
      if (arrow === -1) return
      var keys = label.slice(0, arrow).trim()
      var description = label.slice(arrow + 1).trim()
      var parts = keys.split("+")
      var mods = parts.length > 1 ? parts[0].trim().split(/\s+/).filter(function(m) { return m }) : []
      var key = parts.length > 1 ? parts.slice(1).join("+").trim() : keys
      list.push({
        key: keys + " " + description,
        name: description,
        // Omarchy's wording, kept verbatim: it is the join key into the plugin's
        // Chinese labels, and it stays searchable after the label is replaced.
        english: description,
        chord: keybinds.normChord(keys),
        caps: keybinds.capTokens(mods.concat([key])),
        dispatcher: cols[1] || "",
        arg: cols.slice(2).join("\t"),
        search: (description + " " + keys).toLowerCase()
      })
    })
    return list
  }

  // Keycaps show what is printed on the keyboard, not XKB keysyms or evdev
  // dumps: SUPER / LEFTBRACKET / XF86AudioPlay / code:201 mean nothing to
  // someone who is learning the chords.
  function capToken(token) {
    var clean = String(token || "").trim()
    if (!clean) return ""
    var map = {
      SUPER: "Win", CTRL: "Ctrl", SHIFT: "Shift", ALT: "Alt",
      LEFT: "\u2190", RIGHT: "\u2192", UP: "\u2191", DOWN: "\u2193",
      RETURN: "Enter", ESCAPE: "Esc", TAB: "Tab", SPACE: "Space",
      BACKSPACE: "Backspace", DELETE: "Del", INSERT: "Ins",
      PAGE_UP: "PgUp", PAGE_DOWN: "PgDn", PAGEUP: "PgUp", PAGEDOWN: "PgDn",
      HOME: "Home", END: "End", PRINT: "PrtSc",
      PLUS: "+", MINUS: "-", EQUAL: "=", COMMA: ",", PERIOD: ".", SEMICOLON: ";",
      SLASH: "/", BACKSLASH: "\\", APOSTROPHE: "'", QUOTE: "'", GRAVE: "`",
      LEFTBRACKET: "[", RIGHTBRACKET: "]", KP_ENTER: "Enter",
      MOUSE_UP: "\u6eda\u8f6e\u4e0a", MOUSE_DOWN: "\u6eda\u8f6e\u4e0b",
      "MOUSE:272": "\u5de6\u952e", "MOUSE:273": "\u53f3\u952e", "MOUSE:274": "\u4e2d\u952e",
      "LEFT MOUSE BUTTON": "\u5de6\u952e", "RIGHT MOUSE BUTTON": "\u53f3\u952e",
      "MIDDLE MOUSE BUTTON": "\u4e2d\u952e", "MOUSE WHEEL UP": "\u6eda\u8f6e\u4e0a",
      "MOUSE WHEEL DOWN": "\u6eda\u8f6e\u4e0b",
      XF86AUDIOPLAY: "\u64ad\u653e", XF86AUDIOPREV: "\u4e0a\u4e00\u66f2",
      XF86AUDIONEXT: "\u4e0b\u4e00\u66f2", XF86AUDIOPAUSE: "\u6682\u505c",
      XF86AUDIOMUTE: "\u9759\u97f3", XF86AUDIOMICMUTE: "\u9ea6\u514b\u98ce",
      XF86AUDIORAISEVOLUME: "\u97f3\u91cf +", XF86AUDIOLOWERVOLUME: "\u97f3\u91cf -",
      XF86MONBRIGHTNESSUP: "\u4eae\u5ea6 +", XF86MONBRIGHTNESSDOWN: "\u4eae\u5ea6 -",
      XF86KBDLIGHTONOFF: "\u80cc\u5149\u5f00\u5173", XF86KBDUP: "\u80cc\u5149 +",
      XF86KBDOWN: "\u80cc\u5149 -", XF86TOUCHPADTOGGLE: "\u89e6\u63a7\u677f",
      XF86TOUCHPADON: "\u89e6\u63a7\u677f\u5f00", XF86TOUCHPADOFF: "\u89e6\u63a7\u677f\u5173",
      XF86CALCULATOR: "\u8ba1\u7b97\u5668", XF86EJECT: "\u5f39\u51fa", XF86POWEROFF: "\u7535\u6e90"
    }
    var upper = clean.toUpperCase()
    // `XF86KbdBrightnessUp/Down` differ only by the word in the middle, so fold
    // them onto the two backlight caps instead of adding near-duplicate keys.
    if (upper.indexOf("XF86KBD") === 0 && upper.indexOf("UP") === upper.length - 2) upper = "XF86KBDUP"
    else if (upper.indexOf("XF86KBD") === 0 && upper.indexOf("DOWN") === upper.length - 4) upper = "XF86KBDOWN"
    if (upper.indexOf("SWITCH:") === 0) return upper.indexOf(":ON:") > 0 ? "\u5408\u76d6" : "\u5f00\u76d6"
    if (upper.indexOf("CODE:") === 0) return "\u952e\u7801 " + clean.slice(5)
    var mapped = map[upper]
    return mapped === undefined ? clean : mapped
  }

  function capTokens(tokens) {
    return (tokens || []).map(keybinds.capToken).filter(function(part) { return part })
  }

  // One keycap per token of a canonical chord ("CTRL + ALT + LEFT" -> 3 caps).
  // Keycaps show what is printed on his keyboard, not XKB keysyms: SUPER / PLUS /
  // LEFT mean nothing to someone learning the chords.
  function keyCaps(chord) {
    return keybinds.capTokens(String(chord || "").split("+"))
  }

  // A row that still says PREFIX gets the live prefix chord spliced in, so the
  // reader sees the keys to press instead of a word they cannot press.
  function expandPrefix(caps, prefix) {
    var out = []
    var parts = caps || []
    for (var i = 0; i < parts.length; ++i) {
      if (parts[i] === "PREFIX" && prefix && prefix.length) out = out.concat(prefix)
      else out.push(parts[i])
    }
    return out
  }

  function parseLayers(raw) {
    var model = null
    try {
      model = JSON.parse(String(raw || ""))
    } catch (error) {
      // Finding nothing is a supported state (no keybinds plugin, no ghostty);
      // output that will not parse is not, and would otherwise look like
      // "the terminal layers vanished".
      if (String(raw || "").trim()) console.warn("island: keybinding layer list failed to parse")
      return []
    }
    var rows = (model && model.active) || []
    // herdr lists its prefix as a binding of its own (`prefix = "ctrl+space"`),
    // so a `prefix+shift+o` row can show what to actually press instead of the
    // word PREFIX.
    var prefix = []
    rows.forEach(function(row) {
      if (row.herdr_action === "prefix") prefix = keyCaps(row.key)
    })
    // Category metadata for this view's tabs: the plugin's labels/order, plus an
    // index of the Hyprland rows so the script's rows can be labelled too.
    var order = (model && model.category_order) || []
    var labels = {}
    // Named, not a leading "(": a statement that starts with a parenthesis is
    // read as a call on the previous line's object literal.
    var groups = (model && model.groups) || []
    groups.forEach(function(g) { labels[String(g.id)] = String(g.label) })
    var catMap = {}
    var zhMap = {}
    var deadOf = {}
    rows.forEach(function(row) {
      if (row.layer) return
      if (row.status === "disabled") deadOf[keybinds.normChord(String(row.key || ""))] = true
      var cat = String(row.category || "")
      if (!cat) return
      // Index both spellings of the chord: `raw_key` keeps Hyprland's `code:10`,
      // while `key` is the decoded `SUPER + 1` that Omarchy's list actually prints.
      // Without the decoded one, thirty workspace rows land in a tab only because
      // their English description happens to match - silently lost on a reword.
      var chords = [row.raw_key, row.key]
      var matched = false
      chords.forEach(function(chord) {
        var hash = "#" + keybinds.normChord(String(chord || ""))
        if (row.status !== "disabled" || !catMap[hash]) catMap[hash] = cat
        if (hash !== "#") matched = true
      })
      if (!matched) return
      var desc = "@" + String(row.description || "").toLowerCase()
      if (!catMap[desc]) catMap[desc] = cat
      var zh = String(row.description_zh || "")
      if (!zh) return
      chords.forEach(function(chord) {
        var hash = "#" + keybinds.normChord(String(chord || ""))
        if (row.status !== "disabled" || !zhMap[hash]) zhMap[hash] = zh
      })
      if (!zhMap[desc]) zhMap[desc] = zh
    })
    keybinds.groupOrder = order
    keybinds.groupLabel = labels
    keybinds.catOf = catMap
    keybinds.zhOf = zhMap
    keybinds.deadChords = deadOf
    var out = []
    rows.forEach(function(row) {
      // Hyprland and island rows come from Omarchy's own list; only the layers
      // inside the terminal window come from here.
      if (row.layer !== "terminal" && row.layer !== "herdr" && row.layer !== "pi") return
      var layer = row.layer === "herdr" ? "herdr" : (row.layer === "pi" ? "pi" : "ghostty")
      var herdr = layer === "herdr"
      var dead = String(row.shadowed_by || "")
      var unbound = row.status === "disabled"
      // A struck-out chord does nothing when you press it, and this view exists
      // to be read, not audited: the unbound rows live in the keybinds manager
      // (launcher entry "Keybindings", or `omarchy-keybinds` with no args) where
      // they can be given a key again.
      if (unbound) return
      var zh = String(row.description_zh || "").trim()
      var action = String(row.action || "")
      var detail = []
      if (dead) detail.push("被 " + dead + " 层抢占")
      // With a Chinese label the row is already explained; `toggle_command_palette
      // · ghostty/config` underneath is debug output, so it only surfaces when the
      // label is missing (an action this plugin does not know yet).
      if (!zh && !unbound) {
        if (action) detail.push(action)
        if (row.file) detail.push(row.file)
      }
      out.push({
        key: layer + " " + String(row.key || ""),
        name: zh || action || String(row.description || ""),
        detail: detail.join(" · "),
        caps: keybinds.expandPrefix(keyCaps(row.key), prefix),
        layerName: layer,
        layerLabel: layer,
        category: String(row.category || ""),
        sortKey: (action || String(row.raw_key || "")).toLowerCase(),
        dead: dead,
        unbound: unbound,
        // Another config file owns this chord, so there is nothing to run and
        // no edit to offer here; the cursor steps over the row.
        disabled: true,
        dispatcher: "",
        search: [
          zh, row.description, action, row.raw_key, row.key, row.file,
          layer + " 终端 终端层 terminal",
          "只读 read only",
          dead ? "dead 失效 死键 " + dead : "",
          unbound ? "unbind 解绑" : ""
        ].join(" ").toLowerCase()
      })
    })
    // herdr first, since that is what you actually press inside the window;
    // unbound chords sink to the bottom of their layer and everything else
    // groups by the action it triggers, like the keybinds panel does.
    out.sort(function(a, b) {
      var rank = function(entry) {
        return (entry.layerName === "herdr" ? 0 : 100) + (entry.unbound ? 50 : 0)
      }
      var ra = rank(a), rb = rank(b)
      if (ra !== rb) return ra - rb
      if (a.sortKey !== b.sortKey) return a.sortKey < b.sortKey ? -1 : 1
      return String(a.key) < String(b.key) ? -1 : 1
    })
    return out
  }

  // Close first so the binding acts on your window, not the island.
  Process { id: runner }
  function run(entry) {
    // Read-only rows never get here (ListPicker steps over disabled rows), but
    // a stray click must not start an empty dispatch either.
    if (!entry || !entry.dispatcher) return
    host.view = "rest"
    runner.command = ["bash", "-c",
      'd="$1"; a="$2"; sleep 0.15; ' + keybinds.script + 'dispatch_binding "$d" "$a"',
      "--", entry.dispatcher, entry.arg]
    runner.startDetached()
  }

  row: Component {
    Item {
      id: bindRow
      property var entry: ({})
      property bool selected: false
      readonly property var e: bindRow.entry || ({})
      readonly property bool hint: !!bindRow.e.hint
      readonly property bool unbound: !!bindRow.e.unbound
      readonly property bool dimmed: hint || unbound
      readonly property bool hasDetail: !hint && String(bindRow.e.detail || "").length > 0

      // Two lines when the row names another config file (label, then what it
      // really runs); Omarchy's own bindings keep a single centred line.
      Column {
        id: label
        anchors.left: parent.left
        anchors.right: meta.left
        anchors.rightMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        spacing: 1
        Text {
          width: label.width
          text: String(bindRow.e.name || "")
          textFormat: Text.PlainText
          elide: Text.ElideRight
          color: bindRow.dimmed
            ? keybinds.host.theme.muted
            : keybinds.host.theme.text
          font.family: keybinds.host.theme.textFontFamily
          font.pixelSize: keybinds.host.theme.px(16)
          font.weight: Font.Medium
          font.strikeout: bindRow.unbound
        }
        Text {
          width: label.width
          visible: bindRow.hasDetail
          text: String(bindRow.e.detail || "")
          textFormat: Text.PlainText
          elide: Text.ElideMiddle
          color: keybinds.host.theme.muted
          font.family: keybinds.host.theme.textFontFamily
          font.pixelSize: keybinds.host.theme.px(11)
        }
      }

      // DEAD marks a chord that never reaches the layer that bound it, which is
      // the whole reason the terminal layers are listed here.
      Row {
        id: meta
        anchors.right: caps.left
        anchors.rightMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        spacing: 6
        Repeater {
          model: {
            var badges = []
            if (String(bindRow.e.dead || "")) badges.push({ text: "失效", alert: true })
            if (bindRow.e.layerName)
              badges.push({ text: bindRow.e.layerLabel || bindRow.e.layerName, alert: false })
            return badges
          }
          delegate: Rectangle {
            id: badge
            required property var modelData
            width: badgeLabel.implicitWidth + 12
            height: 18
            radius: 9
            color: badge.modelData.alert
              ? keybinds.host.theme.withAlpha(keybinds.host.theme.urgent, 0.18)
              : "transparent"
            border.width: 1
            border.color: badge.modelData.alert
              ? keybinds.host.theme.withAlpha(keybinds.host.theme.urgent, 0.55)
              : keybinds.host.theme.withAlpha(keybinds.host.theme.text, 0.12)
            Text {
              id: badgeLabel
              anchors.centerIn: parent
              text: String(badge.modelData.text)
              textFormat: Text.PlainText
              color: badge.modelData.alert
                ? keybinds.host.theme.urgent
                : keybinds.host.theme.muted
              font.family: keybinds.host.theme.textFontFamily
              font.pixelSize: keybinds.host.theme.px(10)
              font.weight: Font.DemiBold
            }
          }
        }
      }

      // Keys as keycaps.
      Row {
        id: caps
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: 4
        Repeater {
          model: bindRow.e.caps || []
          delegate: Rectangle {
            id: cap
            required property var modelData
            width: Math.max(26, capLabel.implicitWidth + 14)
            height: 24
            radius: 6
            color: keybinds.host.theme.withAlpha(keybinds.host.theme.text, 0.08)
            border.width: 1
            border.color: keybinds.host.theme.withAlpha(keybinds.host.theme.text, 0.1)
            Text {
              id: capLabel
              anchors.centerIn: parent
              text: String(cap.modelData)
              textFormat: Text.PlainText
              color: keybinds.host.theme.muted
              font.family: keybinds.host.theme.textFontFamily
              font.pixelSize: keybinds.host.theme.px(11)
              font.weight: Font.DemiBold
            }
          }
        }
      }
    }
  }
}
