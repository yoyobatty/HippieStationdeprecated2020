#!/bin/bash
unset __COMPAT_LAYER # with this set, dm.exe leaks two kernel handles for every file it opens until the next reboot
# Path engine bench (tools/path_bench/path_bench.dm): the same bot searches by hippie_path.dll and by AStar() on the Hippie station,
# answers compared and both timed. About 2 minutes. Builds its own copy (pathbench.mdme), so hippiestation.dmb is left alone.
# Usage: tools/path_bench/run_path_bench.sh    SEARCHES=600 SEED=1 LIB=hippie_path (a build under another name, see
# tools/path_engine/build.sh OUT=) AHEAD=4 (path-ahead) KIND=permissive (one kind) NOCOMPILE=1 (reuse the build a KEEP=1 run left) PORT=45396
# EXTRA_PARAMS="path-picture=off" (more world params)
# Results: data/path_bench/results.txt, and the server's logs in data/logs/path_bench_logs
set -u
cd "$(dirname "$0")/../.."
BYOND_BIN="${BYOND_BIN:-/c/Program Files (x86)/BYOND/bin}"
PORT="${PORT:-45396}"

if [ "${NOCOMPILE:-0}" != "1" ] || [ ! -f pathbench.mdme.dmb ]; then
	cp hippiestation.dme pathbench.mdme
	printf '#include "tools\\path_bench\\path_bench.dm"\r\n' >> pathbench.mdme
	echo "Compiling..."
	"$BYOND_BIN/dm.exe" pathbench.mdme | grep -E "error|warning|dmb -" || true
	if [ ! -f pathbench.mdme.dmb ]; then echo "Compile failed"; rm -f pathbench.mdme; exit 1; fi
fi
mkdir -p data/path_bench

rm -rf data/path_bench/results.txt data/logs/path_bench_logs
began=$(date +%s)
"$BYOND_BIN/dd.exe" pathbench.mdme.dmb "$PORT" -trusted -invisible -params "path-bench=1&log-directory=path_bench_logs&bot-map=hippiestation&searches=${SEARCHES:-600}&seed=${SEED:-1}&path-lib=${LIB:-hippie_path}&path-ahead=${AHEAD:-4}&kind=${KIND:-}${EXTRA_PARAMS:+&$EXTRA_PARAMS}" > /dev/null 2>&1 &
dd=$!
while kill -0 $dd 2>/dev/null; do
	sleep 2
	[ -f data/path_bench/results.txt ] && break
	if [ $(($(date +%s) - began)) -gt 900 ]; then echo "still going after 900 s - stopped"; break; fi
done
sleep 1
kill $dd 2>/dev/null; sleep 1; kill -9 $dd 2>/dev/null
echo "took $(($(date +%s) - began)) s"
[ "${KEEP:-0}" = "1" ] || rm -f pathbench.mdme pathbench.mdme.dmb pathbench.mdme.rsc pathbench.mdme.int pathbench.mdme.lk pathbench.mdme.dyn.rsc pathbench.mdme.rsc.lk pathbench.mdme.dyn.rsc.lk # KEEP=1 keeps the build for NOCOMPILE=1
cat data/path_bench/results.txt 2>/dev/null || echo "no results: see data/logs/path_bench_logs"
runtimes=$(grep -c 'runtime error' data/logs/path_bench_logs/runtime.log 2>/dev/null)
echo "runtimes: ${runtimes:-0}"
grep -h -A2 'runtime error' data/logs/path_bench_logs/runtime.log 2>/dev/null | head -12
