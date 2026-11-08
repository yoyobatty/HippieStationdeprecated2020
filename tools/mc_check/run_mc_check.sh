#!/bin/bash
# MC health self-test (tools/mc_check/mc_selftest.dm): breaks the MC each way the watchdog and the Failsafe are meant to catch
# (loop gone, freezes, a fire() asleep, lag, a subsystem that keeps crashing it) and checks what they did and told admins.
# About 6 minutes. Builds its own copy (mccheck.mdme -> mccheck.mdme.dmb), so hippiestation.dmb is left alone.
# Usage: tools/mc_check/run_mc_check.sh        STEPS=freeze_outside,lag to run only those (names in mc_selftest.dm run_all())
# Results: data/mc_check/results.txt, and the server's logs in data/logs/mc_check_logs
set -u
cd "$(dirname "$0")/../.."
BYOND_BIN="${BYOND_BIN:-/c/Program Files (x86)/BYOND/bin}"
PORT="${PORT:-45393}"
# Boots the small test map (_maps/testbench.json: Runtime Station, no Lavaland or ruins): the test needs no station,
# and loading the Hippie map costs ~17 s a boot. MAP=hippiestation (any _maps/*.json name) to boot another.
MAP="${MAP:-testbench}"

cp hippiestation.dme mccheck.mdme
printf '#include "tools\\mc_check\\mc_selftest.dm"\r\n' >> mccheck.mdme
echo "Compiling..."
"$BYOND_BIN/dm.exe" mccheck.mdme | grep -E "error|warning|dmb -" || true
if [ ! -f mccheck.mdme.dmb ]; then echo "Compile failed"; rm -f mccheck.mdme; exit 1; fi

rm -rf data/mc_check data/logs/mc_check_logs
began=$(date +%s)
"$BYOND_BIN/dd.exe" mccheck.mdme.dmb "$PORT" -trusted -invisible -params "mc-selftest=1&log-directory=mc_check_logs&bot-map=$MAP${STEPS:+&mc-steps=$STEPS}" > /dev/null 2>&1 &
dd=$!
while kill -0 $dd 2>/dev/null; do
	sleep 2
	[ -f data/mc_check/results.txt ] && break
	if [ $(($(date +%s) - began)) -gt 1200 ]; then echo "still going after 1200 s - stopped"; break; fi
done
sleep 1
kill $dd 2>/dev/null; sleep 1; kill -9 $dd 2>/dev/null
rm -f mccheck.mdme mccheck.mdme.dmb mccheck.mdme.rsc mccheck.mdme.int mccheck.mdme.lk mccheck.mdme.dyn.rsc mccheck.mdme.rsc.lk mccheck.mdme.dyn.rsc.lk
echo "took $(($(date +%s) - began)) s"
cat data/mc_check/results.txt 2>/dev/null || echo "no results: see data/logs/mc_check_logs"
runtimes=$(grep -c 'runtime error' data/logs/mc_check_logs/runtime.log 2>/dev/null)
echo "runtimes: ${runtimes:-0}"
grep -h 'runtime error' data/logs/mc_check_logs/runtime.log 2>/dev/null | sed 's/^\[[^]]*\] //' | sort | uniq -c | sort -rn | head -20 # the strike checks make RunQueue runtime on purpose (tick_overrun)
