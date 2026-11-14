#!/bin/bash
unset __COMPAT_LAYER # with this set, dm.exe leaks two kernel handles for every file it opens until the next reboot
# Native map parser check (tools/map_engine/check.dm): every map in _maps parsed by DM and by hippie_map.dll, compared.
# Builds its own copy (mapcheck.mdme -> mapcheck.mdme.dmb), so hippiestation.dmb is left alone for whatever else is running.
# Usage: tools/map_engine/run_check.sh      (MAP_LIB=hippie_map_test to check another build of the library)
# Results: data/map_engine_check/results.txt, and the server's logs in data/logs/map_engine_check_logs
set -u
cd "$(dirname "$0")/../.."
BYOND_BIN="${BYOND_BIN:-/c/Program Files (x86)/BYOND/bin}"
PORT="${PORT:-45431}"

cp hippiestation.dme mapcheck.mdme
printf '#include "tools\map_engine\check.dm"\r\n' >> mapcheck.mdme
echo "Compiling..."
"$BYOND_BIN/dm.exe" mapcheck.mdme | grep -E "error|warning|dmb -" || true
if [ ! -f mapcheck.mdme.dmb ]; then echo "Compile failed"; rm -f mapcheck.mdme; exit 1; fi

rm -rf data/map_engine_check data/logs/map_engine_check_logs
began=$(date +%s)
"$BYOND_BIN/dd.exe" mapcheck.mdme.dmb "$PORT" -trusted -invisible -params "map-engine-check=1&log-directory=map_engine_check_logs&bot-map=testbench&map-lib=${MAP_LIB:-hippie_map}" > /dev/null 2>&1 &
dd=$!
while kill -0 $dd 2>/dev/null; do
	sleep 2
	[ -f data/map_engine_check/results.txt ] && break
	if [ $(($(date +%s) - began)) -gt 900 ]; then echo "still going after 900 s - stopped"; break; fi
done
sleep 1
kill $dd 2>/dev/null; sleep 1; kill -9 $dd 2>/dev/null
rm -f mapcheck.mdme mapcheck.mdme.dmb mapcheck.mdme.rsc mapcheck.mdme.int mapcheck.mdme.lk mapcheck.mdme.dyn.rsc mapcheck.mdme.rsc.lk mapcheck.mdme.dyn.rsc.lk
echo "took $(($(date +%s) - began)) s"
cat data/map_engine_check/results.txt 2>/dev/null || echo "no results: see data/logs/map_engine_check_logs"
runtimes=$(grep -c 'runtime error' data/logs/map_engine_check_logs/runtime.log 2>/dev/null)
echo "runtimes: ${runtimes:-0}"
grep -h -A3 'runtime error' data/logs/map_engine_check_logs/runtime.log 2>/dev/null | head -60
