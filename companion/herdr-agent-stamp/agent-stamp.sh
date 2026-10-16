#!/bin/sh
# island 的会话看板戳。herdr 在状态变化时拉起这个脚本，我们只留一个时间戳，
# 让岛立刻去读 `herdr agent list`（真相仍以 CLI 为准，戳只负责"现在值得读一次"）。
# 故意不调用任何 herdr 命令，避免事件回调里再触发事件。
reason="${1:-event}"
dir="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/island-agent-stamp"
file="$dir/changed"
mkdir -p "$dir" 2>/dev/null || exit 0
printf '%s\t%s\t%s\n' "$(date +%s)" "$reason" "${HERDR_EVENT:-}" > "$file.tmp" 2>/dev/null \
  && mv -f "$file.tmp" "$file" 2>/dev/null || exit 0
exit 0
