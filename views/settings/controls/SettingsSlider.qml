import QtQuick
import QtQuick.Layouts
import "../../../components"

// A continuous capsule slider for the settings pages: the Control Center
// slider's look, scaled down to sit inside a group card. Emit `moved` and let
// the page write the setting; `value` stays a plain binding in, never a
// two-way write-back, so the page owns the truth.
// `view` is the SettingsView, for its colours.
Item {
  id: s
  required property var view
  property real value: 0
  property real from: 0
  property real to: 1
  signal moved(real value)

  implicitHeight: 24
  Layout.fillWidth: true
  Layout.preferredHeight: implicitHeight

  readonly property real clamped: Math.max(from, Math.min(to, value))
  readonly property real fraction: to > from ? (clamped - from) / (to - from) : 0
  readonly property real cap: Math.max(8, track.height)

  // Animate the level only while the pointer is away, so dragging tracks 1:1.
  property real shown: fraction
  Behavior on shown {
    enabled: !dragArea.pressed
    MotionAnimation { theme: s.view.host.theme; pace: "quick" }
  }

  function valueAt(xPos) {
    var usable = Math.max(1, track.width - cap)
    var fraction = (xPos - cap / 2) / usable
    return from + Math.max(0, Math.min(1, fraction)) * (to - from)
  }

  Rectangle {
    id: track
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    height: 20
    radius: height / 2
    color: s.view.host.theme.withAlpha(s.view.text, dragArea.pressed ? 0.26 : (dragArea.containsMouse ? 0.22 : 0.16))
    Behavior on color { MotionColorAnimation { theme: s.view.host.theme } }

    Rectangle {
      height: parent.height
      radius: parent.height / 2
      width: s.cap + (parent.width - s.cap) * s.shown
      color: "#ececec"
    }
    // The knob, sitting on the fill's end.
    Rectangle {
      x: Math.min(parent.width - width, s.cap + (parent.width - s.cap) * s.shown - width / 2)
      anchors.verticalCenter: parent.verticalCenter
      width: s.cap + 2
      height: s.cap + 2
      radius: height / 2
      color: "#ffffff"
      border.width: 1
      border.color: s.view.host.theme.withAlpha("#000000", 0.18)
    }
  }

  MouseArea {
    id: dragArea
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    onPressed: function (mouse) { s.moved(s.valueAt(mouse.x)) }
    onPositionChanged: function (mouse) { if (dragArea.pressed) s.moved(s.valueAt(mouse.x)) }
  }
}
