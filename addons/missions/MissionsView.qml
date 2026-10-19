import QtQuick
import "../../components"

// The mission list: one card per durable record, the ones waiting on a person
// already standing out by colour. `board` is the MissionsAddon, which holds the
// document the tile reads too, so a change in `~/.pi/agent/missions/` redraws both.
//
// Rows lead with the project directory on purpose: a mission auto-created from a
// prompt stores `[prompt redacted]` as its title, so the title is not always
// something a person can read - the directory is.
//
// The chips at the bottom of a card start nothing: pi-subagents owns these
// records, so they copy the exact ask (with ids) or jump to the pane that owns
// the mission. The agent is what writes.
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
      readonly property bool gated: (mission.openDecisions || []).length > 0
      readonly property string tone: String(mission.tone || "")
      readonly property color ink: gated || tone === "urgent" ? theme.urgent
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
            // A mission can be waiting on you while its lifecycle status still reads
            // 待启动, which is how the tile and the list used to disagree.
            text: String(card.mission.label || "") + (card.gated && card.mission.status !== "needs_decision"
              ? " · 等你回答" : "")
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

        // What the runs actually cost, newest last: a mission that looks idle at
        // the top has often spent a long stretch getting there.
        Text {
          width: parent.width
          visible: text !== ""
          text: panel.runsText(card.mission)
          color: panel.theme.muted
          font.family: theme.textFontFamily
          font.pixelSize: theme.px(11)
          wrapMode: Text.WrapAtWordBoundaryOrAnywhere
        }

        // The durable state the agents keep for themselves (`mission.state.set`):
        // a few keys as a preview, and how much more sits behind them.
        Text {
          width: parent.width
          visible: text !== ""
          text: panel.stateText(card.mission)
          color: panel.theme.muted
          font.family: theme.textFontFamily
          font.pixelSize: theme.px(11)
          wrapMode: Text.WrapAtWordBoundaryOrAnywhere
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

        Item {
          width: 1
          height: theme.px(5)
          visible: chipModel.count > 0
        }

        // The hand-off. Answering or closing has to be written by the agent, so a
        // chip either carries the ask to the clipboard or takes you to the pane
        // that owns the mission - and the note below says which happened.
        Row {
          visible: chipModel.count > 0
          spacing: theme.px(6)
          Repeater {
            id: chipModel
            model: panel.actions(card.mission)
            Rectangle {
              required property var modelData
              readonly property bool held: chipTouch.pressed
              width: chipLabel.implicitWidth + theme.px(16)
              height: theme.px(21)
              radius: height / 2
              color: theme.withAlpha(card.ink, held ? 0.26 : 0.12)
              border.color: theme.withAlpha(card.ink, 0.4)
              border.width: 1
              Behavior on color { MotionColorAnimation { theme: panel.theme } }

              Text {
                id: chipLabel
                anchors.centerIn: parent
                text: String(modelData.label)
                color: card.ink
                font.family: theme.textFontFamily
                font.pixelSize: theme.px(11)
              }
              HoverHandler { id: chipTouch }
              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: panel.act(String(modelData.key), card.mission)
              }
            }
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
    text: panel.board.hidden > 0
      ? panel.board.hidden + " 条已收口的按设置没列出（设置 → Addons → Mission → 已收口的）。"
      : panel.board.missing
      ? "还没有 mission。在 pi 里用 workflow 委派时带 `mission: {title: …}`，记录就会落到 "
        + panel.board.dir + "。"
      : "这里列的是 pi-subagents 的 durable 记录，现在都是空的。"
    color: panel.theme.muted
    font.family: panel.theme.textFontFamily
    font.pixelSize: panel.theme.px(12)
    wrapMode: Text.WrapAtWordBoundaryOrAnywhere
  }

  // What the addon did with a click, kept for a moment under the cards.
  Text {
    width: panel.width
    visible: panel.board.note !== ""
    text: panel.board.note
    color: panel.theme.accent
    font.family: panel.theme.textFontFamily
    font.pixelSize: panel.theme.px(11)
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

  function runsText(m) {
    var list = m.runList || []
    if (list.length === 0) return ""
    var bits = []
    for (var i = 0; i < list.length; ++i) {
      var run = list[i]
      var name = String(run.agent || "run")
      var status = String(run.status || "")
      var tokens = Number(run.tokens) || 0
      bits.push(name + (status !== "" ? " " + status : "")
        + (tokens > 0 ? " " + ago.tokens(tokens) : ""))
    }
    var more = (Number(m.runs) || 0) - list.length
    return "运行：" + bits.join(" · ") + (more > 0 ? "（共 " + m.runs + " 次）" : "")
  }

  function stateText(m) {
    var state = m.state
    if (!state || !(state.entries || []).length) return ""
    var bits = []
    for (var i = 0; i < state.entries.length; ++i) {
      bits.push(state.entries[i].key + "=" + state.entries[i].value)
    }
    var more = (Number(state.count) || 0) - state.entries.length
    return "durable：" + bits.join(" · ") + (more > 0 ? "（还有 " + more + " 个键）" : "")
  }

  // Which hand-off a card offers: the ask it still needs, and the pane it came from.
  function actions(m) {
    var out = []
    if (m && String(m.id || "") !== "") {
      out.push((m.openDecisionIds || []).length > 0
        ? { key: "answer", label: "复制回答指令" }
        : { key: "close", label: "复制收口指令" })
    }
    if (m && String(m.ownerSessionId || "") !== "") {
      out.push({ key: "jump", label: "跳到会话" })
    }
    return out
  }

  function act(key, m) {
    if (key === "jump") panel.board.jump(m)
    else panel.board.handoff(m)
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
