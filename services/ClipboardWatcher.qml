import QtQuick
import Quickshell.Io
import "file:///usr/share/omarchy/shell/plugins/clipboard/ClipboardHistory.js" as ClipboardHistory

// Watches Omarchy's clipboard history for something newly copied, for the
// clipboard pill. The entries already there when the island starts aren't
// news. The clipboard view sets `quietUntil` when it pastes, since pasting
// copies the entry again.
Item {
  id: watcher
  required property string home
  required property var settings
  property var last: null
  property double quietUntil: 0
  property string lastKey: ""
  property bool seeded: false
  signal copied()

  // 剪贴板历史是一个明文 JSON 文件，任何进程都能读。上游 capture.sh 已经
  // 跳过应用自己声明敏感的复制（`CLIPBOARD_STATE=sensitive`、KDE 的
  // `x-kde-passwordManagerHint`），但一个只懂“复制”的密码管理器和
  // 你复制一个路径没有区别，所以这里按内容认：私钥、和大厂令牌那几种格式。
  // 故意窄 —— 口令本身看起来就是随机字符，按熵猜会吃掉你正要粘的那条。
  readonly property var secretPatterns: [
    { label: "私钥", re: /-----BEGIN [A-Z ]*PRIVATE KEY-----/ },
    { label: "访问令牌", re: /\b(gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,})\b/ },
    { label: "访问令牌", re: /\bxox[baprs]-[A-Za-z0-9-]{10,}\b/ },
    { label: "访问令牌", re: /\b\d{8,10}:AA[A-Za-z0-9_-]{30,}\b/ },
    { label: "访问令牌", re: /\beyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\b/ },
    { label: "API 密钥", re: /\b(AKIA[0-9A-Z]{16}|AIza[0-9A-Za-z_-]{30,}|[rs]k_live_[A-Za-z0-9]{10,}|npm_[A-Za-z0-9]{30,})\b/ }
  ]
  // 这段文本是哪种密钥，不是就回 ""。只有文本项会暴露自己。
  function secretKind(text) {
    var value = String(text || "")
    if (value === "") return ""
    for (var i = 0; i < secretPatterns.length; i++)
      if (secretPatterns[i].re.test(value)) return secretPatterns[i].label
    return ""
  }

  // 这项是不是密钥。只有文本项会暴露自己。
  function isSecret(entry) {
    return !!entry && entry.type === "text" && secretKind(entry.text) !== ""
  }

  FileView {
    id: historyView
    path: watcher.home + "/.local/state/omarchy/clipboard-history.json"
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: watcher.historyChanged(text())
  }
  function isHtml(text) {
    return /^\s*<(img|meta|html|!doctype|body|div|span|p|a|picture|figure|table)\b/i.test(String(text || ""))
  }
  function historyChanged(raw) {
    var history = ClipboardHistory.parseHistory(raw)
    // 认出来的密钥不从盘上过夜：那文件是谁都能读的明文 JSON。监听一直在跑，
    // 所以不用等你打开剪贴板视图才抹。自己写回自己也要静默一下，不然这次
    // 改写会被当成一次新的复制，弹个胶囊出来。
    var kept = history.filter(function(entry) { return !watcher.isSecret(entry) })
    if (kept.length !== history.length) {
      quietUntil = Math.max(quietUntil, Date.now() + 3000)
      historyView.setText(JSON.stringify(kept, null, 2) + "\n")
      history = kept
    }
    var top = history.length ? history[0] : null
    if (top && top.type === "text" && isHtml(top.text) && history.length > 1 && history[1].type === "image")
      top = history[1]
    var key = top ? ClipboardHistory.entryKey(top) : ""
    var fresh = seeded && key !== "" && key !== lastKey
    lastKey = key
    seeded = true
    // 密钥不弹胶囊：那等于把密钥大字写在屏上。
    if (top && top.type === "text" && watcher.secretKind(top.text) !== "") return
    if (!fresh || !settings.clipboard || Date.now() < quietUntil) return
    last = top
    copied()
  }
}
