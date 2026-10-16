import QtQuick
import Quickshell.Io

// The island's own settings, saved to ~/.config/omarchy/island.json and
// changed live from Settings. `values` is the adapter: read and assign its
// properties directly. A missing file is written with the defaults below.
Item {
  id: islandSettings
  required property string home
  readonly property QtObject values: settingsData

  FileView {
    path: islandSettings.home + "/.config/omarchy/island.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onAdapterUpdated: writeAdapter()
    onLoadFailed: function(error) {
      if (error !== FileViewError.FileNotFound) return
      writeAdapter()
      Qt.callLater(reload)
    }
    JsonAdapter {
      id: settingsData
      property real motionScale: 1.5
      property bool hoverLift: true
      property bool clock24h: true
      property bool mediaPill: true
      property bool volumeHud: true
      property bool brightnessHud: true
      property int bannerSeconds: 5
      property bool notch: false
      // Glass shell. 1 = the upstream solid black; lower lets the desktop behind
      // the island show through, blurred by the "island-glass" layer rule
      // (~/.config/hypr/looknfeel.lua). Settings → General → Appearance.
      property real glassOpacity: 1
      // GitHub update check and its one-click update. Off pins the plugin to
      // what is in the folder; update by hand with `omarchy plugin update`.
      property bool autoUpdate: true
      property bool downloads: true
      property bool clipboard: true
      property bool systemUpdates: true
      property bool batteryActivity: true
      property bool bluetoothActivity: true
      property bool networkActivity: true
      property bool playbackOsd: false
      property bool workspaceHud: false
      property bool colorfulSettingsIcons: true
      property bool colorfulLiveActivities: true
      property string textFontMode: "island"
      property string customFont: ""
      property real textScale: 1
      property string controlCenterOrder: "wifi,bluetooth,focus,night,sound,microphone,display"
      property string controlCenterHidden: "game,power,keyboard"
      property bool microphoneMuteControl: false
      // Before Ask AI was an addon; carried over and cleared (see Addons.qml).
      property string askAi: ""
      // Addon id → enabled, and addon id → its options (see addons/Addons.qml).
      property var addons: ({})
      property var addonOptions: ({})
    }
  }
}
