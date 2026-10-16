import QtQuick
import Quickshell.Io
import ".."

// 输入法：island 早就知道键盘布局（Hyprland 的 us / mn），却不知道 fcitx5
// 此刻用的是英文还是拼音 —— 而"为什么我打出来还是英文"的答案是后者。
//
// fcitx5 换输入法时什么信号都不发：抓整条会话总线（`dbus-monitor`）在半秒内
// 两次切换里只有你自己那次 `Controller1.Toggle` 的方法调用，`InputContext` 的
// StateChanged 一次都没有。所以这里只能轮询 `fcitx5-remote -n`：实测一次 1.7ms，
// 半秒一次约占 0.3% 单核，换来的是切换后半秒内胶囊自己冒出来。
//
// fcitx5 只给内部名（`rime`、`keyboard-us`），中文界面里没人看得懂，所以标签
// 先查设置里的改名（addon 选项 `labels`），再查内置的一份，最后才原样显示。
Addon {
  id: imAddon
  // 第一次读数只记录，不弹胶囊（和键盘布局那个 addon 一样）。
  property bool known: false
  property string name: ""

  property string remote: ""
  readonly property bool chinese: name !== "" && name.indexOf("keyboard") !== 0
  // 切换时要不要弹胶囊。默认不弹（addon 选项 `popup`）：胶囊长在岛顶部，
  // 而他用快捷键切的是一堆会话里的某一个 —— 位置对不上就只会误导，不如不弹。
  readonly property bool popup: !!addon.option("popup")
  readonly property var overrides: parseLabels(addon.option("labels"))
  readonly property string label: {
    if (name === "") return remote === "" ? "未安装" : "未连接"
    if (overrides[name] !== undefined && overrides[name] !== "") return overrides[name]
    return builtin(name)
  }

  function parseLabels(raw) {
    var map = {}
    String(raw || "").split(/[,;\n]/).forEach(function(pair) {
      var at = pair.indexOf("=")
      if (at <= 0) return
      var key = pair.slice(0, at).trim()
      if (key) map[key] = pair.slice(at + 1).trim()
    })
    return map
  }
  // 内置的一份只覆盖常见输入法：拼音/双拼/五笔/雾凇都算中文，`keyboard-*`
  // 是 fcitx5 的英文直输。剩下的原样显示，交给 `labels` 去改。
  function builtin(name) {
    if (name.indexOf("keyboard") === 0) return "英文"
    var cn = ["rime", "pinyin", "shuangpin", "wanxiang", "table", "wubi", "zhuyin", "cangjie", "quick"]
    for (var i = 0; i < cn.length; i++) if (name.indexOf(cn[i]) === 0) return "中文"
    return name
  }
  function apply(raw) {
    var next = String(raw || "").trim()
    // fcitx5 没答话（没在跑，或正在退出）：保留上一次的读数，别把标签闪成空。
    if (next === "") return
    var changed = imAddon.known && next !== imAddon.name
    imAddon.name = next
    imAddon.known = true
    if (changed && imAddon.popup) imAddon.host.showFeedback("", 1400, "addon:" + imAddon.addon.id)
  }
  // 从岛里点这一下，键盘焦点其实在岛自己身上：视图开着时它是
  // keyboard-interactive 的（实测：视图开着时 `wtype` 的字根本进不了原来那个
  // 窗口，关掉视图才进去）。而 fcitx5 的开关只对"当前焦点那个输入上下文"生效，
  // 所以在岛里直接 `-t` 切的是岛自己那个搜索框，他原来那个应用还是中文 ——
  // 这就是"不管用"。跟剪贴板粘贴一个道理：先把视图关掉把键盘还给应用，等
  // 焦点回去（实测关掉就回去了）再按这一下。
  // fcitx5 only ever switches the *focused* input context, and while a view is
  // open that's the island's own search field — so hand the keyboard back to
  // the app first (see Island.qml withAppFocus).
  function toggle() {
    if (imAddon.remote === "") return
    var run = function() { toggleRun.running = true }
    var host = imAddon.host
    if (host && typeof host.withAppFocus === "function") host.withAppFocus(run)
    else run()
  }

  pill: Component { InputMethodPill { im: imAddon } }
  pillWidth: 232
  function pillClicked() { imAddon.toggle() }

  tiles: [{ key: "inputmethod", title: "输入法", present: imAddon.remote !== "", component: imTile }]
  Component {
    id: imTile
    InputMethodTile { im: imAddon; center: parent.center }
  }

  // 二进制在哪：只问一次。quickshell 的 Qt 里没有 `Qt.file`（实测
  // `TypeError: Cannot call method 'exists' of undefined`），所以上路查 PATH 而
  // 不是把 /usr/bin 写死。没找到就什么都不干：胶囊、磁贴、轮询全部关着。
  Process {
    id: finder
    command: ["sh", "-c", "command -v fcitx5-remote 2>/dev/null || true"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var path = String(text).trim()
        imAddon.remote = path.indexOf("/") === 0 ? path : ""
      }
    }
    Component.onCompleted: running = true
  }
  Process {
    id: toggleRun
    command: imAddon.remote !== "" ? [imAddon.remote, "-t"] : ["true"]
    // 切换的那次读数别等下一个轮询周期：胶囊要跟着这一下动。
    onExited: read.running = true
  }
  Process {
    id: read
    command: imAddon.remote !== "" ? [imAddon.remote, "-n"] : ["true"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: imAddon.apply(text)
    }
  }
  Timer {
    id: poll
    interval: 500
    repeat: true
    running: imAddon.remote !== ""
    triggeredOnStart: true
    onTriggered: if (!read.running) read.running = true
  }
}
