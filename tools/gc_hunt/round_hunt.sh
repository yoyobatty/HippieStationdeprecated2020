#!/bin/bash
unset __COMPAT_LAYER # with this set, dm.exe leaks two kernel handles for every file it opens until the next reboot
# Whole rounds with the reference search, several at once. Usage: tools/gc_hunt/round_hunt.sh [rounds] [jobs]. Results append to data/ref_stall.txt.
# The harness goes into a temporary build; hippiestation.dme and .dmb are put back afterwards.
set -u
cd "$(dirname "$0")/../.."
BYOND_BIN="${BYOND_BIN:-/c/Program Files (x86)/BYOND/bin}"
cp hippiestation.dme data/gc_hunt_dme.keep
cp tools/gc_hunt/gc_hunt.dm gc_hunt_tmp.dm
sed -i '/^\/\/ END_INCLUDE/i #include "gc_hunt_tmp.dm"' hippiestation.dme
"$BYOND_BIN/dm.exe" hippiestation.dme | grep -E "error|dmb -" | tee data/gc_hunt_build.log
cp data/gc_hunt_dme.keep hippiestation.dme
rm -f gc_hunt_tmp.dm data/ref_stall.txt
grep -q " 0 errors" data/gc_hunt_build.log || { echo "The harness didn't compile"; "$BYOND_BIN/dm.exe" hippiestation.dme | grep -E "dmb -"; exit 1; }
ROUND=1 QUIET=1 EVENTS=1 NOCOMPILE=1 NAME=gc_hunt JOBS="${2:-2}" tools/bot_gym/run_shift_batch.sh "${1:-2}" 120 fill:20 > /dev/null 2>&1
"$BYOND_BIN/dm.exe" hippiestation.dme | grep -E "error|dmb -"
git status --short hippiestation.dme
