#!/bin/bash
unset __COMPAT_LAYER # with this set, dm.exe leaks two kernel handles for every file it opens until the next reboot
# The log writer in the real engine (tools/log_writer/log_check.dm), booted twice on the small test map: with hippie_log.dll,
# then with log-writer=rustg. Builds its own copy (logcheck.mdme), so hippiestation.dmb is left alone.
# Results: data/log_check/results_{native,rustg}.txt
set -u
cd "$(dirname "$0")/../.."
BYOND_BIN="${BYOND_BIN:-/c/Program Files (x86)/BYOND/bin}"
PORT="${PORT:-45398}"
start=$(date +%s)
cp hippiestation.dme logcheck.mdme
printf '#include "tools\\log_writer\\log_check.dm"\r\n' >> logcheck.mdme
"$BYOND_BIN/dm.exe" logcheck.mdme | grep -E "error|warning|dmb -" || true
if [ ! -f logcheck.mdme.dmb ]; then echo "Compile failed"; rm -f logcheck.mdme; exit 1; fi
rm -rf data/log_check
for mode in native rustg; do
	rm -rf "data/logs/log_check_$mode"
	extra=""
	[ "$mode" = "rustg" ] && extra="&log-writer=rustg"
	began=$(date +%s)
	"$BYOND_BIN/dd.exe" logcheck.mdme.dmb "$PORT" -trusted -invisible -params "log-check=1&log-directory=log_check_$mode&bot-map=testbench$extra" > /dev/null 2>&1 &
	dd=$!
	while kill -0 $dd 2>/dev/null; do
		sleep 1
		if [ $(($(date +%s) - began)) -gt 300 ]; then echo "$mode: still going after 300 s - stopped"; break; fi
	done
	kill $dd 2>/dev/null; sleep 1; kill -9 $dd 2>/dev/null
	echo "== $mode: $(( $(date +%s) - began )) s, runtimes: $(grep -c 'runtime error' "data/logs/log_check_$mode/runtime.log" 2>/dev/null)"
	grep -h -A3 'runtime error' "data/logs/log_check_$mode/runtime.log" 2>/dev/null | head -20
	cat "data/log_check/results_$mode.txt" 2>/dev/null || echo "no results"
done
sleep 2
rm -f logcheck.mdme logcheck.mdme.dmb logcheck.mdme.rsc logcheck.mdme.int logcheck.mdme.lk logcheck.mdme.dyn.rsc logcheck.mdme.rsc.lk logcheck.mdme.dyn.rsc.lk
echo "took $(( $(date +%s) - start )) s"
