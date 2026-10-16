import QtQuick
import QtQuick.Layouts
import "../../components"

// Agent usage: what the coding agents on this machine have spent. One tab per
// agent that has a usage record (Pi and Claude Code, read off their own
// sessions; Codex and Fireworks too with --others), each with its rate limits
// and their reset, today's tokens, prompts, and sessions, the last week a day
// at a time, and the models it went through and what each cost.
//
// Deliberately not here: which endpoint answered and which folder a session ran
// in. A token count is the figure worth a glance, and splitting it by provider
// or by directory turns one number into a table (the records still carry both,
// for Omarchy's own panel; collector.py drops them before this view sees them).
//
// Click a tab or use Left and Right; `r` reads the records again, Esc closes.
// The numbers come from AgentUsage (see AgentsAddon), which reads what
// collector.py prints.
Item {
  id: view
  required property var host
  required property var usage
  property bool active: false

  readonly property var theme: host.theme
  readonly property var agent: usage.current

  implicitHeight: column.implicitHeight
  readonly property int surfaceWidth: 620
  readonly property int surfacePadding: 22
  readonly property int surfaceRadius: 36

  onActiveChanged: {
    if (!active) return
    usage.refresh(false)
    Qt.callLater(function() { view.focusNow() })
  }
  function focusNow() { view.forceActiveFocus() }

  Keys.onEscapePressed: host.view = "rest"
  Keys.onLeftPressed: usage.pick(usage.selected - 1)
  Keys.onRightPressed: usage.pick(usage.selected + 1)
  Keys.onPressed: function(event) {
    if (event.key === Qt.Key_R) { usage.refresh(true); event.accepted = true }
  }

  // ---------- figures ----------

  // 1.5B, 154M, 6.4M, 24K, 534 - enough room for a week of a busy agent.
  function count(n) {
    n = Number(n) || 0
    if (n >= 1e9) return (n / 1e9).toFixed(n >= 1e10 ? 0 : 1) + "B"
    if (n >= 1e6) return (n / 1e6).toFixed(n >= 1e7 ? 0 : 1) + "M"
    if (n >= 1e3) return (n / 1e3).toFixed(n >= 1e4 ? 0 : 1) + "K"
    return String(Math.round(n))
  }
  // Money in yuan: the transcripts carry dollars, collector.py folds them at
  // the rate set in Settings > Addons > Agent usage.
  function cost(n) {
    n = Number(n) || 0
    return n > 0 ? "\u00a5" + n.toFixed(2) : ""
  }
  // A model's split, on its own line: input, output, cache, and what it cost.
  function modelDetail(m) {
    if (!m) return ""
    var parts = ["输入 " + view.count(m.inputTokens), "输出 " + view.count(m.outputTokens)]
    var cache = Number(m.cacheReadTokens) || 0, write = Number(m.cacheWriteTokens) || 0
    if (cache > 0) parts.push("缓存 " + view.count(cache))
    if (write > 0) parts.push("写入 " + view.count(write))
    var spent = view.cost(m.costCny)
    if (spent !== "") parts.push(spent)
    return parts.join("  /  ")
  }

  // "2026-10-13" -> "\u5468\u56db". Built by hand: new Date("2026-10-13") is
  // midnight UTC, which reads as the day before west of Greenwich. Written as
  // escapes so the file stays ASCII.
  readonly property var weekdays: ["\u5468\u65e5", "\u5468\u4e00", "\u5468\u4e8c",
    "\u5468\u4e09", "\u5468\u56db", "\u5468\u4e94", "\u5468\u516d"]
  function dayLabel(iso) {
    var parts = String(iso || "").split("-")
    if (parts.length < 3) return "--"
    return view.weekdays[new Date(Number(parts[0]), Number(parts[1]) - 1, Number(parts[2])).getDay()]
  }
  function todayIso() {
    var now = host.clockDate
    return now.getFullYear() + "-" + (now.getMonth() + 1 < 10 ? "0" : "") + (now.getMonth() + 1)
      + "-" + (now.getDate() < 10 ? "0" : "") + now.getDate()
  }
  // "2026-10-13T04:12:00+00:00" -> "in 2h 5m" / "3h ago".
  function until(iso) {
    var at = new Date(String(iso || "")).getTime()
    if (isNaN(at)) return ""
    var mins = Math.round((at - host.clockDate.getTime()) / 60000)
    if (mins <= 0) return "重置中"
    var hours = Math.floor(mins / 60)
    if (hours >= 24) return Math.round(hours / 24) + "天后重置"
    return hours >= 1 ? hours + "小时" + (mins % 60) + "分后重置" : mins + "分后重置"
  }

  // The week's rows and their widest day, the models' widest model: the bars
  // in a section are compared within it, the way Omarchy's panel scales its
  // weekly chart to its busiest day.
  readonly property var days: {
    var own = view.agent && view.agent.recentDays ? view.agent.recentDays : []
    var today = view.todayIso(), peak = 0, rows = []
    for (var i = 0; i < own.length; i++) {
      var tokens = Number(own[i].tokens) || 0
      peak = Math.max(peak, tokens)
      rows.push({ label: own[i].date === today ? "\u4eca\u5929" : view.dayLabel(own[i].date),
        tokens: tokens, today: own[i].date === today })
    }
    view.peakDay = peak
    return rows
  }
  property int peakDay: 0
  readonly property var models: (view.agent && view.agent.models) ? view.agent.models : []
  readonly property int peakModel: models.length ? (Number(models[0].tokens) || 0) : 0
  readonly property int peakAll: Math.max(peakDay, peakModel)

  ColumnLayout {
    id: column
    anchors.left: parent.left
    anchors.right: parent.right
    spacing: 12

    // ---------- the top line: what this is, and reading it again ----------

    RowLayout {
      Layout.fillWidth: true
      spacing: 10
      Text {
        text: "Agent 用量"
        color: view.theme.muted
        font.family: view.theme.textFontFamily
        font.pixelSize: view.theme.px(12)
        font.weight: Font.DemiBold
        font.letterSpacing: 0.6
        font.capitalization: Font.AllUppercase
      }
      Item { Layout.fillWidth: true }
      Text {
        visible: usage.fetchedAt > 0
        text: usage.loading ? "读取中…"
          : "更新于 " + (usage.list.length ? usage.timeText(usage.list[0].updatedAt) || "--:--" : "--:--")
        color: view.theme.muted
        font.family: view.theme.textFontFamily
        font.pixelSize: view.theme.px(12)
      }
      // The board is the other half of this addon: same subject, other
      // question. (The board carries the matching tab strip back here.)
      Text {
        text: usage.herdr === "" ? "" : "会话 ›"
        color: boardLink.containsMouse ? "#ffffff" : view.theme.muted
        font.family: view.theme.textFontFamily
        font.pixelSize: view.theme.px(12)
        font.weight: Font.DemiBold
        MouseArea {
          id: boardLink
          anchors.fill: parent
          anchors.margins: -6
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: view.host.view = "sessions"
        }
      }
      Text {
        text: usage.loading ? "" : "刷新"
        color: refreshMouse.containsMouse ? "#ffffff" : view.theme.muted
        font.family: view.theme.textFontFamily
        font.pixelSize: view.theme.px(12)
        font.weight: Font.DemiBold
        MouseArea {
          id: refreshMouse
          anchors.fill: parent
          anchors.margins: -6
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: usage.refresh(true)
        }
      }
    }

    // One tab per agent with a record, heaviest first. With a single agent
    // there is nothing to switch, so the row stays out of the way.
    Row {
      Layout.fillWidth: true
      visible: usage.list.length > 1
      spacing: 7
      Repeater {
        model: usage.list
        delegate: Rectangle {
          id: tab
          required property var modelData
          required property int index
          readonly property bool chosen: index === usage.selected
          height: 28
          radius: 14
          width: label.implicitWidth + 24
          color: chosen ? view.theme.accent : Qt.rgba(1, 1, 1, 0.07)
          Behavior on color { MotionColorAnimation { theme: view.theme } }
          Text {
            id: label
            anchors.centerIn: parent
            text: String(modelData.name || modelData.id)
            color: chosen ? view.theme.contrastOn(view.theme.accent) : view.theme.muted
            font.family: view.theme.textFontFamily
            font.pixelSize: view.theme.px(12)
            font.weight: chosen ? Font.DemiBold : Font.Normal
          }
          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: usage.pick(index)
          }
        }
      }
    }

    Text {
      Layout.fillWidth: true
      visible: usage.error !== ""
      text: usage.error
      color: view.theme.urgent
      font.family: view.theme.textFontFamily
      font.pixelSize: view.theme.px(12)
      wrapMode: Text.Wrap
    }

    // Nothing has written a record: say what would.
    Text {
      Layout.fillWidth: true
      visible: !usage.loading && usage.list.length === 0
      text: "还没有用量记录。Pi 和 Claude Code 直接读各自本地的会话记录；"
        + "运行 `omarchy agent usage update` 可以加上 Codex 和 Fireworks。"
      color: view.theme.muted
      font.family: view.theme.textFontFamily
      font.pixelSize: view.theme.px(13)
      wrapMode: Text.Wrap
      lineHeight: 1.15
    }

    // ---------- one agent's figures ----------

    Flickable {
      id: scroller
      visible: view.agent !== null
      Layout.fillWidth: true
      Layout.preferredHeight: Math.min(body.implicitHeight, 700)
      contentHeight: body.implicitHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds

      ColumnLayout {
        id: body
        width: scroller.width
        spacing: 12

        // Limits first: they are the reason to look at the panel at all.
        ColumnLayout {
          Layout.fillWidth: true
          visible: view.agent !== null && view.agent.limits.length > 0
          spacing: 8
          Repeater {
            model: view.agent ? view.agent.limits : []
            delegate: ColumnLayout {
              required property var modelData
              Layout.fillWidth: true
              spacing: 4
              RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Text {
                  Layout.fillWidth: true
                  text: String(modelData.label)
                  elide: Text.ElideRight
                  color: view.theme.text
                  font.family: view.theme.textFontFamily
                  font.pixelSize: view.theme.px(13)
                }
                Text {
                  text: Math.round(Number(modelData.percent) * 100) + "% 已用"
                  color: view.theme.text
                  font.family: view.theme.textFontFamily
                  font.pixelSize: view.theme.px(13)
                }
                Text {
                  visible: view.until(modelData.resetsAt) !== ""
                  text: view.until(modelData.resetsAt)
                  color: view.theme.muted
                  font.family: view.theme.textFontFamily
                  font.pixelSize: view.theme.px(12)
                }
              }
              Meter {
                Layout.fillWidth: true
                fraction: Number(modelData.percent) || 0
                fill: Number(modelData.percent) >= 0.9 ? view.theme.urgent : view.theme.accent
              }
            }
          }
        }

        // Signed in but no limits, or not signed in at all.
        Text {
          Layout.fillWidth: true
          visible: view.agent !== null && view.agent.usageStatusText !== ""
          text: view.agent ? (view.agent.usageStatusText + (view.agent.authHelpText ? " - " + view.agent.authHelpText : "")) : ""
          color: view.theme.muted
          font.family: view.theme.textFontFamily
          font.pixelSize: view.theme.px(12)
          wrapMode: Text.Wrap
          lineHeight: 1.15
        }

        // Today.
        RowLayout {
          Layout.fillWidth: true
          visible: view.agent !== null
          spacing: 16
          Stat {
            value: view.count(view.agent ? view.agent.todayTotalTokens : 0)
            caption: "今日 tokens"
          }
          Stat {
            value: String(Number(view.agent ? view.agent.todayPrompts : 0) || 0)
            caption: "今日提问"
          }
          Stat {
            value: String(Number(view.agent ? view.agent.todaySessions : 0) || 0)
            caption: "今日会话"
          }
          Stat {
            visible: view.cost(view.agent ? view.agent.todayCostCny : 0) !== ""
            value: view.cost(view.agent ? view.agent.todayCostCny : 0)
            caption: "今日花费"
          }
          Item { Layout.fillWidth: true }
        }

        // The week, a day per row, today held out in full colour.
        ColumnLayout {
          Layout.fillWidth: true
          visible: view.days.length > 0
          spacing: 6
          Caption { text: "最近7天" }
          Repeater {
            model: view.days
            delegate: RowLayout {
              required property var modelData
              Layout.fillWidth: true
              spacing: 10
              Text {
                Layout.preferredWidth: 46
                text: modelData.label
                color: modelData.today ? "#ffffff" : view.theme.muted
                font.family: view.theme.textFontFamily
                font.pixelSize: view.theme.px(12)
                font.weight: modelData.today ? Font.DemiBold : Font.Normal
              }
              Meter {
                fraction: view.peakDay > 0 ? (Number(modelData.tokens) || 0) / view.peakDay : 0
                fill: modelData.today ? view.theme.accent : Qt.rgba(1, 1, 1, 0.45)
                dim: !modelData.today
              }
              Text {
                Layout.preferredWidth: 58
                horizontalAlignment: Text.AlignRight
                text: view.count(modelData.tokens)
                color: modelData.today ? "#ffffff" : view.theme.muted
                font.family: view.theme.textFontFamily
                font.pixelSize: view.theme.px(12)
                font.weight: modelData.today ? Font.DemiBold : Font.Normal
              }
            }
          }
        }

        // The models behind the record, each row scaled to the heaviest.
        ColumnLayout {
          Layout.fillWidth: true
          visible: view.models.length > 0
          spacing: 8
          Caption { text: "模型用量" }
          Repeater {
            model: view.models
            delegate: ColumnLayout {
              required property var modelData
              Layout.fillWidth: true
              spacing: 4
              // The model and what it spent, then the split underneath: the
              // "in / out / cache" line is long, and beside the figure it ran
              // into both the name and the total.
              RowLayout {
                Layout.fillWidth: true
                spacing: 10
                Text {
                  Layout.fillWidth: true
                  text: String(modelData.name)
                  elide: Text.ElideMiddle
                  color: view.theme.text
                  font.family: view.theme.textFontFamily
                  font.pixelSize: view.theme.px(13)
                }
                Text {
                  Layout.preferredWidth: 58
                  horizontalAlignment: Text.AlignRight
                  text: view.count(modelData.tokens)
                  color: view.theme.text
                  font.family: view.theme.textFontFamily
                  font.pixelSize: view.theme.px(13)
                }
              }
              Meter {
                fraction: view.peakModel > 0 ? (Number(modelData.tokens) || 0) / view.peakModel : 0
                fill: view.theme.accent
              }
              Text {
                Layout.fillWidth: true
                text: view.modelDetail(modelData)
                visible: text !== ""
                color: view.theme.muted
                font.family: view.theme.textFontFamily
                font.pixelSize: view.theme.px(11)
              }
            }
          }
        }
      }
    }
    // All time: model totals cover everything, not just the week.
    RowLayout {
      Layout.fillWidth: true
      visible: view.agent !== null
      spacing: 6
      Text {
        text: "全部 " + view.count(view.agent ? view.agent.allTimeTokens : 0) + " tokens"
          + " / " + String(Number(view.agent ? view.agent.totalSessions : 0) || 0) + "次会话"
          + " / " + String(Number(view.agent ? view.agent.activeDays : 0) || 0) + "天活跃"
          + (view.cost(view.agent ? view.agent.totalCostCny : 0) !== ""
             ? " / " + view.cost(view.agent ? view.agent.totalCostCny : 0) : "")
        color: view.theme.muted
        font.family: view.theme.textFontFamily
        font.pixelSize: view.theme.px(11)
      }
      Item { Layout.fillWidth: true }
    }
  }

  // A bar, scaled to whatever its section's heaviest row is.
  component Meter: Rectangle {
    id: meter
    property real fraction: 0
    property color fill: "#ffffff"
    property bool dim: false
    Layout.fillWidth: true
    Layout.preferredHeight: 5
    radius: 2.5
    color: Qt.rgba(1, 1, 1, 0.07)
    Rectangle {
      anchors.left: parent.left
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      width: Math.min(parent.width, Math.max(meter.radius * 2,
        parent.width * Math.min(1, Math.max(0, meter.fraction))))
      radius: parent.radius
      color: meter.fill
      opacity: meter.dim ? 0.6 : 1
      Behavior on width { MotionAnimation { theme: view.theme; pace: "expressive" } }
    }
  }

  // A big figure over what it counts.
  component Stat: ColumnLayout {
    id: stat
    property string value: ""
    property string caption: ""
    Layout.fillWidth: true
    spacing: 1
    Text {
      text: stat.value
      color: "#ffffff"
      font.family: view.theme.textFontFamily
      font.pixelSize: view.theme.px(20)
      font.weight: Font.DemiBold
      font.letterSpacing: -0.3
    }
    Text {
      text: stat.caption
      color: view.theme.muted
      font.family: view.theme.textFontFamily
      font.pixelSize: view.theme.px(11)
    }
  }

  // A small label over a section.
  component Caption: Text {
    id: caption
    color: view.theme.muted
    font.family: view.theme.textFontFamily
    font.pixelSize: view.theme.px(11)
    font.weight: Font.DemiBold
    font.letterSpacing: 0.5
    font.capitalization: Font.AllUppercase
  }
}
