import QtQuick
import "../../views/control-center"

// The control center tile: how many added plugins are on. Opens the plugin
// list. `plugins` is the PluginsAddon.
CcTile {
  required property var plugins

  anchors.fill: parent
  // The tile's title stays English like the others; its count is the island's
  // own mix of Chinese.
  icon: "󰐱"
  title: "Plugins"
  subtitle: plugins.total < 0 ? ""
    : plugins.total === 0 ? "还没有添加插件"
    : plugins.enabled + "/" + plugins.total + " 已启用"
  onClicked: plugins.host.view = "plugins"
}
