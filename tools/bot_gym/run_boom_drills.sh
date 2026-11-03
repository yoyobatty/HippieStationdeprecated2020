#!/bin/bash
# The explosion drills (hippiestation/code/modules/bots_ai/gym/boom_drill.dm), each on its own 40-crew Bot Shift, a few at a time, then
# the drills' lines side by side. Usage: tools/bot_gym/run_boom_drills.sh <label> [drills...]
#   tools/bot_gym/run_boom_drills.sh before                         # all five
#   tools/bot_gym/run_boom_drills.sh after maxcap nuke              # just these
# Environment: CREW=fill:40, AT_ONCE=3, BASE_PORT=45600, NOCOMPILE=1. Results: data/logs/shift_batch/boom-<label>-<drill>/
set -u
cd "$(dirname "$0")/../.."
LABEL="${1:?a label for this set}"
shift
DRILLS=("$@")
if [ ${#DRILLS[@]} -eq 0 ]; then DRILLS=(maxcap maxcap6 superboom tesla nuke); fi
CREW="${CREW:-fill:40}"
AT_ONCE="${AT_ONCE:-3}"
BASE_PORT="${BASE_PORT:-45600}"
if [ "${NOCOMPILE:-0}" != "1" ]; then
	unset __COMPAT_LAYER
	"/c/Program Files (x86)/BYOND/bin/dm.exe" hippiestation.dme | grep -E "error|warning|dmb -" || true
fi
i=0
for d in "${DRILLS[@]}"; do
	while [ "$(jobs -rp | wc -l)" -ge "$AT_ONCE" ]; do wait -n; done
	NOCOMPILE=1 NAME="boom-$LABEL-$d" JOBS=1 BASE_PORT=$((BASE_PORT + i * 10)) EXTRA_PARAMS="boom-drill=$d" \
		tools/bot_gym/run_shift_batch.sh 1 9 "$CREW" > "data/boom-$LABEL-$d.out" 2>&1 &
	i=$((i + 1))
	sleep 3
done
wait
for d in "${DRILLS[@]}"; do
	f="data/logs/shift_batch/boom-$LABEL-$d/run1/boom.txt"
	if [ -f "$f" ]; then cat "$f"; echo; else echo "boom drill $d: no result (see data/boom-$LABEL-$d.out)"; fi
done
