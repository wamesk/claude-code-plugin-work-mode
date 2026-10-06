#!/usr/bin/env bash
# wame-mode.sh — switch a project between the WAME "build" and "harden" work modes.
#
# Usage (run from anywhere; the project is $CLAUDE_PROJECT_DIR, else the current directory):
#   wame-mode.sh build [--keep-security-review]
#   wame-mode.sh harden [--clear-deferred]
#   wame-mode.sh status
#
# Files it manages (all inside the project):
#   .claude/wame-mode.local.md      YAML frontmatter: mode, since, base_commit, security_review_env
#   .claude/wame-deferred.local.md  list of touched files/screens whose checks were deferred
#   .claude/settings.local.json     env ENABLE_STOP_REVIEW / ENABLE_CODE_SECURITY_REVIEW (build only)
#   .gitignore                      appends the ignore patterns only when they are missing
#
# Prints a short human-readable summary; exits non-zero only on bad usage.

set -euo pipefail

ACTION="${1:-status}"
shift || true

KEEP_SECURITY_REVIEW=0
CLEAR_DEFERRED=0
for arg in "$@"; do
  case "$arg" in
    --keep-security-review) KEEP_SECURITY_REVIEW=1 ;;
    --clear-deferred) CLEAR_DEFERRED=1 ;;
    *) echo "Unknown option: $arg" >&2; exit 64 ;;
  esac
done

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$PWD}"
CLAUDE_DIR="$PROJECT_DIR/.claude"
MODE_FILE="$CLAUDE_DIR/wame-mode.local.md"
DEFERRED_FILE="$CLAUDE_DIR/wame-deferred.local.md"
SETTINGS_FILE="$CLAUDE_DIR/settings.local.json"
ENV_KEYS=(ENABLE_STOP_REVIEW ENABLE_CODE_SECURITY_REVIEW)

# Read one frontmatter value (pure bash) from the mode file; empty when absent.
frontmatter_value() {
  local key="$1" line in_fm=0
  [ -f "$MODE_FILE" ] || return 0
  while IFS= read -r line || [ -n "$line" ]; do
    if [ "$line" = "---" ]; then
      if [ "$in_fm" -eq 0 ]; then in_fm=1; continue; else break; fi
    fi
    if [ "$in_fm" -eq 1 ] && [[ "$line" =~ ^${key}:[[:space:]]*(.*)$ ]]; then
      local value="${BASH_REMATCH[1]}"
      value="${value%\"}"; value="${value#\"}"
      printf '%s' "$value"
      return 0
    fi
  done < "$MODE_FILE"
}

# Count deferred entries (lines starting with "- ").
deferred_count() {
  [ -f "$DEFERRED_FILE" ] || { echo 0; return; }
  grep -c '^- ' "$DEFERRED_FILE" 2>/dev/null || true
}

# Make sure .claude/*.local.md and .claude/settings.local.json are git-ignored.
ensure_gitignored() {
  git -C "$PROJECT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 0
  local added=()
  local pattern probe
  for pair in ".claude/*.local.md|.claude/wame-mode.local.md" ".claude/settings.local.json|.claude/settings.local.json"; do
    pattern="${pair%%|*}"; probe="${pair##*|}"
    if ! git -C "$PROJECT_DIR" check-ignore -q "$probe" 2>/dev/null; then
      if [ -s "$PROJECT_DIR/.gitignore" ] && [ -n "$(tail -c 1 "$PROJECT_DIR/.gitignore")" ]; then
        printf '\n' >> "$PROJECT_DIR/.gitignore"
      fi
      printf '%s\n' "$pattern" >> "$PROJECT_DIR/.gitignore"
      added+=("$pattern")
    fi
  done
  if [ "${#added[@]}" -gt 0 ]; then
    echo "gitignore: appended ${added[*]} to .gitignore (was missing) — commit it when convenient."
  fi
}

# Set (build) or remove (harden) the security-review env keys in settings.local.json.
# Other keys are preserved. Needs python3; without it, prints what to change by hand.
update_settings_env() {
  local op="$1"
  if ! command -v python3 >/dev/null 2>&1; then
    echo "settings: python3 not found — edit $SETTINGS_FILE by hand (env: ${ENV_KEYS[*]} = \"0\" in build, remove in harden)."
    return 0
  fi
  python3 -I - "$SETTINGS_FILE" "$op" "${ENV_KEYS[@]}" <<'PY'
import json, os, sys
path, op, keys = sys.argv[1], sys.argv[2], sys.argv[3:]
data = {}
if os.path.exists(path):
    with open(path, encoding="utf-8") as fh:
        raw = fh.read().strip()
    data = json.loads(raw) if raw else {}
env = data.get("env") or {}
if op == "set":
    for key in keys:
        env[key] = "0"
    data["env"] = env
else:
    for key in keys:
        env.pop(key, None)
    if env:
        data["env"] = env
    else:
        data.pop("env", None)
if op == "unset" and not data and not os.path.exists(path):
    sys.exit(0)
os.makedirs(os.path.dirname(path), exist_ok=True)
with open(path, "w", encoding="utf-8") as fh:
    json.dump(data, fh, indent=2, ensure_ascii=False)
    fh.write("\n")
PY
}

write_mode_file() {
  local mode="$1" since="$2" base="$3" env_state="$4"
  mkdir -p "$CLAUDE_DIR"
  cat > "$MODE_FILE" <<EOF
---
mode: $mode
since: "$since"
base_commit: "$base"
security_review_env: $env_state
---

# WAME work mode

Managed by \`/wame-mode\` and \`/wame-harden\` (plugin \`wame-work-mode\`). Do not commit.

- \`build\` — build fast: no tests, no Pint, no self-check, no docs lookups, no browser,
  no review agents. Touched files/screens go to \`.claude/wame-deferred.local.md\`.
- \`harden\` — the default: every quality rule applies; \`/wame-harden\` runs the deferred checks once.
EOF
}

ensure_deferred_file() {
  [ -f "$DEFERRED_FILE" ] && return 0
  mkdir -p "$CLAUDE_DIR"
  cat > "$DEFERRED_FILE" <<'EOF'
# Deferred checks (build mode)

One line per touched file or screen whose checks were skipped in build mode.
Format: `- <path or screen URL> — <what changed> — skipped: <tests, pint, self-check, browser, …>`
`/wame-harden` reads this list, runs every check once, and then clears it.

EOF
}

case "$ACTION" in
  build)
    since="$(date '+%Y-%m-%dT%H:%M:%S%z')"
    base="$(git -C "$PROJECT_DIR" rev-parse HEAD 2>/dev/null || true)"
    # Keep the original start when re-entering build mode.
    if [ "$(frontmatter_value mode)" = "build" ]; then
      prev_since="$(frontmatter_value since)"; prev_base="$(frontmatter_value base_commit)"
      [ -n "$prev_since" ] && since="$prev_since"
      [ -n "$prev_base" ] && base="$prev_base"
    fi
    env_state="untouched"
    if [ "$KEEP_SECURITY_REVIEW" -eq 0 ]; then
      update_settings_env set
      env_state="disabled"
    elif [ "$(frontmatter_value security_review_env)" = "disabled" ]; then
      update_settings_env unset
    fi
    write_mode_file build "$since" "$base" "$env_state"
    ensure_deferred_file
    ensure_gitignored
    echo "mode: build (since $since, base ${base:-none})"
    if [ "$env_state" = "disabled" ]; then
      echo "security: automatic Stop/SubagentStop security review OFF (ENABLE_STOP_REVIEW=0, ENABLE_CODE_SECURITY_REVIEW=0 in .claude/settings.local.json)."
      echo "security: /wame-harden always runs a security review. Restart the session if the env change does not take effect."
    fi
    echo "deferred: $(deferred_count) entries in .claude/wame-deferred.local.md"
    ;;
  harden)
    if [ "$(frontmatter_value security_review_env)" = "disabled" ]; then
      update_settings_env unset
      echo "security: automatic security review env restored (keys removed from .claude/settings.local.json). Restart the session if it does not take effect."
    fi
    write_mode_file harden "$(date '+%Y-%m-%dT%H:%M:%S%z')" "" "untouched"
    if [ "$CLEAR_DEFERRED" -eq 1 ] && [ -f "$DEFERRED_FILE" ]; then
      rm -f "$DEFERRED_FILE"
      echo "deferred: list cleared"
    else
      echo "deferred: $(deferred_count) entries still pending — run /wame-harden to check them"
    fi
    ensure_gitignored
    echo "mode: harden"
    ;;
  status)
    mode="$(frontmatter_value mode)"
    echo "mode: ${mode:-harden (default, no mode file)}"
    [ -n "$(frontmatter_value since)" ] && echo "since: $(frontmatter_value since)"
    [ -n "$(frontmatter_value base_commit)" ] && echo "base_commit: $(frontmatter_value base_commit)"
    echo "security_review_env: $(frontmatter_value security_review_env || true)"
    echo "deferred: $(deferred_count) entries in .claude/wame-deferred.local.md"
    ;;
  *)
    echo "Usage: wame-mode.sh build [--keep-security-review] | harden [--clear-deferred] | status" >&2
    exit 64
    ;;
esac
