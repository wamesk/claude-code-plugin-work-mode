#!/usr/bin/env bash
# UserPromptSubmit hook — when the project is in WAME build mode, add a short reminder
# to the prompt's context. Silent (no output) in every other case. Pure bash, no network,
# never blocks the prompt: always exits 0.

cat >/dev/null 2>&1 || true

MODE_FILE="${CLAUDE_PROJECT_DIR:-$PWD}/.claude/wame-mode.local.md"
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

[ "$mode" = "build" ] || exit 0

reminder="WAME BUILD MODE is on for this project (.claude/wame-mode.local.md). Build fast: do NOT write or run tests, do NOT run Pint or other formatters, skip the 5-dimension self-check, skip framework version and docs lookups, no browser or click-through checks, no review or audit agents. Tell subagents in their brief: build mode. Never install or uninstall Playwright, Puppeteer, Dusk or other browser tooling. Append every touched file or screen to .claude/wame-deferred.local.md as one line: - <path or screen> — <what changed> — skipped: <checks>. End with a line Deferred checks: <list>. The user runs /wame-harden once at the end to run everything."

printf '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"%s"}}\n' "$reminder"
exit 0
