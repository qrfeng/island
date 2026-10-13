import QtQuick
import "../../components"

// The task list: what's still to do, in the order it was written, with the
// finished ones dimmed under a rule. Type in the field at the bottom and Enter
// appends the line to the file; Up and Down pick a task, Space finishes it (or
// opens it up again) and d deletes it. The list is a picture of the file, so a
// task added in a terminal shows up by itself and nothing is stored twice.
//
// The Chinese here is written as \uXXXX escapes so the file stays pure ASCII:
// the icon glyphs are private-use codepoints that editors and tools mangle.
Item {
  id: panel
  required property var host
  required property var todos
  property bool active: false

  readonly property var theme: host.theme
  readonly property color ink: theme.text
  readonly property color inkMuted: theme.muted
  readonly property color inkFaint: theme.withAlpha(theme.text, 0.42)
  readonly property color doneTint: "#34c759"
  readonly property color late: "#ff453a"

  readonly property var tasks: todos.tasks
  // Each row with its place in the whole list, which is what the arrows walk.
  readonly property var openRows: rows(false)
  readonly property var doneRows: rows(true)
  function rows(wantDone) {
    var out = []
    for (var i = 0; i < tasks.length; i++)
      if (!!tasks[i].done === wantDone) out.push({ task: tasks[i], at: i })
    return out
  }

  // The picked row, kept inside the list as the list changes under it.
  property int row: 0
  readonly property int clamped: tasks.length === 0 ? 0 : Math.max(0, Math.min(row, tasks.length - 1))
  onTasksChanged: row = Math.max(0, Math.min(row, tasks.length - 1))
  function pick(at) {
    row = at
    panel.forceActiveFocus()
  }
  function move(by) {
    if (tasks.length === 0) return
    row = Math.max(0, Math.min(clamped + by, tasks.length - 1))
    field.focus = false
    panel.forceActiveFocus()
  }
  function picked() { return tasks[clamped] || null }
  function togglePicked() { if (picked()) todos.toggle(picked()) }
  function removePicked() {
    var task = picked()
    if (!task) return
    todos.remove(task)
    row = Math.max(0, clamped - 1)
  }

  implicitHeight: column.height

  onActiveChanged: {
    if (!active) return
    row = 0
    Qt.callLater(function() { field.forceActiveFocus() })
  }

  // ---------- keys ----------

  Keys.onEscapePressed: function(event) {
    if (field.text !== "") { field.clear(); event.accepted = true; return }
    host.view = "rest"
  }
  Keys.onUpPressed: function(event) { panel.move(-1); event.accepted = true }
  Keys.onDownPressed: function(event) { panel.move(1); event.accepted = true }
  Keys.onReturnPressed: function(event) {
    if (field.activeFocus) return
    panel.togglePicked()
    event.accepted = true
  }
  Keys.onSpacePressed: function(event) {
    if (field.activeFocus) return
    panel.togglePicked()
    event.accepted = true
  }
  Keys.onDeletePressed: panel.removePicked()
  // `d` deletes the picked task, `n` goes back to the field.
  Keys.onPressed: function(event) {
    if (field.activeFocus) return
    if (event.key === Qt.Key_D) {
      panel.removePicked()
      event.accepted = true
    } else if (event.key === Qt.Key_N) {
      field.forceActiveFocus()
      event.accepted = true
    }
  }

  Column {
    id: column
    width: parent.width
    spacing: 12

    // ---------- the header ----------

    Item {
      width: parent.width
      height: 22

      Text {
        id: title
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        // "To do"
        text: "\u5f85\u529e"
        color: panel.theme.accent
        font.family: panel.theme.textFontFamily
        font.pixelSize: panel.theme.px(15)
        font.weight: Font.Bold
        font.letterSpacing: 0.3
      }
      Rectangle {
        anchors.left: title.right
        anchors.leftMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        width: badge.implicitWidth + 16
        height: 20
        radius: 10
        visible: panel.todos.open > 0
        color: panel.theme.withAlpha(panel.theme.accent, 0.16)
        Text {
          id: badge
          anchors.centerIn: parent
          // N \u9879
          text: panel.todos.open + " \u9879"
          color: panel.theme.accent
          font.family: panel.theme.textFontFamily
          font.pixelSize: panel.theme.px(11)
          font.weight: Font.DemiBold
          font.features: { "tnum": 1 }
        }
      }
      Text {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        // "Reading\u2026", or "all done" once there is nothing left
        text: panel.todos.loading ? "\u8bfb\u5165\u4e2d\u2026"
          : panel.todos.open === 0 && panel.todos.finished > 0 ? "\u5168\u90e8\u5b8c\u6210" : ""
        color: panel.inkFaint
        font.family: panel.theme.textFontFamily
        font.pixelSize: panel.theme.px(12)
        font.weight: Font.Medium
      }
    }

    // ---------- the list, or why there isn't one ----------

    Flickable {
      id: scroller
      width: parent.width
      height: Math.min(body.implicitHeight, 392)
      contentHeight: body.implicitHeight
      contentWidth: width
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      visible: panel.tasks.length > 0

      Column {
        id: body
        width: scroller.width
        spacing: 3

        Repeater {
          model: panel.openRows
          delegate: TodosRow {
            required property var modelData
            view: panel
            task: modelData.task
            at: modelData.at
          }
        }

        // The finished ones, dimmed under a rule, so they stay visible without
        // competing with what's still to do.
        Item {
          width: body.width
          height: panel.doneRows.length ? 26 : 0
          visible: panel.doneRows.length > 0

          Rectangle {
            id: rule
            anchors.top: parent.top
            width: parent.width
            height: 1
            color: Qt.rgba(1, 1, 1, 0.07)
          }
          Text {
            anchors.left: parent.left
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 1
            // "Done \u00b7 N"
            text: "\u5df2\u5b8c\u6210 \u00b7 " + panel.doneRows.length
            color: panel.inkFaint
            font.family: panel.theme.textFontFamily
            font.pixelSize: panel.theme.px(11)
            font.weight: Font.DemiBold
            font.letterSpacing: 0.4
          }
        }

        Repeater {
          model: panel.doneRows
          delegate: TodosRow {
            required property var modelData
            view: panel
            task: modelData.task
            at: modelData.at
          }
        }
      }
    }

    Item {
      width: parent.width
      height: panel.tasks.length ? note.implicitHeight : 0
      visible: panel.tasks.length > 0 && panel.todos.error !== ""
      Text {
        id: note
        width: parent.width
        wrapMode: Text.WordWrap
        text: panel.todos.error
        color: panel.late
        font.family: panel.theme.textFontFamily
        font.pixelSize: panel.theme.px(12)
        font.weight: Font.Medium
      }
    }

    Text {
      visible: panel.tasks.length === 0
      width: parent.width
      wrapMode: Text.WordWrap
      // "Nothing yet: type a line below, and Enter writes it into the file"
      text: panel.todos.error !== "" ? panel.todos.error
        : "\u8fd8\u6ca1\u6709\u4efb\u52a1\uff1a\u5728\u4e0b\u9762\u8f93\u5165\u4e00\u884c\uff0c"
          + "\u56de\u8f66\u5c31\u5199\u8fdb " + panel.todos.path
      color: panel.todos.error !== "" ? panel.late : panel.inkMuted
      font.family: panel.theme.textFontFamily
      font.pixelSize: panel.theme.px(13)
      font.weight: Font.Medium
      lineHeight: 1.35
    }

    // ---------- the field ----------

    Rectangle {
      width: parent.width
      height: 38
      radius: 12
      color: Qt.rgba(1, 1, 1, 0.05)
      border.width: 1
      border.color: field.activeFocus ? panel.theme.withAlpha(panel.theme.accent, 0.55) : "transparent"
      Behavior on border.color { MotionColorAnimation { theme: panel.theme } }

      Text {
        id: plus
        anchors.left: parent.left
        anchors.leftMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        text: "\udb81\udd15"
        color: field.text !== "" ? panel.theme.accent : panel.inkMuted
        font.family: panel.theme.fontFamily
        font.pixelSize: panel.theme.px(15)
        Behavior on color { MotionColorAnimation { theme: panel.theme } }
      }
      TextInput {
        id: field
        anchors.left: plus.right
        anchors.leftMargin: 12
        anchors.right: parent.right
        anchors.rightMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        color: panel.ink
        selectionColor: panel.theme.withAlpha(panel.theme.accent, 0.4)
        selectedTextColor: panel.ink
        font.family: panel.theme.textFontFamily
        font.pixelSize: panel.theme.px(14)
        clip: true
        onAccepted: submit()
        function submit() {
          var what = text.trim()
          if (what === "") return
          todos.add(what)
          clear()
          panel.row = 0
        }
        function clear() { text = "" }
        Keys.onEscapePressed: function(event) {
          if (text !== "") { clear(); event.accepted = true; return }
          panel.host.view = "rest"
        }
        Text {
          anchors.fill: parent
          verticalAlignment: Text.AlignVCenter
          visible: field.text === ""
          // "Jot something down" - what follows is todo.txt: +project, @context, p:1
          text: "\u8bb0\u4e00\u4ef6\u4e8b\uff0c\u56de\u8f66\u5199\u8fdb\u6e05\u5355"
            + "\uff08+\u9879\u76ee @\u573a\u666f p:1\uff09"
          color: panel.inkFaint
          font: field.font
        }
      }
    }

    // ---------- what the keys do ----------

    Text {
      width: parent.width
      // "Up/Down pick \u00b7 Space finish \u00b7 d delete \u00b7 Esc close"
      text: "\u2191\u2193 \u9009\u62e9 \u00b7 \u7a7a\u683c \u5b8c\u6210 \u00b7 "
        + "d \u5220\u9664 \u00b7 Esc \u5173\u95ed"
      color: panel.inkFaint
      font.family: panel.theme.textFontFamily
      font.pixelSize: panel.theme.px(11)
      opacity: 0.8
    }
  }
}
