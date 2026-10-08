---
name: work-mode
description: Use when the user wants to switch how much verification Claude does while working, or to run the checks that fast mode skipped — "/work-mode", "/work-mode fast", "/work-mode full", "/work-mode status", "fast mode", "rýchly režim", "zapni fast mode", "staviaj rýchlo bez testov", "vypni testy a review kým staviame", "prepni na full", "spusti odložené kontroly", "teraz otestuj a skontroluj všetko", "dotiahni to", "aký je režim", "run the deferred checks", and the 1.x names "/wame-mode", "/wame-harden", "build mode", "harden". Without an argument it shows the current mode and asks which one to use. fast writes the project's .claude/work-mode.local.md and starts the deferred list .claude/work-mode-deferred.local.md, and in fast mode visual changes are made live in Chrome (the screen first, then a checklist and a stop until the user approves the look, then the rest); full runs every deferred check once (tests, Pint, five-dimension self-check, security and code review, docs, one visual pass), fixes the findings and switches to full; full --no-checks only switches.
argument-hint: "[fast [--keep-security-review] | full [--no-checks] [--no-full-suite] [--no-visual] | status]"
---

# work-mode — fast or full

Two work modes for a project:

| Mode | What Claude does |
|---|---|
| **fast** | Builds fast. No tests (neither writing nor running), no Pint/formatter, no 5-dimension self-check, no framework-version or docs lookups, no browser checks or click-throughs, no review/audit agents — checks are skipped, UI/UX and accessibility are not. **Visual work happens live in Chrome**: the minimum the screen needs to render first, then the visual edits in a Chrome tab the user watches and comments on, then a short checklist and a stop until the user approves the look, then everything else; a task with no visual change skips all of it ([reference/live-visual.md](reference/live-visual.md)). Every touched file or screen is appended to `.claude/work-mode-deferred.local.md`; replies end with `Deferred checks: …`. |
| **full** (default) | Every rule of the WAME agents and skills applies unchanged. `/work-mode full` first runs everything that fast mode deferred, once. |

The mode lives in `.claude/work-mode.local.md` (YAML frontmatter, `mode: fast|full`). The
plugin's `UserPromptSubmit` hook reads it and, in fast mode, reminds Claude on every prompt —
including the live-visual order and the path to its procedure. The WAME agents
(`laravel-agents`, `laravel-nova-agents`) and the `teamwork-task` skill read the same file.
`teamwork-task-test` ≥ 1.5.0 does not: a QA pass always runs full.

The default for projects where nobody chose a mode is the plugin option `default_mode` in
`/config` — now `${user_config.default_mode}` (the first word is the mode; if that reads
literally as a placeholder, the option is not set and the default is `full`). A SessionStart hook writes it into the project
(`source: default`); a mode set here (`source: command`) always wins.

## The script

Every switch goes through the bundled script, run from the project root — it is deterministic,
do not re-implement it by hand:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/work-mode.sh" status
bash "${CLAUDE_PLUGIN_ROOT}/scripts/work-mode.sh" fast [--keep-security-review]
bash "${CLAUDE_PLUGIN_ROOT}/scripts/work-mode.sh" full [--clear-deferred]
```

If `${CLAUDE_PLUGIN_ROOT}` is not expanded, the script is `../../scripts/work-mode.sh` relative
to this skill's base directory ("Base directory for this skill: …").

## 1. Read the argument

- `fast`, `full`, `status` — go to step 3. Extra flags pass through.
- `build` → `fast`, `harden` → `full` (the 1.x names): say once that the mode was renamed, then
  continue with the new name.
- Empty — step 2 (the menu).

## 2. Menu (no argument)

1. Run `status`. It prints the mode, the source, `since`, and `deferred: N entries`.
2. Ask with **AskUserQuestion**, one question, in the user's language. Put the current mode in
   the question ("Teraz: fast, 7 odložených kontrol"). Options, in this order, only those that
   apply:
   - **fast** — build now, check later. Label it as the current mode if it is.
   - **full** — with N > 0: "run the N deferred checks once, then switch to full";
     with N = 0: "every check right away".
   - **full without the checks** — only when N > 0: switch to full, the list stays pending.
   - **Keep as it is** — nothing changes.

   Mark one option "(Recommended)": fast with N > 0 → full; otherwise keep as it is.
3. Continue with step 3 for the chosen option. "Keep as it is" ends the skill.

## 3. Run it

- **status** — relay the output in two or three lines.
- **fast** — run `fast` (with `--keep-security-review` when given).
- **full** with pending entries (N > 0) and without `--no-checks` — read
  [reference/full-pass.md](reference/full-pass.md) and follow it. It runs the checks, fixes the
  findings and ends with `full --clear-deferred` itself.
- **full** with N = 0, or with `--no-checks` — run `full`. The list stays as it is.

## 4. Tell the user (always, in their language)

Relay the script output in two or three lines. Additionally:

- **fast:** say that visual changes will be made live in Chrome — the screen first, then a
  checklist and a stop until the user approves the look, then the rest.
- **fast with the env set:** say plainly that the **automatic security review is now off**
  (the `security-guidance` Stop/SubagentStop hook), that **`/work-mode full` always runs a
  security review**, and that the env change may need a **session restart** to take effect.
- **.gitignore changed:** say which line was appended and that it is theirs to commit.
- **tracked:** say that git tracks the named file, so the ignore rule does not apply to it,
  and that `git rm --cached <path>` untracks it (the file stays on disk) — the user runs it,
  never do it yourself.
- **migrated:** say that the 1.x files `.claude/wame-mode.local.md` /
  `.claude/wame-deferred.local.md` now have the new names. If git tracks or stages the old
  file, tell the user to run `git rm --cached <old path>` — never do it yourself.
- **full without the checks and N > 0:** say the N entries are still pending and
  `/work-mode full` runs them.

Switching alone runs no tests, no Pint and no check — only the full pass in step 3 does.

## Browser rule (both modes)

In fast mode the browser is the canvas for live visual work (chrome-devtools MCP, one foreground
tab), never a verification step. Never install or uninstall Playwright, Puppeteer, Dusk or any
other browser tooling for a single run. Use the chrome-devtools MCP or the runner the project
already has. A missing runner means: ask the user once, then install it permanently (a committed
dev dependency) and leave it there.
