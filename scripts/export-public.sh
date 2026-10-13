#!/usr/bin/env bash
# Sync the tracked source of this (private) repo into the public tree, minus anything personal or
# tied to private infrastructure. Re-runnable: it wipes and rebuilds the target's contents (keeping .git).
#   1. copy git-tracked files (working-tree versions) -> staging
#   2. delete excluded paths (Nova voice, private docs, live-model tests, real-prompt fixtures, agent config)
#   3. scrub personal strings (sed)
#   4. apply scripts/public.patch (source edits that detach the app from private services)
#   5. overlay scripts/public/ (LICENSE, README, workflows, release scripts)
# Never touches the private repo and never pushes. Usage: scripts/export-public.sh [target-dir]
set -euo pipefail
SRC="$(cd "$(dirname "$0")/.." && pwd)"
DEST="${1:-$HOME/Projects/true-public}"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

echo "==> copying tracked files from $SRC"
(cd "$SRC" && git ls-files -z) | (cd "$SRC" && rsync -a --from0 --files-from=- ./ "$STAGE/")

echo "==> deleting excluded paths"
cd "$STAGE"
rm -rf .claude .builder .playwright-mcp docs SPEC.md CLAUDE.md True.app True.app.old dist .build \
       Sources/True/Nova \
       Tests/TrueTests/Nova*.swift \
       Tests/TrueTests/CommandBarLiveTests.swift Tests/TrueTests/OverseerLiveTests.swift \
       Tests/TrueTests/WatcherLiveTests.swift \
       Tests/TrueTests/Fixtures/commandbar-labelled.json Tests/TrueTests/Fixtures/watcher-labelled.json \
       Tests/TrueTests/CommandBarFixture.swift Tests/TrueTests/WatcherFixture.swift \
       scripts/make-kit.sh scripts/export-public.sh scripts/public scripts/public.patch
find . \( -iname 'HANDOFF*' -o -name briefs -o -name heldout \) -prune -exec rm -rf {} +

echo "==> scrubbing personal strings"
# order matters: specific forms first
find . -type f \( -name '*.swift' -o -name '*.sh' -o -name '*.json' -o -name '*.html' -o -name '*.js' -o -name '*.py' -o -name '*.md' \) \
  -not -path './Resources/Remote/xterm.js' -print0 | xargs -0 sed -i '' \
  -e 's/needs_yahia/needs_user/g' \
  -e 's/## Yahia told me/## User told me/g' \
  -e "s/Yahia's/the user's/g" \
  -e 's/Yahia/the user/g' \
  -e 's#/Users/y/#/Users/example/#g' \
  -e 's#/Users/y"#/Users/example"#g' \
  -e 's/-Users-y-/-Users-example-/g' \
  -e 's/net\.prismlens\.true/io.github.true-terminal.True/g' \
  -e 's/net\.prismlens\.jev-cli/io.github.true-terminal.jev/g' \
  -e 's/jev-agent-brain/agent-index-builder/g' \
  -e 's/second-brain-rag/notes-index/g' \
  -e 's/agent-brain/agent-index/g' \
  -e 's/taild56e9a/tail0000/g'

# these URLs were directories on the author's disk, so Foundation appended a slash; pin that.
sed -i '' -E 's#URL\(fileURLWithPath: "(/Users/example(/[A-Za-z/]+)?)"\)#URL(fileURLWithPath: "\1", isDirectory: true)#g' Tests/TrueTests/ScreenshotWatcherTests.swift

echo "==> applying scripts/public.patch"
[ -s "$SRC/scripts/public.patch" ] && patch -p1 --no-backup-if-mismatch < "$SRC/scripts/public.patch"
find . -name '*.orig' -delete

echo "==> overlaying scripts/public/"
rsync -a "$SRC/scripts/public/" "$STAGE/"

echo "==> syncing into $DEST"
mkdir -p "$DEST"
[ -d "$DEST/.git" ] || git -C "$DEST" init -q -b main
rsync -a --delete --exclude '/.git/' --exclude '/.build*/' --exclude '/dist/' "$STAGE/" "$DEST/"
echo "OK: $DEST updated (no commit made)"
