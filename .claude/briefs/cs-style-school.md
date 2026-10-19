# Clip Studio — Style School: learn 4 creator styles, render the same test clips in each, blind grade sheet

Repo ~/Projects/clip-studio (engine/, venv engine/.venv). Worktree branch only. Never merge/push, never touch installed ClipStudio.app, never change post.golive / autopilot.pause in the real library. Another builder (cs-two-speaker) is editing render.py / captions.py layouts right now: keep your code changes minimal and inside stylelearn.py / stylepack.py / vibepack.py / new files; if a pack needs a renderer feature that doesn't exist, LIST it in the README as a gap instead of building it.

## The "students" (one style each)
| id | creator | where to get refs (YouTube Shorts, public) |
|---|---|---|
| hormozi | Alex Hormozi | youtube.com/@AlexHormozi/shorts |
| jre | JRE Clips | youtube.com/@JREClips/shorts |
| flagrant | Flagrant Clips | youtube.com/@flagrantclips/shorts |
| doac | The Diary Of A CEO | youtube.com/@TheDiaryOfACEO/shorts |
Verify each channel resolves (yt-dlp --flat-playlist). If one doesn't, say so; don't substitute silently.

## Steps
1. Refs: per student, pull the 4 highest-view recent shorts (yt-dlp --flat-playlist with view_count, pick top by views from the latest ~40). Save to ~/Projects/clip-studio-refs/school/<id>/ (refs never in git; RIGHTS rule in stylelearn.py: only numbers leave the video). Record titles, urls, view counts in refs/school/<id>/refs.json.
2. Learn: `python -m clipengine edit-style-learn <video> --name <id>-<n>` on each ref, then merge into one pack per student (`edit-style-pack`) -> ~/Projects/clip-studio-refs/style-packs/<id>.json. Also write a plain-English "what this style does" (captions font/size/colour/position/animation, cut pace, zooms, layout, grade, sfx) from the measured numbers + your own look at ref stills.
3. Render: same 3 Solved moments for every student: mom_8f399fa883, mom_6ef3c64af7, mom_9358c25556. Sandbox ONLY: CLIPSTUDIO_HOME = dir with `sqlite3 .backup` copy of ~/Library/Application Support/ClipStudio/library.sqlite + symlinks to cache, models, fingerprints, media/downloads (NOT media/clips). Use the Edit Room path (edit-run / edit-render) with edit_style:cmp_6fe50dcdb4 = {"pack":"<id>","depth_captions":"all"} set in the copy. Campaign rules still apply (no music, credit, tags, face first 5s, full subtitles).
4. Self-score: `edit-style-score <render> --style <pack>` for each render = how faithfully the student copied its teacher. Report it.
5. BLIND grade sheet in docs/proof/style-school/: copy renders as S1..S4 per moment (shuffle student->letter, key in KEY.json, NOT in the README), one contact sheet per moment (3 stills each, labelled only S1..S4), README: how to grade (Yahia scores each S 1-10), and a table per student id of fidelity score + QC + gaps. Look at your stills before claiming done.

## Done =
4 packs (or honest reason one failed), 12 renders, blind sheets, README, engine tests green, commit on branch.
