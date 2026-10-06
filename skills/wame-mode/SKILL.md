---
name: wame-mode
description: Use when the user wants to switch how much verification Claude does while working — "/wame-mode build", "/wame-mode harden", "/wame-mode status", "build mode", "režim stavby", "zapni build mode", "prepni do build módu", "staviaj rýchlo bez testov", "vypni testy a review kým staviame", "prepni na harden", "aký je režim". Writes the project's work mode (build | harden) into .claude/wame-mode.local.md, keeps the deferred-checks list in .claude/wame-deferred.local.md, makes sure both are git-ignored, and in build mode switches off the automatic security-review Stop hook via .claude/settings.local.json env (restored in harden). For running the deferred checks use /wame-harden instead.
argument-hint: build [--keep-security-review] | harden | status
allowed-tools: Bash, Read
---

# wame-mode — switch between build and harden

Two work modes for a project:

| Mode | What Claude does |
|---|---|
| **build** | Builds fast. No tests (neither writing nor running), no Pint/formatter, no 5-dimension self-check, no framework-version or docs lookups, no browser or click-through checks, no review/audit agents. Every touched file or screen is appended to `.claude/wame-deferred.local.md`; replies end with `Deferred checks: …`. |
| **harden** (default) | Every rule of the WAME agents and skills applies unchanged. `/wame-harden` runs everything that was deferred, once. |

The mode lives in `.claude/wame-mode.local.md` (YAML frontmatter, `mode: build|harden`). The
plugin's `UserPromptSubmit` hook reads it and, in build mode, reminds Claude on every prompt.
The WAME agents (`laravel-agents`, `laravel-nova-agents`) and the Teamwork skills
(`teamwork-task`, `teamwork-task-test`) read the same file.

## Run

Parse the argument (`build`, `harden`, `status`; empty = `status`) and run the bundled script
from the project root — it is deterministic, do not re-implement it by hand:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/wame-mode.sh" build      # or: harden | status
bash "${CLAUDE_PLUGIN_ROOT}/scripts/wame-mode.sh" build --keep-security-review
```

If `${CLAUDE_PLUGIN_ROOT}` is not expanded, the script is `../../scripts/wame-mode.sh` relative to
this skill's base directory ("Base directory for this skill: …").

What it does:

- **build** — writes `mode: build`, `since`, `base_commit` (HEAD at the start; kept when build
  is re-entered) to `.claude/wame-mode.local.md`; creates `.claude/wame-deferred.local.md` with a
  header if missing; unless `--keep-security-review` is passed, merges
  `"ENABLE_STOP_REVIEW": "0"` and `"ENABLE_CODE_SECURITY_REVIEW": "0"` into the `env` of
  `.claude/settings.local.json` (other keys untouched) and records `security_review_env: disabled`.
- **harden** — writes `mode: harden`; removes the two env keys again, but only when this script
  set them (`security_review_env: disabled`). The deferred list is kept — switching to harden
  without running `/wame-harden` leaves the checks pending.
- **status** — prints mode, since, base commit, env state and the number of deferred entries.
- Every action checks that `.claude/*.local.md` and `.claude/settings.local.json` are git-ignored
  (`git check-ignore`) and appends the missing pattern to the project's `.gitignore` only then.

## Tell the user (always, in their language)

Relay the script output in two or three lines. Additionally:

- **build with the env set:** say plainly that the **automatic security review is now off**
  (the `security-guidance` Stop/SubagentStop hook), that **`/wame-harden` always runs a security
  review**, and that the env change may need a **session restart** to take effect.
- **.gitignore changed:** say which line was appended and that it is theirs to commit.
- **harden with pending entries:** suggest `/wame-harden` (it runs the checks and then switches
  to harden itself).

Do not run tests, Pint or any check as part of this skill — it only switches the mode.

## Browser rule (both modes)

Never install or uninstall Playwright, Puppeteer, Dusk or any other browser tooling for a single
run. Use the chrome-devtools MCP or the runner the project already has. A missing runner means:
ask the user once, then install it permanently (a committed dev dependency) and leave it there.
