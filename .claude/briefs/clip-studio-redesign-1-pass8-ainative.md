PASS 8 — AI-native Clip Studio: the agent does the work, Yahia approves (same worktree/branch as pass 7b).

Yahia (verbatim): "improve our whole text and scale to fit better and have a true ai native flow to it with ai driven flows
and everything being automated and ai driven". His answers: (1) AUTONOMY = "AI does it all, I approve": it watches channels,
records when live, finds moments, sorts type, cuts, captions, picks sound, writes hook + title, books a slot; NOTHING posts
until he taps Approve; dry-run go-live gate stays. (2) HOME = clip feed + ask bar. (3) NAV = 3 places: For you · Studio · Sources.

## 0. Merge the content-types branch first
Merge `builder/clip-studio-layouts-1-20261012-140934` (typeroute.py, cliptype.py, recipes.json, liverender.py, typecli.py,
split layouts, zero-zoom rule; read its docs/clip-types.md + docs/proof/types/README.md). Resolve conflicts, then full gates.
Known weak spots you inherit (do NOT hide them in the UI): podcast detection 0/15 (no speaker labels), 4 types untested.

## 1. Engine: the agent loop (`python -m clipengine agent ...`, new module agent.py, additive)
- `agent tick [--dry-run] [--json]`: one idempotent pass, safe to run every 10 min. Per channel with a rights choice:
  live + auto_record on → ensure ONE recorder (reuse live.py; never two per channel) · new source/VOD → finder → moments ·
  top moments (Clip score ≥ floor, quality gate passes) → cliptype → render via typeroute recipe (HD bar, captions v3, zero-zoom
  rule) → sound per campaign/vibe rules (vibe packs = "needs your sound", never auto-music) → AI title + hook + one-line "why"
  → status `ready` → pencil into the next free slot as `awaiting_approval`. Respect every existing gate: rights, campaign rules,
  PB Blake requires_manual_edit, 3/day cap, go-live dry run. The tick NEVER publishes or submits; approval stays the only path.
- Budget, enforced in code and shown in the app: ≤12 renders/day, ≤$0.60/day Anthropic (meter() already exists; this sits
  inside the $25/month ceiling), recording only on channels with rights + auto_record on. Over budget → skip + log, never queue.
- `agent_events` table (ts, kind, channel, moment, text, cost) + `agent status --json` (now-doing line, today's counts, spend,
  next slot). Every step writes one plain-English event ("Cut Malik 18:31 — gaming + cam, split layout").
- AI title/why: Claude via the existing anthropic path (CLAUDE_MODEL, metered), ≤60-char sentence-case title, never invented
  words beyond the clip's content; no key / over budget → fallback = cleaned first spoken sentence. "Why" cites real signals only
  (chat spike x, keyword, laugh, score) — never fabricated.
- Learning: reject takes an optional reason chip (boring / wrong moment / bad crop / wrong type / bad captions); type overrides
  feed the existing per-channel prior; store reasons for the finder floor (no auto-threshold moves: calibration diffs only).
- launchd: write `scripts/launchagents/com.clipstudio.agent.plist` (tick every 10 min) + install/uninstall script. Do NOT load it.

## 2. Engine: ask bar + "Change…" (one router, no new privileges)
- `ask "<text>" [--moment ID] --json`. Route with Jev FIRST (clipengine/jev.py; choice over a closed intent list: make clips from
  URL · record/watch channel · change this clip · find campaign · question about my numbers · settings · none). Jev confidence
  below floor → Claude tool-use (reuse finder_chat.py pattern: validated tools, one repair turn, else a plain question back).
- "Change…" on a clip maps to a CLOSED op list executed through existing CLI paths: trim to a spoken word/phrase, shorter/longer,
  type/layout override, vibe/style pack, sound swap/none, hook rewrite, captions on/off, mask profanity. Every op re-renders and
  shows before/after. Anything outside the list → say so plainly. Publishing/approval can never be triggered from the ask bar.
- Tests: intent routing on ≥30 labelled phrasings (held-out 10 not used while writing prompts), op parsing incl. "start at the
  scream", budget-exceeded path, Jev-down fallback.

## 3. Swift: 3 places + the feed
- Top bar: Clip Studio · For you · Studio · Sources · centered ask bar (⌘K, works on every screen) · agent pill (now-doing line,
  click → activity log with spend) · settings. Today's 5 tabs + 9 sub-tabs go; every existing screen keeps a home:
  For you = feed (Ready for you · Needs your sound · Scheduled · Posted with REAL numbers + Insights summary);
  Studio = review player / edit room, Sounds (library + trending), Styles/vibes, Format picker (docs/clip-types.md contract);
  Sources = channels (rights + auto-record toggle per channel), Live, Discover, Campaigns, Insights/Funnel detail.
- Feed card (per the preview Yahia picked): video thumb · AI title (2 lines max) · type · vibe · length · Clip score · one-line
  why · Approve / Reject (reason chips) / Change… (inline ask field scoped to that clip). Keyboard: A / R / C / ↑↓ / Space.
- Empty states say what the agent is doing ("Watching 2 live channels · next check 18:50"), never a blank panel.

## 4. Text + scale (fixes Yahia saw: truncated titles, rows clipping off-screen, ALL-CAPS transcript fragments, mixed fonts)
- One type scale in Brand.swift as role tokens: caption 12 · body 14 · callout 15 · headline 17 semibold · title 22 · large 28 ·
  stat 40. Inter for everything; Space Grotesk only for stat numbers + the wordmark; mono only for timecodes. Sentence case
  titles (no all-caps card titles). Every Brand.sans(N) call site moves to a role token.
- App-wide text size: ⌘+ / ⌘− / ⌘0 (0.85–1.4×, persisted `textScale`), applied through the tokens.
- No horizontal clipping: card rows become adaptive grids (LazyVGrid .adaptive, min ~240) that reflow with the window;
  horizontal scrollers only where intentional and with a visible scroll affordance. Inspector width = clamp(340, 28% , 460).
  Titles never single-line truncate below 2 lines; channel names never truncate under 24 chars.

## Proof + gates
- swift build, swift build --build-tests, swift test (grep Executed); engine pytest (each new/changed test file).
- Sandbox run: CLIPSTUDIO_HOME = sandbox holding a COPY of the real library (read real via sqlite3 "file:...?mode=ro" → copy);
  run `agent tick --dry-run` then a real tick in the sandbox; the feed must show REAL clips with AI titles + real why-lines.
  Write docs/proof/agent/README.md: events log, counts, spend, what was skipped and why.
- Renders (QA snapshot) light + dark of For you, Studio, Sources, ask bar open, Change… open, activity log — at 1100x700,
  1280x800 and 1680x1050. Write a truncation audit (every Text that truncates in any render, with reason). Read every render.
- Run the taste checklist (~/.claude/skills/taste/SKILL.md) on the renders before finishing; fix what fails.
- Commit in logical steps; no push; no merge to main; never quit/relaunch ClipStudio.app and never run scripts/package.sh
  (Yahia's open app IS this worktree's ClipStudio.app; render from .build/debug like render.sh); never write the
  real library, the real musiclib.sqlite, or load any LaunchAgent. Result: what works, what is untested, real numbers only.
