FIX PASS — Malik clips (same worktree/branch). Yahia watched the 3 live "clip that" clips and said (verbatim):
"this is ass it just keeps zooming into random areas when voice works even though its not malik spekaing its still doing it
also the clips fomrat still the same way the cam inst moved and the content isnt half half with face cam biggeer than the clip"

## Root causes (verified by Claude, read before coding)
- ZOOMS: live clips render via live.py `_render` → render.render_moment(..., track=False) → interrupts.plan_zooms + zoom_filter:
  a centre-crop punch-in every 2–4 s on any emphasis word in the transcript, whoever says it (teammates, game audio, the Spotify
  widget song). Built for podcast talking heads; on by default (INTERRUPTS env default "on"). editroom path has punch_in off.
- FORMAT: live.py never uses your layouts — it renders the old blur-letterbox frame. Your split proof (docs/proof/modes/
  c1_split_contact.png) also misses his ask: cam panel is ~38% / game ~62%; captions sit on his face; the hook box repeats the
  caption line with raw profanity ("why did you fuck that bro?"); the game crop lands on random slices (logo letters).

## Fix (engine only)
1. Zoom rule: NO zoom of any kind (interrupts zooms, cut-zooms, punch-ins, push-ins) on content-mode / facecam sources or on any
   layout render (split, split_bottom, card, pip). Zooms only on cam-mode talking heads, and only aimed at the speaker's face
   box (never centre-crop). Enforce in render.render_moment AND editroom; unit test: content-mode source → zero zooms in the
   filter graph even with INTERRUPTS=on.
2. Split = Yahia's format: TOP half = his facecam, cropped from the detected inset and scaled UP to fill a 1080×960 panel (face
   centred, head-room ~12%); BOTTOM half = gameplay 1080×960, centre-weighted crop of the full game frame (exclude the cam inset
   area and the Spotify/now-playing widget from the crop; never a slice of a HUD/logo). Make it the default layout for
   twitch/kick content-mode channels (layoutsel); designedbymalik → split. Thin seam, no black bars.
3. Captions: on the seam / upper part of the GAME panel, never over his face. Spoken words only (captions v3 rule), slurs
   masked as today. Hook box: only a clean short hook (≤6 words, no profanity, not a copy of the caption line); if none → no box.
4. Live path: live.py `_render` renders through the same layout path (layoutsel + templates + slur mute), still "veryfast",
   one render at a time (keep live-render.lock). Live clip latency must stay ≤120 s p90 — measure and report.

## Re-cut the 3 clips Yahia watched (proof)
Make a FRESH read-only copy of the real library into a new sandbox dir under your worktree
(`sqlite3 "file:$HOME/Library/Application Support/ClipStudio/library.sqlite?mode=ro" ".backup <wt>/.sbx-malik/library.sqlite"`),
CLIPSTUDIO_HOME=<wt>/.sbx-malik. Moments: mom_31e179fe0a (src_a6e2576a71, VOD cut), mom_0a034c34ff and mom_378058063a
(src_2860e28c3e — a LIVE recording still running until ~18:16, pid 83292: read its media, never touch the process or its
files). Render all 3 in split. Copy finals to docs/proof/malik-split/<moment>.mp4 (git-ignored is fine) + contact sheets
(4 stills each) + measure: zoom count in filter graph = 0, face in top panel ≥90% of sampled frames, captions never overlap
the face box, cam:game = 50:50. READ your contact sheets; if anything still looks off, fix and re-render before finishing.

## Gates
Full pytest green (file by file fine). Commit on your branch; no push/merge to main; never write the real library; never quit
or relaunch ClipStudio.app; never touch the live recorder process.
