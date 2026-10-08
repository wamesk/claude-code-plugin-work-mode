# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.1.0] - 2026-10-08

Fast mode built screens blind: no browser at all until `/work-mode full`, so the user saw the
look only at the end and every visual comment cost another round.

### Added

- **Visual work live in Chrome (fast mode).** When a task changes something on a screen, fast
  mode now works in a fixed order: (1) only the minimum the screen needs to render, (2) the
  visual edits live in a foreground Chrome tab via the chrome-devtools MCP — Vite dev server
  started in the background for HMR, the user watches and comments, comments on the look come
  first — and (3) everything else. The live part runs in the main conversation, every change
  goes into the source files, and a login in the MCP's Chrome profile is left to the user.
  Procedure: `skills/work-mode/reference/live-visual.md`; the fast-mode reminder hook names
  that file and the order on every prompt.
- Screens shaped live are marked `live in Chrome` in the deferred list; the full pass treats
  their look as agreed and checks only the console, reachability, other breakpoints and the
  empty and error states.

### Changed

- **`teamwork-task-test` is no longer a reader of the mode.** From its 1.5.0 a QA pass always
  runs full; the fast-mode reminder says so too, so it does not pull a QA run into fast mode.

## [2.0.2] - 2026-10-07

### Fixed

- **No duplicate `.gitignore` lines for a tracked file.** When git tracked
  `.claude/settings.local.json` (or a `.claude/*.local.md` file), `git check-ignore` reported
  it as not ignored even though `.gitignore` already had the rule, so every switch appended the
  same line again. The check now runs with `--no-index`, and a line that is already in the file
  is never appended twice. The same fix applies to `.git/info/exclude` (SessionStart hook).
- **A tracked file is reported.** The switch prints `tracked: <path> …` with the
  `git rm --cached <path>` that untracks it; an ignore rule alone never does. The plugin does
  not run it — the skill tells the user to. Only the plugin's own files are checked, by fixed
  name (`.claude/work-mode.local.md`, `.claude/work-mode-deferred.local.md`,
  `.claude/settings.local.json`): a file name read from the repository could otherwise put
  shell syntax into the suggested command or instructions into Claude's context.

## [2.0.1] - 2026-10-07

### Changed

- **`/config` picker explains each choice.** The `default_mode` choices now read
  `full — tests, Pint and review on every task` and
  `fast — build now, run the checks once with /work-mode full`, and the field description
  only says what the option is for. A plugin option in `/config` has no description per
  choice, so the explanation is part of the choice. The SessionStart hook takes the first
  word as the mode. A value stored as plain `fast` by 2.0.0 is no longer one of the choices,
  so `/config` treats it as unset (`full`); pick `fast` again if you had chosen it.

## [2.0.0] - 2026-10-07

The names did not say what the modes do. "Harden" named two different things — the
mode where every check runs right away, and the command that runs the checks fast mode
skipped — and fitted neither well. The plugin also had no global default and no menu.

### Changed

- **Renamed** the plugin `wame-work-mode` → `work-mode` (repository
  `claude-code-plugin-work-mode`) and the modes `build` → **`fast`** and `harden` →
  **`full`**.
- **One command.** The skills `wame-mode` and `wame-harden` are merged into `/work-mode`.
  `/work-mode fast|full|status` switches directly; `/work-mode full` runs the pending
  deferred checks once (the former `/wame-harden`, now `reference/full-pass.md`) and then
  switches; `/work-mode full --no-checks` only switches. The merged skill no longer
  pre-approves Bash through `allowed-tools`, because it now also runs the full pass.
- **Files renamed:** `.claude/wame-mode.local.md` → `.claude/work-mode.local.md`,
  `.claude/wame-deferred.local.md` → `.claude/work-mode-deferred.local.md`,
  `scripts/wame-mode.sh` → `scripts/work-mode.sh`, `hooks/build-mode-reminder.sh` →
  `hooks/fast-mode-reminder.sh`. The mode file gains `source: command|default`.

### Added

- **Menu:** `/work-mode` without an argument shows the current mode and the number of
  deferred checks and asks which mode to use (fast, full with the checks, full without
  them, keep as it is).
- **Default in `/config`:** plugin option `default_mode` (`full` | `fast`, default
  `full`). A new SessionStart hook (`hooks/apply-default-mode.sh`, script action
  `apply-default`) writes it into a project that has no mode, with `source: default`, and
  keeps such projects in step when the option changes. A mode set with `/work-mode` is
  never overwritten. The hook only acts in a git repository, ignores its files through
  `.git/info/exclude` (no visible change in the repository) and never touches the
  security-review env.

### Deprecated

- The 1.x names still work in 2.x: `build` / `harden` as arguments, and
  `.claude/wame-mode.local.md` / `.claude/wame-deferred.local.md` are read and moved to the
  new names on the first switch (deferred entries kept; `status` stays read-only). They
  will be removed in 3.0.0.

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
