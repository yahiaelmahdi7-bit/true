# Brief: OpenChatCut bake-off — can a prompt-taught OpenChatCut edit clips better than our pipeline?

Yahia (2026-10-14): "we can use OpenChatCut https://github.com/0xsline/OpenChatCut and you guide it by teaching it in prompts the cuts we need and edits."
OpenChatCut = AGPL-3.0, TypeScript/Electron/React/Remotion, agent-native editor with MCP + transcript-driven editing.

## Constraints (hard)
- AGPL: use it ONLY as a separate local tool driven over its MCP/CLI. Never copy its code into ~/Projects/clip-studio or ~/Projects/true. Clip Studio may only call it as an external process.
- Install in ~/Projects/openchatcut (clone pinned to a commit; record the sha). BEFORE any npm/pnpm install: read package.json + every pre/post-install script + any downloaded binaries/scripts; report anything that phones home, needs accounts/keys, or runs remote code. If a step needs a paid API key or login, stop that path and report it (don't sign up for anything).
- Never post/submit anything; never touch ~/Library/Application Support/ClipStudio (use a sandbox home: copy /tmp/cs-tune-home library.sqlite + playbook, symlink models + media).

## Steps
1. Clone, audit, install, launch; find its MCP server / agent-tool API (tool names, project format, how media + transcript go in, how export comes out). Smoke test: import one source, make a 1-cut edit via MCP, export an mp4.
2. Teaching prompt: wait (poll every 5 min, up to 3 h) for ~/Projects/clip-studio-research/clipfarm-course/NOTES.md (another builder is writing the Clip Farm course editing recipe). Build a reusable "clip editor system prompt" from: that recipe + Clip Studio's settled rules (9:16 1080x1920 HD, captions = only spoken words on time, big readable subtitles the whole clip, face in first seconds, NO word punch-in zooms, NO pop/boop SFX, no music on Solved, no mid-thought cuts, no ad reads). Save it as ~/Projects/openchatcut-bridge/teach/clip_editor_prompt.md.
3. Bake-off on 3 real moments from the sandbox library (e.g. mom_0185f2fcd1, mom_72e6616de2, mom_8f399fa883): give OpenChatCut the source span + word transcript + the teaching prompt, let its agent/MCP tools make the edit, export. Our side = Clip Studio render of the same moment (cd ~/Projects/clip-studio/engine; CLIP_PIPELINE=v2 CLIP_VERIFY=1 CLIP_TOOLS_EXTRA=caption_readability; render.render_moment). Same start/end.
4. Output ~/Projects/openchatcut-bridge/bakeoff/: ab.mp4 (per moment: left = Clip Studio, right = OpenChatCut, synced, played twice: left audio then right audio), REPORT.md: render time per clip, edit quality notes per pair from frames you actually viewed, what OpenChatCut did that we can't, what broke, cost (which model/API its agent needs), and a recommendation: (a) adopt as the editor behind a flag, (b) use only as a manual-edit timeline (Edit Room / PB Blake hands-on pass), (c) borrow ideas only. Include how a bridge would work (Clip Studio -> OpenChatCut MCP -> mp4 back into the queue).
5. If adopting looks right, write a minimal bridge script ~/Projects/openchatcut-bridge/bridge.py (separate repo dir, not in clip-studio) — call-only, no copied AGPL code.

Done = audit notes + smoke test result + teaching prompt + ab.mp4 + REPORT.md. Report anything you couldn't do and why.
