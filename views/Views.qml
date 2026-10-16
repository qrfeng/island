import QtQuick
import "../components"
import "control-center"
import "bluetooth"
import "wifi"
import "power"
import "launcher"
import "themes"
import "wallpapers"
import "emoji"
import "keybinds"
import "clipboard"
import "menu"
import "player"
import "settings"

// Every view the island can open. Each is a Surface: its name (also its IPC
// route: `omarchy-shell guilhermerisu.island show <name>`), how wide the
// island gets, its padding, and the view itself. Adding a view means adding
// its folder under views/ and one Surface here. Enabled addons' views are
// added at the end (see addons/Addon.qml).
Item {
  id: views
  required property var host

  readonly property var surfaces: [controlsSurface, wifiSurface, bluetoothSurface, themesSurface, wallpapersSurface, appsSurface, powerSurface, emojiSurface, keybindsSurface, clipboardSurface, menuSurface, playerSurface, settingsSurface]
  function surfaceFor(name) {
    for (var i = 0; i < surfaces.length; i++) if (surfaces[i].viewName === name) return surfaces[i]
    for (var j = 0; j < addonSurfaces.count; j++) {
      var surface = addonSurfaces.itemAt(j)
      if (surface && surface.viewName === name) return surface
    }
    return null
  }

  // Building a view is cheap and the open animation hides it: measured on this
  // machine (min of 5, main-thread CPU) a first open that has to build its view
  // beats the same open a second later by only 10-20ms, while the open itself
  // costs 70-130ms of animation. So views are made at their first open and
  // kept, and this idle pass only gets ahead of the views that open within a
  // keystroke of the island appearing — one per tick, so no frame pays for two.
  // Building all twenty of them up front instead cost roughly 150MB of resident
  // memory (650MB idle against 500MB) and a second of CPU right after launch,
  // for a saving nobody could see.
  readonly property var hot: ["controls", "apps", "player", "clipboard", "menu"]
  property bool prewarmDone: false
  function prewarmStep() {
    if (host.view !== "rest") return true  // Island busy: wait, still pending.
    for (var i = 0; i < hot.length; i++) {
      var surface = surfaceFor(hot[i])
      if (surface && !surface.built) { surface.built = true; return true }
    }
    return false
  }
  Timer {
    id: prewarm
    interval: 150
    running: !views.prewarmDone
    repeat: true
    onTriggered: views.prewarmDone = !views.prewarmStep()
  }

  Surface {
    id: controlsSurface
    host: views.host
    viewName: "controls"
    fixedWidth: 540
    maxHeight: 780
    Loader {
      anchors.fill: parent
      active: controlsSurface.buildNow
      sourceComponent: Component {
        ControlCenter { host: views.host; active: controlsSurface.active; anchors.fill: parent }
      }
    }
  }

  Surface {
    id: wifiSurface
    host: views.host
    viewName: "wifi"
    fixedWidth: 480
    Loader {
      anchors.fill: parent
      active: wifiSurface.buildNow
      sourceComponent: Component {
        WifiView { host: views.host; active: wifiSurface.active; anchors.fill: parent }
      }
    }
  }

  Surface {
    id: bluetoothSurface
    host: views.host
    viewName: "bluetooth"
    fixedWidth: 480
    Loader {
      anchors.fill: parent
      active: bluetoothSurface.buildNow
      sourceComponent: Component {
        BluetoothView { host: views.host; active: bluetoothSurface.active; anchors.fill: parent }
      }
    }
  }

  Surface {
    id: themesSurface
    host: views.host
    viewName: "themes"
    fixedWidth: 820
    padding: 20
    Loader {
      anchors.fill: parent
      active: themesSurface.buildNow
      sourceComponent: Component {
        ThemeSwitcher { host: views.host; active: themesSurface.active; anchors.fill: parent }
      }
    }
  }

  Surface {
    id: wallpapersSurface
    host: views.host
    viewName: "wallpapers"
    fixedWidth: 820
    padding: 20
    Loader {
      anchors.fill: parent
      active: wallpapersSurface.buildNow
      sourceComponent: Component {
        WallpaperSwitcher { host: views.host; active: wallpapersSurface.active; anchors.fill: parent }
      }
    }
  }

  Surface {
    id: appsSurface
    host: views.host
    viewName: "apps"
    fixedWidth: 600
    Loader {
      anchors.fill: parent
      active: appsSurface.buildNow
      sourceComponent: Component {
        AppLauncher { host: views.host; active: appsSurface.active; anchors.fill: parent }
      }
    }
  }

  Surface {
    id: emojiSurface
    host: views.host
    viewName: "emoji"
    fixedWidth: 600
    Loader {
      anchors.fill: parent
      active: emojiSurface.buildNow
      sourceComponent: Component {
        EmojiPicker { host: views.host; active: emojiSurface.active; anchors.fill: parent }
      }
    }
  }

  Surface {
    id: keybindsSurface
    host: views.host
    viewName: "keybinds"
    fixedWidth: 700
    Loader {
      anchors.fill: parent
      active: keybindsSurface.buildNow
      sourceComponent: Component {
        KeybindList { host: views.host; active: keybindsSurface.active; anchors.fill: parent }
      }
    }
  }

  Surface {
    id: clipboardSurface
    host: views.host
    viewName: "clipboard"
    fixedWidth: 780
    Loader {
      anchors.fill: parent
      active: clipboardSurface.buildNow
      sourceComponent: Component {
        ClipboardList { host: views.host; active: clipboardSurface.active; anchors.fill: parent }
      }
    }
  }

  Surface {
    id: menuSurface
    host: views.host
    viewName: "menu"
    fixedWidth: 520
    Loader {
      anchors.fill: parent
      active: menuSurface.buildNow
      sourceComponent: Component {
        OmarchyMenu { host: views.host; active: menuSurface.active; anchors.fill: parent }
      }
    }
  }

  Surface {
    id: playerSurface
    host: views.host
    viewName: "player"
    fixedWidth: 440
    padding: 24
    Loader {
      anchors.fill: parent
      active: playerSurface.buildNow
      sourceComponent: Component {
        PlayerView { host: views.host; active: playerSurface.active; anchors.fill: parent }
      }
    }
  }

  Surface {
    id: settingsSurface
    host: views.host
    viewName: "settings"
    fixedWidth: 760
    padding: 16
    Loader {
      anchors.fill: parent
      active: settingsSurface.buildNow
      sourceComponent: Component {
        SettingsView { host: views.host; active: settingsSurface.active; anchors.fill: parent }
      }
    }
  }

  Surface {
    id: powerSurface
    host: views.host
    viewName: "power"
    padding: 18
    // Eager, unlike the rest: with no fixedWidth the island sizes this one to
    // its content, so the content has to exist before the first open measures.
    PowerMenu { host: views.host; active: powerSurface.active; anchors.fill: parent }
  }

  Repeater {
    id: addonSurfaces
    model: views.host.addons.views
    delegate: Surface {
      id: addonSurface
      required property var modelData
      // Its item's own size, if it has one, over its entry's.
      readonly property var own: view && view.item
      host: views.host
      viewName: modelData.name
      fixedWidth: own && own.surfaceWidth !== undefined ? own.surfaceWidth : modelData.width || 0
      padding: own && own.surfacePadding !== undefined ? own.surfacePadding
        : modelData.padding === undefined ? 16 : modelData.padding
      cornerRadius: own && own.surfaceRadius !== undefined ? own.surfaceRadius : (modelData.radius || 0)
      Loader {
        anchors.fill: parent
        active: addonSurface.buildNow
        sourceComponent: modelData.component
      }
    }
  }
}
