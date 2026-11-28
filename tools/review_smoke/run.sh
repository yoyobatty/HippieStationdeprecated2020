#!/bin/bash
unset __COMPAT_LAYER # with this set, dm.exe leaks two kernel handles for every file it opens until the next reboot
# Review smoke tests (review_smoke.py, review_smoke.dm, dash_client.py): what the 2026-11-28 backend review fixes claim for the
# dashboard, light textures and the lobby build, checked in a real headless dd.exe, one server at a time on ports 45530-45539.
# Builds its own review_smoke.mdme.dmb (hippiestation.dmb is left alone) and removes it after, unless --keep-build.
# Usage: tools/review_smoke/run.sh [STEP ...] [--no-build] [--keep-build]
#   steps: dash dash_bind dash_local sprites sprites2 sprites_old lobby_powernets lobby_ruins lobby_atom (all by default)
#   e.g.   tools/review_smoke/run.sh dash --keep-build ; tools/review_smoke/run.sh sprites sprites2 --no-build
# Results: data/review_smoke/results.txt; each server's logs in data/logs/review_smoke_<step>/
cd "$(dirname "$0")/../.."
exec python tools/review_smoke/review_smoke.py "$@"
