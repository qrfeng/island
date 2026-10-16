import QtQuick
import Quickshell
import "../../components"

// The task list: what's still to do, in the order it was written - or under
// their +projects, which is what `g` switches between - with the finished ones
// dimmed under a rule. Type in the field at the bottom and Enter appends the
// line to the file; Up and Down pick a task, Space finishes it (or opens it up
// again) and d deletes it. A task can be dragged to a new place, and the path at
// the bottom right is the file all of this is read from. The list is a picture
// of the file, so a task added in a terminal shows up by itself and nothing is
// stored twice.
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
  // One row tall, which is what a drag is counted in.
  readonly property int span: 36
  readonly property bool grouped: todos.grouped
  // Finished tasks old enough to be filed away, and offered for it.
  readonly property bool canFile: todos.archiveDays > 0 && todos.archivable > 0

  // ---------- the order on screen ----------

  // Runs of rows: the open ones as they were written or gathered under their
  // +project, then the finished ones under a rule. Every row carries its place
  // down the page (`at`), which is what the arrows walk and what a drag answers
  // to, so no key or gesture has to know how the list happens to be grouped.
  readonly property var sections: build()
  readonly property var order: flat()

  function runsOf(open) {
    if (!panel.grouped) return [{ key: "", title: "", list: open }]
    var keys = [], byKey = {}
    for (var i = 0; i < open.length; i++) {
      // The first +project speaks for the line, which is what the row trails.
      var own = String((open[i].projects || [])[0] || "")
      if (byKey[own] === undefined) { byKey[own] = []; keys.push(own) }
      byKey[own].push(open[i])
    }
    // Everything in one named project, or nothing in any, says nothing; say it
    // once at the top instead of a heading per run.
    if (keys.length === 0 || (keys.length === 1 && keys[0] === ""))
      return [{ key: "", title: "", list: open }]
    var runs = []
    for (var k = 0; k < keys.length; k++)
      runs.push({ key: keys[k], title: keys[k] === "" ? "\u6536\u4ef6\u7bb1" : "+ " + keys[k],
        list: byKey[keys[k]] })
    return runs
  }

  function build() {
    var open = [], finished = []
    for (var i = 0; i < tasks.length; i++)
      (tasks[i].done ? finished : open).push(tasks[i])
    var runs = runsOf(open), secs = [], at = 0
    for (var r = 0; r < runs.length; r++) {
      var rows = []
      for (var t = 0; t < runs[r].list.length; t++) rows.push({ task: runs[r].list[t], at: at++ })
      secs.push({ key: runs[r].key, title: runs[r].title, done: false, rows: rows })
    }
    if (finished.length > 0) {
      var under = []
      for (var f = 0; f < finished.length; f++) under.push({ task: finished[f], at: at++ })
      secs.push({ key: "\u0000", title: "", done: true, rows: under })
    }
    return secs
  }

  function flat() {
    var out = []
    for (var i = 0; i < sections.length; i++) out = out.concat(sections[i].rows)
    return out
  }

  // Where a row sits inside its own run, which is what a drag is counted in.
  function place(at) {
    for (var i = 0; i < sections.length; i++) {
      if (sections[i].done) continue
      var rows = sections[i].rows
      for (var j = 0; j < rows.length; j++) if (rows[j].at === at) return { sec: i, index: j }
    }
    return null
  }

  function flashOf(task) { return todos.flashOf(task) }

  // The task's path with the home folder written as ~, which is the half of it
  // that identifies the file rather than the machine.
  readonly property string shortPath: {
    var own = todos.path
    var home = String(Quickshell.env("HOME") || "")
    return home !== "" && own.indexOf(home) === 0 ? "~" + own.substring(home.length) : own
  }

  // ---------- the picked row ----------

  property int row: 0
  readonly property int clamped: order.length === 0 ? 0 : Math.max(0, Math.min(row, order.length - 1))
  function picked() { return order[clamped] ? order[clamped].task : null }
  function togglePicked() { if (picked()) todos.toggle(picked()) }
  function removePicked() {
    var task = picked()
    if (!task) return
    todos.remove(task)
    row = Math.max(0, clamped - 1)
  }
  function pick(at) {
    row = at
    panel.forceActiveFocus()
  }
  function move(by) {
    if (order.length === 0) return
    row = Math.max(0, Math.min(clamped + by, order.length - 1))
    field.focus = false
    panel.forceActiveFocus()
  }

  // The list is rebuilt by whoever changed the file, so the picked row is kept
  // inside it, and a drag - which holds a place in a list that has just moved -
  // is let go of rather than retargeted.
  onSectionsChanged: {
    row = Math.max(0, Math.min(row, Math.max(0, order.length - 1)))
    if (dragActive) cancelDrag()
  }

  implicitHeight: column.height

  onActiveChanged: {
    if (!active) return
    row = 0
    Qt.callLater(function() { field.forceActiveFocus() })
  }

  // ---------- dragging to reorder ----------

  property int dragAt: -1
  property real dragDy: 0
  property var dragTask: null
  property var dragWhere: null
  readonly property bool dragActive: dragAt >= 0 && dragWhere !== null
  // How many rows the dragged one has crossed, which is what is written back
  // when the pointer lets go - a row snaps to the slots it passed over.
  readonly property int dragStep: {
    if (!dragActive || dragWhere === null || !sections[dragWhere.sec]) return 0
    var n = sections[dragWhere.sec].rows.length
    var by = Math.round(dragDy / span)
    return Math.max(-dragWhere.index, Math.min(n - 1 - dragWhere.index, by))
  }
  // Everyone the dragged row is passing, stepping one row out of its way.
  readonly property var dragOffsets: {
    var out = {}
    if (!dragActive || dragWhere === null || dragStep === 0) return out
    var rows = sections[dragWhere.sec] ? sections[dragWhere.sec].rows : []
    for (var i = 0; i < rows.length; i++) {
      if (dragStep > 0 && i > dragWhere.index && i <= dragWhere.index + dragStep) out[rows[i].at] = -panel.span
      else if (dragStep < 0 && i >= dragWhere.index + dragStep && i < dragWhere.index) out[rows[i].at] = panel.span
    }
    return out
  }

  function beginDrag(at) {
    var where = place(at), line = order[at]
    if (where === null || !line) return
    dragAt = at
    dragWhere = where
    dragTask = line.task
    dragDy = 0
    row = at
    scroller.interactive = false
    field.focus = false
    panel.forceActiveFocus()
  }
  function dragTo(dy) {
    if (dragActive) dragDy = dy
  }
  function cancelDrag() {
    dragAt = -1
    dragDy = 0
    dragTask = null
    dragWhere = null
    scroller.interactive = true
  }
  function endDrag() {
    var task = dragTask, step = dragStep, where = dragWhere
    cancelDrag()
    if (!task || step === 0 || where === null) return
    var run = sections[where.sec]
    if (!run) return
    // Down the list means landing above the row it was dropped past, and up
    // means above the row it was dropped on; past the last row is -1.
    var at = where.index + (step > 0 ? step + 1 : step)
    todos.move(task, at < run.rows.length ? run.rows[at].task.line : -1)
  }

  // ---------- keys ----------

  Keys.onEscapePressed: function(event) {
    if (dragActive) { cancelDrag(); event.accepted = true; return }
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
  // `d` deletes the picked task, `n` goes back to the field, `g` groups by
  // +project, `a` files the finished ones away, `o` opens the folder it's in.
  Keys.onPressed: function(event) {
    if (field.activeFocus) return
    if (event.key === Qt.Key_D) {
      panel.removePicked()
      event.accepted = true
    } else if (event.key === Qt.Key_N) {
      field.forceActiveFocus()
      event.accepted = true
    } else if (event.key === Qt.Key_G) {
      todos.setGrouped(!todos.grouped)
      event.accepted = true
    } else if (event.key === Qt.Key_A) {
      todos.archive()
      event.accepted = true
    } else if (event.key === Qt.Key_O) {
      todos.openFolder()
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
          model: panel.sections
          delegate: Column {
            id: run
            required property var modelData
            width: body.width
            spacing: 3
            property var part: modelData

            // Row choreography: a task lands, the rows below slide to make
            // room; one is checked off, it fades and the list closes the gap.
            // Only y/opacity/scale move here, never the column's own height
            // binding, so the scroller above just follows implicitHeight.
            add: Transition {
              ParallelAnimation {
                MotionAnimation {
                  theme: panel.host.theme
                  property: "opacity"; from: 0; to: 1
                  pace: "standard"
                }
                MotionAnimation {
                  theme: panel.host.theme
                  property: "y"; from: -6; to: 0
                  pace: "standard"; curve: "morph"
                }
              }
            }
            // A checked-off row disappears; the ones below slide up into its
            // place. Positioners animate add/move/populate only, so there is
            // no exit fade for the row itself.
            move: Transition {
              MotionAnimation {
                theme: panel.host.theme
                property: "y"
                pace: "expressive"; curve: "morph"
              }
            }

            // A +project's name, or the rule and the count over the finished
            // ones. Nothing is said for a list that isn't grouped.
            Item {
              width: run.width
              height: run.part.done ? 26 : (run.part.title !== "" ? 20 : 0)
              visible: height > 0

              Rectangle {
                anchors.top: parent.top
                width: parent.width
                height: 1
                color: Qt.rgba(1, 1, 1, 0.07)
                visible: run.part.done
              }
              Text {
                anchors.left: parent.left
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 1
                // "Done \u00b7 N" over the finished ones
                text: run.part.done ? "\u5df2\u5b8c\u6210 \u00b7 " + run.part.rows.length : run.part.title
                color: run.part.done ? panel.inkFaint : panel.inkMuted
                font.family: panel.theme.textFontFamily
                font.pixelSize: panel.theme.px(11)
                font.weight: Font.DemiBold
                font.letterSpacing: 0.4
              }
              Text {
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 1
                visible: !run.part.done && panel.grouped
                text: run.part.rows.length + " \u9879"
                color: panel.inkFaint
                font.family: panel.theme.textFontFamily
                font.pixelSize: panel.theme.px(11)
                font.weight: Font.Medium
              }
              // The offer, when something finished is old enough to go: it says
              // where they go rather than asking twice.
              Rectangle {
                id: filing
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 1
                width: filingText.implicitWidth + 16
                height: 19
                radius: 6
                visible: run.part.done && panel.canFile
                color: filingHover.hovered ? panel.theme.withAlpha(panel.doneTint, 0.24)
                  : Qt.rgba(1, 1, 1, 0.05)
                Behavior on color { MotionColorAnimation { theme: panel.theme } }
                Text {
                  id: filingText
                  anchors.centerIn: parent
                  // "File N \u6761"
                  text: "\u5f52\u6863 " + panel.todos.archivable + " \u6761"
                  color: panel.doneTint
                  font.family: panel.theme.textFontFamily
                  font.pixelSize: panel.theme.px(11)
                  font.weight: Font.DemiBold
                }
                HoverHandler { id: filingHover }
                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: panel.todos.archive()
                }
              }
            }

            Repeater {
              model: run.part.rows
              delegate: TodosRow {
                required property var modelData
                view: panel
                task: modelData.task
                at: modelData.at
              }
            }
          }
        }
      }
    }

    // ---------- what changed, or why nothing did ----------

    Item {
      width: parent.width
      height: panel.noteHeight
      visible: height > 0
      Text {
        id: note
        width: parent.width
        wrapMode: Text.WordWrap
        anchors.bottom: parent.bottom
        text: panel.todos.error !== "" ? panel.todos.error : panel.todos.note
        color: panel.todos.error !== "" ? panel.late : panel.doneTint
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
          + "\u56de\u8f66\u5c31\u5199\u8fdb " + panel.shortPath
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

    // ---------- the keys ----------

    Text {
      width: parent.width
      elide: Text.ElideRight
      // "Up/Down pick \u00b7 Space finish \u00b7 drag to order \u00b7 d delete \u00b7 g group
      // \u00b7 Esc close"
      text: "\u2191\u2193 \u9009\u62e9 \u00b7 \u7a7a\u683c \u5b8c\u6210 \u00b7 \u62d6\u52a8 \u6392\u5e8f \u00b7 "
        + "d \u5220\u9664 \u00b7 g \u5206\u7ec4 \u00b7 Esc \u5173\u95ed"
      color: panel.inkFaint
      font.family: panel.theme.textFontFamily
      font.pixelSize: panel.theme.px(11)
      opacity: 0.8
    }

    // ---------- the file the keys act on ----------

    Item {
      width: parent.width
      height: 22

      Text {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: Math.max(0, parent.width - paper.width - 14)
        elide: Text.ElideRight
        // "a files the finished ones away \u00b7 o opens the folder it's in"
        text: (panel.canFile ? "a \u5f52\u6863\u5b8c\u6210\u9879 \u00b7 " : "")
          + "o \u6253\u5f00\u6240\u5728\u6587\u4ef6\u5939"
        color: panel.inkFaint
        font.family: panel.theme.textFontFamily
        font.pixelSize: panel.theme.px(11)
        opacity: 0.66
      }

      Rectangle {
        id: paper
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: Math.min(pin.implicitWidth + pathText.implicitWidth + 22, 240)
        height: 21
        radius: 7
        color: paperHover.hovered ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(1, 1, 1, 0.045)
        Behavior on color { MotionColorAnimation { theme: panel.theme } }

        Text {
          id: pin
          anchors.left: parent.left
          anchors.leftMargin: 9
          anchors.verticalCenter: parent.verticalCenter
          text: "\udb80\udd92"
          color: paperHover.hovered ? panel.inkMuted : panel.inkFaint
          font.family: panel.theme.fontFamily
          font.pixelSize: panel.theme.px(12)
        }
        Text {
          id: pathText
          anchors.left: pin.right
          anchors.leftMargin: 6
          anchors.verticalCenter: parent.verticalCenter
          // Elided from the middle: the file's name is the part worth reading.
          width: Math.min(implicitWidth, 240 - pin.implicitWidth - 34)
          elide: Text.ElideMiddle
          text: panel.shortPath
          color: paperHover.hovered ? panel.ink : panel.inkFaint
          font.family: panel.theme.textFontFamily
          font.pixelSize: panel.theme.px(11)
          Behavior on color { MotionColorAnimation { theme: panel.theme } }
        }
        HoverHandler { id: paperHover }
        MouseArea {
          anchors.fill: parent
          acceptedButtons: Qt.LeftButton | Qt.RightButton
          cursorShape: Qt.PointingHandCursor
          // Left goes to the folder, right takes the path to the clipboard for
          // pasting into a terminal.
          onClicked: function(mouse) {
            if (mouse.button === Qt.RightButton) panel.todos.copyPath()
            else panel.todos.openFolder()
          }
        }
      }
    }
  }

  readonly property real noteHeight: panel.tasks.length > 0
    && (todos.error !== "" || todos.note !== "") ? note.implicitHeight : 0
}
