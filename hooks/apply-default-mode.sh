#!/usr/bin/env bash
# SessionStart hook — applies the plugin option default_mode (set in /config) to the project:
# a project without a mode file gets fast mode when the default is fast, and a mode file the
# hook wrote earlier (source: default) follows the option when it changes. A mode set by hand
# with /work-mode is never touched. Pure bash, no network, always exits 0.

cat >/dev/null 2>&1 || true

case "${CLAUDE_PLUGIN_OPTION_DEFAULT_MODE:-}" in
  fast|full) ;;
  *) exit 0 ;;
esac

bash "$(dirname "$0")/../scripts/work-mode.sh" apply-default "$CLAUDE_PLUGIN_OPTION_DEFAULT_MODE" 2>/dev/null || true
exit 0
