#!/bin/bash
unset __COMPAT_LAYER # with this set, dm.exe leaks two kernel handles for every file it opens until the next reboot
# Integrated circuits self-test (tools/circuit_check/circuit_selftest.dm): a player's way through the printer, wirer and
# Load Program, then every circuit type swept, in the real engine.
# Builds its own copy (circuitcheck.mdme -> circuitcheck.mdme.dmb), so hippiestation.dmb is left alone for whatever else is running.
# Usage: tools/circuit_check/run_circuit_check.sh
# Results: data/circuit_check/results.txt, and the server's logs in data/logs/circuit_check_logs
set -u
cd "$(dirname "$0")/../.."
BYOND_BIN="${BYOND_BIN:-/c/Program Files (x86)/BYOND/bin}"
PORT="${PORT:-45391}"
# Boots the small test map (_maps/testbench.json: Runtime Station, no Lavaland or ruins): the test builds its own room,
# and loading the Hippie map costs ~17 s a boot. MAP=hippiestation (any _maps/*.json name) to boot another.
MAP="${MAP:-testbench}"

cp hippiestation.dme circuitcheck.mdme
printf '#include "tools\\circuit_check\\circuit_selftest.dm"\r\n' >> circuitcheck.mdme
echo "Compiling..."
"$BYOND_BIN/dm.exe" circuitcheck.mdme | grep -E "error|warning|dmb -" || true
if [ ! -f circuitcheck.mdme.dmb ]; then echo "Compile failed"; rm -f circuitcheck.mdme; exit 1; fi

rm -rf data/circuit_check data/logs/circuit_check_logs
began=$(date +%s)
"$BYOND_BIN/dd.exe" circuitcheck.mdme.dmb "$PORT" -trusted -invisible -params "circuit-selftest=1&log-directory=circuit_check_logs&bot-map=$MAP" > /dev/null 2>&1 &
dd=$!
while kill -0 $dd 2>/dev/null; do
	sleep 2
	[ -f data/circuit_check/results.txt ] && break
	if [ $(($(date +%s) - began)) -gt 900 ]; then echo "still going after 900 s - stopped"; break; fi
done
sleep 1
kill $dd 2>/dev/null; sleep 1; kill -9 $dd 2>/dev/null
rm -f circuitcheck.mdme circuitcheck.mdme.dmb circuitcheck.mdme.rsc circuitcheck.mdme.int circuitcheck.mdme.lk circuitcheck.mdme.dyn.rsc circuitcheck.mdme.rsc.lk circuitcheck.mdme.dyn.rsc.lk
echo "took $(($(date +%s) - began)) s"
cat data/circuit_check/results.txt 2>/dev/null || echo "no results: see data/logs/circuit_check_logs"
runtimes=$(grep -c 'runtime error' data/logs/circuit_check_logs/runtime.log 2>/dev/null)
echo "runtimes: ${runtimes:-0}"
grep -h -A3 'runtime error' data/logs/circuit_check_logs/runtime.log 2>/dev/null | head -60
