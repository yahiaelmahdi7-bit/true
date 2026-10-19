# Clip Studio quality fix1 — what the drafts get wrong (reviewer LOOKED at PB Blake onboarding drafts + Kumar cards)

Repo ~/Projects/clip-studio (main = 566a09d, all of scout/onboard/Kumar/playbook/auto-submit/e2e merged). Engine tests:
`PYTHONPATH=. ~/Projects/clip-studio/engine/.venv/bin/python -m pytest -q` from the worktree's engine/. Another builder is fixing
publish/queue/campaign-rules wiring at the same time (queue.py, publish.py, campaigns.py, ingest.py, spend ceiling) — stay out of
those files except where an item below names them. Each item: fix + test + one line in result.md. Tmp library/home only.

1. IRRELEVANT B-ROLL. Draft edit_281fc32896 (finance/trading clip) cuts to a steak-and-potatoes cooking shot. Before any b-roll
   shot is placed, gate it: Jev noul "is this shot about the same subject as the spoken line it covers?" with state = shot tags/
   caption + the spoken words under it + clip topic. Below floor → pick the next candidate, else no b-roll there. Log each
   decision (shot, line, p). Test with a fixture where a food shot is offered for a trading line.
2. HOOK TEXT REQUIRED WHEN THE CAMPAIGN STYLE HAS IT. PB Blake's approved style has a hook title; drafts mix hook / no hook
   (edit_d9ecd5745a has none; Jev picked preset D/E → empty top band). If the campaign's edit_style or learned style pack has hook
   text, only presets with a hook may be picked (pick_preset filter), and render refuses a hookless EDL for that campaign. Test.
3. PB BLAKE NEEDS A HUMAN EDIT. Yahia edits every PB clip by hand: add per-campaign flag `requires_manual_edit` (PB Blake = on).
   approve_edit refuses until an Edit Room edit by a human exists for that edit (record who/when). Gate it at approve AND at the
   publish/queue entry (last step before output). App: show "needs your edit" instead of Approve. Test both refusals.
4. PROFANITY. edit_d9ecd5745a captions "IN THE FUCKING" uncensored. If campaign rules mention profanity / brand-safe / no
   swearing → mask captions (F***ING) and duck nothing else; otherwise keep it but add a QC flag "profanity in captions" shown at
   approval. Word list in one place. Test both paths.
5. ACCOUNT KIT applies campaign account rules: PB Blake display name contains "PB Blake", bio contains
   https://www.youtube.com/@PBBlakeYT, avatar = PB Blake asset. Every account maps to Upload-Post profile `default` (one profile,
   many platforms), NOT one profile per account. Kit marks each rule pass/fail. Test with PB Blake rules.
6. ONBOARDING YIELD = 6 DRAFTS. PB proof gave 5 (3 sources → 4 mined moments over floor). Keep adding sources (popular, then latest)
   until >= 6 moments over MOMENT_FLOOR or cap 8 sources / quota budget; record why if it stops short. (The 3/day cap logic
   belongs to the other builder — don't edit cap_left.)
7. DEPTH CARDS DROP WORDS. cards.txt wide: "unprofitable trader I've" → UNPROFITABLE / TRADER ("I've" vanished). No spoken word
   may disappear: words after the carrying word go to the next card's label or the front caption for that chunk. Test asserts
   every transcript word appears on screen exactly once across cards + front captions. Number cards ("$2,000") with any digit or
   separator occluded by the head → place front instead (reason "number_occluded").
8. SCOUT fan_edit GATE C: vision check on 3 frames per candidate; reject memes, screen recordings, plain movie scenes with no edit
   grammar. Gate B accepted 3/6 junk. Calibrate on the existing accepted/rejected set, log the table.
9. NITS: auto-submit tests write docs/proof/submit/happy.png from two tests (watched test overwrites it) → distinct names.
   Add `agentmail` to the common.py key table (Keychain service app.clipstudio, account agentmail; key is INBOX-SCOPED: only
   /v0/inboxes/eliteclipperzzz@agentmail.to/messages works, /v0/inboxes is 403). Never print the key.

Proof (LOOK before claiming): re-run PB Blake onboarding from scratch in a tmp home → 6 drafts; contact sheet for each; state for
each draft: hook present, b-roll decisions, profanity flag, approve blocked until manual edit. Re-render the Kumar wide proof and
show cards.txt word-coverage check. Commit on the builder branch only; never push; never touch the real library, lab home or
ClipStudio.app; nothing posts or approves.
