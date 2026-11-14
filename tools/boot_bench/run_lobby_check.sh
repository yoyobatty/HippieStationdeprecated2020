#!/bin/bash
unset __COMPAT_LAYER # with this set, dm.exe leaks two kernel handles for every file it opens until the next reboot
# Lobby build check (tools/boot_bench/lobby_check.dm): Lavaland and the space ruin levels, built after startup, checked over.
# OFF=1 builds them at startup instead (lobby-build=off), for comparison.
# Builds its own copy (lobbycheck.mdme -> lobbycheck.mdme.dmb), so hippiestation.dmb is left alone for whatever else is running.
# Usage: tools/boot_bench/run_lobby_check.sh
# Results: data/lobby_check/results.txt (+ type_counts.txt), and the server's logs in data/logs/lobby_check_logs
set -u
cd "$(dirname "$0")/../.."
BYOND_BIN="${BYOND_BIN:-/c/Program Files (x86)/BYOND/bin}"
PORT="${PORT:-45433}"
MAP="${MAP:-hippiestation}"

cp hippiestation.dme lobbycheck.mdme
printf '#include "tools\\boot_bench\\lobby_check.dm"\r\n' >> lobbycheck.mdme
echo "Compiling..."
"$BYOND_BIN/dm.exe" lobbycheck.mdme | grep -E "error|warning|dmb -" || true
if [ ! -f lobbycheck.mdme.dmb ]; then echo "Compile failed"; rm -f lobbycheck.mdme; exit 1; fi

rm -rf data/lobby_check data/logs/lobby_check_logs
began=$(date +%s)
"$BYOND_BIN/dd.exe" lobbycheck.mdme.dmb "$PORT" -trusted -invisible -params "lobby-check=1&log-directory=lobby_check_logs&bot-map=$MAP${OFF:+&lobby-build=off}${EXTRA:+&$EXTRA}" > /dev/null 2>&1 &
dd=$!
while kill -0 $dd 2>/dev/null; do
	sleep 2
	[ -f data/lobby_check/results.txt ] && break
	if [ $(($(date +%s) - began)) -gt 600 ]; then echo "still going after 600 s - stopped"; break; fi
done
sleep 1
kill $dd 2>/dev/null; sleep 1; kill -9 $dd 2>/dev/null
rm -f lobbycheck.mdme lobbycheck.mdme.dmb lobbycheck.mdme.rsc lobbycheck.mdme.int lobbycheck.mdme.lk lobbycheck.mdme.dyn.rsc lobbycheck.mdme.rsc.lk lobbycheck.mdme.dyn.rsc.lk
echo "took $(($(date +%s) - began)) s"
cat data/lobby_check/results.txt 2>/dev/null || echo "no results: see data/logs/lobby_check_logs"
grep -h "Lobby build\|Initializations complete" data/logs/lobby_check_logs/runtime.log 2>/dev/null
runtimes=$(grep -c 'runtime error' data/logs/lobby_check_logs/runtime.log 2>/dev/null)
echo "runtimes: ${runtimes:-0}"
grep -h -A3 'runtime error' data/logs/lobby_check_logs/runtime.log 2>/dev/null | head -60
