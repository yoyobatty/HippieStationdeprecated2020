#!/bin/bash
unset __COMPAT_LAYER # with this set, dm.exe leaks two kernel handles for every file it opens until the next reboot
# Gas tanks self-test (tools/atmos_check/atmos_check.dm): every map's tank consoles, sensors and monitors linked at
# roundstart, and on the Hippie map the Oxygen tank driven, broken and put back the ways a player would.
# Builds its own copy (atmoscheck.mdme -> atmoscheck.mdme.dmb), so hippiestation.dmb is left alone for whatever else is running.
# Usage: tools/atmos_check/run_atmos_check.sh            MAPS="hippiestation" to pick maps (default: the main maps, hippiestation and metastation)
#        FULL=metastation runs the full check on that map instead of hippiestation
# Results: data/atmos_check/results_<map name>.txt, and each server's logs in data/logs/atmos_check_<map>
set -u
cd "$(dirname "$0")/../.."
BYOND_BIN="${BYOND_BIN:-/c/Program Files (x86)/BYOND/bin}"
PORT="${PORT:-45397}"
MAPS="${MAPS:-hippiestation metastation}"
FULL="${FULL:-hippiestation}"
start=$(date +%s)

cp hippiestation.dme atmoscheck.mdme
printf '#include "tools\\atmos_check\\atmos_check.dm"\r\n' >> atmoscheck.mdme
echo "Compiling..."
"$BYOND_BIN/dm.exe" atmoscheck.mdme | grep -E "error|warning|dmb -" || true
if [ ! -f atmoscheck.mdme.dmb ]; then echo "Compile failed"; rm -f atmoscheck.mdme; exit 1; fi
echo "built after $(( $(date +%s) - start )) s"

rm -rf data/atmos_check
cp data/next_map.json data/atmos_check_next_map.json 2>/dev/null
for map in $MAPS; do
	mode=roundstart
	[ "$map" = "$FULL" ] && mode=full
	rm -rf "data/logs/atmos_check_$map"
	began=$(date +%s)
	"$BYOND_BIN/dd.exe" atmoscheck.mdme.dmb "$PORT" -trusted -invisible -params "atmos-check=$mode&log-directory=atmos_check_$map&bot-map=$map" > /dev/null 2>&1 &
	dd=$!
	while kill -0 $dd 2>/dev/null; do
		sleep 2
		if [ $(($(date +%s) - began)) -gt 600 ]; then echo "$map: still going after 600 s - stopped"; break; fi
	done
	kill $dd 2>/dev/null; sleep 1; kill -9 $dd 2>/dev/null
	echo "== $map ($mode): $(( $(date +%s) - began )) s"
	runtimes=$(grep -c 'runtime error' "data/logs/atmos_check_$map/runtime.log" 2>/dev/null)
	echo "runtimes: ${runtimes:-0}"
	grep -h -A3 'runtime error' "data/logs/atmos_check_$map/runtime.log" 2>/dev/null | head -40
done
[ -f data/atmos_check_next_map.json ] && mv data/atmos_check_next_map.json data/next_map.json
rm -f atmoscheck.mdme atmoscheck.mdme.dmb atmoscheck.mdme.rsc atmoscheck.mdme.int atmoscheck.mdme.lk atmoscheck.mdme.dyn.rsc atmoscheck.mdme.rsc.lk atmoscheck.mdme.dyn.rsc.lk
for f in data/atmos_check/results_*.txt; do
	[ -f "$f" ] || continue
	echo "---- $f"
	cat "$f"
done
echo "took $(( $(date +%s) - start )) s"
