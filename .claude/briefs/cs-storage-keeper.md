# cs-storage-keeper — never run out of disk; keep what matters, clear what regenerates (Yahia 2026-10-14)

You are in a builder worktree of ~/Projects/clip-studio (from main 2ed2b39). Engine: engine/clipengine (APP_SUPPORT in common.py:4).

## Measured 2026-10-14 16:50 (re-measure yourself; don't trust blindly)
- Disk: 926 GB, **63 GB free**.
- ~/Library/Application Support/ClipStudio = 61 GB: media/downloads 32 GB (4K source episodes, 3840x2160), media/live 13 GB (find out what this is), media/backgrounds 11 GB, media/clips 2.6 GB, maskcache 1.7 GB, edits 317 MB.
- User temp dir (`getconf DARWIN_USER_TEMP_DIR`) = 78 GB, 24,256 entries, all < 2.3 days old: edit* 4.2 GB/133, tmp* 4.1 GB/827, clipstudio-test* 2.8 GB/392, mix* 1.7 GB, remotion-webpack 1.5 GB, gn-calls 1.4 GB, chk* 1.1 GB, clipstudio-school 1.1 GB, djA/djB 2.1 GB (Timbre — not ours, report only), many more small groups (find where the rest of the 78 GB is).
- /private/tmp = 33 GB of old sandbox/proof homes: cs-regress 10G, cs-sbx 3.7G, cs-proof-2 2.4G, cs-ab 1.6G, cs-t3 1.4G, p12 1.1G, cs-p11, qcw, csbox, … (some may belong to RUNNING builders: cs-wide-proof, cs-trends-home, etc.).
- ~/Projects/clip-studio.builders 27 GB, ~/Projects/true.builders 28 GB (worktrees; most branches merged + acked). ~/Library/Caches 20 GB, ~/Library/Developer 11 GB.

## Build: `clip storage` (engine module storage.py + CLI) — plan / apply / report
1. **Free-space floor.** config `storage.floor_gb` (default 50) and `storage.hard_gb` (default 25). Before every download, render and campaign run: if free < floor → run the safe cleanup tier; if still < hard → refuse to start the job, emit a plain-English needs-you event ("Disk almost full — N GB free; cleared X GB; need Y more"), autopilot holds instead of crashing mid-render. Wire this into ingest/download, render_moment, campaign_run, autopilot tick.
2. **Library retention** (each a rule with a reason string; all configurable):
   - Source episodes: delete the VIDEO (keep transcript, analysis, words, URL) when its campaign ended, OR 7 days after its last cut with no un-cut moments above bar. Re-download on demand by URL (yt-dlp) when a later cut needs it — implement that path and test it. Never delete a source a running job holds.
   - Clips: posted → keep the mp4 35 days after post (30-day keep-live + payout ticket), then delete the video, keep thumb + metadata row. Rejected/discarded/QA-failed renders and .stage/.part leftovers → 3 days. Ready-but-unposted → keep.
   - maskcache LRU cap 2 GB; edits/ older than 30 days and not open; media/live + backgrounds: find what they are, propose a rule, apply only if clearly regenerable.
3. **Temp hygiene.** One engine-owned temp root (APP_SUPPORT/tmp or $TMPDIR/clipstudio/) for every mkdtemp/NamedTemporaryFile in the engine; cleanup in finally; a sweeper removes entries older than 6 h whose owner pid is dead. Fix the leaks you find (grep mkdtemp/TemporaryDirectory/tempfile across engine + tests; tests must use pytest tmp_path). Sweep the user temp dir ONLY for prefixes our code creates (verify each prefix in code before listing it), older than 12 h.
4. **Dev-machine hygiene** as a separate script `~/.claude/bin/disk-keeper` (plan/apply, same output format): remove worktrees of builders that are acked AND whose branch is merged into the repo's main (`git worktree remove`, KEEP the branch; never `builder gc` — it is global); remove /private/tmp sandbox homes (cs-*, csbox, qcw, p1*, …) older than 24 h that no running process references (check `ps`/`lsof` + `builder status` cwd's in ~/Projects/clip-studio, ~/Projects/true, ~/Projects/clipping-site, ~/Prism). Caches/DerivedData/Timbre dj*: report only.
5. **Every delete is plan-first.** `plan` prints a table (path, size, rule, reason); `apply` deletes exactly the planned set (re-check each item right before deleting), logs to ~/Library/Logs/ClipStudio/storage.log. Never touch: library.sqlite / *.db, backups/, models/, playbook/, campaigns/, fingerprints, anything modified in the last hour, any file open by a process.
6. **Daily run**: user LaunchAgent (no sudo) running the safe tier daily + whenever the floor trips; report line (free GB, cleared GB, biggest folders) into the daily digest/events. Do NOT install it on the real machine — give the one command.

## Proof
- Run `plan` against the REAL library and real temp dirs READ-ONLY and save the output to docs/proof/storage/PLAN-real.txt (sizes per rule, total reclaimable). Do NOT run apply on real data.
- Run apply in a sandbox CLIPSTUDIO_HOME built from copies/fixtures, including: a source deleted then re-downloaded for a new cut (use a short public test clip or a fixture), a posted clip kept at day 34 and removed at day 36, floor trip refusing a render with the needs-you event.
- Full suite: `cd engine && env -u CLIP_PIPELINE ~/Projects/clip-studio/engine/.venv/bin/python -m pytest -q -p no:cacheprovider` (baseline 1296 passed / 3 skipped) + new tests. Commit on your branch. docs/storage.md in plain English.

## Rules
- Don't delete anything real. Don't touch main, push, post, submit, flip post.golive / autopilot.pause, or install launch agents.
- Done = plan output on real data with GB per rule, sandbox apply proven, tests green, REPORT in docs/proof/storage/REPORT.md with the exact commands to apply.
