import QtQuick
import "../../views/control-center"

// The control center tile: how many missions are open, and whether one of them
// is waiting on you. Opens the mission list. `board` is the MissionsAddon.
CcTile {
  id: tile
  required property var board

  anchors.fill: parent
  icon: "\u25ce"
  available: !board.missing && !board.failed
  title: board.missing ? "还没建过 mission"
    : board.waiting > 0 ? board.waiting + " 个等你回答"
      : board.running > 0 ? board.running + " 个进行中"
        : board.open > 0 ? board.open + " 个未收口"
          : board.missions.length > 0 ? "都收口了" : "还没建过 mission"
  subtitle: {
    if (board.missing) return "在 pi 里跑带 mission 的委派"
    if (board.error !== "") return "读不到记录"
    var bits = []
    if (board.waiting > 0 && board.running > 0) bits.push(board.running + " 个在跑")
    if (board.tokens > 0) bits.push(tile.count(board.tokens) + " tokens")
    if (board.stale > 0) bits.push(board.stale + " 条记录已清")
    return bits.length ? bits.join(" / ") : board.missions.length + " 条记录"
  }
  onClicked: board.host.view = "missions"

  function count(n) {
    n = Number(n) || 0
    if (n >= 1e6) return (n / 1e6).toFixed(n >= 1e7 ? 0 : 1) + "M"
    if (n >= 1e3) return (n / 1e3).toFixed(n >= 1e4 ? 0 : 1) + "K"
    return String(Math.round(n))
  }
}
