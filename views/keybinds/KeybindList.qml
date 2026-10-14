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
  placeholder: "Search keybindings"
  emptyText: "No keybindings match"
  rowHeight: 44
  visibleRows: 9
  disabledOpacity: 0.62

  property var hyprland: []
  property var terminal: []
  readonly property var all: {
    var rows = keybinds.hyprland.slice()
    var summary = keybinds.summaryRow()
    if (summary) rows.push(summary)
    return rows.concat(keybinds.terminal)
  }
  items: {
    var q = query.trim().toLowerCase()
    if (!q) return all
    var terms = q.split(/\s+/)
    return all.filter(function(b) {
      // The summary row only makes sense as a map of the unfiltered list.
      if (b.hint) return false
      return terms.every(function(t) { return b.search.indexOf(t) !== -1 })
    })
  }
  onChosen: function(entry) { run(entry) }
  // Both layers are read fresh on every open: bindings change while the island
  // is closed (a ghostty reload, a herdr config edit) and each load costs
  // well under a frame budget's worth of waiting.
  onActiveChanged: {
    if (!active) return
    if (!loader.running) loader.running = true
    if (!layerLoader.running) layerLoader.running = true
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
      onStreamFinished: keybinds.hyprland = keybinds.parse(text)
    }
  }

  // The terminal layers. Best-effort by design: no keybinds plugin, no ghostty
  // installed, or herdr without a config all end here with an empty list.
  Process {
    id: layerLoader
    command: ["bash", "-c", "command -v omarchy-keybinds >/dev/null 2>&1 && omarchy-keybinds list 2>/dev/null || true"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: keybinds.terminal = keybinds.parseLayers(text)
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
        caps: mods.concat([key]),
        dispatcher: cols[1] || "",
        arg: cols.slice(2).join("\t"),
        search: (description + " " + keys).toLowerCase()
      })
    })
    return list
  }

  // One keycap per token of a canonical chord ("CTRL + ALT + LEFT" -> 3 caps).
  function keyCaps(chord) {
    return String(chord || "").split("+").map(function(part) {
      return part.trim()
    }).filter(function(part) { return part })
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
    var out = []
    rows.forEach(function(row) {
      // Hyprland and island rows come from Omarchy's own list; only the two
      // layers inside the terminal window come from here.
      if (row.layer !== "terminal" && row.layer !== "herdr") return
      var herdr = row.layer === "herdr"
      var dead = String(row.shadowed_by || "")
      var unbound = row.status === "disabled"
      var zh = String(row.description_zh || "").trim()
      var action = String(row.action || "")
      var detail = []
      if (dead) detail.push("被 " + dead + " 层抢占")
      if (action && !unbound) detail.push(action)
      if (row.file) detail.push(row.file)
      out.push({
        key: (herdr ? "herdr " : "ghostty ") + String(row.key || ""),
        name: zh || action || String(row.description || ""),
        detail: detail.join(" · "),
        caps: row.herdr_prefix_chord && prefix.length
          ? prefix.concat(keyCaps(row.key).slice(1))
          : keyCaps(row.key),
        layerName: herdr ? "herdr" : "ghostty",
        sortKey: (action || String(row.raw_key || "")).toLowerCase(),
        dead: dead,
        unbound: unbound,
        // Another config file owns this chord, so there is nothing to run and
        // no edit to offer here; the cursor steps over the row.
        disabled: true,
        dispatcher: "",
        search: [
          zh, row.description, action, row.raw_key, row.key, row.file,
          herdr ? "herdr 终端 终端层" : "ghostty 终端 终端层 terminal",
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

  // The terminal layers are invisible in an unfiltered list (they sort after
  // ~160 Hyprland rows), so leave one dimmed row that says they exist, how
  // many there are, and what to type to get to them.
  function summaryRow() {
    var herdr = 0, ghostty = 0, unbound = 0, dead = 0
    terminal.forEach(function(entry) {
      if (entry.layerName === "herdr") herdr += 1
      else ghostty += 1
      if (entry.unbound) unbound += 1
      if (entry.dead) dead += 1
    })
    if (!terminal.length) return null
    var label = "终端层（只读）  herdr " + herdr + "  ·  ghostty " + ghostty
    if (unbound) label += "（" + unbound + " 已解绑）"
    label += dead ? "  ·  " + dead + " 失效" : "  ·  无失效"
    return {
      key: "terminal-summary",
      name: label,
      // The keycaps double as the words to type next.
      caps: ["herdr", "ghostty", "dead"],
      hint: true,
      disabled: true,
      dispatcher: "",
      search: "终端层 terminal ghostty herdr 只读 dead 失效 解绑"
    }
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
            if (String(bindRow.e.dead || "")) badges.push({ text: "DEAD", alert: true })
            if (bindRow.e.layerName) badges.push({ text: bindRow.e.layerName, alert: false })
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
