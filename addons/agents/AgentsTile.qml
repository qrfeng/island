import QtQuick
import "../../views/control-center"

// The control center tile: today's tokens across every agent that has a record,
// with the heaviest one beside it. Opens the Agent usage view. `usage` is the
// AgentsAddon.
CcTile {
  id: tile
  required property var usage

  anchors.fill: parent
  icon: "\uf201"
  available: usage.hasData
  title: usage.hasData
    ? tile.count(usage.todayTokens) + " tokens today"
    : "Agent usage"
  subtitle: !usage.hasData ? "No usage recorded"
    : String((tile.first && tile.first.name) || "") + " / "
      + String(Number(tile.first && tile.first.totalSessions) || 0) + " sessions"
      + (usage.todayTokens > 0 ? "" : " / none today")
  onClicked: usage.host.view = "agents"

  // The agent that has spent the most, which is the one the view opens on.
  readonly property var first: usage.list.length ? usage.list[0] : null

  function count(n) {
    n = Number(n) || 0
    if (n >= 1e9) return (n / 1e9).toFixed(n >= 1e10 ? 0 : 1) + "B"
    if (n >= 1e6) return (n / 1e6).toFixed(n >= 1e7 ? 0 : 1) + "M"
    if (n >= 1e3) return (n / 1e3).toFixed(n >= 1e4 ? 0 : 1) + "K"
    return String(Math.round(n))
  }
}
