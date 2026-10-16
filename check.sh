#!/usr/bin/env bash
# omarchy:summary=Check the island before restarting the shell
# omarchy:args=[file.qml ...] [--log]
#
# Two gates, both cheap, both things that have actually bitten this plugin:
#
#   1. the manifest, with Omarchy's own checker (the shell refuses — silently —
#      anything that fails these rules, so the CLI is the same contract);
#   2. QML syntax. qmllint reports a syntax error as a `[syntax]` *warning*,
#      never as `Error:`, and a single one of those makes the whole plugin
#      fail to load: the shell logs
#      "island option guilhermerisu.island failed to load, falling back to
#      omarchy.bar" and the island disappears from the desktop. So grepping
#      for "^Error" is a false pass — this greps for `[syntax]` too.
#
# With --log it also reads the newest quickshell log for runtime QML errors;
# run that after `omarchy-restart-shell`.
#
# With no file arguments it checks every QML file git tracks.

set -uo pipefail
cd "$(dirname "$0")" || exit 2

fail=0
scan_log=0
files=()
for arg in "$@"; do
  if [ "$arg" = "--log" ]; then scan_log=1; else files+=("$arg"); fi
done

if [ "$scan_log" = 1 ]; then
  log=$(ls -t /run/user/"$(id -u)"/quickshell/by-id/*/log.qslog 2>/dev/null | head -1)
  if [ -z "$log" ]; then
    echo "! no quickshell log found"
  else
    # The log is written with \0 padding and \r, so it has to be cleaned first.
    # KNOWN is the noise this plugin does not cause and cannot fix: the OSD IPC
    # shim references a type only the built-in shell has, and it has logged ever
    # since the island became the bar.
    known='OsdShellIpc.qml'
    hits=$(tr -d '\000' <"$log" | tr '\r' '\n' | grep -aE 'Expected token|is not a type|Type .* unavailable|failed to load|TypeError|ReferenceError' | grep -av "$known" | tail -20 || true)
    if [ -n "$hits" ]; then echo "✗ log: $log"; printf '%s\n' "$hits"; fail=1; else echo "✓ log clean: $log (ignored: $known)"; fi
  fi
  exit $fail
fi

if command -v omarchy-plugin-validate >/dev/null 2>&1; then
  if out=$(omarchy-plugin-validate . 2>&1); then
    echo "✓ manifest"
  else
    echo "✗ manifest"
    printf '%s\n' "$out"
    fail=1
  fi
else
  echo "! omarchy-plugin-validate not found, manifest not checked"
fi

qmllint=/usr/lib/qt6/bin/qmllint
if [ ! -x "$qmllint" ]; then
  echo "! qmllint not found at $qmllint, QML not checked"
  exit $fail
fi

if [ ${#files[@]} -eq 0 ]; then
  while IFS= read -r f; do files+=("$f"); done < <(git ls-files '*.qml' 2>/dev/null)
fi
if [ ${#files[@]} -eq 0 ]; then
  echo "! nothing to check"
  exit $fail
fi

for f in "${files[@]}"; do
  [ -f "$f" ] || { echo "! missing: $f"; fail=1; continue; }
  out=$("$qmllint" -I . "$f" 2>&1 | grep -E '\[syntax\]|^Error' || true)
  if [ -n "$out" ]; then
    echo "✗ $f"
    printf '%s\n' "$out"
    fail=1
  else
    echo "✓ $f"
  fi
done

if [ "$fail" = 0 ]; then echo "ok — safe to omarchy-restart-shell"; fi
exit $fail
