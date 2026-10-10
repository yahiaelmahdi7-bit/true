# Roadmap
Owner: cto · Last verified: 2026-09-30

## Now
Run 7 (Hub + background helpers via `truectl spawn`) is built; its Hub panel is **not visually verified** because the app was never launched by the builder. [source: SPEC.md "Run 7 notes"] Next: eyeball the Hub in the real app.

## Next
Unknown — see Open questions (index.md #6).

## Later
Smart input (one box: shell vs agent request, next-command, commit/PR text) · illustrated character art (no Gemini) · Nova as a separate menu-bar app driving True over a control socket. [source: SPEC.md "Later (not v1)"]

## Done (dated)
- 2026-09-29 Run 1 terminal core; Run 2 agents mode [source: git log]
- 2026-09-30 Truectl + global agents; Open Project palette (⌘O); screenshot tray; drag-and-drop; icon; stable signing [source: git log]
- 2026-09-30 Run 4 restore, Run 5 Context Cleaner, Run 6 Jev backend, Run 7 Hub, KeepAwake [source: git log; SPEC.md]

## Kill criteria
"Fans spinning" is the reason Axon died: if idle CPU is not ~0%, that is a stop-and-fix. [source: SPEC.md:6-8, Hard rules] Other kill criteria: Unknown — see Open questions.

## Next: Nova screen hands
`do_on_screen`/`read_screen`/`click_row`/`type_into_row`/`press_keys`/`scroll` (AX table + OCR fallback), the `computer_toolset_20260801` fallback wired to tools, (live partial transcript in the HUD: done in Run 26b), unsaved-changes detection for `quit_app`.
