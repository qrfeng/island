import QtQuick
import "../../views/control-center"

// The control center tile for the session board. Its whole job is the one
// question the board answers: is an agent sitting on a prompt waiting for me.
// `usage` is the AgentsAddon.
CcTile {
  id: tile
  required property var usage

  anchors.fill: parent
  // A prompt character: what every one of those sessions is sitting in. The
  // nerd font here has no session glyph whose shape I could confirm, so this
  // stays plain text like the calculator tile's "=".
  icon: ">"
  available: usage.herdr !== ""
  checked: usage.boardWaiting > 0
  title: usage.herdr === "" ? "Agent 会话"
    : usage.boardWaiting > 0 ? String(usage.boardWaiting) + " 个 agent 等你" : "Agent 会话"
  subtitle: usage.herdr === "" ? "未安装 herdr"
    : usage.boardSummary !== "" ? usage.boardSummary : "没有会话"
  onClicked: usage.host.view = "sessions"
}
