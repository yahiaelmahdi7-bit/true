# Brief: Run 25 — ⌘K + Hub on the phone (start work anywhere, see every session)

Worktree. Do NOT push, do NOT launch True.app, do NOT run `tailscale` or `builder` commands, never read
`.claude/heldout/`. Lane: `Sources/True/` (Remote/, CommandBar/, Hub code), `Tests/`, `Resources/Remote/`, `SPEC.md`,
`docs/kb/`. Gate = docs/kb/conventions.md:5-9 exactly; weaken no test. No result.md in repo.

Yahia: "make it truly an omni tool working across devices". He picked this after Phone ↔ Mac drop (Run 24, merged).
Read SPEC.md first: "Run 7 — The Hub", "Run 14 — The Command bar", "True on the web — phase 1 (Run 22)" and the
Run 24 drop section. Every remote auth rule there holds (identity, exact Host/Origin, bearer, headers, caps).

## Build
1. **Hub on the phone.** The web app's first tab becomes **Hub** (tab bar: Hub · Shots · Send). Same data and
   grouping as the Mac Hub (projects sorted by latest activity, header counts "3 working · 1 needs you", rows with
   status pill Working / Needs you / Done / Idle, builders running or finished-not-acked). `GET /api/hub` returns
   the Hub's own model — reuse the Mac Hub's code, don't re-derive. Tap a row with a True pane → that pane (phase 1
   view). A session in another terminal (no True pane) → read-only detail, no input. Builder row → its result text
   (read-only) + **Ack** button (`POST /api/hub/builder/<id>/ack`; id must match a known builder, never a path).
   Refresh: poll every 5 s while visible.
2. **⌘K on the phone.** A floating "＋" button on Hub opens a sheet: one text field + the **route line** as chips
   (kind · project · new pane/where · model · effort), exactly the Mac Command bar's pipeline (`CommandRules` first,
   Jev only selects among code-built candidates, same fallbacks when Jev is down). Flow:
   `POST /api/route {"text"}` → `{routeId, route, alternatives}`; chips open pickers fed ONLY by the server's
   candidate lists (`POST /api/route/<routeId>/slot {"slot","value"}` → server re-validates, returns updated route).
   **Run** = `POST /api/run {"routeId"}`; "Run in background" toggle = the Mac's ⌘Return path. routeId: random,
   single use, 2 min expiry, bound to the device that made it. The phone never submits a raw command or route
   payload — the server runs only what it proposed. Nothing runs without the Run tap.
3. **New panes are visible on the Mac.** Anything launched from the phone opens as a normal True tab on the Mac
   (never hidden), tagged "from iPhone" in its title chip for 10 min. After Run the phone jumps straight into that
   new pane. Every safety gate the Mac bar has (e.g. the danger_push confirm) shows on the phone as a confirm sheet;
   none is skipped. Log every remote route + run (device id, text hash, route, result); max 10 runs/min/device.
4. **History**: phone gets the bar's ↑ history as a "Recent" list (same file, read-only from the phone).

## Design bar
Read `~/.claude/skills/taste/SKILL.md` first and say so. Phone-first, 44 pt targets, same look as Runs 22/24.

## Tests (no app launch)
Hub JSON matches the Mac Hub model for a fixture (sessions + builders + dedupe), builder ack id validation, routeId
single-use / expiry / wrong-device → 4xx, slot values outside candidates rejected, no raw-command route exists
(assert the route table), danger gate surfaces as `needsConfirm` and run without confirm → refused, rate limit,
launched pane is a normal visible tab. SPEC.md new section + docs/kb/remote-access.md threat model update.

## Final answer
Files, tests, gate tail, phone eyeball checklist.
