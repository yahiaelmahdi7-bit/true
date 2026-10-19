# Clip Studio — bring back the redesign-1 look; keep the new features underneath it

Repo: ~/Projects/clip-studio (worktree off main @5aa438c; gates green: engine 1070 pass/1 skip, swift 119/0).

## Why (Yahia, 2026-10-13, verbatim): "why did u fully redesing the page this looks like ass"
He named ALL of: Home / sidebar, Campaign page, Set up accounts, Analytics. His call: "Bring old look back" — restore the
previous visual design and keep the new features working underneath it.

## The two looks
- OLD = what he wants: redesign-1 (merged a5d3c16, state of main at 5e348e4). Dark, media-first, TOP TAB BAR
  (Home · Library · Moments · Campaigns · Publish), video tiles as the UI, one green accent, Brand.swift tokens.
  Reference stills: docs/screens/redesign/*.png (home-dark.png, campaigns-dark.png, ...). Brief that made it:
  /Users/y/Projects/true/.claude/briefs/clip-studio-redesign-1-*.md (pass1 = the shell; read it for the design rules).
- NEW = what he rejects: the campaign-first shell from the ecosystem L3 lane — left SIDEBAR (Home / Campaigns / Across all
  campaigns), text-only cards, empty admin-panel board. Commits baffc70, 50f0343, af55a7c (EcoShellViews.swift,
  EcoAnalyticsViews.swift, Shell.swift), plus 1a225cf (SetupAccountsView) and e6591a2 (Accounts+Mail "sidebar IA").
  Stills: docs/proof/ecosystem/*.png, docs/proof/setup-queue/*.png.

## Work
1. Shell: restore the redesign-1 window chrome and top tab bar exactly (git show 5e348e4:<file> is your reference). No global
   sidebar anywhere. Header right side as redesign-1 (jobs, New clip, status dot, settings); keep the Ask bar and an
   Autopilot status pill ONLY if they sit in that header the redesign-1 way (one row, same type scale).
2. Re-home the new features inside that look, restyled with redesign-1's components (Brand tokens, FeedCard-style video
   tiles, its section headers "NEEDS YOU / READY TO POST" + "See all", its stat row):
   - Campaign page (board/review/posted/analytics/accounts/settings) -> lives under the Campaigns tab (campaigns list as in
     campaigns-dark.png; opening one shows its page). Review + Posted are VIDEO TILES (thumbnails, score ring), not text
     cards. The 8-stage board, if kept, uses thumbnails where a clip/moment exists and must not look like an empty grid.
   - Analytics -> reachable from the campaign page and Home, charts restyled to Brand (one accent, redesign-1 type).
   - Set up accounts + Accounts/Mail -> reachable from the campaign's Accounts and from Settings, styled as redesign-1
     panels (not a sidebar list). All of its behaviour stays: queue progress, current card, profile form, Chrome helper.
   - Home -> the redesign-1 Home (stat row, Your channels, Needs you, Ready to post tiles); add campaign/autopilot info only
     inside that structure.
3. Logic is OFF LIMITS: no changes to engine/, ClipStudioCore data/models, AppModel behaviour, view-model logic or CLI
   contracts. Views and view composition only. Every existing feature must still be reachable — list each one and where
   it now lives in the report (a feature you could not place = say so, don't delete it).

## Proof (this is the deliverable — he judges by eye)
- Render stills (the existing snapshot/stills mechanism; fixtures WITH real-looking thumbnails so tiles are not empty) for:
  Home, Campaigns list, Campaign page (each tab), Analytics, Set up accounts, Accounts/Mail — dark AND light, 1440x900 and
  1280x800. Put them in docs/lanes/restore-look/ plus a side-by-side vs the matching docs/screens/redesign/ still.
- LOOK at every still. Self-check against /Users/y/.claude/skills/taste/SKILL.md and write the pass/fail per rule.
  Known nits to fix while there: grey-on-grey selected rows, controls that look disabled, ragged left/right edges,
  low-contrast secondary buttons.
- Do NOT run scripts/package.sh and do not touch the installed app: Yahia approves the stills first.

## Gates
`swift test` AT REPO ROOT (119+ pass, 0 fail) and `cd engine && PYTHONPATH=$PWD ~/Projects/clip-studio/engine/.venv/bin/python
-m pytest -q` (must stay 1070/1 skip — you should not be touching it). Before every commit: `git checkout --
docs/proof/submit/happy.png; rm -f docs/proof/submit/happy-watched-run.png`.
Report docs/lanes/restore-look.md: what changed, the feature-placement table, still paths, taste self-check, verified vs NOT.

Rules: never flip post.golive; never touch the live DB, ~/Projects/clip-studio.live or the main checkout; no posting.

```
DISCIPLINE (non-negotiable):
- Commits: atomic, message says what+why. NEVER push, NEVER merge. The user pushes, not you.
- Gates: run in the FOREGROUND and wait. NO background shells, NO watch modes, NO until-loops.
- Claims: 'done' means you ran the gate and pasted the passing output. Code written ≠ working; a still you did not look at
  is not proof.
- If blocked: say BLOCKED + one line why. Do not invent extra scope.
```
