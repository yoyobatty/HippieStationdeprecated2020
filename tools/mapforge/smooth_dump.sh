#!/bin/bash
unset __COMPAT_LAYER # with this set, dm.exe leaks two kernel handles for every file it opens until the next reboot
# Side build that writes data/mapforge/smoothing.txt (smoothing vars + spawner contents) for mapforge's renderer.
# Rerun after changing smoothing groups, base_icon_state or window spawners.
set -u
cd "$(dirname "$0")/../.."
BYOND_BIN="${BYOND_BIN:-/c/Program Files (x86)/BYOND/bin}"
mkdir -p data/mapforge
# include the dump last, so it sees every type
sed '$a #include "tools\\mapforge\\smooth_dump.dm"' hippiestation.dme > mapforge_smooth.mdme
"$BYOND_BIN/dm.exe" mapforge_smooth.mdme | grep -E "error|dmb -" | head -20
[ -f mapforge_smooth.mdme.dmb ] || { echo "build failed"; rm -f mapforge_smooth.*; exit 1; }
"$BYOND_BIN/dd.exe" mapforge_smooth.mdme.dmb -trusted -invisible > data/mapforge/smooth_dump_dd.log 2>&1
rm -f mapforge_smooth.*
wc -l data/mapforge/smoothing.txt
