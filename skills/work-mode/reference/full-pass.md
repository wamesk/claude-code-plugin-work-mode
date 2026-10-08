# Full pass — one verification run at the end of fast mode

Fast mode skipped the checks; this pass runs every one of them **once**, fixes what they find,
and switches the project to full mode. Flags: `--no-full-suite`, `--no-visual`.

**The contract:** what was built and agreed with the user stays — behaviour, look (layout,
colours, components) and user-facing texts. The pass fixes bugs, missing tests, style, security,
performance, reachability, translations and docs underneath them. When a fix would change
something the user agreed to (a visible text, a flow, a screen's look, an API contract), do not
apply it — list it in the report as a question.

## 0. Scope

1. Read `.claude/work-mode.local.md` (`mode`, `since`, `base_commit`) and
   `.claude/work-mode-deferred.local.md` (one line or block per touched file/screen). The 1.x
   names `.claude/wame-mode.local.md` / `.claude/wame-deferred.local.md` count too.
2. Build the change set: `git diff --name-only <base_commit>` (committed since fast mode started)
   + `git status --porcelain` (uncommitted). No `base_commit` → `git log --since="<since>"`. No
   mode file and no list → ask the user what to check (default: uncommitted changes + the last
   commit).
3. Read the project's `CLAUDE.md` for the test commands (filtered, full, parallel), the formatter,
   module-specific rules and which docs exist. Read the `CLAUDE.md` of every touched module.
4. Say in two lines what will be checked (files, screens, which steps apply). Do not ask for
   confirmation unless the scope is unclear.

## 1. Tests

- Missing tests for touched behaviour: write them (Pest in Laravel projects — delegate to
  `laravel-agents:pest-tester`, brief it **full mode**, list the files; Nova screens via
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

When the agents are installed, spawn both in one message, each briefed **full mode** with the
change set and the expected output (`file:line — severity — finding — fix`, max 20 lines):

- `laravel-agents:security-auditor` — **always run a security review**, even for small diffs:
  fast mode may have switched the automatic `security-guidance` review off.
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

Screens marked `live in Chrome` in the deferred list were shaped with the user watching: their
look is agreed. Check only the console, reachability and what the live loop never covered
(other breakpoints, empty and error states); reuse the live tab when it is still open.

**Browser rule:** never install or uninstall Playwright, Puppeteer, Dusk or any other browser
tooling for a single run. Use the chrome-devtools MCP or the runner the project already has. A
missing runner means: ask the user once, then install it permanently (a committed dev
dependency) and leave it there.

## 7. Re-run once, then close

1. Re-run only the filtered tests affected by the fixes (one run, not a loop); Pint `--dirty`
   again if code changed.
2. Switch to full and clear the list:

   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/work-mode.sh" full --clear-deferred
   ```

   (`${CLAUDE_PLUGIN_ROOT}` not expanded → `../../scripts/work-mode.sh` from the skill's base
   directory.) This also restores the automatic security review env if fast mode had disabled
   it — mention that a session restart may be needed. If tests are still red, switch to full but
   **keep** the list (omit `--clear-deferred`) and say so.
3. Do not commit unless the user asked; the user's commit conventions apply. Never stage or
   commit the mode file or the deferred list.

## Report (in the user's language, max ~20 lines)

- Scope: N files, M screens, base commit.
- Per step: ✅ done / ⚠️ findings fixed (count) / ❌ still failing / ⏭ skipped (why).
- Test result: filtered X passed; full suite X passed / Y failed (pre-existing vs new).
- Fixes applied (one line each, `file:line`).
- Open questions: findings whose fix would change agreed behaviour, look or texts.
- Mode is now `full`; deferred list cleared (or kept, and why).
