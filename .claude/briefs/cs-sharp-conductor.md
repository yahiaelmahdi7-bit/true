# Clip Studio — sharper clips end to end + reveal-zoom on the conductor path

Repo: ~/Projects/clip-studio (worktree off main @dac8525; gates green: engine 1056 pass/1 skip, swift 119/0, extension node 6/6).
Yahia's ask (2026-10-13, on the 4 clips in Review): "get it sharpened and better made".

## Evidence (measured 2026-10-13, real library)
The 4 ClipFarm x Solved clips (mom_9358c25556, mom_72e6616de2, mom_4dc7ab17af, mom_f900bcaca4; files in
~/Library/Application Support/ClipStudio/media/clips/) look soft. Three stacked causes:
1. SOURCE is starved: sources (solved-gMynmU0owYc.mp4, solved--rKZe8TEOik.mp4, solved-cp2X0ihF4Zg.mp4) are 1920x1080 H.264
   at ~1.1 Mbps. `yt-dlp -F` shows all three also exist at 2560x1440 (itag 400 AV1 mp4, 271 VP9 webm). The downloader at
   engine/clipengine/ingest.py:71 (cmd_youtube) uses `bv*[ext=mp4]+ba[ext=m4a]` which forces the low-bitrate avc1 stream;
   RANGE_FMT at ingest.py:109 caps at 1080 + ext=mp4. Local ffmpeg decodes AV1 (libdav1d) and VP9.
2. CROP UPSCALE: the 9:16 face crop takes ~608 px of a 1920-wide frame and stretches it 1.78x with default bicubic
   (render.py:366 `crop=...,scale={W}:{H}`; also :369). No sharpening after upscale. templates.py:287 already uses lanczos.
3. EXPORT is thin: outputs are 1.7-3.2 Mbps; render.py:286 venc defaults to crf 20; e2e.py:198 already declares the target
   as 12-16 Mbps for 1080x1920.

## Production path — fix THIS, prove on THIS
Conductor (launchd com.clipstudio.conductor) -> autopilot.cut_one (autopilot.py ~:110-140) -> agent._render (agent.py:141)
-> render.render_moment. The edit-room path (editroom.py render_edit) is a twin; keep both consistent. A fix proven only on
the agent/edit-room path does NOT count (that mistake happened before).

## Work
1. Best source: every yt-dlp call that fetches VIDEO for clipping (ingest.cmd_youtube, RANGE_FMT, and any other video
   downloader you find via grep in campaigns.py/streamsrc.py/channels.py/etc.) picks the highest resolution up to 2160p and
   highest bitrate, any codec, merged to mp4. Keep audio-only fetches as they are. CHECK the Swift app still previews
   sources: find where it plays source files (AVPlayer/AVAsset); if AV1/VP9-in-mp4 does not play on this Mac, keep the
   high-quality master for rendering and add a light H.264 preview proxy, or pick the codec it plays — measure, don't guess.
2. Source upgrade command: `python -m clipengine source-upgrade <source_id>` re-downloads an existing YouTube source at best
   quality, checks duration matches within 0.5 s (same video -> moment timestamps stay valid), swaps sources.path, keeps the
   old file as <name>.lowq.mp4 until success. Dry-run flag that prints old vs new resolution/bitrate. I run it on the live
   library after merge; you run it only in a sandbox.
3. Crop/scale: lanczos for every crop->scale in render.py (and editroom twin), then a mild sharpen ONLY when the crop is
   upscaled (ratio > 1.05), strength scaled with the ratio, no halos. Pick the filter + strength by measurement (step 6).
4. Export: hit 12-16 Mbps for 1080x1920 (crf ~17-18 with maxrate 16M / bufsize 32M, preset slow or medium if render time
   per clip stays < 2x current — report the times). One shared encoder setting, not three different ones.
5. Reveal-zoom on the conductor path: editroom.py:454 _reveal_plan (pushes in to show on-screen text the 9:16 crop drops,
   e.g. the infographic at mom_72e6616de2 ~5 s) runs today only in the edit room. Wire it into render.render_moment for
   the conductor. Plus the 3 QC gaps: (a) editroom qc_video still uses the absolute sharpness threshold -> pass the source so
   it is relative like autopilot.cut_one now is (dac8525); (b) FIT/punch layouts fall back to absolute -> make them relative
   too; (c) held_quality is final (autopilot.py:118 INSERT OR IGNORE) -> store a QC version on the held row and re-claim held
   moments when QC_VERSION increases (bump it in this lane).
6. Measure, honestly, in a SANDBOX library (`sqlite3 "<live db>" ".backup <tmp>/library.sqlite"`, CLIPSTUDIO_HOME=<tmp>,
   copy only the media you need): re-render the 4 moments old vs new from upgraded sources. Report per clip: output
   bitrate, face-region Laplacian sharpness (quality.py's measure), and the relative out/src ratio. Pick the sharpen strength
   on 2 of the clips, report the other 2 as held-out. Extract matched stills (t=1 s, 5 s, mid) old|new side by side into
   docs/lanes/sharp-conductor/ and LOOK at them: faces natural, no halos, captions crisp, mom_72e6616de2 shows the infographic.
7. Sandbox conductor proof: run one autopilot tick in the sandbox so cut_one renders a moment end to end with the new path;
   paste the events/autopilot_events rows.

## Tests + gates
Unit tests: format selector strings (no network), upscale-ratio -> sharpen decision, encoder args, reveal plan reaches
render_moment, QC version re-claim, source-upgrade duration guard (mock yt-dlp). One test MUST exercise autopilot.cut_one.
Gates (foreground): `cd engine && PYTHONPATH=$PWD ~/Projects/clip-studio/engine/.venv/bin/python -m pytest -q`, `swift test`
AT REPO ROOT, extension `node --test` if you touch it. Before every commit: `git checkout -- docs/proof/submit/happy.png;
rm -f docs/proof/submit/happy-watched-run.png`. test_inbox copies the live DB: don't assume live state in tests.
Report in docs/lanes/sharp-conductor.md: what changed, the measurement table (calibration vs held-out), stills, render
times, sandbox tick rows, verified vs NOT verified.

Rules: never flip post.golive; never write the live DB or touch ~/Projects/clip-studio.live or the main checkout (only run
its venv python); no posting; no re-download into the live media folder.

```
DISCIPLINE (non-negotiable):
- Commits: atomic, message says what+why. NEVER push, NEVER merge. The user pushes, not you.
- Gates: run in the FOREGROUND and wait. NO background shells, NO watch modes, NO until-loops.
- Claims: 'done' means you ran the gate and pasted the passing output. Code written ≠ working; a threshold is validated
  only on held-out data.
- If blocked: say BLOCKED + one line why. Do not invent extra scope.
```
