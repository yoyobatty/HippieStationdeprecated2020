#!/bin/bash
unset __COMPAT_LAYER # with this set, dm.exe leaks two kernel handles for every file it opens until the next reboot
# Realistic explosions on the real station (headless, a few minutes): pictures with realism off and on, totals at 150 random spots,
# and live bombs in a sealed closet, the bar and outside the hull.
# Usage: tools/explosion_preview/run_realism.sh [map]
# Results: data/explosion_realism_<map>/results.txt, pictures in data/previews/explosion_realism_<map>/
set -u
cd "$(dirname "$0")/../.."
BYOND_BIN="${BYOND_BIN:-/c/Program Files (x86)/BYOND/bin}"
MAP="${1:-hippiestation}"
PORT="${PORT:-45343}"
START=$(date +%s)

rm -rf data/explosion_preview
mkdir -p data/explosion_preview
{
	cat hippiestation.dme
	printf '#include "tools\\explosion_preview\\explosion_preview.dm"\r\n'
	printf '#include "tools\\explosion_preview\\realism_preview.dm"\r\n'
} > xrealism.mdme
"$BYOND_BIN/dm.exe" xrealism.mdme | grep -E "error|dmb -"
[ -f xrealism.mdme.dmb ] || { echo "Build failed"; rm -f xrealism.mdme*; exit 1; }
echo "Built in $(( $(date +%s) - START )) s"

"$BYOND_BIN/dd.exe" xrealism.mdme.dmb "$PORT" -trusted -invisible -params "explosion-realism-preview=1&bot-map=$MAP${EXTRA:+&$EXTRA}" > data/explosion_preview/dd.log 2>&1 &
DD=$!
for i in $(seq 1 900); do
	kill -0 "$DD" 2>/dev/null || break
	grep -q "^done" data/explosion_preview/results.txt 2>/dev/null && break
	sleep 1
done
sleep 2
kill "$DD" 2>/dev/null
echo "Ran in $(( $(date +%s) - START )) s"
grep -iE "runtime error" -A3 data/explosion_preview/dd.log | head -40
sleep 3
rm -f xrealism.mdme xrealism.mdme.dmb xrealism.mdme.rsc xrealism.mdme.int xrealism.mdme.dyn.rsc xrealism.mdme.lk xrealism.mdme.rsc.lk xrealism.mdme.dyn.rsc.lk
OUTDIR="${OUTDIR:-explosion_realism_$MAP}"
rm -rf "data/$OUTDIR"
mkdir -p "data/$OUTDIR"
cp data/explosion_preview/* "data/$OUTDIR/" 2>/dev/null
cat "data/$OUTDIR/results.txt"
python tools/explosion_preview/render.py "data/$OUTDIR" "data/previews/$OUTDIR"
