# work-mode

Build fast, verify once — two work modes for Claude Code, by [WAME](https://wame.sk).
Part of the `wame` marketplace.

## Why

On almost every prompt the agents used to verify instead of build: tests, Pint, the
five-point quality self-check, docs lookups, browser checks, plus the `security-guidance`
plugin's Stop hook running an LLM security review and forcing the turn to continue.
This plugin splits the work:

| Mode | What Claude does |
|------|------------------|
| **fast** | Builds. No tests (writing or running), no Pint, no self-check, no framework/docs lookups, no browser checks, no review agents. Visual changes are made live in Chrome. Every touched file/screen is appended to `.claude/work-mode-deferred.local.md`; replies end with `Deferred checks: …`. |
| **full** (default) | All rules of the WAME agents and skills apply unchanged. |

At the end, `/work-mode full` runs everything that was skipped — once — and switches to full.

### Visual work live in Chrome (fast mode)

When a task changes something on a screen, fast mode works in this order:

1. **The minimum the screen needs to render** — route, controller or component skeleton, view,
   data to show. Nothing else yet.
2. **The visual edits, live** — the screen opens in a Chrome tab via the chrome-devtools MCP
   (Vite dev server started in the background when the project uses it, so every edit shows up
   through HMR). You watch the tab and comment in the chat; a comment on the look is applied
   before anything else.
3. **Everything else** — logic, validation, policies, persistence, menu entries, other languages.

The live part runs in the main conversation, never in a subagent. Every change goes into the
source files. The tab uses the MCP's own Chrome profile — when the screen needs a login, you log
in there once. Without the chrome-devtools MCP, Claude gives you the URL to open yourself.
The procedure is in [`skills/work-mode/reference/live-visual.md`](skills/work-mode/reference/live-visual.md).
What you approve on screen is the agreed look that `/work-mode full` keeps.

## Installation

```
/plugin marketplace add wamesk/claude-code
/plugin install work-mode@wame
```

## Usage

```
/work-mode                    # shows the mode and offers the choices
/work-mode fast               # start building fast
/work-mode full               # run the deferred checks once, fix, switch to full
/work-mode full --no-checks   # switch to full without the checks (the list stays pending)
/work-mode status             # mode, source, since, base commit, deferred entries
```

`/work-mode fast --keep-security-review` keeps the automatic security review on.
`/work-mode full --no-full-suite` / `--no-visual` skip the full test suite / the browser pass.
Plain sentences work too: "zapni fast mode", "spusti odložené kontroly", "aký je režim".

### Default mode in `/config`

The plugin option **`default_mode`** (`full` or `fast`, default `full`) is asked for when the
plugin is enabled and shows up as a row in `/config` (Claude Code ≥ 2.1.269). The picker
shows each choice with a short explanation next to it, because `/config` has no separate
description per choice. It applies to every project where nobody chose a mode:

- A SessionStart hook writes it into the project's `.claude/work-mode.local.md` with
  `source: default`, so every plugin that reads the mode sees it.
- When you change the option, those projects follow it at the next session start.
- A mode set with `/work-mode` (`source: command`) is never overwritten by the default.
- The hook only acts inside a git repository. It ignores its files through
  `.git/info/exclude`, so it never leaves a visible change in a repository. It does not touch
  the security-review env — only `/work-mode fast` does.

### What `/work-mode full` runs, in order

1. Tests for the touched areas — written where missing, run filtered first, then the
   project's full (parallel) suite command from its `CLAUDE.md`, once.
2. Formatter — `vendor/bin/pint --dirty --format agent`.
3. Five-dimension self-check — `ui_ux`, `performance`, `security`, `reachability`, `framework`.
4. Security review (`laravel-agents:security-auditor`) and code review
   (`laravel-agents:code-reviewer-laravel`) in parallel, when installed. A security review
   always runs.
5. Docs — module `CLAUDE.md`, project docs, translations.
6. One visual pass via the chrome-devtools MCP, only if a UI changed.

Findings are fixed while keeping the agreed behaviour, look and texts; anything that would
change them is reported as a question instead.

## Files in the project

| File | Purpose |
|------|---------|
| `.claude/work-mode.local.md` | YAML frontmatter `mode: fast\|full`, `source: command\|default`, `since`, `base_commit`, `security_review_env`. |
| `.claude/work-mode-deferred.local.md` | One line per touched file/screen whose checks were deferred. |
| `.claude/settings.local.json` | In fast mode `env.ENABLE_STOP_REVIEW` and `env.ENABLE_CODE_SECURITY_REVIEW` = `"0"`. |

`.claude/*.local.md` and `.claude/settings.local.json` are appended to `.gitignore` only when
they are not ignored yet — you are told when that happens. If git already tracks one of the
three files in the table above, an ignore rule does not apply to it: the switch says so
(`tracked: …`) and names the `git rm --cached <path>` that untracks it. The plugin never runs
it for you, and never names other tracked files.

**Security note:** in fast mode the `security-guidance` plugin's automatic Stop/SubagentStop
review is switched off through those env keys (it may need a session restart to take effect).
`/work-mode full` always runs a security review and removes the keys again.

## Who reads the mode

- `UserPromptSubmit` hook of this plugin — fast-mode reminder on every prompt (pure bash,
  no network, silent in full mode).
- `laravel-agents` ≥ 1.3.0 and `laravel-nova-agents` ≥ 1.3.0 — skip tests, Pint, lookups,
  self-check and browser work in fast mode and end with `Deferred checks: …`.
- `teamwork-task` ≥ 1.7.0 — `--mode=fast|full` and the project's mode file map onto its
  existing switches.
- `teamwork-task-test` ≥ 1.5.0 does **not** read the mode: a QA pass always runs full, in a
  fast-mode project too (1.3.0–1.4.0 followed it).

A brief that says "fast mode" / "rýchly režim" switches an agent to fast mode too.

## Upgrading from wame-work-mode 1.x

Version 2.0.0 renames the plugin `wame-work-mode` → `work-mode`, the modes `build` → `fast`
and `harden` → `full`, and the commands `/wame-mode` + `/wame-harden` → `/work-mode`.

1. `/plugin uninstall wame-work-mode@wame`, then `/plugin install work-mode@wame`.
2. The first switch moves `.claude/wame-mode.local.md` and `.claude/wame-deferred.local.md`
   to the new names (the deferred entries are kept). Until then every reader still reads the
   old files, and `build` / `harden` are still understood.
3. If git tracks or stages an old file, run `git rm --cached <old path>`.

## Browser rule

In fast mode the browser is the canvas for live visual work, never a verification step.
Never install or uninstall Playwright, Puppeteer, Dusk or any other browser tooling for a
single run. Use the chrome-devtools MCP or the runner the project already has. A missing
runner means: ask once, then install it permanently (a committed dev dependency) and keep it.

## License

MIT — see [LICENSE](LICENSE).
