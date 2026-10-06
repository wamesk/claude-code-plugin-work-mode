# wame-work-mode

Build fast, verify once — two work modes for Claude Code, by [WAME](https://wame.sk).
Part of the `wame` marketplace.

## Why

On almost every prompt the agents used to verify instead of build: tests, Pint, the
five-point quality self-check, docs lookups, browser checks, plus the `security-guidance`
plugin's Stop hook running an LLM security review and forcing the turn to continue.
This plugin splits the work:

| Mode | What Claude does |
|------|------------------|
| **build** | Builds. No tests (writing or running), no Pint, no self-check, no framework/docs lookups, no browser, no review agents. Every touched file/screen is appended to `.claude/wame-deferred.local.md`; replies end with `Deferred checks: …`. |
| **harden** (default) | All rules of the WAME agents and skills apply unchanged. |

At the end, `/wame-harden` runs everything that was skipped — once — and switches back to harden.

## Installation

```
/plugin marketplace add wamesk/claude-code
/plugin install wame-work-mode@wame
```

## Usage

```
/wame-mode build          # start building fast
/wame-mode status         # mode, since, base commit, deferred entries
/wame-harden              # run the deferred checks once, fix, back to harden
/wame-mode harden         # switch back without running the checks (list stays pending)
```

`/wame-mode build --keep-security-review` keeps the automatic security review on.
`/wame-harden --no-full-suite` / `--no-visual` skip the full test suite / the browser pass.

### What `/wame-harden` runs, in order

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
| `.claude/wame-mode.local.md` | YAML frontmatter `mode: build\|harden`, `since`, `base_commit`, `security_review_env`. |
| `.claude/wame-deferred.local.md` | One line per touched file/screen whose checks were deferred. |
| `.claude/settings.local.json` | In build mode `env.ENABLE_STOP_REVIEW` and `env.ENABLE_CODE_SECURITY_REVIEW` = `"0"`. |

`.claude/*.local.md` and `.claude/settings.local.json` are appended to `.gitignore` only when
they are not ignored yet — you are told when that happens.

**Security note:** in build mode the `security-guidance` plugin's automatic Stop/SubagentStop
review is switched off through those env keys (it may need a session restart to take effect).
`/wame-harden` always runs a security review, and `/wame-mode harden` / `/wame-harden` remove
the keys again.

## Who reads the mode

- `UserPromptSubmit` hook of this plugin — build-mode reminder on every prompt (pure bash,
  no network, silent in harden mode).
- `laravel-agents` ≥ 1.2.0 and `laravel-nova-agents` ≥ 1.2.0 — skip tests, Pint, lookups,
  self-check and browser work in build mode and end with `Deferred checks: …`.
- `teamwork-task` ≥ 1.6.0 and `teamwork-task-test` ≥ 1.3.0 — `--mode=build|harden` and the
  `mode` config key map onto their existing switches.

A brief that says "build mode" / "režim stavby" switches an agent to build mode too.

## Browser rule

Never install or uninstall Playwright, Puppeteer, Dusk or any other browser tooling for a
single run. Use the chrome-devtools MCP or the runner the project already has. A missing
runner means: ask once, then install it permanently (a committed dev dependency) and keep it.

## License

MIT — see [LICENSE](LICENSE).
