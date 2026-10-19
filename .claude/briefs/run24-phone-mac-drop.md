# Brief: Run 24 — Phone ↔ Mac drop (files, photos, clipboard over True's web pipe)

Worktree. Do NOT push, do NOT launch True.app, do NOT run `tailscale` commands, never read `.claude/heldout/`.
Lane: `Sources/True/` (Remote/, Model/, Views/ where the Shots tray and menus live), `Tests/`, `Resources/Remote/`,
`SPEC.md`, `docs/kb/`. Gate = docs/kb/conventions.md:5-9 exactly; weaken no test. No result.md in repo.

Yahia picked this so True works across his devices: "make it truly an omni tool working across devices".
Read SPEC.md "True on the web — phase 1 (Run 22)" + "Run 17"/"Shots overlay (Run 18)" first: auth, tray contract,
Downloads strip. Every rule there still holds (identity header, exact Host, exact Origin, bearer, headers, caps).

## Build
1. **Phone → Mac, files.** Web app gets a bottom tab bar: **Panes · Shots · Send**. Send screen: big "Send to Mac"
   button (`<input type=file multiple>` → Photos, camera, Files) with per-file progress, and a text box
   "Send to Mac clipboard". `POST /api/drop` — raw body, filename in `X-Filename` (percent-encoded). Body cap
   **200 MB for this route only** (other routes keep their caps), streamed to a temp file, 120 s body deadline,
   413 when too big, 507 when the disk has < 1 GB free.
   - Images (UTType conforms to `public.image`, raster only: png jpeg heic heif gif webp tiff) → `TrayStore.ingest`
     (24-cap applies, unseen dot shows). Everything else → `~/Downloads/` (so the Downloads strip lists it).
   - Filename: last path component only, strip `/ : \` control chars and leading dots, ≤ 120 chars, empty →
     `iPhone-<date>`; never overwrite (`name-2.ext`). Set `com.apple.quarantine` on files written to Downloads.
   - Mac toast: "Received <name> from iPhone". Never open or execute anything received.
2. **Phone → Mac, clipboard.** `POST /api/clip {"text"}` (≤ 256 KB) → NSPasteboard; toast "Clipboard from iPhone".
3. **Mac → phone, Shots.** Shots screen: grid of the tray (newest first). `GET /api/shots` (id, created, kind, w, h)
   and `GET /api/shots/<id>` — `id` must match `^\d{8}-\d{6}-[0-9a-f]{4}$` AND exist in index.json; never accept a
   path. Tap → full view with **Share** (`navigator.share({files})` → Save Image / AirDrop) and Save.
4. **Mac → phone, Send to Phone (push only).** "Send to Phone" in the Shots overlay viewer toolbar, the tray zoom
   toolbar and each Downloads row, plus Shell ▸ "Send Clipboard to Phone". These add to a **phone inbox**
   (`~/Library/Application Support/True/RemoteInbox/`, dir 0700, files 0600, max 20 items, 24 h expiry, copies not
   links). `GET /api/inbox`, `GET /api/inbox/<id>`, `DELETE /api/inbox/<id>`. Send screen shows the inbox on top;
   text items get a Copy button. Phone polls every 5 s only while visible (+ on `visibilitychange`). **There is no
   route that reads the Mac clipboard or any Mac path** — the phone only sees what the Mac pushed or the tray.
5. **File responses can't run script.** Raster images: correct image Content-Type. Everything else (incl. SVG, HTML,
   PDF): `application/octet-stream` + `Content-Disposition: attachment`. All file responses add
   `Content-Security-Policy: sandbox` on top of the usual headers.
6. **iOS share sheet via Shortcuts** (Safari has no Web Share Target). Remote Access sheet → "iPhone Shortcut" section:
   "Create Shortcut token" makes a paired device named "Shortcut" (revocable like any device), shows the token once
   with Copy, and short steps: Shortcut → Show in Share Sheet → Get Contents of URL `https://<dns>:8444/api/drop`,
   POST, header `Authorization: Bearer <token>`, header `X-Filename` = Name, body File = Shortcut Input.
   Server: on `/api/drop` and `/api/clip` ONLY, a request with **no Origin header** is allowed when the bearer is
   valid (browsers always send Origin on POST; a bearer token isn't ambient, so no CSRF). A present Origin must
   still be exact. Identity header + exact Host still required everywhere.

## Design bar
Read `~/.claude/skills/taste/SKILL.md` first and say so. Phone-first, 44 pt targets, same look as phase 1.

## Tests (no app launch)
Filename sanitizer (traversal `../../x`, `/etc/passwd`, `.hidden`, unicode, 300 chars, empty), no-overwrite naming,
200 MB cap → 413, body deadline, image-vs-file routing, quarantine xattr set, shot id regex + not-in-index → 404,
inbox cap/expiry/0600, no Origin + valid bearer accepted only on /api/drop and /api/clip (403 elsewhere), bad bearer
→ 401, SVG/HTML served as attachment octet-stream with `sandbox` CSP, clip size cap, no route returns the Mac
clipboard (assert the route table). Update SPEC.md (new section) + docs/kb/remote-access.md threat model.

## Final answer
Files, tests, gate tail, the exact Shortcut steps as Yahia will see them, and a phone eyeball checklist.
