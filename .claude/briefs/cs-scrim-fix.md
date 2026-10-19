# Brief: caption_readability box lands over a head in STACK layouts (bug fix)

Repo ~/Projects/clip-studio, your worktree is branched from main (dbcf97b). Python: ~/Projects/clip-studio/engine/.venv/bin/python. Tests: `cd engine && env -u CLIP_PIPELINE <venv python> -m pytest -q -p no:cacheprovider` (1253 passed / 2 skipped at start).

Bug (Yahia saw it in the A/B reel): with CLIP_TOOLS_EXTRA=caption_readability on a two-person STACK clip (mom_0185f2fcd1, about 15-20 s in), a semi-transparent grey box is drawn in the LOWER panel over the guest's head, at roughly 0.68 of the frame height. The caption it is meant to back ("a lucky") sits at the stack SEAM, about 0.5 of the frame height, with no box behind it. Likely cause: engine/clipengine/tools2/caption_readability.py samples and places the box using the default caption BAND (band_region / BAND constants) instead of where the caption card actually renders when the layout moves captions to the seam. The earlier "slab over head in stack" fix only covered depth-caption docs. Confirm the real cause before you change anything.

Fix: the box (and the background sampling that decides whether a box is needed) must use the card's REAL rendered rect for every layout (stack seam, card, crop, fit). It must never be drawn where no caption is showing, and never over a face (reuse the face boxes the layout already has). If the outline ring (main now gives every caption contrast >= 4.5) already makes a seam caption readable, no box is needed.

Proof: render mom_0185f2fcd1 in a sandbox (copy /tmp/cs-tune-home to a fresh dir and point CLIPSTUDIO_HOME at it; NEVER the real home) with CLIP_PIPELINE=v2 CLIP_VERIFY=1 CLIP_TOOLS_EXTRA=caption_readability,reaction_detector,pacing_check, before and after your fix. Save frames at 15, 16, 17, 18 s side by side to docs/proof/scrim-fix/before_after.png. Add a unit test: stack doc, seam caption -> box rect overlaps the caption rect and does not overlap the lower face box.

DISCIPLINE: only this worktree. Atomic commits (what+why). NEVER push/merge. Tests in the foreground, no background shells. 'Done' = full test tail pasted + the png made. Never post, flip post.golive, unpause autopilot, or touch the real library/home. macOS has no `timeout`. Kill any render after 15 min.
Report: root cause in one line, the fix, test tail, png path.
