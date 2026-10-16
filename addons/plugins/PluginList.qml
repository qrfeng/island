import QtQuick
import Quickshell
import Quickshell.Io
import "../../components"

// Two things in one list. Third-party plugins (every plugin added with
// `omarchy plugin add` but the bar in use, and the island's own notifications
// companion, which setup manages: switching it off here would quietly bring
// back Omarchy's notifications and send the island back to "Click to Setup").
// And Omarchy's own panels, which are worth summoning right here: Wi-Fi QR,
// speed test, reminders, image picker. Enter opens an enabled panel, overlay,
// or menu plugin through the shell; a plugin with no panel of its own is opened
// through the desktop entry that carries its command instead (hyprmoncfg's
// layout editor runs in a floating terminal this way). A plugin with neither
// gets told so, rather than silently switched off - Enter used to disable every
// bar widget it was pressed on. Shift+Enter always flips enabled, the same as
// `omarchy plugin enable|disable`; for a first-party panel that switch is the
// built-in one, so it is left alone.
ListPicker {
  id: plugins
  placeholder: "搜索插件"
  emptyText: all.length ? "无匹配插件" : loading ? "加载中…" : "还没有添加插件"
  rowHeight: 46
  visibleRows: 9
  items: {
    var q = query.trim().toLowerCase()
    return all.filter(function(p) {
      return !q || p.name.toLowerCase().indexOf(q) !== -1 || p.id.toLowerCase().indexOf(q) !== -1
    })
  }
  onChosen: function(entry) {
    if (!entry) return
    if (entry.enabled && entry.openable) open(entry)
    else if (entry.enabled && entry.launcher) launch(entry)
    else if (entry.enabled) explain(entry)
    else setEnabled(entry, true)
  }
  onKeyFilter: function(event) {
    if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && (event.modifiers & Qt.ShiftModifier)) {
      if (selected) setEnabled(selected, !selected.enabled)
      event.accepted = true
    }
  }
  onActiveChanged: if (active) refresh()

  readonly property var openKinds: ["panel", "overlay", "menu"]
  // Overlays the island already does better itself, so offering Omarchy's copy
  // of them would only be a second, worse door to the same room.
  readonly property var replaced: ["omarchy.clipboard", "omarchy.emojis", "omarchy.menu", "omarchy.osd"]
  function wanted(p) {
    var kinds = p.kinds || []
    if (p.id === "guilhermerisu.notifications") return false
    if (!p.firstParty) return kinds.indexOf("bar") === -1
    // Omarchy's own panels: only the ones that are switched on, since the
    // disabled ones are off for a reason and this list is not where you decide
    // that about the built-in shell.
    return !!p.enabled && plugins.replaced.indexOf(p.id) === -1
      && kinds.some(function(k) { return plugins.openKinds.indexOf(k) !== -1 })
  }
  property var all: []
  property bool loading: false
  // Plugins whose kinds the island cannot open (a bar widget, a headless
  // service) usually still ship a desktop entry that runs their command.
  property var launchers: ({})

  Process {
    id: listProc
    command: ["omarchy-plugin-list", "--json"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        plugins.loading = false
        try {
          var added = JSON.parse(text).filter(plugins.wanted).map(function(p) {
            var kinds = p.kinds || []
            return {
              key: p.id, id: String(p.id), name: String(p.name || p.id), kinds: kinds,
              enabled: !!p.enabled, canDisable: p.canDisable !== false,
              system: !!p.firstParty,
              openable: kinds.some(function(k) { return plugins.openKinds.indexOf(k) !== -1 })
            }
          })
          plugins.all = added.map(plugins.withLauncher)
          plugins.resolveLaunchers(added.filter(function(p) { return !p.openable }))
        } catch (e) {}
      }
    }
  }
  function refresh() {
    if (listProc.running) return
    loading = true
    listProc.running = true
  }

  function withLauncher(p) {
    p.launcher = plugins.launchers[p.id] || ""
    return p
  }

  // One pass over the plugins with no panel the island can open, asking which
  // desktop entry carries their command. The user's applications dir wins, and
  // a `NoDisplay=true` entry never does: those are aliases kept for
  // `gtk-launch`, not entries meant to be picked.
  Process {
    id: launcherProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var found = {}
        String(text).split("\n").forEach(function(line) {
          var at = line.indexOf("\t")
          if (at > 0 && line.slice(at + 1) !== "") found[line.slice(0, at)] = line.slice(at + 1)
        })
        plugins.launchers = found
        plugins.all = plugins.all.map(plugins.withLauncher)
      }
    }
  }
  function resolveLaunchers(closed) {
    if (launcherProc.running || !closed.length) return
    launcherProc.command = ["bash", "-c", launcherProbe, "--"].concat(closed.map(function(p) { return p.id }))
    launcherProc.running = true
  }
  readonly property string launcherProbe: [
    "for id in \"$@\"; do",
    "  tok=${id##*.}",
    "  [ ${#tok} -ge 4 ] || continue",
    "  exact=; prefix=",
    "  for d in \"$HOME/.local/share/applications\" /usr/share/applications; do",
    "    [ -d \"$d\" ] || continue",
    "    for f in \"$d/$tok.desktop\" \"$d/$tok-\"*.desktop; do",
    "      [ -e \"$f\" ] || continue",
    "      b=${f##*/}; b=${b%.desktop}",
    "      grep -q '^[[:space:]]*NoDisplay=true' \"$f\" && continue",
    "      if [ \"$b\" = \"$tok\" ]; then { [ -n \"$exact\" ] || exact=$b; }; else { [ -n \"$prefix\" ] || prefix=$b; }; fi",
    "    done",
    "  done",
    "  printf '%s\\t%s\\n' \"$id\" \"${exact:-$prefix}\"",
    "done"
  ].join("\n")

  Process {
    id: toggleProc
    onExited: plugins.refresh()
  }
  function setEnabled(entry, enabled) {
    if (!entry || toggleProc.running || (!enabled && !entry.canDisable)) return
    toggleProc.command = [enabled ? "omarchy-plugin-enable" : "omarchy-plugin-disable", entry.id]
    toggleProc.running = true
  }

  // Close first so the plugin's window, not the island, gets the keyboard.
  // The shell's own API is in-process; the CLI is only the fallback for a host
  // that was handed no shell object.
  Process { id: runner }
  function open(entry) {
    if (!entry) return
    var shell = host.shell
    if (shell && typeof shell.toggle === "function") {
      host.withAppFocus(function() { shell.toggle(entry.id, "{}") })
      return
    }
    host.view = "rest"
    runner.command = ["bash", "-c", 'sleep 0.15; exec omarchy-shell shell toggle "$1" "{}"', "--", entry.id]
    runner.startDetached()
  }

  // Same desktop-entry launcher the island's app launcher uses, so the
  // terminal the command needs is opened by xdg-terminal-exec under the
  // floating TUI window rule like Omarchy does it.
  function launch(entry) {
    host.withAppFocus(function() {
      runner.command = ["bash", "-c", 'exec uwsm-app -- gtk-launch "$1"', "--", entry.launcher]
      runner.startDetached()
    })
  }

  Process { id: hint }
  // Nothing to open here: say which kinds the plugin is, and how to still
  // switch it, instead of changing anything.
  function explain(entry) {
    hint.command = ["notify-send", "-a", "Island Plugins", String(entry.name),
      "这里没有它能打开的面板（" + (entry.kinds || []).join(" / ") + "）· 按 Shift+Enter 启用或禁用"]
    hint.startDetached()
  }

  row: Component {
    Item {
      id: pluginRow
      property var entry: ({})
      property bool selected: false

      Text {
        id: icon
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: 24
        horizontalAlignment: Text.AlignHCenter
        text: "󰐱"
        color: pluginRow.entry.enabled ? plugins.host.theme.accent : plugins.host.theme.muted
        font.family: plugins.host.theme.fontFamily
        font.pixelSize: plugins.host.theme.px(17)
      }
      Column {
        anchors.left: icon.right
        anchors.leftMargin: 12
        anchors.right: stateLabel.left
        anchors.rightMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        spacing: 1
        Text {
          width: parent.width
          text: String(pluginRow.entry.name || "")
          textFormat: Text.PlainText
          elide: Text.ElideRight
          color: plugins.host.theme.text
          font.family: plugins.host.theme.textFontFamily
          font.pixelSize: plugins.host.theme.px(14)
          font.weight: Font.Medium
        }
        Text {
          width: parent.width
          text: String(pluginRow.entry.id || "") + " · " + (pluginRow.entry.kinds || []).join(", ")
            + (pluginRow.entry.system ? " · Omarchy 自带" : "")
          textFormat: Text.PlainText
          elide: Text.ElideRight
          color: plugins.host.theme.muted
          font.family: plugins.host.theme.textFontFamily
          font.pixelSize: plugins.host.theme.px(11)
        }
      }
      Text {
        id: stateLabel
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        text: !pluginRow.entry.enabled ? "关闭"
          : pluginRow.entry.openable ? "打开"
          : pluginRow.entry.launcher ? "启动" : "开启"
        color: pluginRow.entry.enabled ? plugins.host.theme.text : plugins.host.theme.muted
        font.family: plugins.host.theme.textFontFamily
        font.pixelSize: plugins.host.theme.px(12)
      }
    }
  }
}
