# Clip Studio Autopilot — join a campaign, everything else is automatic

Yahia (2026-10-13), REVERSING the earlier "AI does it, he approves": "I don't want me to post clips. I need auto
clip finding and content based on the campaign's content when joined, and make it a straightforward thing that
auto uploads and all." No Approve step in the normal path. Make it ONE simple flow.

Base: main (a5d3c16) — has Jev brain (pass 9), type profiles + captions (pass 10), post fix + tracker, agent tick,
campaigns.py (Content Rewards campaigns: rules, platforms, cpm, source_links / sources_allowlist, submit rules like
`submit_within_minutes`), accounts.py (Upload-Post profile "default"), slot routine (post+submit = one routine).
Another builder runs depth captions (pass 11) on builder/clip-studio-redesign-1-…: stay out of captions/depth files.

## The flow (per JOINED campaign, status='joined' / joined_at set)
1. **Source**: pull new content ONLY from the campaign's provided sources (sources_allowlist / source_links;
   campaigns.plan_sources). Poll for new uploads/VODs; download via existing ingest. Nothing outside the allowlist.
2. **Find**: type detection → type profile → Jev-scored moments (Claude off). Campaign brief/category steers Jev
   state (e.g. "quotes, takes, reactions").
3. **Edit**: type's edit + campaign requirements (required tags/overlay assets via pick_overlay, length limits,
   watermark/CTA rules from parse_rules). Vibe pack: campaign default.
4. **Gate (automatic, no human)**: campaign rules check (check_rules), platform allowed AND linked in Upload-Post,
   Jev quality floor (type-specific; untested types need a higher floor), duplicate check (never repost the same
   moment / near-identical clip — TikTok rejected duplicate content once), per-campaign daily cap
   (default 3/day/platform, configurable), global daily cap, budget_left > 0 and campaign not ended.
5. **Post**: Upload-Post at the next slot, then **submit** the post URL to the campaign within its window
   (existing submit flow / docs/proof/submit). Then the tracker records views.
6. Everything that happens is written to the activity log in plain English; refusals say why.

## UI: straightforward
- Sources/Campaigns: each campaign card has ONE toggle "Autopilot" (on when joined) + status line
  ("Posting 3/day to YouTube · last post 14:30 · 2,310 views"). Joining itself stays manual on the website (no login
  automation); a "I joined" button marks it.
- For you becomes a read-only "What autopilot did" feed (posted, submitted, skipped + why) with an Undo/Delete per
  post. No Approve buttons in the autopilot path. A global PAUSE switch (kill switch) in the top bar.
- Blocking problems surface plainly: "Can't post ClipFarm: needs Instagram or YouTube linked — Link now".

## Go-live
Keep `post.golive` as the master switch. Build + prove the whole loop with golive OFF (dry-run posts + dry-run
submit) on a sandbox copy. Do NOT flip it; the session lead flips it after reviewing your proof.
Launch agents (agent tick, slot, tracker): write/update plists, do NOT load.

## Proof
Sandbox end-to-end: mark a real campaign joined (sandbox copy) → new source content → clips found → edited →
gated → dry-run posted + dry-run submitted → activity feed. Screens of campaign card, feed, pause, blocker banner.
docs/proof/autopilot/README.md with exactly what would have been posted where and why.

## Rules
Real library read-only; sandbox writes. Don't quit/relaunch ClipStudio, no package.sh, never push, never merge
to main, no real uploads/submits. Commit on this branch. Gates: swift build, --build-tests, swift test, engine
pytest. Report plain English, verdict first.

## Settled constraints that still bind autopilot (from earlier decisions)
- **Campaigns that require a human edit** (PB Blake: "every clip must be edited by you" → `requires_manual_edit`):
  autopilot finds + edits + queues, but does NOT auto-post those — card says "This campaign requires your edit".
  That's the campaign's rule, not ours; posting unedited would break its terms.
- **Clips that need a trending sound added by hand** ("needs your sound") are not auto-posted; no-music campaigns
  auto-post. Autopilot should prefer no-music output for autopilot campaigns.
- **HD bar**: masters 1080x1920 at ~12–16 Mbps, no silent upscale >~1.3x, output QC (sharpness/blockiness) is a gate.
- Accounts: everything on Upload-Post profile `default`; Solved IG/YT not created yet → blocker banner, not failure.
