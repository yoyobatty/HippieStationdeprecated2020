#!/bin/bash
# Reagent heat check (tools/chem_heat_check/chem_heat_check.dm): heating by volume, drift towards the air, the chem tank, a pile of hot
# beakers. Headless on Runtime Station, about a minute. Results: data/chem_heat_check.txt
# Usage: tools/chem_heat_check/run_chem_heat_check.sh [port]
unset __COMPAT_LAYER
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
TREE="$HERE/../.."
PORT="${1:-45431}"
BYOND_BIN="/c/Program Files (x86)/BYOND/bin"
cd "$TREE"
cp "$HERE/chem_heat_check.dm" zz_chem_heat_check.dm
cp hippiestation.dme chemheat.mdme
printf '#include "zz_chem_heat_check.dm"\r\n' >> chemheat.mdme
"$BYOND_BIN/dm.exe" chemheat.mdme | grep -E "error|dmb -"
rm -f data/chem_heat_check.txt
rm -rf data/logs/chem_heat_logs
"$BYOND_BIN/dd.exe" chemheat.mdme.dmb "$PORT" -trusted -invisible -params "chem-heat-check=1&log-directory=chem_heat_logs&bot-map=testbench" > /dev/null 2>&1 &
dd=$!
began=$(date +%s)
while kill -0 $dd 2>/dev/null; do
	sleep 2
	[ -f data/chem_heat_check.txt ] && break
	if [ $(($(date +%s) - began)) -gt 400 ]; then echo "stopped after 400 s"; break; fi
done
sleep 1
kill $dd 2>/dev/null; sleep 1; kill -9 $dd 2>/dev/null
rm -f zz_chem_heat_check.dm chemheat.mdme chemheat.mdme.dmb chemheat.mdme.rsc chemheat.mdme.int chemheat.mdme.lk chemheat.mdme.dyn.rsc chemheat.mdme.rsc.lk chemheat.mdme.dyn.rsc.lk
cat data/chem_heat_check.txt 2>/dev/null || echo "no result"
echo "runtimes: $(grep -c 'runtime error' data/logs/chem_heat_logs/runtime.log 2>/dev/null)"
grep -A3 'runtime error' data/logs/chem_heat_logs/runtime.log 2>/dev/null | head -30
