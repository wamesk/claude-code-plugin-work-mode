#!/usr/bin/env bash
# UserPromptSubmit hook — when the project is in fast mode, add a short reminder to the
# prompt's context, including the live-in-Chrome rule for visual work. Silent (no output) in
# every other case. Pure bash, no network, never blocks the prompt: always exits 0.

cat >/dev/null 2>&1 || true

CLAUDE_DIR="${CLAUDE_PROJECT_DIR:-$PWD}/.claude"
MODE_FILE="$CLAUDE_DIR/work-mode.local.md"
# wame-work-mode 1.x wrote .claude/wame-mode.local.md with mode: build.
[ -f "$MODE_FILE" ] || MODE_FILE="$CLAUDE_DIR/wame-mode.local.md"
[ -f "$MODE_FILE" ] || exit 0

mode=""
in_fm=0
while IFS= read -r line || [ -n "$line" ]; do
  if [ "$line" = "---" ]; then
    if [ "$in_fm" -eq 0 ]; then in_fm=1; continue; else break; fi
  fi
  if [ "$in_fm" -eq 1 ] && [[ "$line" =~ ^mode:[[:space:]]*\"?([A-Za-z]+)\"? ]]; then
    mode="${BASH_REMATCH[1]}"
    break
  fi
done < "$MODE_FILE"

case "$mode" in
  fast|build) ;;
  *) exit 0 ;;
esac

# The live-visual procedure ships with the plugin; escape the path for the JSON string.
live_visual="$(cd "$(dirname "$0")/.." 2>/dev/null && pwd)/skills/work-mode/reference/live-visual.md"
live_visual="${live_visual//\\/\\\\}"
live_visual="${live_visual//\"/\\\"}"

reminder="FAST MODE is on for this project (.claude/work-mode.local.md). Build fast: do NOT write or run tests, do NOT run Pint or other formatters, skip the 5-dimension self-check, skip framework version and docs lookups, no browser checks or click-throughs, no review or audit agents. Tell subagents in their brief: fast mode. VISUAL WORK IS LIVE IN CHROME: when the task changes anything on a screen, (1) build only the minimum the screen needs to render, (2) open it in Chrome via the chrome-devtools MCP (one foreground tab, tell the user the URL) and make the visual edits live in the main conversation while the user watches and comments (their comments come first), (3) only then everything else. Procedure: $live_visual (read it once before the first visual edit). Never install or uninstall Playwright, Puppeteer, Dusk or other browser tooling. Append every touched file or screen to .claude/work-mode-deferred.local.md as one line: - <path or screen> — <what changed> — skipped: <checks>. Never stage or commit that file. End with a line Deferred checks: <list>. The user runs /work-mode full once at the end to run everything. /teamwork-task-test ignores fast mode and always runs full."

printf '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"%s"}}\n' "$reminder"
exit 0
