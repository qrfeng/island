import QtQuick
import "../../views/control-center"

// The control center tile: how much is still to do, or that the list is empty.
// Opens the task list. `todos` is the TodosAddon.
CcTile {
  required property var todos

  anchors.fill: parent
  // The tile's title stays English like the others; its count is the island's
  // own mix of Chinese.
  icon: "\udb81\udf56"
  title: "Tasks"
  subtitle: {
    if (todos.error !== "") return "\u8bfb\u4e0d\u5230\u6587\u4ef6"
    if (todos.open > 0) return todos.open + " \u9879\u5f85\u529e"
    return todos.exists ? "\u90fd\u5b8c\u6210\u4e86" : "\u8fd8\u6ca1\u6709\u4efb\u52a1"
  }
  onClicked: todos.host.view = "todos"
}
