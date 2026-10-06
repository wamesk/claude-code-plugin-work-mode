# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2026-10-06

Agents spent most of every prompt verifying instead of building: tests, Pint, the
five-point quality self-check, docs lookups, browser checks — and, on top, the
`security-guidance` plugin's Stop/SubagentStop hook ran an LLM security review of
the diff and forced the turn to continue. Some runs also installed and removed
Playwright or Puppeteer on the fly. This plugin splits the work into two modes:
build fast first, then verify everything once at the end.

### Added

- `/wame-mode build|harden|status` (skill `wame-mode`) and `scripts/wame-mode.sh` —
  stores the mode in the project's `.claude/wame-mode.local.md` (YAML frontmatter:
  `mode`, `since`, `base_commit`, `security_review_env`), creates the deferred list
  `.claude/wame-deferred.local.md`, and appends `.claude/*.local.md` /
  `.claude/settings.local.json` to `.gitignore` only when they are not ignored yet.
  In build mode it merges `ENABLE_STOP_REVIEW=0` and `ENABLE_CODE_SECURITY_REVIEW=0`
  into `.claude/settings.local.json` `env` (other keys kept; opt out with
  `--keep-security-review`); harden removes them again, only if build set them.
- `UserPromptSubmit` hook `hooks/build-mode-reminder.sh` — in build mode adds a short
  reminder to every prompt: no tests, no Pint, no self-check, no docs lookups, no
  browser, no review agents, never install/uninstall browser tooling, record touched
  files/screens in the deferred list. Pure bash, no network, silent otherwise.
- `/wame-harden` (skill `wame-harden`) — reads the deferred list and the diff since
  `base_commit`, runs tests (filtered, then the project's full/parallel suite),
  Pint `--dirty`, the five-dimension self-check, a security review
  (`laravel-agents:security-auditor`) and a code review
  (`laravel-agents:code-reviewer-laravel`) in parallel, docs/CLAUDE.md updates and
  one chrome-devtools MCP visual pass if a UI changed; fixes findings while keeping
  the agreed behaviour, look and texts (anything that would change them is reported
  as a question), re-runs the affected tests once, then switches to harden and
  clears the list.
- Browser rule in both skills and the README: never install or uninstall
  Playwright, Puppeteer or Dusk for a single run; use the chrome-devtools MCP or the
  project's own runner; a missing runner is asked for once and installed permanently.
