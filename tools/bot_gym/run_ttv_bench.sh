#!/bin/bash
unset __COMPAT_LAYER # with this set, dm.exe leaks two kernel handles for every file it opens until the next reboot
# TTV bench: boots a shift with nobody on it, sets off a list of tank transfer valve mixes in empty space and prints how big
# each would have been. See hippiestation/code/modules/bots_ai/gym/ttv_bench.dm.
set -u
cd "$(dirname "$0")/../.."
BYOND_BIN="${BYOND_BIN:-/c/Program Files (x86)/BYOND/bin}"
PORT="${PORT:-45127}"
LOG=data/ttv_bench_dd.log
mkdir -p data
"$BYOND_BIN/dm.exe" hippiestation.dme | grep -E "error|dmb -" || true
timeout "${LIMIT:-580}" "$BYOND_BIN/dd.exe" hippiestation.dmb "$PORT" -trusted -invisible \
	-params "bot-shift=${MINUTES:-40}&bot-crew=Assistant&timewarp=0&ttv-bench=${BENCH:-1}${MAP:+&bot-map=$MAP}" > "$LOG" 2>&1 &
DD=$!
trap 'kill $DD 2>/dev/null' INT TERM
while kill -0 $DD 2>/dev/null; do
	sleep 3
	if grep -q "TTV BENCH: done" "$LOG" 2>/dev/null; then
		break
	fi
done
kill $DD 2>/dev/null
grep "TTV BENCH" "$LOG"
