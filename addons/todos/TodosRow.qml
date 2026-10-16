import QtQuick
import "../../components"

// One task: a circle to tick, the task itself, and its +projects and @contexts
// trailing. The task takes whatever width is left and elides, so the trailing
// names never get written over.
//
// The row's `sheet` is the part that moves - out of the way of a row being
// dragged, or along with the pointer. The row itself keeps its place in the
// list, and the pointer with it, so a drag is measured against the finger
// rather than against the row's own travelling.
Item {
  id: row
  required property var view
  required property var task
  // Its place in the whole list, which is what the arrows walk and what a drag
  // is aimed at.
  required property int at

  readonly property var theme: view.theme
  readonly property bool done: task.done
  readonly property bool picked: view.clamped === at
  readonly property bool dragging: view.dragAt === at
  // Only what's still to do has an order to keep.
  readonly property bool canDrag: !done && !view.dragActive
  readonly property real offset: dragging ? view.dragDy : Number(view.dragOffsets[at] || 0)
  // 1 = just finished, 2 = just opened back up, 0 = an ordinary row. The addon
  // holds this, so a row redrawn a moment later still knows it was the one that
  // changed.
  readonly property int flash: view.flashOf(task)
  // The circle's two answers: `pulse` to the finger that pressed it, `pop` to
  // the file that has since agreed.
  property real pulse: 1
  property real pop: 1

  height: 36
  width: parent ? parent.width : 0

  onFlashChanged: if (flash !== 0) kickoff.restart()
  Component.onCompleted: if (flash !== 0) kickoff.restart()

  Item {
    id: sheet
    width: parent.width
    height: parent.height
    // Moved rather than transformed: the pointer stays with the row underneath.
    y: row.offset
    // The dragged row follows the pointer exactly; everyone else eases over.
    Behavior on y {
      MotionAnimation { theme: row.theme; pace: "expressive" }
      enabled: !row.dragging
    }

    Rectangle {
      anchors.fill: parent
      radius: 10
      color: row.dragging ? Qt.rgba(1, 1, 1, 0.13)
        : row.picked ? Qt.rgba(1, 1, 1, 0.09)
        : hover.hovered ? Qt.rgba(1, 1, 1, 0.045) : "transparent"
      Behavior on color { MotionColorAnimation { theme: row.theme } }
    }

    // The warm wash under a row that just changed hands, drawn once by `land`.
    Rectangle {
      id: wash
      anchors.fill: parent
      radius: 10
      color: row.flash === 2 ? row.view.theme.accent : row.view.doneTint
      opacity: 0
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
      opacity: row.done || hover.hovered || row.dragging ? 1 : 0.75
      font.family: row.theme.fontFamily
      font.pixelSize: row.theme.px(16)
      scale: row.pop * row.pulse * (row.done ? 1 : 0.94)
      Behavior on opacity { MotionAnimation { theme: row.theme; pace: "fade"; curve: "fade" } }
    }

    Text {
      id: taskText
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

    // The line that draws itself through a task as it is finished, over the
    // strikeout the font already makes.
    Rectangle {
      id: line
      anchors.left: taskText.left
      anchors.verticalCenter: taskText.verticalCenter
      height: Math.max(1, row.theme.px(1.2))
      width: 0
      radius: height / 2
      opacity: 0
      color: row.view.doneTint
    }
  }

  // A row is made at the moment it changes, and its text has no width until the
  // frame after, which is the width the line has to be drawn across.
  Timer {
    id: kickoff
    interval: 32
    onTriggered: land.restart()
  }

  SequentialAnimation {
    id: land
    PropertyAction { target: wash; property: "opacity"; value: 0.9 }
    PropertyAction { target: line; property: "opacity"; value: row.flash === 1 ? 1 : 0 }
    PropertyAction { target: line; property: "width"; value: 0 }
    PropertyAction { target: row; property: "pop"; value: 0.55 }
    ParallelAnimation {
      NumberAnimation {
        target: row; property: "pop"; to: 1; duration: 440
        easing.type: Easing.BezierSpline
        easing.bezierCurve: [0.16, 1, 0.3, 1, 1, 1]
      }
      NumberAnimation {
        target: line; property: "width"; to: row.flash === 1 ? taskText.paintedWidth : 0
        duration: 340
        easing.type: Easing.BezierSpline
        easing.bezierCurve: [0.16, 1, 0.3, 1, 1, 1]
      }
      NumberAnimation {
        target: wash; property: "opacity"; to: 0; duration: 660
        easing.type: Easing.OutQuad
      }
    }
    NumberAnimation { target: line; property: "opacity"; to: 0; duration: 240 }
  }

  // The press answers at once; the file agrees some tens of milliseconds later.
  SequentialAnimation {
    id: press
    PropertyAction { target: row; property: "pulse"; value: 0.62 }
    NumberAnimation {
      target: row; property: "pulse"; to: 1; duration: 280
      easing.type: Easing.BezierSpline
      easing.bezierCurve: [0.16, 1, 0.3, 1, 1, 1]
    }
  }

  HoverHandler { id: hover }
  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton
    // The list is a Flickable, and a drag that starts on a row is a drag of the
    // row, not a flick of the list.
    preventStealing: true
    cursorShape: Qt.PointingHandCursor
    property real pressY: 0
    property bool pulling: false

    onPressed: function(mouse) {
      pressY = mouse.y
      pulling = false
    }
    onPositionChanged: function(mouse) {
      if (!row.canDrag) return
      var dy = mouse.y - pressY
      if (!pulling) {
        // Nothing until the finger means it, so a shaky click still ticks.
        if (Math.abs(dy) < 5) return
        pulling = true
        row.view.beginDrag(row.at)
      }
      row.view.dragTo(dy)
    }
    onReleased: function(mouse) {
      if (pulling) {
        pulling = false
        row.view.endDrag()
        return
      }
      // The circle ticks it; anywhere else on the row picks it.
      if (mouse.x <= box.x + box.width + 12) {
        press.restart()
        row.view.todos.toggle(row.task)
      } else {
        row.view.pick(row.at)
      }
    }
    onCanceled: {
      if (!pulling) return
      pulling = false
      row.view.cancelDrag()
    }
  }
}
