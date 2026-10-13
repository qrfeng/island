import QtQuick
import "../../components"

// One task: a circle to tick, the task itself, and its +projects and @contexts
// trailing. The task takes whatever width is left and elides, so the trailing
// names never get written over.
Item {
  id: row
  required property var view
  required property var task
  // Its place in the whole list, which is what the arrows walk.
  required property int at

  readonly property var theme: view.theme
  readonly property bool done: task.done
  readonly property bool picked: view.clamped === at
  height: 36
  width: parent ? parent.width : 0

  Rectangle {
    anchors.fill: parent
    radius: 10
    color: row.picked ? Qt.rgba(1, 1, 1, 0.09)
      : hover.hovered ? Qt.rgba(1, 1, 1, 0.045) : "transparent"
    Behavior on color { MotionColorAnimation { theme: row.theme } }
  }

  Item {
    id: tail
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    width: Math.min(tailText.implicitWidth, 130)
    height: parent.height
    visible: tailText.text !== ""

    Text {
      id: tailText
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      text: (row.task.projects || []).map(function(p) { return "+" + p })
        .concat((row.task.contexts || []).map(function(c) { return "@" + c })).join("  ")
      width: Math.min(implicitWidth, 130)
      elide: Text.ElideRight
      color: row.view.inkFaint
      font.family: row.theme.textFontFamily
      font.pixelSize: row.theme.px(12)
    }
  }

  Text {
    id: box
    anchors.left: parent.left
    anchors.leftMargin: 10
    anchors.verticalCenter: parent.verticalCenter
    text: row.done ? "\udb80\udd34" : "\udb80\udd30"
    color: row.done ? row.view.doneTint : row.view.inkMuted
    opacity: row.done || hover.hovered ? 1 : 0.75
    font.family: row.theme.fontFamily
    font.pixelSize: row.theme.px(16)
    scale: row.done ? 1 : 0.94
    Behavior on opacity { MotionAnimation { theme: row.theme; pace: "fade"; curve: "fade" } }
    Behavior on scale { MotionAnimation { theme: row.theme; pace: "expressive" } }
  }

  Text {
    anchors.left: box.right
    anchors.leftMargin: 10
    anchors.right: tail.visible ? tail.left : parent.right
    anchors.rightMargin: 12
    anchors.verticalCenter: parent.verticalCenter
    text: row.task.body
    textFormat: Text.PlainText
    elide: Text.ElideRight
    color: row.done ? row.view.inkMuted : row.view.ink
    opacity: row.done ? 0.7 : 1
    font.family: row.theme.textFontFamily
    font.pixelSize: row.theme.px(14)
    font.weight: Font.Medium
    font.strikeout: row.done
  }

  HoverHandler { id: hover }
  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton
    cursorShape: Qt.PointingHandCursor
    // The circle ticks it; anywhere else on the row picks it.
    onClicked: function(mouse) {
      if (mouse.x <= row.box.width + row.box.x + 12) row.view.todos.toggle(row.task)
      else row.view.pick(row.at)
    }
  }
}
