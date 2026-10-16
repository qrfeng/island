import QtQuick
import "../../components"

// Shown for a moment when fcitx5 switches input method: the input-method
// leading, the label you set for it in the middle ("中文" / "英文"), and its
// fcitx5 name muted at the end, so an unexpected one is at least identifiable.
// `im` is the InputMethodAddon.
Item {
  id: pill
  required property var im
  readonly property var host: im.host
  readonly property bool shown: im.pillShown

  opacity: shown ? 1 : 0
  visible: opacity > 0.01
  Behavior on opacity { MotionAnimation { theme: pill.host.theme; pace: "fade"; curve: "fade" } }

  Text {
    id: leading
    anchors.left: parent.left
    anchors.leftMargin: 14
    anchors.verticalCenter: parent.verticalCenter
    text: "󰍛"
    color: pill.host.theme.accent
    font.family: pill.host.theme.fontFamily
    font.pixelSize: pill.host.theme.px(20)
    scale: pill.shown ? 1 : 0.86
    Behavior on scale { MotionAnimation { theme: pill.host.theme; pace: "expressive" } }
  }

  // English shows no name: "英文" already says everything the name would.
  Text {
    id: trailing
    anchors.right: parent.right
    anchors.rightMargin: 14
    anchors.verticalCenter: parent.verticalCenter
    text: pill.im.chinese ? pill.im.name : ""
    textFormat: Text.PlainText
    elide: Text.ElideMiddle
    color: Qt.rgba(1, 1, 1, 0.45)
    font.family: pill.host.theme.textFontFamily
    font.pixelSize: pill.host.theme.px(11)
  }

  Text {
    anchors.left: leading.right
    anchors.leftMargin: 10
    anchors.right: trailing.left
    anchors.rightMargin: trailing.text ? 12 : 0
    anchors.verticalCenter: parent.verticalCenter
    text: pill.im.label
    textFormat: Text.PlainText
    elide: Text.ElideRight
    color: "#ffffff"
    font.family: pill.host.theme.textFontFamily
    font.pixelSize: pill.host.theme.px(13)
    font.weight: Font.Medium
    font.letterSpacing: -0.2
  }
}
