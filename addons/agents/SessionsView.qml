import QtQuick
import "../../components"

// Agent 会话看板: every coding-agent session herdr is watching, the ones
// waiting for a person first. Typing filters, Enter jumps to that pane in herdr
// (`herdr agent focus`), R shows the tail of its terminal in the side pane, and
// Esc closes. The list itself is `board.js` over `herdr agent list`, held by
// AgentsAddon, so the tile and this view read the same numbers.
ListPicker {
  id: board
  required property var usage
  readonly property var theme: board.host.theme

  placeholder: "搜索会话（名称 / 目录 / 窗格）"
  // 盘上装了新 herdr 而 server 还旧时，插件会静默失灵（事件戳一断，看板就只好靠
  // 定时轮询），所以这句排在最前头。
  hint: [usage.herdrStale, usage.boardSummary]
    .filter(function(part) { return part !== "" })
    .concat("Enter 跳过去 · R 读输出").join(" · ")
  emptyText: usage.herdr === ""
    // Nothing to ask: say what would make this view say something.
    ? "没有 herdr，所以看不到会话。在 herdr 里跑起 agent 再开一次。"
    : usage.boardError !== "" ? usage.boardError
      : usage.boardFetchedAt === 0 ? "正在读取 herdr…"
        : board.query !== "" ? "没有匹配的会话" : "herdr 里没有 agent 会话"
  rowHeight: 46
  visibleRows: 8
  minRows: 3
  fillSelection: true
  // itemsFor() 只过滤、不重算「等你看」，所以搜索时分组标题跟着剩下的
  // 行走，也不会把没显示出来的窗格的记号弄丢。
  items: usage.itemsFor(board.query)

  // The two screens of this addon are two tabs of one thing - "what have my
  // agents spent, and which one wants me back". Ctrl+Tab cycles them.
  tabs: [{ label: "用量", count: String(usage.list.length) },
    { label: "会话", count: String(usage.boardRows.length) }]
  tabIndex: 1
  onTabChosen: function(index) { if (index === 0) board.host.view = "agents" }

  // 分组标题不可选（ListPicker 会跳过 disabled 行），这里再挡一下点击。
  onChosen: function(row) { if (row && row.header !== true) usage.focusRow(row) }
  onKeyFilter: function(event) {
    if (event.key === Qt.Key_R) { usage.readRow(selected); event.accepted = true }
  }

  // The read belongs to one session, so a stale one clears as you move.
  sideWidth: 300
  sideVisible: usage.readFor !== "" && usage.selected !== null && usage.readFor === usage.selected.key
  side: Component {
    Item {
      property var entry: ({})
      Flickable {
        anchors.fill: parent
        anchors.leftMargin: 12
        contentWidth: width
        contentHeight: body.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        Text {
          id: body
          width: parent.width
          text: board.usage.readRunning ? "读取中…" : board.usage.readText
          color: board.theme.muted
          font.family: board.theme.textFontFamily
          font.pixelSize: board.theme.px(11)
          wrapMode: Text.WrapAtWordBoundaryOrAnywhere
          lineHeight: 1.1
        }
      }
    }
  }

  row: Component {
    Item {
      id: row
      property var entry: ({})
      property bool selected: false

      // 分组标题（`items()` 在有两个以上项目时才插进来），不可选、只报个名字。
      readonly property bool isHeader: entry.header === true
      readonly property string ink: selected ? board.theme.contrastOn(board.theme.accent) : board.theme.text
      readonly property string faint: selected
        ? board.theme.withAlpha(board.theme.contrastOn(board.theme.accent), 0.6) : board.theme.muted
      // 「等你处理」比「跑完没看」更该扎眼，两者都比状态本身重要。
      readonly property string attention: String(entry.attention || "")
      readonly property bool urgent: attention === "waiting" || entry.tone === "urgent"
      readonly property bool unseen: attention === "unseen"

      Rectangle {
        id: head
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: 1
        color: board.theme.withAlpha(board.theme.muted, 0.25)
        visible: row.isHeader
      }

      Text {
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 8
        text: String(entry.label || "") + "  ·  " + String(entry.count || 0)
        color: board.theme.muted
        font.family: board.theme.textFontFamily
        font.pixelSize: board.theme.px(11)
        font.weight: Font.DemiBold
        visible: row.isHeader
      }

      Rectangle {
        id: dot
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: 8
        height: 8
        radius: 4
        visible: !row.isHeader
        // 跑完没看的也亮起来，不然一眼扫过去只看得到在跑的。
        color: board.usage.toneColor(row.unseen ? "accent" : String(entry.tone || ""))
      }

      Text {
        id: status
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        visible: !row.isHeader
        // 有记号就说记号（等你 / 等你看），没有才说 herdr 的状态。
        text: String(entry.attentionLabel || entry.statusLabel || "")
        color: row.urgent ? board.theme.urgent : row.unseen ? board.theme.accent : row.faint
        font.family: board.theme.textFontFamily
        font.pixelSize: board.theme.px(12)
        font.weight: Font.DemiBold
      }

      Text {
        id: name
        anchors.left: dot.right
        anchors.leftMargin: 10
        anchors.right: status.left
        anchors.rightMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: -8
        text: String(entry.title || "")
        visible: !row.isHeader
        elide: Text.ElideRight
        color: row.ink
        font.family: board.theme.textFontFamily
        font.pixelSize: board.theme.px(14)
        font.weight: Font.Medium
      }

      // Where it runs, which pane Enter focuses, and herdr's own mark for the
      // pane the user is standing in.
      Text {
        anchors.left: name.left
        anchors.right: status.left
        anchors.rightMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: 10
        visible: !row.isHeader
        text: [String(entry.folder || ""), String(board.usage.branches[String(entry.cwd || "")] || ""),
          String(entry.pane || ""), entry.focused === true ? "当前" : ""]
          .filter(function(part) { return part !== "" }).join("  ·  ")
        elide: Text.ElideMiddle
        color: row.faint
        font.family: board.theme.textFontFamily
        font.pixelSize: board.theme.px(11)
      }
    }
  }
}
