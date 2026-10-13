import QtQuick
import Quickshell.Io
import ".."

// Ask AI: text typed in the launcher can be sent to Pi (the Ask row, see
// launcherRow), answered Siri-style in the island (see AnswerView) through the
// command-line tool you're signed in to.
//
// A question opens a conversation: under its answer, a field to keep asking,
// and a follow-up goes through the same session, so the tool knows what it
// just answered. Asking from the launcher starts a fresh conversation.
//
// The island makes a copy of the view for every screen, but this root is made
// once while the addon is on, so the conversation, the prompt and the
// command-line run live here: one question is one run, whatever the number of
// screens showing its answer.
Addon {
  id: askAddon
  views: [{ name: "answer", component: answerView }]
  launcherHint: "ask"

  Component {
    id: answerView
    AnswerView { host: askAddon.host; ask: askAddon; active: askAddon.host.view === "answer" }
  }

  // Only Pi. This install has neither Claude Code nor Codex, and offering a
  // tool that isn't installed ends in "command not found" anyway. To bring one
  // back: add it here, add its branch back to runCommand, and put its choice
  // into the Ask With option again (see addons/Addons.qml).
  readonly property var providers: ({
    pi: { name: "Pi", cli: "pi", glyph: "\u03c0", tile: "#3b3a44", ink: "#ffffff" }
  })
  readonly property var provider: providers[addon.option("with")] || providers.pi

  // ---------- reaching the internet ----------

  // Search the web (Settings > Addons > Ask AI): with it on, Pi keeps its own
  // tools off and takes along only the two that look things up, so an answer
  // can read the internet and still can't touch the desktop. Pi's installed
  // packages stay unloaded and the one that provides those tools is named,
  // which keeps a launcher question from reaching any other extension.
  readonly property bool web: addon.option("web") !== false
  readonly property var webTools: ({ web_search: "Searching the web...", fetch_content: "Reading a page...", source_check: "Checking sources..." })
  // What the pill says while it is out fetching.
  property string working: ""

  // ---------- the conversation ----------

  // The turns answered before the one on screen, each { q, a, failed }.
  property var turns: []
  // The turn on screen: its question, and the answer as it streams in.
  property string question: ""
  property string text: ""
  property string error: ""
  property bool busy: false
  // The session these turns run in, which is what lets a follow-up ask about
  // an answer above it: an id of ours, so every turn of one conversation lands
  // in the same session file.
  property string sessionId: ""

  // Pi lists the sessions it's told to reuse among your own work, where a
  // desktop question would turn up in its resume picker; give it a folder of
  // the island's instead.
  readonly property string sessionFolder: host.home + "/.local/state/omarchy/island-ask"

  function newSessionId() {
    var hex = "0123456789abcdef", id = ""
    for (var i = 0; i < 36; i++)
      id += (i === 8 || i === 13 || i === 18 || i === 23) ? "-"
        : (i === 14 ? "4" : hex.charAt(Math.floor(Math.random() * 16)))
    return id
  }

  // The launcher's Ask row and `omarchy-shell ... ask`: always a new
  // conversation.
  function ask(what) { submit(what, true) }
  // AnswerView's field: the same session, so it remembers the answers above.
  // Nothing to continue while a turn is still out: its view of the
  // conversation would be missing the answer being written, so a second
  // question here would be dropped mid-answer.
  function followUp(what) { if (!busy) submit(what, false) }

  function submit(what, fresh) {
    what = String(what || "").trim()
    if (!what) return
    stopRun()
    // Fold the answer that was on screen into the turns above the new one.
    if (question !== "")
      turns = turns.concat([{ q: question, a: error !== "" ? error : text, failed: error !== "" }])
    if (fresh) {
      turns = []
      sessionId = newSessionId()
    }
    question = what
    text = ""
    error = ""
    working = ""
    busy = true
    host.view = "answer"
    runner.command = runCommand(what)
    runner.running = true
  }

  function stopRun() { if (runner.running) runner.running = false }

  // The command line for this turn. Pi streams its events as JSON with
  // `--mode json`; skills, prompt templates, themes, MCP and context files are
  // all off so asking a question stays cheap, and it gets an empty stdin: Pi
  // treats anything piped to it as part of the prompt and waits for the pipe to
  // close, and the Process keeps that pipe open, so without `< /dev/null` the
  // answer never arrives. With Search the web on, its own tools give way to the
  // two that look things up (see `web`).
  function runCommand(what) {
    var toolFlags = web
      ? '-e npm:pi-web-access --no-builtin-tools --tools web_search,fetch_content '
      : '--no-tools '
    return ["sh", "-c",
      'mkdir -p "$1"; exec pi -p --mode json --no-extensions --no-skills --no-prompt-templates '
      + '--no-themes --no-mcp --no-context-files --thinking off ' + toolFlags
      + '--session-dir "$1" --session-id "$2" --system-prompt "$3" "$4" < /dev/null',
      "sh", sessionFolder, sessionId, systemPrompt, what]
  }

  // What the model is told, plus facts about this install so answers about
  // the desktop are concrete instead of guesses: where things are
  // configured, the Omarchy commands for common jobs, and the live list of
  // key bindings (loaded once, like the Keybindings view does).
  readonly property string systemPrompt: "You answer questions typed into the search bar of Omarchy, "
    + "Be brief: give the direct answer first, then at most a few short sentences or a short list. "
    + "Reply in plain text like Siri: no Markdown, no bold, no headings, no code formatting; "
    + "write key combinations as Super+Alt+Space. For questions about this "
    + "desktop, prefer Omarchy's own tools and the facts below. Only name commands, menu entries, or "
    + "key bindings that appear below or that you are sure exist; if you are unsure, say so.\n\n"
    + "Facts about this install:\n"
    + "- Hyprland is configured in Lua in ~/.config/hypr/ (bindings.lua, hyprland.lua, input.lua, "
    + "monitors.lua, looknfeel.lua, autostart.lua). There is no hyprland.conf.\n"
    + "- Omarchy's own settings are in ~/.config/omarchy/.\n"
    + "- The Omarchy menu (Super+Alt+Space) has Style, Setup, Install, Remove, Update, and System sections.\n"
    + "- Theme: Omarchy menu > Style > Theme, or `omarchy-theme-set <name>` (`omarchy-theme-list` lists them).\n"
    + "- Wallpaper: Omarchy menu > Style > Background, `omarchy-theme-bg-next` for the next one, or "
    + "`omarchy-theme-bg-set <file>`. Extra wallpapers go in ~/.config/omarchy/backgrounds/<theme>/.\n"
    + "- Font: Omarchy menu > Style > Font, or `omarchy-font-set <name>`.\n"
    + "- Update everything: `omarchy-update` (Omarchy menu > Update).\n"
    + "- Packages: `omarchy-pkg-install` / `omarchy-pkg-remove`, or the Install and Remove menus. Web apps: `omarchy-webapp-install`.\n"
    + "- Restart the desktop shell: `omarchy-restart-shell`.\n"
    + (bindings ? "\nKey bindings (keys \u2192 action):\n" + bindings : "")
    + (web ? "\nYou can reach the internet with web_search and fetch_content. Use them only when the "
      + "answer needs something current or online; for anything you already know, answer at once "
      + "without them. When you do use them, make one short search query, or fetch one address that "
      + "returns little (a small JSON endpoint beats a web page). Never repeat page source: say the "
      + "answer in your own words, in plain text.\n" : "")

  property string bindings: ""
  Process {
    running: true
    command: ["bash", "-c", 'set -- --print; source "$(command -v omarchy-menu-keybindings)" >/dev/null; output_binding_records | cut -f1']
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: askAddon.bindings = String(text || "").split("\n")
        .map(function(line) { return line.replace(/\s{2,}/g, " ").trim() })
        .filter(function(line) { return line.indexOf("\u2192") > 0 })
        .join("\n")
    }
  }

  // Pi's own JSON events.
  function handle(line) {
    var event
    try { event = JSON.parse(line) } catch (e) { return }
    if (event.type === "tool_execution_start") {
      // Out on the web: say so in the pill, which otherwise looks idle.
      working = String(webTools[String(event.toolName || "")] || "Working...")
    } else if (event.type === "message_update" && event.assistantMessageEvent
        && event.assistantMessageEvent.type === "text_delta") {
      // Assistant text arrives in deltas and opens with a blank line.
      error = ""
      var chunk = String(event.assistantMessageEvent.delta || "")
      if (!text) chunk = chunk.replace(/^\s+/, "")
      text += chunk
    } else if (event.type === "turn_end") {
      // Pi closes a turn every time it stops to call a tool, so that is not
      // the answer arriving; `agent_end` is. (AnswerView counts on `busy` to
      // know when to hand the field back.)
    } else if (event.type === "agent_end" || event.type === "agent_settled") {
      settled()
    } else if (event.type === "error" || event.type === "turn.failed") {
      error = String((event.error && event.error.message) || event.message || "Couldn't get an answer")
      working = ""
      busy = false
    }
  }
  function settled() {
    working = ""
    busy = false
  }

  Process {
    id: runner
    workingDirectory: "/tmp"
    stdout: SplitParser { onRead: function(line) { askAddon.handle(line) } }
    stderr: StdioCollector { id: runnerErr; waitForEnd: true }
    onExited: function(code) {
      if (askAddon.busy && !askAddon.text && !askAddon.error) {
        // Pi says "Warning: No project session found ...; creating a new
        // session" on every first turn, so that is not what went wrong when
        // nothing came back.
        var notes = String(runnerErr.text || "").trim().split("\n")
          .filter(function(line) { return !/^Warning: /.test(line.trim()) })
        askAddon.error = code === 0 || !notes.length ? "No answer came back" : notes[notes.length - 1]
      }
      askAddon.working = ""
      askAddon.busy = false
    }
  }

  // The Ask row: first when the text reads like a question.
  function launcherRow(text) {
    return {
      glyph: provider.glyph, tile: provider.tile, ink: provider.ink,
      label: "Ask " + provider.name, detail: "“" + text + "”",
      first: looksLikeQuestion(text),
      run: function() { askAddon.ask(text) }
    }
  }
  function looksLikeQuestion(text) {
    if (/\?$/.test(text)) return true
    var words = text.split(/\s+/)
    return words.length >= 3
      && /^(who|what|when|where|why|how|which|whose|can|could|should|would|is|are|was|were|do|does|did|will|explain|write|tell|give|summari[sz]e|translate|define|compare|help)$/i.test(words[0])
  }
}
