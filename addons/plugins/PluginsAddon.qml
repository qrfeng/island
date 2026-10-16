import QtQuick
import Quickshell.Io
import ".."

// Plugins added with `omarchy plugin add`, as an island view (see PluginList)
// and a control center tile (see PluginsTile) that opens it.
Addon {
  id: pluginsAddon
  views: [{ name: "plugins", width: 520, component: pluginList }]
  tiles: [{ key: "open", title: "插件", component: pluginsTile }]
  Component {
    id: pluginList
    PluginList { host: pluginsAddon.host; active: pluginsAddon.host.view === "plugins" }
  }
  Component {
    id: pluginsTile
    PluginsTile { plugins: pluginsAddon; center: parent.center }
  }

  // How many added plugins there are and how many are on, so the tile says
  // something before the list is ever opened. -1 until the first read lands.
  property int total: -1
  property int enabled: -1

  // Once the island is up, and again each time the control center opens: the
  // list only changes through `omarchy plugin`, the island itself, or this
  // view, so opening the control center is often enough.
  Timer {
    running: true
    interval: 400
    onTriggered: pluginsAddon.refresh()
  }
  property string openView: host.view
  onOpenViewChanged: if (openView === "controls") refresh()
  function refresh() {
    if (!listProc.running) listProc.running = true
  }

  Process {
    id: listProc
    command: ["omarchy-plugin-list", "--json"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var added = JSON.parse(text).filter(function(p) {
            return !p.firstParty && (p.kinds || []).indexOf("bar") === -1
              && p.id !== "guilhermerisu.notifications"
          })
          pluginsAddon.total = added.length
          pluginsAddon.enabled = added.filter(function(p) { return p.enabled }).length
        } catch (e) {}
      }
    }
  }
}
