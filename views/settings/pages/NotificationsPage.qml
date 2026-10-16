import QtQuick
import QtQuick.Layouts
import "../controls"

// Settings → Notifications: how long banners stay.
ColumnLayout {
  id: page
  required property var view
  visible: view.currentPage === "Notifications"
  Layout.fillWidth: true
  spacing: 20

  SettingsGroup {
    view: page.view
    title: "横幅"
    SettingsRow {
      view: page.view
      label: "横幅时长"
      detail: "通知在胶囊上停留多久"
      last: true
      SettingsPopUp {
        view: page.view
        options: [{ label: "3秒", value: 3 }, { label: "5秒", value: 5 }, { label: "8秒", value: 8 }]
        value: page.view.settings.bannerSeconds
        onPicked: function(v) { page.view.settings.bannerSeconds = v }
      }
    }
  }
}
