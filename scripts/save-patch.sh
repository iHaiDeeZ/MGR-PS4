#!/usr/bin/env bash
# Export the PS4 changes of the upstream checkout (branch ps4 against patches/BASE.txt) into patches/mgr-ps4.patch.
# Run in WSL: scripts/save-patch.sh
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
SRC="${MGR_SRC:-$HOME/mgr-build/src/mgr-nx-deko}"
base="$(cat "$HERE/patches/BASE.txt")"
cd "$SRC"
# New files join the diff as intent-to-add entries. app/codegen_flavor.toml is written by build-mgr.sh codegen, and
# the PS4's FFmpeg configuration is kept in patches/ffmpeg (FFmpeg's .gitignore hides it).
git ls-files --others --exclude-standard -z | xargs -0 -r git add --intent-to-add --
git diff "$base" -- . ':(exclude)app/codegen_flavor.toml' > "$HERE/patches/mgr-ps4.patch"
echo "patches/mgr-ps4.patch: $(grep -c '^diff --git' "$HERE/patches/mgr-ps4.patch") files against $base"
