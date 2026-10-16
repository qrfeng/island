import QtQuick
import QtQuick.Layouts
import "../../components"

// A compact Control Center with grouped switches, sliders, and notifications.
// What the controls show and do is in Controls.qml, the grid and editing it
// in ControlLayout.qml; the cards are their own files.
ColumnLayout {
  id: cc
  required property var host
  property bool active: false
  readonly property Controls controls: Controls { host: cc.host }

  // Keep the black island while deriving its controls from the active theme.
  readonly property color accent: host.theme.accent
  readonly property color accentInk: host.theme.accentText
  readonly property color text: host.theme.text
  readonly property color textMuted: Qt.tint(host.theme.background, host.theme.withAlpha(text, 0.6))
  readonly property color tile: Qt.tint(host.theme.background, host.theme.withAlpha(text, 0.11))
  readonly property color card: Qt.tint(host.theme.background, host.theme.withAlpha(text, 0.075))
  readonly property color edge: host.theme.withAlpha(text, 0.05)
  readonly property color well: Qt.tint(host.theme.background, host.theme.withAlpha(text, 0.16))
  readonly property color wellHover: Qt.tint(host.theme.background, host.theme.withAlpha(text, 0.22))
  readonly property string iconFont: host.theme.fontFamily
  // macOS shapes: switches are capsules, cards concentric with the island.
  readonly property real cardRadius: 24
  // The icon on a switched-on (accent) badge: a deep shade of the accent.
  readonly property color badgeOnInk: Qt.hsla(accent.hslHue, accent.hslSaturation, 0.16, 1)
  property bool editMode: false
  property bool outputsOpen: false
  property bool inputsOpen: false
  onEditModeChanged: {
    outputsOpen = false
    inputsOpen = false
    cc.forceActiveFocus()
  }
  onActiveChanged: {
    if (!active) {
      revealed = false
      outputsOpen = false; inputsOpen = false; editMode = false; controlLayout.endDrag(); return
    }
    // Rest the tiles out of the way first, then let them in one tick later, once
    // the grid is laid out and every tile's place in the cascade is known.
    Qt.callLater(function() { cc.forceActiveFocus(); cc.revealed = true })
    controls.refresh()
  }

  // ---------- Entrance choreography ----------
  // The tiles land on top of the island's own open morph: each one fades in and
  // lifts into place just after the tile before it, so a glance reads the grid as
  // assembling instead of simply appearing. The delay lives in the per-card
  // Behaviors on the cards below, indexed by the grid's own order, so nothing
  // ticks while the panel sits open.
  property bool revealed: false
  readonly property int revealStagger: 20    // ms between neighbouring tiles
  readonly property int revealStaggerMax: 8  // tiles that stagger; the later ones land together
  // controlKey -> grid order, taken from the grid's own visible list so the
  // cascade still follows the tiles on screen after the user reorders them.
  readonly property var revealRanks: {
    var ranks = {}
    var keys = controlLayout.visibleControlKeys
    for (var i = 0; i < keys.length; i++) {
      if (!(keys[i] in ranks)) ranks[keys[i]] = i
    }
    return ranks
  }
  // Past the cap every tile waits the longest delay, so a full grid still lands
  // together instead of trickling in.
  function revealDelay(key) {
    var rank = revealRanks.hasOwnProperty(key) ? revealRanks[key] : revealStaggerMax
    return Math.min(rank, revealStaggerMax) * revealStagger
  }
  function controlComponent(key) {
    var tile = host.addons.tileFor(key)
    if (tile) return tile.component
    if (key === "sound") return soundCard
    if (key === "microphone") return microphoneCard
    if (key === "display") return displayCard
    return quickCard
  }

  spacing: 10

  // Esc leaves edit mode, then closes the control center.
  Keys.onEscapePressed: {
    if (cc.editMode) { cc.editMode = false; controlLayout.endDrag() }
    else cc.host.view = "rest"
  }

  // ---------- Header ----------

  RowLayout {
    Layout.fillWidth: true
    Layout.preferredHeight: 34
    Layout.leftMargin: 4
    Layout.rightMargin: 4
    Text {
      text: "控制中心"
      color: cc.text
      font.family: cc.host.theme.textFontFamily
      font.pixelSize: cc.host.theme.px(17)
      font.weight: Font.DemiBold
    }
    Item { Layout.fillWidth: true }
    Rectangle {
      Layout.preferredWidth: cc.editMode ? 64 : 32
      Layout.preferredHeight: 32
      radius: 16
      color: editMouse.containsMouse || cc.editMode ? cc.well : cc.card
      Tooltip { theme: cc.host.theme; text: cc.editMode ? "" : "编辑控件" }
      Text {
        anchors.centerIn: parent
        text: cc.editMode ? "完成" : "󰏫"
        color: cc.text
        font.family: cc.editMode ? cc.host.theme.textFontFamily : cc.iconFont
        font.pixelSize: cc.editMode ? cc.host.theme.px(12) : cc.host.theme.px(17)
        font.weight: Font.DemiBold
      }
      MouseArea {
        id: editMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: cc.editMode = !cc.editMode
      }
    }
    Rectangle {
      Layout.preferredWidth: 32
      Layout.preferredHeight: 32
      radius: 16
      color: settingsMouse.containsMouse ? cc.well : cc.card
      Tooltip { theme: cc.host.theme; text: "island 设置" }
      Text {
        anchors.centerIn: parent
        text: "󰒓"
        color: cc.text
        font.family: cc.iconFont
        font.pixelSize: cc.host.theme.px(17)
      }
      MouseArea {
        id: settingsMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: cc.host.view = "settings"
      }
    }
    // Battery, as macOS's menu bar shows it: the percentage, then a battery
    // filled to the level (green while charging, red when low), with a bolt
    // while charging.
    Row {
      visible: cc.controls.hasBattery
      Layout.leftMargin: 6
      Layout.rightMargin: 6
      spacing: 6
      readonly property bool low: cc.controls.batteryPercent <= 20 && !cc.controls.charging
      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: cc.controls.batteryPercent + "%"
        color: parent.low ? "#ff453a" : cc.text
        font.family: cc.host.theme.textFontFamily
        font.pixelSize: cc.host.theme.px(13)
        font.weight: Font.DemiBold
        font.features: { "tnum": 1 }
      }
      BatteryIcon {
        anchors.verticalCenter: parent.verticalCenter
        width: 30
        height: 14
        level: cc.controls.batteryPercent
        charging: cc.controls.charging
        low: parent.low
        color: cc.text
      }
    }
  }

  ControlLayout {
    id: controlLayout
    Layout.fillWidth: true
    center: cc
  }

  NotificationHistory { center: cc }

  // ---------- Cards, loaded by the grid and the gallery ----------

  // Each card is wrapped in a surface that owns the entrance: the cards bind
  // their own opacity (a CcTile dims to half while unavailable) and that binding
  // has to keep working, so the cascade rides on a parent of theirs instead. The
  // wrapper is a plain Item filled by the Loader that loads it, which is how all
  // three of its users (grid, gallery, drag ghost's source) size it anyway.
  Component {
    id: quickCard
    Item {
      id: revealQuick
      property var center: cc
      // The grid, the gallery and the drag ghost all declare `controlKey` and
      // `galleryPreview` on the Loader that loads this component, so the wrapper
      // has to forward them from its own parent: the card below still reads
      // `parent.controlKey`, and its parent is now this item.
      readonly property string controlKey: parent && parent.controlKey !== undefined ? String(parent.controlKey) : ""
      readonly property bool galleryPreview: parent ? parent.galleryPreview === true : false
      anchors.fill: parent
      opacity: cc.revealed ? 1 : 0
      Behavior on opacity {
        enabled: cc.revealed
        SequentialAnimation {
          PauseAnimation { duration: cc.revealDelay(revealQuick.controlKey) }
          MotionAnimation { theme: cc.host.theme; pace: "standard" }
        }
      }
      transform: Translate {
        y: cc.revealed ? 0 : 6
        Behavior on y {
          enabled: cc.revealed
          SequentialAnimation {
            PauseAnimation { duration: cc.revealDelay(revealQuick.controlKey) }
            MotionAnimation { theme: cc.host.theme; pace: "standard"; curve: "morph" }
          }
        }
      }
      CcTile {
        center: cc
        anchors.fill: parent
        icon: cc.controls.controlIcon(parent.controlKey)
        title: cc.controls.controlTitle(parent.controlKey)
        subtitle: cc.controls.controlSubtitle(parent.controlKey)
        checked: cc.controls.controlChecked(parent.controlKey)
        available: parent.galleryPreview || cc.controls.controlAvailable(parent.controlKey)
        clickable: cc.controls.controlClickable(parent.controlKey)
        opens: (parent.controlKey === "bluetooth" && !!cc.controls.btAdapter) || (parent.controlKey === "wifi" && !!cc.controls.wifiDevice)
        onClicked: cc.controls.toggleControl(parent.controlKey)
        onOpened: cc.host.view = parent.controlKey
      }
    }
  }
  Component {
    id: soundCard
    Item {
      id: revealSound
      property var center: cc
      property string controlKey: "sound"
      property bool galleryPreview: false
      anchors.fill: parent
      opacity: cc.revealed ? 1 : 0
      Behavior on opacity {
        enabled: cc.revealed
        SequentialAnimation {
          PauseAnimation { duration: cc.revealDelay(revealSound.controlKey) }
          MotionAnimation { theme: cc.host.theme; pace: "standard" }
        }
      }
      transform: Translate {
        y: cc.revealed ? 0 : 6
        Behavior on y {
          enabled: cc.revealed
          SequentialAnimation {
            PauseAnimation { duration: cc.revealDelay(revealSound.controlKey) }
            MotionAnimation { theme: cc.host.theme; pace: "standard"; curve: "morph" }
          }
        }
      }
      SoundCard { center: cc }
    }
  }
  Component {
    id: microphoneCard
    Item {
      id: revealMicrophone
      property var center: cc
      property string controlKey: "microphone"
      property bool galleryPreview: false
      anchors.fill: parent
      opacity: cc.revealed ? 1 : 0
      Behavior on opacity {
        enabled: cc.revealed
        SequentialAnimation {
          PauseAnimation { duration: cc.revealDelay(revealMicrophone.controlKey) }
          MotionAnimation { theme: cc.host.theme; pace: "standard" }
        }
      }
      transform: Translate {
        y: cc.revealed ? 0 : 6
        Behavior on y {
          enabled: cc.revealed
          SequentialAnimation {
            PauseAnimation { duration: cc.revealDelay(revealMicrophone.controlKey) }
            MotionAnimation { theme: cc.host.theme; pace: "standard"; curve: "morph" }
          }
        }
      }
      MicrophoneCard { center: cc }
    }
  }
  Component {
    id: displayCard
    Item {
      id: revealDisplay
      property var center: cc
      property string controlKey: "display"
      property bool galleryPreview: false
      anchors.fill: parent
      opacity: cc.revealed ? 1 : 0
      Behavior on opacity {
        enabled: cc.revealed
        SequentialAnimation {
          PauseAnimation { duration: cc.revealDelay(revealDisplay.controlKey) }
          MotionAnimation { theme: cc.host.theme; pace: "standard" }
        }
      }
      transform: Translate {
        y: cc.revealed ? 0 : 6
        Behavior on y {
          enabled: cc.revealed
          SequentialAnimation {
            PauseAnimation { duration: cc.revealDelay(revealDisplay.controlKey) }
            MotionAnimation { theme: cc.host.theme; pace: "standard"; curve: "morph" }
          }
        }
      }
      DisplayCard { center: cc }
    }
  }
}
