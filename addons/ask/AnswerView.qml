import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import "../../components"

// Siri-style answers: a question typed in the launcher is sent to the chosen
// AI through its command-line tool, signed in with your own account (Pi's
// `pi -p --mode json`, which streams the answer word by word). Like Siri in the
// Dynamic Island, a compact pill with glowing dots while it thinks, then the
// answer in large type as it arrives. Under the answer, a field to keep asking: a
// follow-up goes through the same session, so the tool knows what it just
// said, and the turns above stay readable above it. The conversation, the
// prompt and the run all live in AskAddon, which the island makes once for
// every screen; this is only its view. Copy and Esc: Copy takes the answer on
// screen, Esc closes it (and stops a pending answer).
Item {
  id: answer
  required property var host
  // The addon (see AskAddon), which holds the conversation and the AI.
  required property var ask
  property bool active: false

  // Thinking, and thinking before there is anything above to keep room for:
  // only that second case shrinks the island to a pill.
  readonly property bool thinking: ask.busy && ask.text === "" && ask.error === ""
  readonly property bool compact: thinking && ask.turns.length === 0
  readonly property bool firstTurn: ask.turns.length === 0

  implicitHeight: layout.implicitHeight

  readonly property int surfaceWidth: compact ? 280 : 580
  readonly property int surfacePadding: compact ? 14 : 28
  readonly property int surfaceRadius: 44

  onActiveChanged: {
    if (active) Qt.callLater(function() { answer.focusNow() })
    else ask.stopRun()
  }
  // While it answers there is nothing to type yet, so the island itself keeps
  // the keyboard and Esc still closes it.
  function focusNow() {
    if (ask.busy) answer.forceActiveFocus()
    else followup.forceActiveFocus()
  }
  Connections {
    target: ask
    function onBusyChanged() {
      if (!ask.busy && answer.active) Qt.callLater(function() { answer.focusNow() })
    }
  }

  Keys.onEscapePressed: close()
  function close() {
    ask.stopRun()
    host.view = "rest"
  }

  function askAgain() {
    var what = String(followup.text || "").trim()
    if (what === "" || ask.busy) return
    followup.text = ""
    ask.followUp(what)
  }

  // Written as plain text, like Siri: the model slips in Markdown, and web
  // search results carry citation markers wrapped in private-use characters
  // (U+E200 open, U+E202 turn, U+E201 close). Escaped here instead of literal
  // so the file stays ASCII and an edit can't mangle the glyphs.
  function plain(s) {
    return String(s || "")
      .replace(/\ue200[^\ue201]*\ue201/g, "").replace(/[\ue000-\uf8ff]/g, "")
      .replace(/\*\*(.+?)\*\*/g, "$1").replace(/__(.+?)__/g, "$1")
      .replace(/`([^`]+)`/g, "$1").replace(/^#+\s*/gm, "")
      .replace(/\[([^\]]+)\]\([^)]*\)/g, "$1")
      .replace(/[ \t]+$/gm, "").trim()
  }

  Process { id: helper }
  function copy() {
    helper.command = ["wl-copy", "--", ask.text]
    helper.startDetached()
  }

  ColumnLayout {
    id: layout
    anchors.left: parent.left
    anchors.right: parent.right
    spacing: 14

    // Thinking to a first question: Siri's glowing dots, on their own.
    SiriDots {
      visible: answer.compact
      running: answer.compact && answer.active
      Layout.leftMargin: 2
    }

    // What it's doing out on the web, so the dots don't read as idle.
    Text {
      visible: answer.thinking && ask.working !== ""
      Layout.leftMargin: 2
      text: ask.working
      color: answer.host.theme.muted
      font.family: answer.host.theme.textFontFamily
      font.pixelSize: answer.host.theme.px(13)
    }

    // The conversation, oldest first; the answer on screen in large type.
    Flickable {
      id: scroller
      visible: !answer.compact
      Layout.fillWidth: true
      Layout.preferredHeight: Math.min(transcript.implicitHeight, 460)
      contentHeight: transcript.implicitHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      // The answer grows downwards as it streams: keep its tail in view.
      onContentHeightChanged: Qt.callLater(function() {
        if (scroller.contentHeight > scroller.height)
          scroller.contentY = scroller.contentHeight - scroller.height
      })

      ColumnLayout {
        id: transcript
        width: scroller.width
        spacing: 10

        // The turns before this one: question and answer, a step down from
        // what's being answered now.
        Repeater {
          model: ask.turns
          delegate: ColumnLayout {
            required property var modelData
            required property int index
            Layout.fillWidth: true
            Layout.topMargin: index > 0 ? 6 : 0
            spacing: 4
            Text {
              Layout.fillWidth: true
              text: answer.plain(modelData.q)
              color: answer.host.theme.muted
              font.family: answer.host.theme.textFontFamily
              font.pixelSize: answer.host.theme.px(13)
              wrapMode: Text.Wrap
              lineHeight: 1.1
            }
            Text {
              Layout.fillWidth: true
              text: answer.plain(modelData.a)
              color: modelData.failed ? answer.host.theme.urgent : "#b6b6bb"
              font.family: answer.host.theme.textFontFamily
              font.pixelSize: answer.host.theme.px(15)
              wrapMode: Text.Wrap
              lineHeight: 1.1
            }
          }
        }

        // This turn. A first question is just its answer, as ever; after that
        // its question shows above, so the answers keep their order.
        Text {
          id: now
          visible: !answer.firstTurn && ask.question !== ""
          Layout.fillWidth: true
          text: answer.plain(ask.question)
          color: answer.host.theme.muted
          font.family: answer.host.theme.textFontFamily
          font.pixelSize: answer.host.theme.px(13)
          wrapMode: Text.Wrap
          lineHeight: 1.1
        }
        SiriDots {
          visible: answer.thinking && !answer.firstTurn
          running: visible && answer.active
          Layout.leftMargin: 2
        }

        Text {
          id: body
          visible: !answer.thinking
          Layout.fillWidth: true
          text: ask.error !== "" ? ask.error : answer.plain(ask.text)
          textFormat: Text.PlainText
          wrapMode: Text.Wrap
          color: ask.error !== "" ? answer.host.theme.urgent : "#ffffff"
          font.family: answer.host.theme.textFontFamily
          font.pixelSize: answer.host.theme.px(21)
          font.letterSpacing: -0.3
          lineHeight: 1.1
        }
      }
    }

    // Keep asking: Enter sends it in the same session, so the tool has the
    // turns above to lean on.
    Rectangle {
      id: followBox
      visible: !answer.compact
      Layout.fillWidth: true
      height: 38
      radius: 19
      color: Qt.rgba(1, 1, 1, followup.activeFocus ? 0.14 : 0.07)
      Behavior on color { MotionColorAnimation { theme: answer.host.theme } }

      Text {
        id: mark
        anchors.left: parent.left
        anchors.leftMargin: 15
        anchors.verticalCenter: parent.verticalCenter
        text: ask.busy ? "…" : "?"
        color: answer.host.theme.muted
        font.family: answer.host.theme.textFontFamily
        font.pixelSize: answer.host.theme.px(14)
        font.weight: Font.DemiBold
      }
      TextInput {
        id: followup
        anchors.left: mark.right
        anchors.leftMargin: 10
        anchors.right: copyRow.left
        anchors.rightMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        color: answer.host.theme.text
        selectionColor: answer.host.theme.withAlpha(answer.host.theme.accent, 0.4)
        selectedTextColor: answer.host.theme.text
        font.family: answer.host.theme.textFontFamily
        font.pixelSize: answer.host.theme.px(15)
        clip: true
        Keys.onReturnPressed: function(event) { answer.askAgain(); event.accepted = true }
        Keys.onEnterPressed: function(event) { answer.askAgain(); event.accepted = true }
        Keys.onEscapePressed: function(event) { answer.close(); event.accepted = true }
        Text {
          anchors.fill: parent
          verticalAlignment: Text.AlignVCenter
          visible: followup.text === ""
          text: ask.busy ? "思考中…" : "继续追问"
          color: answer.host.theme.muted
          font: followup.font
        }
      }
      // Copy the answer on screen, out of the way at the end of the row and
      // only while there's nothing being typed.
      Text {
        id: copyRow
        anchors.right: parent.right
        anchors.rightMargin: 16
        anchors.verticalCenter: parent.verticalCenter
        visible: ask.text !== "" && !ask.busy && followup.text === ""
        text: "复制"
        color: copyMouse.containsMouse ? "#ffffff" : answer.host.theme.muted
        font.family: answer.host.theme.textFontFamily
        font.pixelSize: answer.host.theme.px(12)
        font.weight: Font.DemiBold
        MouseArea {
          id: copyMouse
          anchors.fill: parent
          anchors.margins: -6
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: answer.copy()
        }
      }
    }
  }
}
