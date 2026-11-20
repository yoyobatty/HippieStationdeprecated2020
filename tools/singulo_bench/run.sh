#!/bin/bash
unset __COMPAT_LAYER # with this set, dm.exe leaks two kernel handles for every file it opens until the next reboot
# Singularity bench (singulo_bench.dm): stage six singularity + litter, headless, before (git REF, default HEAD) and after
# (working tree) side by side.  tools/singulo_bench/run.sh [seconds=60] [items=300]   results in data/singulo_bench/
set -u
cd "$(dirname "$0")/../.."
BYOND_BIN="${BYOND_BIN:-/c/Program Files (x86)/BYOND/bin}"
SECS="${1:-60}"
ITEMS="${2:-300}"
REF="${REF:-HEAD}"
SING='code\modules\power\singularity\singularity.dm'
PULL='hippiestation\code\modules\power\singularity_pull.dm'
mkdir -p data/singulo_bench/before

# before: the dme with the two singularity files swapped for REF's copies
git show "$REF:code/modules/power/singularity/singularity.dm" > data/singulo_bench/before/singularity.dm
git show "$REF:hippiestation/code/modules/power/singularity_pull.dm" > data/singulo_bench/before/singularity_pull.dm
python - "$SING" "$PULL" <<'EOF'
import sys
sing, pull = sys.argv[1], sys.argv[2]
d = open('hippiestation.dme', 'rb').read()
inc = b'#include "tools\\singulo_bench\\singulo_bench.dm"\r\n'
open('singulo_after.mdme', 'wb').write(d + inc)
b = d.replace(('#include "%s"' % sing).encode(), b'#include "data\\singulo_bench\\before\\singularity.dm"')
b = b.replace(('#include "%s"' % pull).encode(), b'#include "data\\singulo_bench\\before\\singularity_pull.dm"')
assert b.count(b'singulo_bench\\before') == 2
open('singulo_before.mdme', 'wb').write(b + inc)
EOF
for v in before after; do
	"$BYOND_BIN/dm.exe" "singulo_$v.mdme" | grep -E "error|dmb -" &
done
wait
rm -f singulo_*.mdme singulo_*.mdme.int singulo_*.mdme.lk
[ -f singulo_before.mdme.dmb ] && [ -f singulo_after.mdme.dmb ] || { echo "build failed"; exit 1; }

port=45431
for v in before after; do
	rm -f "data/singulo_bench/$v.txt"; rm -rf "data/logs/singulo_$v"
	"$BYOND_BIN/dd.exe" "singulo_$v.mdme.dmb" $port -trusted -invisible \
		-params "singulo-bench=1&singulo-bench-label=$v&singulo-bench-seconds=$SECS&singulo-bench-items=$ITEMS&log-directory=singulo_$v&bot-map=${MAP:-testbench}" > /dev/null 2>&1 &
	eval "dd_$v=$!"
	port=$((port + 1))
done
began=$(date +%s)
while true; do
	sleep 3
	grep -q "^done" data/singulo_bench/before.txt 2>/dev/null && grep -q "^done" data/singulo_bench/after.txt 2>/dev/null && break
	[ $(($(date +%s) - began)) -gt $((SECS + 240)) ] && { echo "timed out"; break; }
done
sleep 2
kill $dd_before $dd_after 2>/dev/null; sleep 1; kill -9 $dd_before $dd_after 2>/dev/null
for v in before after; do
	echo "== $v"; cat "data/singulo_bench/$v.txt" 2>/dev/null
	echo "runtimes: $(grep -c 'runtime error' "data/logs/singulo_$v/runtime.log" 2>/dev/null)"
	grep -h 'runtime error' "data/logs/singulo_$v/runtime.log" 2>/dev/null | sed 's/^\[[^]]*\] //' | sort | uniq -c | sort -rn | head -5
done
rm -f singulo_*.mdme.dmb singulo_*.mdme.rsc singulo_*.mdme.dyn.rsc
