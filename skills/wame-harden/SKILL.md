---
name: wame-harden
description: Use when the user finishes a build-mode stretch and wants everything that was skipped checked and fixed in one pass — "/wame-harden", "harden", "sprav harden", "dotiahni to", "teraz otestuj a skontroluj všetko", "spusti odložené kontroly", "finish and verify", "run the deferred checks". Reads .claude/wame-deferred.local.md and the diff since build mode started, then runs the deferred checks ONCE in order — tests for the touched areas (filtered, then the project's full/parallel suite), Pint --dirty, the 5-dimension self-check (ui_ux, performance, security, reachability, framework), a security review and a code review (laravel-agents agents when installed), docs/CLAUDE.md updates, one visual pass via the chrome-devtools MCP if a UI changed — fixes the findings while keeping the agreed behaviour, look and texts, then switches the project back to harden mode and clears the deferred list.
argument-hint: "[--no-full-suite] [--no-visual]"
---

# wame-harden — one verification pass at the end

Build mode skipped the checks; this skill runs every one of them **once**, fixes what they find,
and returns the project to harden mode. It is the counterpart of `/wame-mode build`.

**The contract:** what was built and agreed with the user stays — behaviour, look (layout,
colours, components) and user-facing texts. Hardening fixes bugs, missing tests, style, security,
performance, reachability, translations and docs underneath them. When a fix would change
something the user agreed to (a visible text, a flow, a screen's look, an API contract), do not
apply it — list it in the report as a question.

## 0. Scope

1. Read `.claude/wame-mode.local.md` (`mode`, `since`, `base_commit`) and
   `.claude/wame-deferred.local.md` (one line per touched file/screen).
2. Build the change set: `git diff --name-only <base_commit>` (committed since build started) +
   `git status --porcelain` (uncommitted). No `base_commit` → `git log --since="<since>"`. No mode
   file and no list → ask the user what to harden (default: uncommitted changes + the last commit).
3. Read the project's `CLAUDE.md` for the test commands (filtered, full, parallel), the formatter,
   module-specific rules and which docs exist. Read the `CLAUDE.md` of every touched module.
4. Say in two lines what will be checked (files, screens, which steps apply). Do not ask for
   confirmation unless the scope is unclear.

## 1. Tests

- Missing tests for touched behaviour: write them (Pest in Laravel projects — delegate to
  `laravel-agents:pest-tester`, brief it **harden mode**, list the files; Nova screens via
  `laravel-nova-agents` patterns). Cover happy, failure and authorization paths; reachability
  for every new screen.
- Run the **filtered** tests for the touched areas first; fix failures in the code, not by
  weakening assertions. Then run the project's **full suite once** with the command its
  `CLAUDE.md` names (e.g. `php artisan test --parallel --processes=8`); skip with
  `--no-full-suite`. Failures that already existed before `base_commit` are reported, not fixed.

## 2. Formatter

`vendor/bin/pint --dirty --format agent` (or the project's formatter). Never pass explicit paths
that bypass the formatter's exclude list.

## 3. Five-dimension self-check

Walk the change set against the five keys — `ui_ux`, `performance`, `security`, `reachability`,
`framework` — using `laravel-agents:wame-laravel-standards` → `reference/cross-cutting-quality.md`
(and `laravel-nova-agents:wame-nova-patterns` for Nova). Only dimensions whose "applies when"
matches. Framework = idioms of the **installed** versions (composer.lock / package.json), looked
up once via Laravel Boost `search-docs` or context7 — nothing newer than installed, no drive-by
rewrites.

## 4. Security review + code review (in parallel)

When the agents are installed, spawn both in one message, each briefed **harden mode** with the
change set and the expected output (`file:line — severity — finding — fix`, max 20 lines):

- `laravel-agents:security-auditor` — **always run a security review**, even for small diffs:
  build mode may have switched the automatic `security-guidance` review off.
- `laravel-agents:code-reviewer-laravel` — standards, N+1, translations, response format.

Not installed → do the review yourself with `laravel-agents:wame-security-checklist` or the
`security-review` skill. Apply Critical/High fixes; list Medium/Low that change agreed behaviour
as questions.

## 5. Docs

Update what the change made stale: the touched modules' `CLAUDE.md`, project docs referenced from
the root `CLAUDE.md`, README/CHANGELOG where the project keeps them, translation files (keys in
English, values in the project's languages). No new documentation files unless the project
already has that kind of file.

## 6. One visual pass (only if a UI changed)

If the change set touches views, Vue/JS/CSS, Nova resources/fields/actions or `dist/`: open each
touched screen **once** via the chrome-devtools MCP (a background tab, never the user's active
tab), take a snapshot/screenshot, check the console and that the screen is reachable from the
menu. Compare against what was agreed; fix rendering bugs, not design. Rebuild assets the project
commits (e.g. `dist/`) if sources changed. Skip with `--no-visual`.

**Browser rule:** never install or uninstall Playwright, Puppeteer, Dusk or any other browser
tooling for a single run. Use the chrome-devtools MCP or the runner the project already has. A
missing runner means: ask the user once, then install it permanently (a committed dev
dependency) and leave it there.

## 7. Re-run once, then close

1. Re-run only the filtered tests affected by the fixes (one run, not a loop); Pint `--dirty`
   again if code changed.
2. Switch back to harden and clear the list:

   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/wame-mode.sh" harden --clear-deferred
   ```

   (`${CLAUDE_PLUGIN_ROOT}` not expanded → `../../scripts/wame-mode.sh` from this skill's base
   directory.) This also restores the automatic security review env if build mode had disabled it
   — mention that a session restart may be needed. If tests are still red, switch to harden but
   **keep** the list (omit `--clear-deferred`) and say so.
3. Do not commit unless the user asked; the user's commit conventions apply.

## Report (in the user's language, max ~20 lines)

- Scope: N files, M screens, base commit.
- Per step: ✅ done / ⚠️ findings fixed (count) / ❌ still failing / ⏭ skipped (why).
- Test result: filtered X passed; full suite X passed / Y failed (pre-existing vs new).
- Fixes applied (one line each, `file:line`).
- Open questions: findings whose fix would change agreed behaviour, look or texts.
- Mode is now `harden`; deferred list cleared (or kept, and why).
