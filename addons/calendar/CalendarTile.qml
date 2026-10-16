import QtQuick
import "../../views/control-center"

// The control center tile, a CcTile like the others: its badge holds
// today's weekday over the date, as Apple's calendar icon, and a dot in the
// next event's colour; beside it that event and when, relative
// while it's near ("In 25 min · 16:36", "Now · until 17:36"), or the date
// ("October 2") and that there's none left. The badge is lit, as a tile
// switched on, while the event is on or within the reminder's lead time.
// Opens the calendar view. `calendar` is the CalendarAddon.
CcTile {
  id: tile
  required property var calendar
  readonly property var next: calendar.nextToday
  readonly property real now: calendar.host.clockDate.getTime()
  readonly property bool ongoing: !!next && next.start <= now
  readonly property int minutesLeft: next ? Math.max(1, Math.round((next.start - now) / 60000)) : 0
  readonly property bool soon: !!next && (ongoing || next.start - now <= calendar.reminderMs)
  readonly property var weekdays: ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]
  readonly property string weekday: weekdays[calendar.today.getDay()]
  // "10月2日"
  readonly property string dateText: Qt.formatDate(calendar.today, "M月d日")

  anchors.fill: parent
  checked: soon
  title: next ? next.title : dateText
  subtitle: !next ? (calendar.urls.length === 0 ? "未添加日历" : "暂无日程")
    : ongoing ? "进行中 · 至 " + calendar.timeText(next.end)
    : minutesLeft <= 60 ? minutesLeft + "分钟后 · " + calendar.timeText(next.start)
    : calendar.spanText(next)
  onClicked: calendar.host.view = "calendar"

  // Over the badge (44 wide, centred on the capsule's end), left without an
  // icon.
  readonly property real badgeLeft: (height - 44) / 2
  Column {
    x: tile.badgeLeft + (44 - width) / 2
    anchors.verticalCenter: parent.verticalCenter
    anchors.verticalCenterOffset: 1
    spacing: -5
    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      text: tile.weekday
      color: tile.checked ? tile.center.badgeOnInk : tile.center.accent
      font.family: tile.center.host.theme.textFontFamily
      font.pixelSize: tile.center.host.theme.px(8)
      font.weight: Font.Bold
      font.letterSpacing: 0.2
    }
    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      text: tile.calendar.today.getDate()
      color: tile.checked ? tile.center.badgeOnInk : tile.center.text
      font.family: tile.center.host.theme.textFontFamily
      font.pixelSize: tile.center.host.theme.px(19)
      font.weight: Font.Normal
      font.features: { "tnum": 1 }
    }
  }
  // The next event's calendar, on the badge's edge.
  Rectangle {
    visible: !!tile.next
    x: tile.badgeLeft + 44 - width + 1
    y: (tile.height + 44) / 2 - height + 1
    width: 13
    height: 13
    radius: width / 2
    color: tile.color
    Rectangle {
      anchors.centerIn: parent
      width: 9
      height: 9
      radius: width / 2
      color: tile.next ? tile.next.color : "transparent"
    }
  }
}
