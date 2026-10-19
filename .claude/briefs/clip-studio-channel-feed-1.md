# Clip Studio — channel feed: daily pull of the creator's newest + most-viewed videos AND Shorts

GOAL (one sentence): every joined campaign keeps itself stocked from the creator's own allowlisted channel — newest and
most-viewed long videos as sources, top-viewed Shorts as proof of what works (and as footage when rules allow) — via a
daily refresh before the first post slot.

## Context (do not re-derive)
- Repo ~/Projects/clip-studio, engine in engine/clipengine (Python). You are in a worktree. Tests:
  `PYTHONPATH=. ~/Projects/clip-studio/engine/.venv/bin/python -m pytest -q` from the worktree's engine/.
- What exists (onboard.py): one-time at onboarding only. `source_entries` (:224) lists allowlisted channel links flat via
  `x.cli("youtube-info", url, "--playlist")` → latest = <channel>/videos, popular = <channel>/videos?view=0&sort=p.
  `pick_sources` (:206) keeps LONG-FORM only (LONG_MIN_S 600 … LONG_MAX_S 5400, :12): ONBOARD_LATEST 2 + ONBOARD_POPULAR 1;
  `more_sources` backfills; `stage_sources` downloads with `--rights campaign`, checks `cp.url_allowed(url, allowlist)`,
  then transcribe → signals → moments --top 12; caps MAX_SOURCES 8, DRAFTS_TOTAL 6, MOMENT_FLOOR 0.48.
- Sources are bound to campaigns (sources.campaign_id; bind.py). Campaign rules JSON lives on the campaign row
  (`rules`, with `sources_allowlist`); rules parsing in campaigns.py (no repost/reupload rule exists today).
- Slot routine: slot.py (`slot-run`, `slot-install` writes ~/Library/LaunchAgents/com.clipstudio.slot.plist; 12:00/16:30/21:00).
  Live install runs from ~/Projects/clip-studio.live — DO NOT touch .live or any LaunchAgent.

## Settled by Yahia — implement exactly
1. Shorts: ALWAYS use the creator's top-viewed Shorts as PROOF (find the same moment in their long video and cut our
   own version); ALSO re-edit the Short itself as footage ONLY when the campaign's rules allow reposting/reuploading the
   creator's existing Shorts. Unknown/unclear rule = NOT allowed (proof only) + an amber flag for Yahia.
2. Refresh = DAILY, before the 12:00 slot (schedule 11:00), max 3 NEW sources per campaign per day.

## Build
A. Listing: extend source_entries to also list <channel>/shorts (newest) and <channel>/shorts?view=0&sort=p (most viewed)
   — flat, no download; keep view_count + upload date when the listing gives them. Pure ranking functions, unit-tested
   with fixture listings: long-form = newest first, then most-viewed not yet in library; Shorts = most-viewed first.
   Never re-ingest a URL already in sources (dedup by video id, also across campaigns).
B. Repost rule: new rules field `reuse_creator_shorts: true|false|null`. Deciding it from the campaign rules text is a
   CLASSIFY step → Jev noul through the existing clipengine/jev.py (code owns the flow, Jev answers "does this text allow
   reposting/reuploading the creator's existing short-form clips?"; route on confidence; log the decision). Below the
   confidence floor or no text → null → treated as false + amber flag. No keyword lists, no LLM prompt-and-parse.
C. Proof path (always): download the top N (=3) Shorts not yet used, transcribe, then align each Short's transcript to the
   bound long videos' transcripts (deterministic text alignment, e.g. normalized word n-gram / sequence match; no LLM).
   Match → store `proof` on the matching long-video moment (short url, short views, match score) and give it a ranking boost
   through the existing moment scoring path (a stored, explainable signal — not a magic constant in many places).
   If the Short's source long video isn't in the library but is on the allowed channel, it becomes the #1 candidate for
   that day's 3 new sources. Shorts used only as proof are stored with a role that keeps them OUT of the editable
   moments/queue (they must never be posted as-is).
D. Footage path (only when reuse_creator_shorts is true): the Short becomes a source with role `creator_short`; it goes
   through the normal edit room (our captions + style pack) — never posted raw.
E. Command `channel-refresh [--campaign ID] [--max-new 3] [--dry-run]`: for each JOINED campaign (skip watching/blocked),
   run A–D within the cap, print one JSON event per action + a summary (new sources, proofs matched, shorts as footage,
   flags). Respect url_allowed on every URL. Dry run = list what it would do, write nothing.
F. Schedule: `refresh-install [--apply]` mirroring slot-install (label com.clipstudio.refresh, 11:00 daily, same python /
   PYTHONPATH pattern, log ~/Library/Logs/ClipStudio-refresh.log). Default prints the plist; DO NOT run --apply and do not
   launchctl anything — Yahia approves installs.
G. App: nothing required. If AppModel already lists sources, the new ones just appear. Do not touch Sources/ (another
   builder is redesigning the Swift UI).

## PROOF (decides done)
- Unit tests for ranking, dedup, alignment (a fixture Short transcript that matches a span of a fixture long transcript →
  correct moment boosted; a non-matching one → no proof), the repost rule routing (Jev mocked: allow / deny / low
  confidence → null), the cap, joined-only, url_allowed rejection, proof-only shorts never queued.
- One LIVE dry run against a COPY of the real library: `T=$(mktemp -d); sqlite3 "$HOME/Library/Application Support/ClipStudio/library.sqlite" ".backup $T/library.sqlite"`
  then `CLIPSTUDIO_HOME=$T python -m clipengine channel-refresh --dry-run` (network listing is fine; no downloads in dry run).
  Paste the summary: per campaign, what it would ingest (titles, views, newest/popular/short-proof), and the repost verdict.
  Then ONE real (non-dry) run on that COPY for a single campaign with --max-new 1 to prove download → transcribe → proof
  match works end to end; paste the events. NEVER point at the real library dir (the engine migrates schema on open).
- Gates: full pytest green (paste tail). No Sources/ diffs.

DISCIPLINE (non-negotiable):
- Lane: ONLY engine/ (clipengine, tests) + docs/ in your worktree branch. Do not touch Sources/, .live, LaunchAgents.
- Commits: atomic, one logical change per commit, message says what+why. NEVER push, NEVER merge, NEVER 'ship'.
- Gates: FOREGROUND only. NO background shells, watch modes, until-loops. Kill anything you started.
- Claims: 'done' = gate output pasted + the live dry-run summary pasted. Never report a state you didn't verify.
- Decisions: classify/route/gate/rank steps = Jev calls via clipengine/jev.py (as in B). No keyword lists.
- If blocked or idle: say BLOCKED/IDLE + one line why. Do not invent extra scope.

## Report
Files changed · dry-run summary per campaign · the one real ingest's events · pytest tail · what's NOT done.
