import QtQuick
import QtQuick.Layouts
import "../controls"

// Settings → General: the pill, appearance and motion.
ColumnLayout {
  id: page
  required property var view
  visible: view.currentPage === "General"
  Layout.fillWidth: true
  spacing: 20

  SettingsGroup {
    view: page.view
    title: "胶囊"
    SettingsRow {
      view: page.view
      label: "24小时制"
      SettingsSwitch {
        view: page.view
        checked: page.view.settings.clock24h
        onToggled: function(on) { page.view.settings.clock24h = on }
      }
    }
    SettingsRow {
      view: page.view
      label: "刘海样式"
      detail: "贴住顶部边缘，形似 MacBook 刘海"
      last: true
      SettingsSwitch {
        view: page.view
        checked: page.view.settings.notch
        onToggled: function(on) { page.view.settings.notch = on }
      }
    }
  }

  SettingsGroup {
    view: page.view
    title: "外观"
    SettingsRow {
      view: page.view
      label: "玻璃外壳"
      detail: Math.round(page.view.settings.glassOpacity * 100) + "% 不透明 · 越低越透出模糊桌面"
      last: true
    }
    Item {
      Layout.fillWidth: true
      Layout.preferredHeight: 28
      Layout.leftMargin: 14
      Layout.rightMargin: 14
      Layout.bottomMargin: 12
      SettingsSlider {
        anchors.fill: parent
        view: page.view
        value: page.view.settings.glassOpacity
        onMoved: function (v) { page.view.settings.glassOpacity = v }
      }
    }
    SettingsRow {
      view: page.view
      label: "彩色活动"
      detail: "活动使用自定义颜色"
      SettingsSwitch {
        view: page.view
        checked: page.view.settings.colorfulLiveActivities
        onToggled: function(on) { page.view.settings.colorfulLiveActivities = on }
      }
    }
    SettingsRow {
      view: page.view
      label: "彩色侧栏图标"
      detail: "侧栏使用 macOS 风格配色"
      last: true
      SettingsSwitch {
        view: page.view
        checked: page.view.settings.colorfulSettingsIcons
        onToggled: function(on) { page.view.settings.colorfulSettingsIcons = on }
      }
    }
  }

  SettingsGroup {
    view: page.view
    title: "文字"
    SettingsRow {
      view: page.view
      label: "字体"
      detail: "内置、Omarchy 菜单字体或自选"
      SettingsPopUp {
        view: page.view
        options: [
          { label: "内置默认", value: "island" },
          { label: "Omarchy 默认", value: "omarchy" },
          { label: "自定义", value: "custom" }
        ]
        value: page.view.settings.textFontMode
        onPicked: function(v) { page.view.settings.textFontMode = v }
      }
    }
    SettingsRow {
      view: page.view
      label: "字号"
      last: page.view.settings.textFontMode !== "custom"
      SettingsPopUp {
        view: page.view
        options: [
          { label: "小", value: 0.9 },
          { label: "默认", value: 1 },
          { label: "大", value: 1.15 },
          { label: "特大", value: 1.3 }
        ]
        value: page.view.settings.textScale
        onPicked: function(v) { page.view.settings.textScale = v }
      }
    }
    SettingsRow {
      view: page.view
      label: "自定义字体"
      detail: "搜索已安装的字体"
      visible: page.view.settings.textFontMode === "custom"
      last: true
      SettingsFontPicker {
        view: page.view
        value: page.view.settings.customFont
      }
    }
  }

  SettingsGroup {
    view: page.view
    title: "动效"
    SettingsRow {
      view: page.view
      label: "动画速度"
      detail: "关闭后界面立即开合"
      SettingsPopUp {
        view: page.view
        options: [{ label: "关闭", value: 0 }, { label: "快", value: 1 }, { label: "标准", value: 1.5 }, { label: "舒缓", value: 2 }]
        value: page.view.settings.motionScale
        onPicked: function(v) { page.view.settings.motionScale = v }
      }
    }
    SettingsRow {
      view: page.view
      label: "悬停抬起"
      detail: "指针经过时胶囊轻微浮起"
      last: true
      SettingsSwitch {
        view: page.view
        checked: page.view.settings.hoverLift
        onToggled: function(on) { page.view.settings.hoverLift = on }
      }
    }
  }

  SettingsGroup {
    view: page.view
    title: "更新"
    footer: "shell 启动6小时后，island 会检查 GitHub 并提示一键更新。本地有改动时请保持关闭：这种更新本来也会被拒绝；想手动合并上游时，随时可以用 `omarchy plugin update guilhermerisu.island`"
    SettingsRow {
      view: page.view
      label: "检查更新"
      detail: "在 GitHub 查找新版本并提示安装"
      last: true
      SettingsSwitch {
        view: page.view
        checked: page.view.settings.autoUpdate
        onToggled: function(on) { page.view.settings.autoUpdate = on }
      }
    }
  }
}
