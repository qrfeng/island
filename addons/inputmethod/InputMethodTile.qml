import QtQuick
import "../../views/control-center"

// Control-center tile: switch input method. Checked = currently Chinese.
// Without fcitx5 running there is nothing to switch, so the tile is
// unavailable rather than silently doing nothing.
CcTile {
  id: tile
  required property var im
  anchors.fill: parent

  icon: "󰍛"
  checked: im.chinese
  available: im.remote !== ""
  clickable: im.remote !== ""
  title: "输入法"
  subtitle: im.remote === "" ? "未安装 fcitx5"
    : im.label + (im.label !== im.name && im.name !== "" ? " · " + im.name : "")
  onClicked: im.toggle()
}
