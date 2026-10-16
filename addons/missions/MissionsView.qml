import QtQuick

// The mission list: one card per durable record, the ones waiting on a person
// already standing out by colour. `board` is the MissionsAddon, which holds the
// document the tile reads too, so a change in `~/.pi/agent/missions/` redraws both.
//
// Rows lead with the project directory on purpose: a mission auto-created from a
// prompt stores `[prompt redacted]` as its title, so the title is not always
// something a person can read - the directory is.
Column {
  id: panel
  required property var host
  required property var board
  required property bool active
  readonly property var theme: panel.host.theme

  spacing: theme.px(9)
  width: panel.parent && panel.parent.width > 0 ? panel.parent.width : 396

  Text {
    width: panel.width
    text: "任务 Mission"
    color: panel.theme.text
    font.family: panel.theme.textFontFamily
    font.pixelSize: panel.theme.px(13)
    font.weight: Font.DemiBold
  }

  Repeater {
    model: panel.board.missions

    Rectangle {
      id: card
      required property var modelData
      readonly property var theme: panel.theme
      readonly property var mission: modelData

      width: panel.width
      radius: theme.px(11)
      color: theme.withAlpha(theme.muted, 0.09)
      height: head.height + body.height + theme.px(18)

      // The status colour is the whole point of the card: an open decision should
      // not look like a mission that is quietly finishing.
      readonly property string tone: String(mission.tone || "")
      readonly property color ink: tone === "urgent" ? theme.urgent
        : tone === "accent" ? theme.accent : theme.muted

      Column {
        id: head
        x: theme.px(13); y: theme.px(11)
        width: card.width - theme.px(26)
        spacing: theme.px(3)

        Row {
          width: parent.width
          spacing: theme.px(8)
          Text {
            width: parent.width - status.width - parent.spacing
            text: String(mission.project || "?")
            color: card.ink
            font.family: theme.textFontFamily
            font.pixelSize: theme.px(12)
            font.weight: Font.DemiBold
            elide: Text.ElideMiddle
          }
          Text {
            id: status
            text: String(card.mission.label || "")
            color: card.ink
            font.family: theme.textFontFamily
            font.pixelSize: theme.px(11)
            font.weight: Font.DemiBold
          }
        }

        Text {
          width: parent.width
          visible: String(card.mission.title || "") !== ""
          text: String(card.mission.title || "")
          color: panel.theme.text
          font.family: theme.textFontFamily
          font.pixelSize: theme.px(12)
          elide: Text.ElideRight
          maximumLineCount: 2
          wrapMode: Text.WrapAtWordBoundaryOrAnywhere
        }
      }

      Column {
        id: body
        x: theme.px(13); y: head.y + head.height + theme.px(5)
        width: card.width - theme.px(26)
        spacing: theme.px(2)

        Text {
          width: parent.width
          text: panel.detail(card.mission)
          color: panel.theme.muted
          font.family: theme.textFontFamily
          font.pixelSize: theme.px(11)
        }

        // An open decision gates the mission, so it is the one line worth reading
        // in full; there is rarely more than one.
        Repeater {
          model: card.mission.openDecisions || []
          Text {
            required property int index
            width: parent.width
            text: "· " + String(modelData)
            color: panel.theme.urgent
            font.family: theme.textFontFamily
            font.pixelSize: theme.px(11)
            wrapMode: Text.WrapAtWordBoundaryOrAnywhere
          }
        }
      }
    }
  }

  Text {
    width: panel.width
    visible: panel.board.loading
    text: "正在读 mission…"
    color: panel.theme.muted
    font.family: panel.theme.textFontFamily
    font.pixelSize: panel.theme.px(12)
  }

  Text {
    width: panel.width
    visible: !panel.board.loading && panel.board.error !== ""
    text: panel.board.error
    color: panel.theme.urgent
    font.family: panel.theme.textFontFamily
    font.pixelSize: panel.theme.px(12)
    wrapMode: Text.WrapAtWordBoundaryOrAnywhere
  }

  // The empty state says what would fill it, since an empty store is normal on a
  // machine that has never delegated durable work.
  Text {
    width: panel.width
    visible: !panel.board.loading && panel.board.error === ""
      && panel.board.missions.length === 0
    text: panel.board.missing
      ? "还没有 mission。在 pi 里用 workflow 委派时带 `mission: {title: …}`，记录就会落到 "
        + panel.board.dir + "。"
      : "这里列的是 pi-subagents 的 durable 记录，现在都是空的。"
    color: panel.theme.muted
    font.family: panel.theme.textFontFamily
    font.pixelSize: panel.theme.px(12)
    wrapMode: Text.WrapAtWordBoundaryOrAnywhere
  }

  function detail(m) {
    var bits = []
    var runs = Number(m.runs) || 0
    if (runs > 0) bits.push(runs + " 次运行")
    var kids = Number(m.children) || 0
    if (kids > 0) bits.push(kids + " 个子任务")
    var tokens = Number(m.tokens) || 0
    if (tokens > 0) bits.push(ago.tokens(tokens) + " tokens")
    var when = ago.since(String(m.updatedAt || ""))
    if (when !== "") bits.push(when)
    if (m.stale === true) bits.push("记录已清")
    return bits.join(" · ")
  }

  // Age and token formatting, shared by the rows.
  QtObject {
    id: ago
    function since(iso) {
      if (iso === "") return ""
      var then = Date.parse(iso)
      if (isNaN(then)) return ""
      var mins = Math.floor((Date.now() - then) / 60000)
      if (mins < 1) return "刚刚"
      if (mins < 60) return mins + " 分钟前"
      var hours = Math.floor(mins / 60)
      if (hours < 24) return hours + " 小时前"
      var days = Math.floor(hours / 24)
      if (days < 30) return days + " 天前"
      return iso.substring(0, 10)
    }
    function tokens(n) {
      n = Number(n) || 0
      if (n >= 1e6) return (n / 1e6).toFixed(n >= 1e7 ? 0 : 1) + "M"
      if (n >= 1e3) return (n / 1e3).toFixed(n >= 1e4 ? 0 : 1) + "K"
      return String(Math.round(n))
    }
  }
}
