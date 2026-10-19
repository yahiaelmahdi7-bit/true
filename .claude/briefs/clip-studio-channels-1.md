BUILD — "My channels + niche trends" (ENGINE ONLY, clip-studio main via your worktree). The Swift screens come in a later
pass after the redesign branch merges; your job is the data + a stable JSON contract they will read.

Yahia (verbatim): "for home and trending tab and live need work they look like the free yt recommend ones whioch is a bunch
of slop we dont wnat or watch". Asked what should replace it, he picked: MY CHANNELS + NICHE TRENDS — channels we can
actually clip (streamers behind joined campaigns + channels that granted rights, e.g. designedbymalik), plus a SMALL trending
section filtered to the niches of joined campaigns (e.g. Dead by Daylight, trading). No generic trending anywhere by default.

Why it's slop today (read these first): discover.py youtube() keyless = yt-dlp search for "live" sorted by viewers; twitch()/
kick() = global top streams; cmd_trends = Google Trends RSS, unfiltered. Nothing is filtered by what we clip.

## Build (engine/clipengine/, additive only)
1. `my-channels [--live] [--refresh] --json` → event "my_channels": one row per (platform, handle), deduped, union of
   - channel_rights grants (channelfeed.grants) → why "rights", pay note from the grant;
   - streamers matched to JOINED campaigns (streamers.board / match_campaign) and channel links in joined campaigns'
     source_links / rules.sources_allowlist (streamers.campaign_sources) → why "campaign:<name>", pay = that campaign's rate.
   Row: platform, handle, name, url, why[], pay{rate_per_1k|null, note}, live{state live|offline|needs_key|unknown, title,
   category, viewers, since, thumbnail, avatar} via streamers.live_status (existing cache/TTL), library{sources, moments,
   last_moment_at} from our own tables, recording (bool, from live.py/liveboard state), niches[]. --live = live rows only.
   Twitch keys are NOT set on this Mac → add a keyless fallback for live status of these specific handles only:
   `yt-dlp -J https://www.twitch.tv/<handle>` (live → title/viewers/thumbnail; "not currently live" error → offline). Status
   "ok_keyless" so the UI can say so. Never a global keyless crawl.
2. Niches: `niches --json` (+ `niches pin <name>` / `niches unpin <name>` stored in settings). Derive a short normalized list
   from joined campaigns (campaigns.category first, then name/rules text) + our channels' recent live/clip categories (e.g.
   Twitch game "Dead by Daylight"). Rule-first; Jev (clipengine/jev.py) only when a campaign has no category — cache the result
   (additive table or column), never re-ask per run. Each niche: name, query terms, platform category ids when known, from[].
3. `discover --niche` (becomes the default when ≥1 niche exists; old behaviour stays behind `discover --all`): per niche —
   Twitch streams by game (Helix games?name= → streams?game_id=) when keys exist else needs_key; Kick by category when keys
   exist; YouTube keyless = yt-dlp search with the niche's query + live filter. Google Trends topics: keep only topics that
   match a niche term, drop the rest. Hard caps: ≤8 items per niche, ≤2 per channel, drop anything with no niche match.
   Every item carries niche + why ("Dead by Daylight · 12.4k watching"). Our own channels are excluded here (they live in 1).
4. Tests with recorded fixtures (no network in tests): dedupe/union, why/pay, keyless twitch parse (live + offline), niche
   derivation (category, text, Jev-cached path stubbed), niche filter + caps, trends filter, --all unchanged.
5. docs/channels.md: the exact JSON contracts of my_channels / niches / discover --niche for the Swift pass + screen notes:
   Home = "Your channels" row (live first) + "Trending in your niches" row (≤8); Discover = your channels on top, niche trends
   below with niche chips; Live = grid of your channels (live dot, recording, chat velocity), empty state "None of your
   channels are live".

## Rules
- Sandbox only: export CLIPSTUDIO_HOME=<worktree>/.sandbox, seed it with `sqlite3 "$HOME/Library/Application Support/ClipStudio/
  library.sqlite" ".backup <sandbox>/library.sqlite"`. clipengine db() MIGRATES on open — the real library must never be
  opened by your code or scripts. Earlier today a builder wiped the real library this way. Check its mtime before and after.
- Proof: run my-channels and niches against the sandbox copy (real campaigns + Malik's channel) and paste the JSON in result.
- Gates: full `pytest -q tests` from engine/ (it was 652 passed on main at e0db83d). Commit on your branch; no push, no merge,
  no Swift (Sources/) changes, no launchctl, no relaunching any app.
