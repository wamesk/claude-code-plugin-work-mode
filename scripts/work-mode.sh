#!/usr/bin/env bash
# work-mode.sh — switch a project between the "fast" and "full" work modes.
#
# Usage (run from anywhere; the project is $CLAUDE_PROJECT_DIR, else the current directory):
#   work-mode.sh fast [--keep-security-review]
#   work-mode.sh full [--clear-deferred]
#   work-mode.sh status
#   work-mode.sh apply-default <fast|full>   (SessionStart hook: the /config default_mode option)
#
# Files it manages (all inside the project):
#   .claude/work-mode.local.md           YAML frontmatter: mode, source, since, base_commit, security_review_env
#   .claude/work-mode-deferred.local.md  list of touched files/screens whose checks were deferred
#   .claude/settings.local.json          env ENABLE_STOP_REVIEW / ENABLE_CODE_SECURITY_REVIEW (fast only)
#   .gitignore                           appends the ignore patterns only when they are missing
#
# Legacy files of wame-work-mode 1.x (.claude/wame-mode.local.md, .claude/wame-deferred.local.md)
# are moved to the new names on every switch; their modes map build → fast, harden → full.
#
# Prints a short human-readable summary; exits non-zero only on bad usage.

set -euo pipefail

ACTION="${1:-status}"
shift || true

KEEP_SECURITY_REVIEW=0
CLEAR_DEFERRED=0
DEFAULT_MODE=""
for arg in "$@"; do
  case "$arg" in
    --keep-security-review) KEEP_SECURITY_REVIEW=1 ;;
    --clear-deferred) CLEAR_DEFERRED=1 ;;
    fast|full) DEFAULT_MODE="$arg" ;;
    *) echo "Unknown option: $arg" >&2; exit 64 ;;
  esac
done

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$PWD}"
CLAUDE_DIR="$PROJECT_DIR/.claude"
MODE_FILE="$CLAUDE_DIR/work-mode.local.md"
DEFERRED_FILE="$CLAUDE_DIR/work-mode-deferred.local.md"
LEGACY_MODE_FILE="$CLAUDE_DIR/wame-mode.local.md"
LEGACY_DEFERRED_FILE="$CLAUDE_DIR/wame-deferred.local.md"
SETTINGS_FILE="$CLAUDE_DIR/settings.local.json"
ENV_KEYS=(ENABLE_STOP_REVIEW ENABLE_CODE_SECURITY_REVIEW)

# Refuse to write through a symlink: a planted link in .claude/ (or .gitignore) must not
# redirect our writes to a file outside the project.
refuse_symlink() {
  local target
  for target in "$@"; do
    if [ -L "$target" ]; then
      echo "Refusing to write: $target is a symlink. Remove it and run the command again." >&2
      exit 73
    fi
  done
}

# Read one frontmatter value (pure bash); empty when the file or the key is absent.
frontmatter_value_in() {
  local file="$1" key="$2" line in_fm=0 value
  [ -f "$file" ] || return 0
  while IFS= read -r line || [ -n "$line" ]; do
    if [ "$line" = "---" ]; then
      if [ "$in_fm" -eq 0 ]; then in_fm=1; continue; else break; fi
    fi
    if [ "$in_fm" -eq 1 ] && [[ "$line" =~ ^${key}:[[:space:]]*(.*)$ ]]; then
      value="${BASH_REMATCH[1]}"
      value="${value%\"}"; value="${value#\"}"
      printf '%s' "$value"
      return 0
    fi
  done < "$file"
}

frontmatter_value() {
  frontmatter_value_in "$MODE_FILE" "$1"
}

# wame-work-mode 1.x called the modes build and harden.
normalize_mode() {
  case "$1" in
    build|fast) echo fast ;;
    harden|full) echo full ;;
    *) echo "" ;;
  esac
}

# Count entries (lines starting with "- ") in a deferred list.
count_entries() {
  [ -f "$1" ] || { echo 0; return; }
  grep -c '^- ' "$1" 2>/dev/null || true
}

deferred_count() {
  count_entries "$DEFERRED_FILE"
}

write_mode_file() {
  local mode="$1" since="$2" base="$3" env_state="$4" source="$5"
  refuse_symlink "$CLAUDE_DIR" "$MODE_FILE"
  mkdir -p "$CLAUDE_DIR"
  cat > "$MODE_FILE" <<EOF
---
mode: $mode
source: $source
since: "$since"
base_commit: "$base"
security_review_env: $env_state
---

# Work mode

Managed by \`/work-mode\` (plugin \`work-mode\`). Do not commit.

- \`fast\` — build fast: no tests, no Pint, no self-check, no docs lookups, no browser,
  no review agents. Touched files/screens go to \`.claude/work-mode-deferred.local.md\`.
- \`full\` — the default: every quality rule applies; \`/work-mode full\` runs the deferred checks once.

\`source: default\` means the SessionStart hook wrote the \`/config\` default; it follows that
option until \`/work-mode\` sets the mode by hand (\`source: command\`).
EOF
}

# Move wame-work-mode 1.x files to the new names. Never overwrites a newer file.
migrate_legacy() {
  local mode
  if [ -f "$LEGACY_MODE_FILE" ]; then
    refuse_symlink "$CLAUDE_DIR" "$LEGACY_MODE_FILE"
    if [ ! -f "$MODE_FILE" ]; then
      mode="$(normalize_mode "$(frontmatter_value_in "$LEGACY_MODE_FILE" mode)")"
      write_mode_file "${mode:-full}" \
        "$(frontmatter_value_in "$LEGACY_MODE_FILE" since)" \
        "$(frontmatter_value_in "$LEGACY_MODE_FILE" base_commit)" \
        "$(frontmatter_value_in "$LEGACY_MODE_FILE" security_review_env || true)" \
        command
    fi
    rm -f "$LEGACY_MODE_FILE"
    echo "migrated: .claude/wame-mode.local.md → .claude/work-mode.local.md"
  fi
  if [ -f "$LEGACY_DEFERRED_FILE" ]; then
    refuse_symlink "$CLAUDE_DIR" "$LEGACY_DEFERRED_FILE" "$DEFERRED_FILE"
    if [ -f "$DEFERRED_FILE" ]; then
      { printf '\n'; cat "$LEGACY_DEFERRED_FILE"; } >> "$DEFERRED_FILE"
      rm -f "$LEGACY_DEFERRED_FILE"
    else
      mv "$LEGACY_DEFERRED_FILE" "$DEFERRED_FILE"
    fi
    echo "migrated: .claude/wame-deferred.local.md → .claude/work-mode-deferred.local.md"
  fi
}

# Make sure .claude/*.local.md and .claude/settings.local.json are git-ignored.
# $1 = "gitignore" (shared, the user commits it) or "exclude" (.git/info/exclude, local only —
# used by the SessionStart hook, which must not leave a visible change in a repository).
#
# check-ignore needs --no-index: without it git calls a tracked file "not ignored" even when a
# rule matches it, and the pattern was appended again on every switch. The literal-line guard
# keeps the append idempotent even when a later "!" rule re-includes the file on purpose.
# A tracked file is only reported — an ignore rule never untracks it, and `git rm --cached`
# is the user's decision. Only the plugin's own files are checked, by fixed name: a file name
# taken from the repository (git ls-files on a glob) could carry shell syntax into the
# suggested command or instructions into Claude's context.
ensure_gitignored() {
  local where="${1:-gitignore}" target pattern probe pair own
  local added=() tracked=()
  git -C "$PROJECT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 0
  if [ "$where" = "exclude" ]; then
    target="$(git -C "$PROJECT_DIR" rev-parse --path-format=absolute --git-path info/exclude 2>/dev/null)" || return 0
  else
    target="$PROJECT_DIR/.gitignore"
  fi
  for pair in ".claude/*.local.md|.claude/work-mode.local.md" ".claude/settings.local.json|.claude/settings.local.json"; do
    pattern="${pair%%|*}"; probe="${pair##*|}"
    if ! git -C "$PROJECT_DIR" check-ignore -q --no-index "$probe" 2>/dev/null \
      && ! { [ -f "$target" ] && grep -qxF -- "$pattern" "$target"; }; then
      refuse_symlink "$target"
      mkdir -p "$(dirname "$target")"
      if [ -s "$target" ] && [ -n "$(tail -c 1 "$target")" ]; then
        printf '\n' >> "$target"
      fi
      printf '%s\n' "$pattern" >> "$target"
      added+=("$pattern")
    fi
  done
  for own in ".claude/work-mode.local.md" ".claude/work-mode-deferred.local.md" ".claude/settings.local.json"; do
    if [ -n "$(git -C "$PROJECT_DIR" ls-files -- ":(literal)$own" 2>/dev/null || true)" ]; then
      tracked+=("$own")
    fi
  done
  if [ "${#tracked[@]}" -gt 0 ]; then
    echo "tracked: ${tracked[*]} committed to git, so the ignore rule does not apply. To untrack (the files stay on disk): git rm --cached ${tracked[*]}"
  fi
  if [ "${#added[@]}" -gt 0 ] && [ "$where" = "gitignore" ]; then
    echo "gitignore: appended ${added[*]} to .gitignore (was missing) — commit it when convenient."
  fi
}

# Set (fast) or remove (full) the security-review env keys in settings.local.json.
# Other keys are preserved. Needs python3; without it, prints what to change by hand.
update_settings_env() {
  local op="$1"
  if ! command -v python3 >/dev/null 2>&1; then
    echo "settings: python3 not found — edit $SETTINGS_FILE by hand (env: ${ENV_KEYS[*]} = \"0\" in fast, remove in full)."
    return 0
  fi
  refuse_symlink "$CLAUDE_DIR" "$SETTINGS_FILE"
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
# Write a temp file and rename it over the target: rename replaces a path, it never follows a link.
tmp = path + ".tmp-" + str(os.getpid())
with open(tmp, "x", encoding="utf-8") as fh:
    json.dump(data, fh, indent=2, ensure_ascii=False)
    fh.write("\n")
os.replace(tmp, path)
PY
}

ensure_deferred_file() {
  refuse_symlink "$CLAUDE_DIR" "$DEFERRED_FILE"
  [ -f "$DEFERRED_FILE" ] && return 0
  mkdir -p "$CLAUDE_DIR"
  cat > "$DEFERRED_FILE" <<'EOF'
# Deferred checks (fast mode)

One line per touched file or screen whose checks were skipped in fast mode.
Format: `- <path or screen URL> — <what changed> — skipped: <tests, pint, self-check, browser, …>`
`/work-mode full` reads this list, runs every check once, and then clears it.

EOF
}

case "$ACTION" in
  fast)
    migrate_legacy
    since="$(date '+%Y-%m-%dT%H:%M:%S%z')"
    base="$(git -C "$PROJECT_DIR" rev-parse HEAD 2>/dev/null || true)"
    # Keep the original start when fast mode is entered again.
    if [ "$(frontmatter_value mode)" = "fast" ]; then
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
    write_mode_file fast "$since" "$base" "$env_state" command
    ensure_deferred_file
    ensure_gitignored gitignore
    echo "mode: fast (since $since, base ${base:-none})"
    if [ "$env_state" = "disabled" ]; then
      echo "security: automatic Stop/SubagentStop security review OFF (ENABLE_STOP_REVIEW=0, ENABLE_CODE_SECURITY_REVIEW=0 in .claude/settings.local.json)."
      echo "security: /work-mode full always runs a security review. Restart the session if the env change does not take effect."
    fi
    echo "deferred: $(deferred_count) entries in .claude/work-mode-deferred.local.md"
    ;;
  full)
    migrate_legacy
    if [ "$(frontmatter_value security_review_env)" = "disabled" ]; then
      update_settings_env unset
      echo "security: automatic security review env restored (keys removed from .claude/settings.local.json). Restart the session if it does not take effect."
    fi
    write_mode_file full "$(date '+%Y-%m-%dT%H:%M:%S%z')" "" "untouched" command
    if [ "$CLEAR_DEFERRED" -eq 1 ] && [ -f "$DEFERRED_FILE" ]; then
      refuse_symlink "$DEFERRED_FILE"
      rm -f "$DEFERRED_FILE"
      echo "deferred: list cleared"
    else
      echo "deferred: $(deferred_count) entries still pending — /work-mode full runs them"
    fi
    ensure_gitignored gitignore
    echo "mode: full"
    ;;
  status)
    # Read-only: never migrates or writes. A legacy file is read as it is.
    file="$MODE_FILE"
    [ -f "$file" ] || file="$LEGACY_MODE_FILE"
    mode="$(normalize_mode "$(frontmatter_value_in "$file" mode)")"
    echo "mode: ${mode:-full (default, no mode file)}"
    if [ "$file" = "$LEGACY_MODE_FILE" ] && [ -f "$file" ]; then
      echo "legacy: .claude/wame-mode.local.md (moved to the new name on the next switch)"
    fi
    for key in source since base_commit security_review_env; do
      value="$(frontmatter_value_in "$file" "$key" || true)"
      [ -n "$value" ] && echo "$key: $value"
    done
    if [ -f "$LEGACY_DEFERRED_FILE" ] && [ ! -f "$DEFERRED_FILE" ]; then
      echo "deferred: $(count_entries "$LEGACY_DEFERRED_FILE") entries in .claude/wame-deferred.local.md (legacy name)"
    else
      echo "deferred: $(deferred_count) entries in .claude/work-mode-deferred.local.md"
    fi
    ;;
  apply-default)
    # Called by the SessionStart hook with the /config option. Silent unless it changes something.
    [ -n "$DEFAULT_MODE" ] || exit 0
    git -C "$PROJECT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0
    migrate_legacy
    current="$(frontmatter_value mode)"
    source="$(frontmatter_value source)"
    if [ -z "$current" ]; then
      # No mode file: full needs none, fast is written so every reader sees it.
      [ "$DEFAULT_MODE" = "fast" ] || exit 0
    elif [ "$source" != "default" ] || [ "$current" = "$DEFAULT_MODE" ]; then
      # Set by hand, or already the default: leave it alone.
      exit 0
    fi
    base=""
    if [ "$DEFAULT_MODE" = "fast" ]; then
      base="$(git -C "$PROJECT_DIR" rev-parse HEAD 2>/dev/null || true)"
    fi
    # The default never touches settings.local.json: the env would only apply after a restart.
    write_mode_file "$DEFAULT_MODE" "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$base" "untouched" default
    if [ "$DEFAULT_MODE" = "fast" ]; then
      ensure_deferred_file
    fi
    ensure_gitignored exclude
    echo "work-mode: this project is now in $DEFAULT_MODE mode (default_mode from /config). Switch with /work-mode."
    ;;
  *)
    echo "Usage: work-mode.sh fast [--keep-security-review] | full [--clear-deferred] | status | apply-default <fast|full>" >&2
    exit 64
    ;;
esac
