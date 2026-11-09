#!/bin/bash
unset __COMPAT_LAYER # with this set, dm.exe leaks two kernel handles for every file it opens until the next reboot
# Spritesheet check: every spritesheet built the old DM way and by rust_g's iconforge on the real station (headless, ~1 minute),
# then compare.py checks every sprite pixel by pixel and prints the main thread times.
# Usage: tools/spritesheet_check/run.sh [rust_g library name]   (a name like rust_g7 tests another rust_g DLL in the repo root)
# Results: data/spritesheet_check/results.txt, the sheets in data/spritesheet_check/dm and /forge
set -u
cd "$(dirname "$0")/../.."
BYOND_BIN="${BYOND_BIN:-/c/Program Files (x86)/BYOND/bin}"
LIB="${1:-}"
PORT="${PORT:-45331}"
START=$(date +%s)

rm -rf data/spritesheet_check
mkdir -p data/spritesheet_check/dm data/spritesheet_check/forge
{
	if [ -n "$LIB" ]; then printf '#define RUST_G "%s"\r\n' "$LIB"; fi
	cat hippiestation.dme
	printf '#include "tools\\spritesheet_check\\spritesheet_check.dm"\r\n'
} > sscheck.mdme
"$BYOND_BIN/dm.exe" sscheck.mdme | grep -E "error|dmb -"
[ -f sscheck.mdme.dmb ] || { echo "Build failed"; rm -f sscheck.mdme*; exit 1; }
echo "Built in $(( $(date +%s) - START )) s"

"$BYOND_BIN/dd.exe" sscheck.mdme.dmb "$PORT" -trusted -invisible -params "spritesheet-check=1" > data/spritesheet_check/dd.log 2>&1 &
DD=$!
for i in $(seq 1 360); do
	kill -0 "$DD" 2>/dev/null || break
	grep -q "^done" data/spritesheet_check/results.txt 2>/dev/null && break
	sleep 1
done
sleep 2
kill "$DD" 2>/dev/null
echo "Ran in $(( $(date +%s) - START )) s"
grep -E "^Spritesheets:" data/spritesheet_check/dd.log
grep -iE "runtime error" data/spritesheet_check/dd.log | sort | uniq -c | sort -rn | head -5
sleep 3
rm -f sscheck.mdme sscheck.mdme.dmb sscheck.mdme.rsc sscheck.mdme.int sscheck.mdme.dyn.rsc sscheck.mdme.lk sscheck.mdme.rsc.lk sscheck.mdme.dyn.rsc.lk
rm -rf "data/spritesheets/forge_${PORT}_a" "data/spritesheets/forge_${PORT}_s"
python tools/spritesheet_check/compare.py
