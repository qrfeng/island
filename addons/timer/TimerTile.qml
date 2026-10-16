import QtQuick
import "../../views/control-center"

// The control center tile, a CcTile like the others: the timer's time left
// ("12:34", "已暂停 · 12:34"), or "关闭" while it's unset, lit while
// it's set. Opens the timer view. `timer` is the TimerAddon.
CcTile {
  required property var timer
  readonly property string phase: timer.phase

  anchors.fill: parent
  icon: "󰔛"
  title: "计时器"
  subtitle: phase === "running" ? timer.timeText(timer.remaining)
    : phase === "paused" ? "已暂停 · " + timer.timeText(timer.remaining)
    : "关闭"
  checked: phase !== "idle"
  onClicked: timer.host.view = "timer"
}
