#!/bin/bash
unset __COMPAT_LAYER # with this set, dm.exe leaks two kernel handles for every file it opens until the next reboot
# RPED sweep (tools/rped_check/rped_check.dm): every board-built machine, a tier 4 bluespace RPED, what it swaps and changes.
# Builds its own copy (rpedcheck.mdme), so hippiestation.dmb is left alone.
# Usage: tools/rped_check/run_rped_check.sh
# Results: data/rped_check/results.txt and sweep.tsv; the server logs in data/logs/rped_check_logs
set -u
cd "$(dirname "$0")/../.."
BYOND_BIN="${BYOND_BIN:-/c/Program Files (x86)/BYOND/bin}"
PORT="${PORT:-45394}"
MAP="${MAP:-testbench}"

cp hippiestation.dme rpedcheck.mdme
printf '#include "tools\\rped_check\\rped_check.dm"\r\n' >> rpedcheck.mdme
echo "Compiling..."
"$BYOND_BIN/dm.exe" rpedcheck.mdme | grep -E "error|warning|dmb -" || true
if [ ! -f rpedcheck.mdme.dmb ]; then echo "Compile failed"; rm -f rpedcheck.mdme; exit 1; fi

rm -rf data/rped_check data/logs/rped_check_logs
began=$(date +%s)
"$BYOND_BIN/dd.exe" rpedcheck.mdme.dmb "$PORT" -trusted -invisible -params "rped-check=1&log-directory=rped_check_logs&bot-map=$MAP" > /dev/null 2>&1 &
dd=$!
while kill -0 $dd 2>/dev/null; do
	sleep 2
	[ -f data/rped_check/results.txt ] && break
	if [ $(($(date +%s) - began)) -gt 600 ]; then echo "still going after 600 s - stopped"; break; fi
done
sleep 1
kill $dd 2>/dev/null; sleep 1; kill -9 $dd 2>/dev/null
rm -f rpedcheck.mdme rpedcheck.mdme.dmb rpedcheck.mdme.rsc rpedcheck.mdme.int rpedcheck.mdme.lk rpedcheck.mdme.dyn.rsc rpedcheck.mdme.rsc.lk rpedcheck.mdme.dyn.rsc.lk
echo "took $(($(date +%s) - began)) s"
cat data/rped_check/results.txt 2>/dev/null || echo "no results: see data/logs/rped_check_logs"
runtimes=$(grep -c 'runtime error' data/logs/rped_check_logs/runtime.log 2>/dev/null)
echo "runtimes: ${runtimes:-0}"
grep -h -A3 'runtime error' data/logs/rped_check_logs/runtime.log 2>/dev/null | head -40
