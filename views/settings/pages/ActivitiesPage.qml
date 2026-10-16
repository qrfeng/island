pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import "../controls"

// Settings → Live Activities: checkable static previews of the real pill.
ColumnLayout {
  id: page
  required property var view
  visible: view.currentPage === "Live Activities"
  Layout.fillWidth: true
  spacing: 20

  readonly property var activities: [
    { kind: "media", key: "mediaPill", title: "正在播放", description: "显示曲目详情与专辑封面" },
    { kind: "playback", key: "playbackOsd", title: "播放与暂停", description: "暂停、恢复或切歌时显示曲目" },
    { kind: "workspace", key: "workspaceHud", title: "工作区指示", description: "显示当前所在的工作区" },
    { kind: "downloads", key: "downloads", title: "下载", description: "显示进行中的下载进度" },
    { kind: "updates", key: "systemUpdates", title: "系统更新", description: "显示可用的系统更新" },
    { kind: "bluetooth", key: "bluetoothActivity", title: "蓝牙设备", description: "显示蓝牙连接状态" },
    { kind: "network", key: "networkActivity", title: "网络", description: "显示 Wi-Fi 连接状态" },
    { kind: "battery", key: "batteryActivity", title: "电池", description: "充电与低电量提醒" },
    { kind: "volume", key: "volumeHud", title: "音量", description: "显示当前音量" },
    { kind: "brightness", key: "brightnessHud", title: "亮度", description: "显示当前亮度" },
    { kind: "clipboard", key: "clipboard", title: "剪贴板", description: "预览最近复制的内容" }
  ]

  GridLayout {
    Layout.fillWidth: true
    columns: page.width < 420 ? 1 : 2
    columnSpacing: 16
    rowSpacing: 14
    Repeater {
      model: page.activities
      delegate: ActivityCard {
        required property var modelData
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignTop
        view: page.view
        kind: modelData.kind
        title: modelData.title
        description: modelData.description
        checked: page.view.settings[modelData.key]
        onToggled: function(on) { page.view.settings[modelData.key] = on }
      }
    }
  }
}
