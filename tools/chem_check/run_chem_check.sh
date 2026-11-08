#!/bin/bash
# Chemistry check (tools/chem_check/chem_check.dm): exact reactions + chem dispenser EMPs timed, headless on Runtime Station. ~1 minute.
# Usage: tools/chem_check/run_chem_check.sh [tree] [port]   tree: a worktree to build instead of this one (it gets the harness copied in)
# TYPE=/obj/machinery/chem_dispenser/drinks EMPs that kind instead; SAME=1 all in one place (piles build up, as round a tesla).
# Results: <tree>/data/chem_exact.txt (diff two builds' to compare reactions) and <tree>/data/chem_emp_check.txt
unset __COMPAT_LAYER
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
TREE="${1:-$HERE/../..}"
PORT="${2:-45411}"
BYOND_BIN="/c/Program Files (x86)/BYOND/bin"
cd "$TREE"
cp "$HERE/chem_check.dm" zz_chem_emp_check.dm
cp hippiestation.dme chememp.mdme
printf '#include "zz_chem_emp_check.dm"\r\n' >> chememp.mdme
"$BYOND_BIN/dm.exe" chememp.mdme | grep -E "dmb -"
rm -f data/chem_emp_check.txt data/chem_exact.txt
rm -rf data/logs/chem_emp_logs
"$BYOND_BIN/dd.exe" chememp.mdme.dmb "$PORT" -trusted -invisible -params "chem-emp-check=1&log-directory=chem_emp_logs&bot-map=testbench&chem-type=${TYPE:-}&chem-same-spot=${SAME:-}" > /dev/null 2>&1 &
dd=$!
began=$(date +%s)
while kill -0 $dd 2>/dev/null; do
	sleep 2
	[ -f data/chem_emp_check.txt ] && break
	if [ $(($(date +%s) - began)) -gt 600 ]; then echo "stopped after 600 s"; break; fi
done
sleep 1
kill $dd 2>/dev/null; sleep 1; kill -9 $dd 2>/dev/null
rm -f zz_chem_emp_check.dm chememp.mdme chememp.mdme.dmb chememp.mdme.rsc chememp.mdme.int chememp.mdme.lk chememp.mdme.dyn.rsc chememp.mdme.rsc.lk chememp.mdme.dyn.rsc.lk
echo "$TREE: $(cat data/chem_emp_check.txt 2>/dev/null || echo no result)"
echo "runtimes: $(grep -c 'runtime error' data/logs/chem_emp_logs/runtime.log 2>/dev/null) (about 13 are the bare test holders' foam and smoke, with nowhere to put it)"
