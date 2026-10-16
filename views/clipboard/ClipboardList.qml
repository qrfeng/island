import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import "../../components"
// Omarchy's own history helpers, so search and previews match its picker.
import "file:///usr/share/omarchy/shell/plugins/clipboard/ClipboardHistory.js" as ClipboardHistory

// Clipboard history: the shared list view over the history Omarchy's
// clipboard plugin keeps (it stays in charge of capturing copies; this only
// reads and acts on them). Enter pastes into the app you were using,
// Shift+Enter copies without pasting, Alt+Enter opens the entry, Ctrl+Enter
// 置顶它，Delete 删掉它（置顶的先取消置顶）— the same keys and
// commands as Omarchy's picker, plus pinning. On top of that: Ctrl+Space 勾选
// 一行、Ctrl+A 全选、Ctrl+D 删掉勾掉的（没勾选时等价于 Delete）、Ctrl+Shift+D
// 清空历史（连按两次确认，置顶项保留）。
//
// 多选用的是每条内容自己的稳定键（和置顶、删除同一套），所以勾选状态不受
// 搜索、翻页和历史变动影响。
ListPicker {
  id: clipboard
  placeholder: "搜索剪贴板"
  // 一行的提示，按当前状态说当下能按的键（全写一行放不下）。
  hint: confirmClear ? "再按一次 Ctrl+Shift+D 真的清空（置顶保留）" :
        markedCount ? "已选 " + markedCount + " 条 · Ctrl+D 删除 · Ctrl+A 全选/取消 · Esc 取消勾选" :
        "Enter 粘贴 · Ctrl+Enter 置顶 · Delete 删除 · Ctrl+Space 多选"
  emptyText: query !== "" ? "无匹配内容" : "剪贴板历史为空"
  rowHeight: 44
  visibleRows: 9
  // Room for the image preview even when only a few entries match.
  minRows: 5
  fillSelection: true
  items: rows
  onChosen: function(entry) { paste(entry, false) }
  onKeyFilter: function(event) {
    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      if (event.modifiers & Qt.ControlModifier) { togglePin(selected); event.accepted = true }
      else if (event.modifiers & Qt.AltModifier) { open(selected); event.accepted = true }
      else if (event.modifiers & Qt.ShiftModifier) { paste(selected, true); event.accepted = true }
    } else if (event.key === Qt.Key_Delete && !(event.modifiers & Qt.ControlModifier)) {
      remove(selected); event.accepted = true
    } else if (event.key === Qt.Key_Space && (event.modifiers & Qt.ControlModifier)) {
      toggleMark(selected); event.accepted = true
    } else if (event.key === Qt.Key_A && (event.modifiers & Qt.ControlModifier)) {
      markAll(); event.accepted = true
    } else if (event.key === Qt.Key_D && (event.modifiers & Qt.ControlModifier)) {
      // Ctrl+Shift+D 清空全部，Ctrl+D 删勾选的那几条。
      if (event.modifiers & Qt.ShiftModifier) clearAll(); else removeMarked()
      event.accepted = true
    } else if (event.key === Qt.Key_Escape && markedCount > 0) {
      // 勾了东西时 Esc 先收回勾选，别一下把整个视图关掉。
      marked = ({})
      event.accepted = true
    }
  }

  readonly property string omarchyPath: Quickshell.env("OMARCHY_PATH") || "/usr/share/omarchy"
  property var history: []
  // 置顶。内容自己存一份（不放 island.json：写那个文件会让 quickshell 整个
  // 重启），而且粘的是文本本身而不是历史下标，所以就算上游把历史裁短、
  // 裁掉了那一条，置顶项也还在列表顶上。
  property var pins: []
  FileView {
    id: pinFile
    path: clipboard.host.home + "/.local/state/omarchy/clipboard-pins.json"
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: clipboard.pinsLoaded(text())
    onLoadFailed: clipboard.pins = []
    onFileChanged: reload()
  }
  function pinsLoaded(raw) { pins = ClipboardHistory.parseHistory(raw) }
  function keyOf(entry) { return ClipboardHistory.entryKey(entry) }
  readonly property var pinKeys: {
    var set = {}
    for (var i = 0; i < pins.length; i++) set[keyOf(pins[i])] = true
    return set
  }
  function togglePin(row) {
    if (!row) return
    var entry = row.pinned ? pins[row.pinIndex] : history[row.index]
    if (!entry) return
    var key = keyOf(entry)
    var rest = pins.filter(function(pinned) { return keyOf(pinned) !== key })
    var next = row.pinned ? rest : [entry].concat(rest)
    pins = next
    pinFile.setText(JSON.stringify(next, null, 2) + "\n")
  }
  // 多选：记的是每条内容自己的稳定键，所以搜索、置顶、历史变动都不会让勾选跑位。
  property var marked: ({})
  readonly property int markedCount: {
    var n = 0
    for (var i = 0; i < rows.length; i++) if (marked[String(rows[i].key)] === true) n++
    return n
  }
  // 行对象 -> 它对应的原始内容（置顶行来自 pins，普通行来自 history）。
  function entryOf(row) { return row ? (row.pinned ? pins[row.pinIndex] : history[row.index]) : null }
  function rowKey(row) { var entry = entryOf(row); return entry ? keyOf(entry) : "" }
  function toggleMark(row) {
    var key = rowKey(row)
    if (!key) return
    var next = {}
    for (var k in marked) next[k] = marked[k]
    if (next[key] === true) delete next[key]
    else next[key] = true
    marked = next
  }
  // 全选只作用于当前列表（搜索时就是筛选结果）；已经全选了就是取消。
  function markAll() {
    if (rows.length && markedCount >= rows.length) { marked = ({}); return }
    var next = {}
    for (var k in marked) next[k] = marked[k]
    for (var i = 0; i < rows.length; i++) { var key = String(rows[i].key); if (key) next[key] = true }
    marked = next
  }

  // 置顶的那条在历史里的位置；-1 = 已被裁掉，那就只能把文本直接递给命令。
  function historyIndexOf(entry) {
    var key = keyOf(entry)
    for (var i = 0; i < history.length; i++) if (keyOf(history[i]) === key) return i
    return -1
  }
  // 密钥类内容不列出来（胶囊那边也不弹）。认格式的规则住在监听那里。
  function isSecret(entry) { return host.clipboard.isSecret(entry) }
  // 置顶项在最前，然后是其余历史（已经被置顶的那条不重复列）。
  readonly property var rows: {
    var out = []
    for (var i = 0; i < pins.length && out.length < 50; i++) {
      var top = ClipboardHistory.displayRows([pins[i]], query, 1)
      if (!top.length) continue
      top[0].pinned = true
      top[0].key = keyOf(pins[i])
      top[0].pinIndex = i
      top[0].index = historyIndexOf(pins[i])
      out.push(top[0])
    }
    var hidden = pinKeys
    var rest = ClipboardHistory.displayRows(history, query, 50)
    for (var j = 0; j < rest.length && out.length < 50; j++) {
      var entry = history[rest[j].index]
      if (entry && hidden[keyOf(entry)] === true) continue
      rest[j].key = entry ? keyOf(entry) : ""
      out.push(rest[j])
    }
    return out
  }
  // A delete re-reads the file first and drops the entry by its stable key, so
  // a copy that landed since the last watch still survives the write.
  property var pendingRemoveKeys: []
  // 清空：整个历史写空。置顶项是用户自己挑的，这里不动。
  property bool pendingClear: false
  FileView {
    id: historyFile
    path: clipboard.host.home + "/.local/state/omarchy/clipboard-history.json"
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: clipboard.historyLoaded(text())
    onLoadFailed: { clipboard.pendingRemoveKeys = []; clipboard.pendingClear = false; clipboard.history = [] }
    onFileChanged: reload()
  }
  function historyLoaded(raw) {
    // 密钥不列出来。抹掉文件里那一条不归这里：剪贴板监听一直在跑，它已经处
    // 理过了（这里再写一次只会两个写入方互相追），这里只负责不再显示。
    var fresh = ClipboardHistory.parseHistory(raw).filter(function(entry) { return !clipboard.isSecret(entry) })
    if (pendingClear) {
      pendingClear = false
      history = []
      historyFile.setText("[]\n")
      return
    }
    if (pendingRemoveKeys.length) {
      var drop = {}
      for (var i = 0; i < pendingRemoveKeys.length; i++) drop[String(pendingRemoveKeys[i])] = true
      pendingRemoveKeys = []
      var next = fresh.filter(function(entry) { return drop[String(ClipboardHistory.entryKey(entry))] !== true })
      history = next
      if (next.length !== fresh.length) historyFile.setText(JSON.stringify(next, null, 2) + "\n")
      return
    }
    history = fresh
  }

  // Close first so the keyboard goes back to the previous app, then let
  // Omarchy's commands paste (or just copy) the entry by its history index.
  Process { id: runner }
  function run(argv) {
    // Pasting copies the entry again; that's not news for the Copied pill.
    host.clipboard.quietUntil = Date.now() + 2500
    // Close first so the keyboard goes back to the previous app, then let
    // Omarchy's commands paste (or just copy) the entry by its history index.
    host.withAppFocus(function() {
      runner.command = ["bash", "-c", 'exec "$@"', "--"].concat(argv)
      runner.startDetached()
    })
  }
  function paste(row, copyOnly) {
    if (!row) return
    var bin = omarchyPath + "/bin/"
    if (row.entryType === "image")
      run([bin + "omarchy-clipboard-paste-file"].concat(copyOnly ? ["--copy-only"] : []).concat([row.mime, row.path]))
    else if (row.index >= 0 && row.fullText)
      run([bin + "omarchy-clipboard-paste-text", copyOnly ? "--copy-only" : "--shift-insert", "--history-index", String(row.index)])
    else if (row.fullText)
      // 置顶但已被历史裁掉：同一个命令也接受把文本直接递给它。
      run([bin + "omarchy-clipboard-paste-text", copyOnly ? "--copy-only" : "--shift-insert", row.fullText])
  }
  function open(row) {
    if (!row || row.index < 0) return
    run([omarchyPath + "/bin/omarchy-clipboard-open", "--history-index", String(row.index)])
  }
  // Writing the shared history file; Omarchy's plugin reloads it too. A
  // pinned row's Delete 先取消置顶：一个键只管一件事。
  function remove(row) {
    if (!row) return
    if (row.pinned) { togglePin(row); return }
    var entry = history[row.index]
    if (!entry) return
    pendingRemoveKeys = [ClipboardHistory.entryKey(entry)]
    historyFile.reload(true)
  }
  // Ctrl+D：删掉勾掉的。置顶行走取消置顶，历史行走一次批量删除（一次读一次
  // 写，不会和剪贴板监听抢着改文件）。一个都没勾就退回删当前行。
  function removeMarked() {
    var keys = []
    var unpins = []
    for (var i = 0; i < rows.length; i++) {
      var key = String(rows[i].key)
      if (!key || marked[key] !== true) continue
      if (rows[i].pinned) unpins.push(key); else keys.push(key)
    }
    if (!keys.length && !unpins.length) { remove(selected); return }
    marked = ({})
    if (unpins.length) {
      var rest = pins.filter(function(pinned) { return unpins.indexOf(String(keyOf(pinned))) === -1 })
      pins = rest
      pinFile.setText(JSON.stringify(rest, null, 2) + "\n")
    }
    if (keys.length) {
      // 删除会顺手再复制一次吗？不会，但保险起见把胶囊压住。
      host.clipboard.quietUntil = Date.now() + 1500
      pendingRemoveKeys = keys
      historyFile.reload(true)
    }
  }
  // Ctrl+Shift+D：清空历史。这一下太狠，所以第一次只 arm，四秒内再按一次才动手。
  property bool confirmClear: false
  Timer {
    id: clearGrace
    interval: 4000
    onTriggered: clipboard.confirmClear = false
  }
  function clearAll() {
    if (!confirmClear) {
      confirmClear = true
      clearGrace.restart()
      return
    }
    confirmClear = false
    clearGrace.stop()
    marked = ({})
    host.clipboard.quietUntil = Date.now() + 2500
    pendingClear = true
    historyFile.reload(true)
  }

  // Preview pane: the selected picture, rounded, at its own proportions.
  sideWidth: 280
  // Only pictures get the pane; text rows already show their content.
  sideVisible: !!(selected && selected.previewImage)
  side: Component {
    Item {
      id: preview
      property var entry: ({})
      readonly property bool isImage: !!entry.previewImage
      readonly property string body: String(entry.fullText || entry.previewText || "").trim()

      Item {
        id: content
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom

        // The picture, fitted to the pane at its own aspect ratio with
        // rounded corners.
        ClippingRectangle {
          readonly property real ratio: previewImage.implicitHeight > 0 ? previewImage.implicitWidth / previewImage.implicitHeight : 1
          anchors.centerIn: parent
          width: Math.min(parent.width, parent.height * ratio)
          height: width / ratio
          radius: 14
          color: "transparent"
          visible: preview.isImage && previewImage.status === Image.Ready
          Image {
            id: previewImage
            anchors.fill: parent
            source: preview.isImage ? "file://" + preview.entry.previewImage : ""
            sourceSize.width: 640
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            smooth: true
          }
        }
        Text {
          anchors.centerIn: parent
          visible: preview.isImage && previewImage.status === Image.Error
          text: "图片不可用"
          color: clipboard.host.theme.muted
          font.family: clipboard.host.theme.textFontFamily
          font.pixelSize: clipboard.host.theme.px(12)
        }
        Text {
          anchors.fill: parent
          visible: !preview.isImage
          text: preview.body
          textFormat: Text.PlainText
          wrapMode: Text.Wrap
          elide: Text.ElideRight
          clip: true
          color: clipboard.host.theme.text
          font.family: clipboard.host.theme.textFontFamily
          font.pixelSize: clipboard.host.theme.px(15)
          lineHeight: 1.3
        }
      }
    }
  }

  row: Component {
    Item {
      id: clipRow
      property var entry: ({})
      property bool selected: false
      readonly property bool hasPreview: !!entry.previewImage
      readonly property bool marked: clipboard.marked[String(entry.key)] === true
      readonly property color ink: selected ? clipboard.host.theme.accentText : clipboard.host.theme.text

      // Image thumbnail, or a plain glyph for text / file entries.
      Item {
        id: badge
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: 28; height: 28
        ClippingRectangle {
          anchors.fill: parent
          radius: 6
          color: "transparent"
          visible: clipRow.hasPreview && thumb.status === Image.Ready
          Image {
            id: thumb
            anchors.fill: parent
            source: clipRow.hasPreview ? "file://" + clipRow.entry.previewImage : ""
            sourceSize.width: 56
            sourceSize.height: 56
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
          }
        }
        Text {
          anchors.centerIn: parent
          visible: !(clipRow.hasPreview && thumb.status === Image.Ready)
          text: clipRow.entry.entryType === "image" ? "󰋩" : clipRow.entry.entryType === "file" ? "󰈔" : "󰆒"
          color: clipRow.selected ? clipRow.ink : clipboard.host.theme.muted
          font.family: clipboard.host.theme.fontFamily
          font.pixelSize: clipboard.host.theme.px(18)
        }
      }
      // 右侧的标记：置顶、已勾选。都不可见时这个 Row 宽度是 0，正文照样占满。
      Row {
        id: pinMark
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: 8
        visible: clipRow.entry.pinned === true || clipRow.marked
        Text {
          visible: clipRow.marked
          text: "已选"
          textFormat: Text.PlainText
          color: clipRow.selected ? clipRow.ink : clipboard.host.theme.urgent
          font.family: clipboard.host.theme.textFontFamily
          font.pixelSize: clipboard.host.theme.px(11)
        }
        Text {
          visible: clipRow.entry.pinned === true
          // 不押一个没把握的置顶字形：图标字体里能确定一定在的只有 ASCII，
          // 而“置顶”两个字本来就比一个小符号好懂。
          text: "置顶"
          textFormat: Text.PlainText
          color: clipRow.selected ? clipRow.ink : clipboard.host.theme.accent
          font.family: clipboard.host.theme.textFontFamily
          font.pixelSize: clipboard.host.theme.px(11)
        }
      }
      Text {
        anchors.left: badge.right
        anchors.leftMargin: 12
        anchors.right: pinMark.left
        anchors.rightMargin: pinMark.visible ? 8 : 0
        anchors.verticalCenter: parent.verticalCenter
        text: String(clipRow.entry.previewText || "").trim()
        textFormat: Text.PlainText
        elide: Text.ElideRight
        maximumLineCount: 1
        color: clipRow.ink
        font.family: clipboard.host.theme.textFontFamily
        font.pixelSize: clipboard.host.theme.px(14)
        font.weight: clipRow.selected ? Font.Medium : Font.Normal
      }
    }
  }
}
