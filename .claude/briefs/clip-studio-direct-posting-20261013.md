# Clip Studio: direct posting — own publishers for Instagram, YouTube, TikTok (engine side)

First read and follow ~/.claude/skills/dispatch-brief/SKILL.md. Repo ~/Projects/clip-studio (you are in your own worktree/branch).
Engine venv only in main checkout: from the worktree's engine/ run `PYTHONPATH=. ~/Projects/clip-studio/engine/.venv/bin/python -m pytest -q`.
No push, no merge, never relaunch ClipStudio.app, real library read-only (`sqlite3 "file:...?mode=ro"`; tests use fixtures/tmp copies).
NO live network calls to Meta / Google / TikTok (no apps or tokens exist yet; mock HTTP in tests). Never post, queue or submit for real.
NEVER change or bypass the go-live gate (publish.py ~line 169, `post.golive`); it must gate the direct path exactly like Upload-Post.
Write result.md EARLY and extend it as you go. Builder self-reports get re-checked: paste real gate tails, not summaries.

## Yahia's ask (2026-10-13, verbatim)
"can we use our own infra and setup to post the content as i dont want to rely on upload third party" -> "go direct posting"
DECIDED: per-platform direct publishers; Upload-Post stays as the per-platform fallback until each platform approves our app.
No browser-automation posting, ever (ToS / bans). No third-party media host: the video goes straight from this Mac to the platform.

## Scope (engine/Python only — a parallel builder owns the Swift "Accounts" tab and the `accounts` table: do NOT ALTER `accounts`,
## do NOT touch Swift, Keys.swift, or the app UI)
1. `engine/clipengine/publishers/` — `instagram.py`, `youtube.py`, `tiktok.py`, plus a small common interface
   (`publish(video_path, caption/title, options) -> {platform_post_id, url, status}`, `status(post_id)`).
2. Router in publish.py: setting `post.provider.<platform>` = `uploadpost` (default, current behaviour unchanged) | `direct`.
   Mixed per post is allowed (e.g. IG direct, TikTok via Upload-Post). Record results in the SAME tables/shape the existing post
   tracker reads, so nothing downstream changes. Existing Upload-Post tests must stay green untouched.
3. OAuth + tokens: `clipengine auth <platform> [--account <accounts.id>]` CLI. App credentials (client id/secret) and user tokens
   live ONLY in the macOS Keychain via `/usr/bin/security` (services `ClipStudio.oauthapp` account=<platform>, and
   `ClipStudio.oauth` account=<platform>:<accounts.id>). Never in SQLite, logs, run records, result.md or exceptions — redact.
   Non-secret link state (external user id, handle, scopes, expires_at, status) goes in a NEW table `platform_auth`
   (CREATE TABLE IF NOT EXISTS; re-run is a no-op). Refresh tokens automatically before expiry.
   Redirects: use a loopback listener (http://127.0.0.1:<port>/cb + PKCE) where the platform allows it; where it demands a
   registered https URL, support "paste the URL you landed on" (parse code+state, verify state). Report which platform needs which.
4. Platform flows — CONFIRM every endpoint, field, limit and scope against the official docs (WebFetch / context7) before coding,
   and cite the URLs in docs/posting/DIRECT.md. Starting points, not facts:
   - Instagram (Instagram API with Instagram Login, Professional account): create a REELS container with `upload_type=resumable`,
     upload the file bytes to rupload.facebook.com, poll the container `status_code` until FINISHED, then `media_publish`.
     Check the 24 h publishing limit endpoint first.
   - YouTube Data API v3: resumable `videos.insert` (scope youtube.upload), Shorts by duration/aspect. Unverified projects get
     uploads forced private until the audit passes — detect and surface that as status `locked_private`, never as success.
   - TikTok Content Posting API (Direct Post, scope video.publish): `creator_info/query` -> `video/init` (FILE_UPLOAD, chunked
     PUT to upload_url) -> poll `status/fetch`. Unaudited apps can only post SELF_ONLY: surface `private_until_audit`.
5. `clipengine publish --dry-run` with a direct provider prints the exact request sequence (tokens redacted) without sending.

## Deliverable docs: docs/posting/DIRECT.md
For each platform, the exact setup Yahia/Claude must do in the platform's developer console: what to create, product/use case to
add, scopes, redirect URIs to register, test-user/tester steps, what review/audit is needed, what it unlocks, typical wait, and
the account type needed (e.g. IG Professional). Also the TikTok Direct Post UX requirements the audit checks (creator nickname
shown, privacy picker without a default, interaction toggles, content disclosure, consent text) as a checklist for the UI phase.

## Gates (run them yourself, paste the tails into result.md)
Full engine pytest green, including new table-driven tests per platform with mocked HTTP: happy path, token expired -> refresh,
container/processing failure, rate-limit/quota response, YouTube locked_private, TikTok private_until_audit, go-live gate off ->
nothing sent, secrets never appear in any captured log/record (assert on it). Migration test on a tmp COPY of the real library.
Commit on your branch only: code, tests, docs/posting/DIRECT.md, result.md.
