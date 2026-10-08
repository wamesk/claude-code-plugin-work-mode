# Live visual work — fast mode

In fast mode, every change a user can see is made **live in Chrome**: the screen is open in a
Chrome window the user watches, each edit shows up there, and the user comments in the chat while
the work goes on. Fast mode still skips the browser *checks* (no click-through verification, no
console audits, no performance traces) — the browser here is the canvas, not a test.

**Applies when** the task changes something on a screen: Blade / Vue / React / Livewire /
Inertia views and components, CSS / Tailwind, layout, icons and images, Nova resources, fields,
cards and tools, or a mail template with a preview route. A task without a visual part skips
this file.

## Order — always

1. **The minimum the screen needs to render**, nothing more: the route, a controller or
   component skeleton, the view, a migration / model only when the screen reads them, and data to
   show (an existing record, a factory row or a stub array). The project's code rules still apply
   to what you write (translation keys, naming) — fast mode only skips the checks.
2. **The visual work, as soon as the screen renders** — live in Chrome, steps below.
3. **Everything else** — business logic, validation, policies, persistence, services, jobs,
   menu entries, other languages. Do not start it before the screen is up in Chrome.

Do the live part in the **main conversation**, never in a subagent: the user comments here. A
subagent may build the step 1 skeleton or the step 3 rest when that pays off.

## Prepare the live screen

1. **URL.** The project's `CLAUDE.md`, then `APP_URL` in `.env`, then a Herd / Valet `*.test`
   site, then a running `php artisan serve`. Not found → ask the user once.
2. **Assets.** Vite: start the dev server in the background (`npm run dev`, Bash
   `run_in_background`) unless it already runs (Laravel writes `public/hot` while it does) — HMR
   then pushes every edit to the open page. A package that commits a built `dist/` (Nova tools,
   fields, cards): run its watch script if it has one, otherwise rebuild after each batch of
   edits. Nothing to build (plain Blade + compiled CSS already present) → nothing to start.
3. **Chrome.** chrome-devtools MCP: `new_page` with the URL **in the foreground**, and keep that
   one tab for the whole task (`list_pages` finds it again in later turns; `select_page` with
   `bringToFront: true` shows it). The MCP runs its own Chrome profile: when the screen needs a
   login, ask the user to log in in that window, then continue — never type a password the user
   did not give you for this purpose.
4. Tell the user in one line where to look: `Live: <URL> — Chrome window, comment here
   anytime.`

No chrome-devtools MCP in the session → give the user the URL to open in their own browser (HMR
still updates it) and work the same way, without screenshots. Never install or uninstall
Playwright, Puppeteer, Dusk or any other browser tooling for this.

## The live loop

- Small steps. Every change goes into the **source files** — never leave a result only in the
  browser (`evaluate_script` styling may try out an alternative the user asked to compare; the
  chosen one goes into the source right away).
- After each step the page updates through HMR, or `navigate_page` with `type: "reload"`. Look at
  it yourself with `take_screenshot` (or `take_snapshot` for the structure) before you call the
  step done. Read the console (`list_console_messages`) only when the screen does not render.
- Other breakpoints only when the task or the user asks (`resize_page` / `emulate`).
- Keep the replies short: what changed on the screen, in a line or two.
- **User comments come first.** A comment on the look interrupts the rest: apply it live, then
  resume step 3 where it stopped. What the user approves on screen is the agreed look —
  `/work-mode full` keeps it.

## Deferred list

Each screen worked on live gets one line in `.claude/work-mode-deferred.local.md`:

```
- <URL> — <what changed> — live in Chrome; skipped: tests, pint, self-check, visual pass
```

Leave the Chrome tab open at the end; the dev server keeps running until the session ends or the
user stops it.
