import QtQuick

// Wraps one island view (control center, a switcher, the launcher, …): names
// it, sizes the island around it, and handles showing it. The view inside
// only needs an `active` input and an implicit size.
//
//   Surface {
//     id: emojiSurface
//     host: root; viewName: "emojis"; fixedWidth: 600
//     EmojiPicker { host: emojiSurface.host; active: emojiSurface.active }
//   }
Item {
  id: surface
  required property var host
  // The island view (and IPC route) that shows this surface.
  required property string viewName
  // Island width while open; 0 sizes it to the view's implicit width.
  property int fixedWidth: 0
  // Space between the island's edge and the view, on every side.
  property int padding: 16
  property int maxHeight: 100000
  // The island's corner radius while open; 0 keeps the usual one.
  property int cornerRadius: 0
  // Whether the island takes the keyboard while this is open.
  property bool wantsKeyboard: true
  // Whether this surface's view has been built yet. Views are made on demand —
  // at their first open, or when the idle pass in views/Views.qml gets to them
  // — and then kept, so no open pays for creation twice.
  property bool built: false
  // Read it, don't watch it: the island measures a surface in the same binding
  // pass in which it opens, so pulling the Loader into existence here means the
  // open animation never aims at a surface that has no size yet.
  readonly property bool buildNow: built || active

  default property alias content: holder.data
  readonly property Item view: holder.children.length ? holder.children[0] : null
  readonly property bool active: host.view === viewName
  readonly property bool revealed: active && host.surfaceContentReady


  readonly property real islandWidth: fixedWidth > 0 ? fixedWidth : implicitWidth + 2 * padding
  readonly property real islandHeight: Math.min(implicitHeight + 2 * padding, maxHeight)

  // The island's width animates while it opens and closes. Anchoring left+right
  // here made every surface track that animation frame by frame, and since QML
  // polishes hidden items too, one open re-laid out all thirteen views (what
  // made opening feel heavy). Size to the settled width instead: the island
  // clips the content and the reveal fade covers the difference.
  anchors.left: parent ? parent.left : undefined
  anchors.top: parent ? parent.top : undefined
  anchors.margins: padding
  width: Math.max(0, islandWidth - 2 * padding)
  implicitWidth: view ? view.implicitWidth : 0
  implicitHeight: view ? view.implicitHeight : 0

  // Content fades in once the island has started morphing open.
  visible: active || opacity > 0.01
  enabled: active
  opacity: revealed ? 1 : 0
  Behavior on opacity { MotionAnimation { theme: surface.host.theme; pace: surface.revealed ? "standard" : "exit"; curve: "fade" } }

  // Lets the island know this view exists (for its open/closed logic).
  Component.onCompleted: host.registerSurface(viewName)
  Component.onDestruction: host.unregisterSurface(viewName)

  Item {
    id: holder
    anchors.fill: parent
    // Transform the content without disturbing the panel's measured size.
    transformOrigin: Item.Top
    scale: surface.revealed ? 1 : 0.985
    Behavior on scale { MotionAnimation { theme: surface.host.theme; pace: surface.revealed ? "expressive" : "exit" } }
    transform: Translate {
      y: surface.revealed ? 0 : -6
      Behavior on y { MotionAnimation { theme: surface.host.theme; pace: surface.revealed ? "expressive" : "exit" } }
    }
  }
}
