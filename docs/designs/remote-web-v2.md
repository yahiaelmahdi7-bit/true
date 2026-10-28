# True phone web app v2 — calm Hub, readable Panes, send images into sessions
Status: building

## Goal
Yahia drives True from his iPhone through the web app True serves over Tailscale (`Resources/Remote/*`,
embedded into `RemoteWebAssets.swift`). Three things are broken or poor: (1) the Hub tab is a wall of finished
background builds, so what needs him is buried; (2) the Panes tab has no visual separation between Mac tabs and
rows look identical ("finance-director-os" ×6), so he can't tell sessions apart; (3) he can't put an image into a
session from the phone — the Shots viewer only has Share/Save, and the pane view has no attach button. Fix all
three and bring the web app up to HIG-quality grouped lists, consistent tokens and honest states. Design rules:
the House system `~/.claude/design/DESIGN-SYSTEM.md` (4 px grid, radii, one accent) + Apple HIG lists/sheets/tab bars.

## Users & journeys
- As Yahia on my phone, I open the Hub and see first what needs me and what is running, so that I act in seconds;
  finished builds are one folded row I can open, and builds older than a day fold away on their own (like the Mac).
- As Yahia, I open Panes and each Mac tab is its own card with its panes inside, each pane named by what it is
  doing (topic / branch / folder), so that I open the right session first time.
- As Yahia, I take a screenshot on the Mac, open Shots on the phone, tap it, tap **Send to session**, pick a pane,
  and the image lands in that session's input box; the app jumps into that pane so I can type my message and Send.
- As Yahia inside a pane, I tap the paperclip, pick a photo from my phone (or a Mac shot), and it lands in that
  session's input box.

## Scope
In:
- `Resources/Remote/index.html`, `app.js`, `app.css` (web app), regenerated `Sources/True/Remote/RemoteWebAssets.swift`
  via `python3 -I Resources/Remote/gen.py`.
- **One additive server field pair** on builder rows of `GET /api/hub` (`RemoteCommandsLive.swift:77-80`):
  `"ended": b.ended ?? NSNull()` and `"fresh": HubTriage.isLive(b.ended ?? b.started, now: now)`. Old clients
  (the native app) ignore unknown keys. Plus one test asserting both keys.
- `RemoteTests.embeddedXtermMatchesResource` (`Tests/TrueTests/RemoteTests.swift:290-296`): add `("/app.css","app.css")`.
- `scripts/remote-mock.py` extended (realistic data, the two new hub keys, input/drop/ack routes, fault toggles).
- `SPEC.md` "Run 40 — phone web v2" section (as-built notes).
Out:
- No new routes, no auth/security changes, no other Swift changes.
- **"Mark all as seen" / any bulk ack** — cut (see Review). Per-builder Ack in the builder sheet stays.
- The native iOS app (`ios/`), the Mac Hub UI, the Mac's own builder visibility rule (`HubModel.swift:150-157`).
- Typing/Send behaviour of the existing line field (raw bytes; it works today).
- Attaching non-image files from a pane (the Send tab's upload still sends any file to Downloads, unchanged).

## Approach
All changes use routes that already exist and are authorised for a full-scope paired device:
`GET /api/hub`, `GET /api/hub/builder/<id>`, `POST /api/hub/builder/<id>/ack`, `GET /api/tabs`, `GET /api/shots`,
`POST /api/drop` (raw body + `X-Filename`; replies `{ok, where:"shots", id}` for images,
`{ok, where:"downloads", name}` otherwise — `RemoteServer.swift:348-349`), and `POST /api/pane/<uuid>/input
{intent, text, attach:[{id}|{name}]}` → `200 {"outcome": wire}` (`RemoteServer+Input.swift:29-71`; resolves a tray
id or a Downloads name, pastes paths through `PaneDelivery`, the one door that types into panes).

1. **Hub = triage bands** (client-side banding of `/api/hub` rows, mirroring the Mac's `HubTriage.swift:95-178`).
   What the server sends today (`HubModel.swift:150-157`): running builders, unacked finished builders of any age,
   and acked ones finished < 24 h ago. Builder `statusKey` is `AgentStatus` (`HubModel.swift:161-168`):
   `working` (running/queued/waiting), `done` (done/landed/unlanded/other), `needsYou` (paused/held),
   `failed` (failed/killed/died). The band rule is one function `band(row)` in app.js, with a comment naming
   HubTriage.swift as its reference:

   | Row | Band |
   |---|---|
   | seat / pane / other with `statusKey` needsYou | Needs you |
   | builder `needsYou` (paused/held), not `acked` | Needs you (any age — it's blocked on him) |
   | builder `failed`, not acked, `fresh` | Needs you (red tone) |
   | any `statusKey` working | Running |
   | builder `done`, not acked, `fresh` | Finished → "New" |
   | builder: acked, or `done`/`failed` and not `fresh` | Finished → "Older" (unacked failures listed first, red) |
   | seat idle/asleep, other idle | Sessions |

   - Header: large title "Hub" + summary line from the server's `summary` field.
   - **Needs you**: project as small label, name, `question` (or status label) as second line. Tap → pane / builder sheet.
   - **Running**: second line = project · elapsed. **Sessions**: max 5 + "Show all N" row.
   - **Finished** = ONE row: "Finished builds" with value "N new" (or "K older" when none are new); hidden only when
     both lists are empty. Tap → sheet (the existing `#sheet` + list renderer) with sections "New" and "Older",
     rows = name · status · "2h ago" (from `ended`). Each row opens the existing builder sheet (result + **Ack**).
     Ack: hide the row at once, POST, put it back with "Couldn't clear" on any non-2xx except 404 (404 = already gone).
   - Loading: skeleton rows on first load; error: "Can't reach the Mac" + Retry; nothing at all → "All clear".
   - Polling stays at 5 s; a poll never resurrects a row whose Ack is in flight.
2. **Panes = one inset card per Mac tab.** `/api/tabs` = `{tabs:[{id,title,selected,panes:[{id,title,cwd,agent,
   needsYou,claude,busy,live,repo,branch,worktree,sessionID,topic}]}], now}` (`RemoteBackendLive.swift:13-38`).
   - Section header per tab: `title` + "N panes"; `selected` → "On Mac screen" tag.
   - Rows in a `.group` card with hairline separators (same component as the Hub). Glyph: `claude` → Claude mark,
     else shell. Status chip: `needsYou` → "Needs you", else `busy` → "Working", else "Idle"; `live:false` → dimmed
     "Not running".
   - Row name = `agent` → `repo` → last path part of `cwd`. Second line = `topic` → `branch` (if not main/master) →
     `cwd` shortened to `~/…`. If all are missing: "pane " + first 4 chars of `id`. If two rows in one tab still
     read the same, suffix "· pane 2", "· pane 3" by server order.
   - Sort inside a tab: needs-you first, then server order (stable).
3. **Send to session from Shots.** Viewer footer: **Send to session** (primary), Share, Save.
   Send opens the **pane picker sheet**, which refetches `/api/tabs` on every open: grouped by Mac tab, Claude panes
   first, shell panes labelled "Shell", `live:false` greyed and not tappable; the last pane opened on the phone is
   pinned on top as "Recent" (localStorage, wrapped in try/catch; dropped if not in the fresh list). States: loading
   skeleton; no live panes → "No open panes on the Mac"; fetch error → "Can't reach the Mac" + Retry.
   Pick → button disabled while in flight → `POST /api/pane/<id>/input {intent:"stage", text:"", attach:[{id}]}`.
   Never auto-retried (the POST isn't idempotent; a retry would paste twice). Result → toast:

   | Reply | Toast | Then |
   |---|---|---|
   | `staged` / `landed` | "Added to <pane> — type your message" | open pane view |
   | `unverified` | "Sent to <pane>, couldn't confirm — check it" | open pane view |
   | `stuckInComposer` | "It's in <pane>'s input box but didn't go further" | open pane view |
   | `promptGone` | "<pane> moved on before it arrived" | open pane view |
   | `noPane` or 404 "No such pane" | "That pane closed — pick another" | picker stays open, refetched |
   | 404 "Unknown attachment" | "That shot is gone from the Mac" | close picker |
   | 401 | (existing `unpair()`) | pairing screen |
   | other / network error | "Couldn't send — nothing was added" | picker stays open |
4. **Attach inside a pane.** Pane view gets a 44 pt paperclip left of the line field. Tap → action sheet:
   - **Photo from iPhone**: hidden `<input type=file accept="image/*">` (Photos / Camera / Files). Upload reuses
     the existing `upload()` (`app.js:579-602`), refactored to return a Promise so the Send tab and the paperclip
     share it: raw body + `X-Filename`, 503 → backoff 1-2-4 s up to 6 tries, then the existing messages (413 "Too big
     (200 MB max)", 507 "Mac disk is full", 408 "Timed out", onerror "Mac unreachable"), 401 → unpair. While it
     runs, a chip replaces the key bar's first slot: thumbnail + progress + Cancel (`xhr.abort()`). On failure the
     chip shows the message + Retry; nothing is staged. On success → stage `{id}` with the same toast table (stays
     in the pane). A non-image reply (`name`) can't happen with `accept="image/*"`; if it does → "Saved to
     Downloads on the Mac", no stage.
   - **From Mac Shots**: grid of recent shots in the shared sheet → stage `{id}`.
   - The back button label reflects where you came from ("Hub" / "Panes" / "Shots").
5. **System pass (HIG + House rules on True's existing skin).** Keep True's skin (warm paper light, true-black
   dark, one warm accent) and its tokens; fix drift: spacing on the 4 px grid, radii only 9/14/20/pill, one type
   scale, every target ≥ 44 pt, one primary button per screen, `aria-label` on icon buttons, visible focus,
   reduced-motion respected, no raw hex outside `:root`. Replace `.row2`/`.tab h2` one-offs with the shared
   `.group`/`.row`/`.sec` components and one list renderer. Loading, error and empty states for every list.

## Alternatives considered
- **Server-side Hub filtering** (drop old builders from `RemoteHubJSON`): changes the shared model for a
  presentation problem. Two additive keys + client banding is enough and reversible.
- **Server-computed `section` per row** (zoom-out's suggestion): the cleanest anti-drift answer, but
  `HubTriage.item` works on Watcher inbox items the remote path doesn't build; `fresh` puts the one time rule in
  one place for a fraction of the change.
- **Mark all as seen**: a bulk write to shared state that could bury unread failures; the 24 h fold fixes the
  spam without it.
- **Phone-side attachment chips that submit with the next Send**: diverges from the Mac's Send (which stages).
  Staging shows the image in Claude's own input box on the live terminal, which is the truth.

## Steps
Ordered so the functional fixes land first; commit after each step (40a = steps 3-5 can merge alone if the run stalls).
1. Worktree `builder/remote-web-v2` off main. Check: `git worktree list` shows it; main checkout untouched.
2. Server keys + mock. Add `ended`/`fresh` to builder rows + a test; extend `scripts/remote-mock.py`: `/api/tabs`
   with 4 tabs (one tab with 4 panes titled the same, different topic/branch/none, one `live:false`, one shell),
   hub with 2 needs-you, 3 running, 3 idle seats, 27 finished builders (5 fresh, 22 old, 2 old unacked failures),
   `/api/pane/<id>/input` (records body, returns `{"outcome":"staged"}`), `/api/drop` (`{ok, where:"shots", id}`
   for images), ack (records). Fault toggles via env `MOCK_FAULT=` (comma list): `input404`, `inputUnknownAttach`,
   `outcome=<wire>`, `drop413`, `drop503x2`, `drop507`, `tabsEmpty`, `hubEmpty`, `builders=0|1|200`, `ack500`.
   Check: `curl` each route with and without a fault.
3. Send to session from Shots + pane picker. Check: mock log shows `intent:"stage"`, `attach:[{id}]` for the picked
   pane; pane view opens with the toast; every row of the toast table reproduced via `MOCK_FAULT`.
4. Paperclip + shared `upload()` + From Mac Shots. Check: Playwright `setInputFiles` → mock gets `/api/drop` then
   `/input` with the returned id; `drop413`/`drop507` show the message + Retry and send no `/input`; `drop503x2`
   recovers.
5. Panes cards. Check: screenshot — 4 separate cards; the 4 same-titled panes read differently; dead pane dimmed.
6. Hub bands + Finished sheet + per-builder Ack. Check: at 390×844 Needs you and Running are above the fold with 27
   builders; Finished is one row; old unacked failures appear first in "Older"; `ack500` puts the row back;
   `builders=0|1|200` and `hubEmpty` render sensibly.
7. System pass + `bash ~/.claude/design/design-lint.sh Resources/Remote/app.css` (record any hit kept on purpose,
   e.g. true-black terminal) + light/dark screenshots of every screen; self-critique against `/taste`.
8. `python3 -I Resources/Remote/gen.py` (must run before tests); `swift build`; test command from
   `docs/kb/conventions.md` with `--filter Remote`. Check: all green.
9. SPEC.md Run 40 section; commit; merge to main; `scripts/package.sh` builds the new True.app.

Screenshots: `scripts/remote-shots.mjs` (needs `PW_PATH`) against `scripts/remote-mock.py` on :8899, one Chromium,
serial, light then dark (`colorScheme` context option), output `.claude/shots/remote-web-v2/`. No Playwright MCP, no
parallel browsers (memory: Playwright floods kill the Mac). Offline case: `context.setOffline(true)`.

## Done means
- Hub, at 390×844 with 27 builders (5 fresh) + 2 needs-you + 3 running: needs-you and running rows visible without
  scrolling; finished builds are exactly one row; no unacked failure is hidden (fresh → Needs you, old → top of
  "Older"); a failed Ack restores the row.
- Panes: each Mac tab is a separate card with a header; no two rows in one card read identically.
- Shots → Send to session → pick pane: mock receives `{intent:"stage", text:"", attach:[{id}]}` for that pane and
  the pane view opens with the toast; each outcome/error in the table shows its own copy; no double POST on double tap.
- Pane view paperclip: phone image → `/api/drop` → `/api/pane/<id>/input` with the returned id; upload errors show
  a message + Retry and stage nothing.
- Every screen screenshotted light + dark at 390×844; no target under 44 pt; lint clean or justified.
- `swift build` + Remote tests pass (including the new hub-key test and app.css in the embed test).
- **Live check (needs Yahia):** after True restarts on the new build, on the phone: Shots → Send to session puts
  `[Image #1]` in a real Claude pane. Claude must not launch/quit True, so this last check is his.

## Risks
- `stage` into a Claude pane mid-turn may come back `stuckInComposer` / `unverified`. Signal: the toast says so and
  the pane view opens on the truth; nothing auto-retries.
- Embedded assets go stale if `gen.py` isn't re-run: `RemoteTests.swift:290-296` compares the embedded bytes with
  the files on disk (app.js, index.html, xterm; app.css added in this run), so a stale embed fails the test.
- iOS Safari file input: `accept="image/*"` opens Photos/Camera/Files; `/api/drop` decodes HEIC. Signal: upload
  fails in the live check.
- The 24 h fold: a build that finished 25 h ago no longer shows "New". It is still in the sheet's "Older" and in
  `builder status`, and unacked failures stay red at the top of "Older".
- Another True session is live in this repo → worktree only; the merge touches only the files above.
- Rollback: revert the merge commit and re-run `scripts/package.sh`; the previous web app is in git.

## Review
Goldfish, 2026-10-29: naive-reader 3/4/2 · zoom-out 0/3/3 · critic 1/9/3 (merged 4 blockers / 12 shoulds / 6 nits).
All 4 blockers and 12 shoulds applied; all 6 nits applied. Partly accepted, with reasons:
- zoom-out "feed RemoteHubJSON from HubTriage / add `section`": took the smaller version (`fresh` computed by
  `HubTriage.isLive`) — a full `section` needs Watcher inbox items the remote path doesn't build.
- zoom-out "split into 40a/40b": kept one run, but reordered so send/attach land first and commit per step; 40a can
  merge alone.
- critic "stop the ack loop on first error / pause polling": moot — Mark all as seen is cut; the per-row Ack keeps the
  optimistic-hide + restore rule.
