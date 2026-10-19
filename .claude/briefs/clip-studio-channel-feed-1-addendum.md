ADDENDUM — resume the SAME build (your worktree + commits stay). Read your original brief
/Users/y/Projects/true/.claude/briefs/clip-studio-channel-feed-1.md again, finish it, AND add Twitch Clips:

Yahia (verbatim): "https://www.twitch.tv/designedbymalik/clip/CourageousDeadHamCurseLit-ONMt2RAMPYFxYgS8 this is a clip i want
to edit and setup can we grab them from his clips tab". His earlier "clips ... from viewers based on top views and most recent"
meant TWITCH VIEWER CLIPS (the channel's Clips tab), not only YouTube Shorts.

Verified (engine .venv yt-dlp): single clip -> extractor twitch:clips, 60 s, 1080p, view_count, timestamp. Channel tab
`https://www.twitch.tv/<slug>/clips?filter=clips&range=all|30d|7d|24hr` -> extractor twitch:videos:clips, flat entries with
title, view_count, duration, sorted by views.

Add:
T1. Twitch channels (allowlisted twitch.tv/<slug>, or a channel registered by Yahia with a rights record) are listed too:
    TOP = range=all and range=30d sorted by views; RECENT = range=7d (and 24hr) sorted by timestamp (fetch timestamps for
    the top ~20 of each list if the flat listing lacks them). Same daily refresh, same cap (3 new per campaign/channel/day),
    dedup by clip slug.
T2. Twitch clips are viewer-made cuts of the creator's own stream = FOOTAGE (role `twitch_clip`), allowed when the channel
    is allowlisted by the campaign OR has a recorded rights grant. Rights grant store: `channel-rights add <url> --rights
    licensed --note "..."` (table channel_rights). Seed nothing automatically. Yahia's grant for designedbymalik: rights
    licensed, note "designedbymalik (Malik) gave Yahia permission to edit and post his Twitch stream clips; recorded 2026-10-12"
    — implement the command, do NOT run it on the real library (Yahia/the orchestrator will).
T3. A short clip (<= 90 s) is ALREADY a moment: do not run the long-form moment finder on it. Create one moment spanning the
    clip, trimmed of leading/trailing dead air (silencedetect), status shown (not below the bar), hook from its title +
    transcript, and let the edit room handle it. (Observed: running `moments` on this 60 s clip gave 1 candidate at 0.512 that
    fell below the bar and 2 dropped as dead air — wrong behaviour for a pre-cut clip.)
T4. `ingest` currently labels Twitch clips kind="youtube" — give them kind "twitch_clip".
PROOF additions: listing dry run for twitch.tv/designedbymalik (top + recent, titles/views/dates) on the COPY; one real ingest
of one top clip on the COPY -> one shown moment spanning it; tests for T1-T4.
