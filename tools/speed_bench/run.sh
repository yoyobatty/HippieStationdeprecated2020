#!/bin/bash
unset __COMPAT_LAYER # Git Bash sets it, and under it dm.exe leaks two kernel handles for every file it opens until the next reboot
# Before and after, in turns so the machine's mood falls on both. Headless, no game window. See speed_bench.dm.
#   tools/speed_bench/run.sh build <name>         builds speedbench_<name>.dmb from the code as it is now
#   tools/speed_bench/run.sh run <name> [label]   one boot of it, results in data/speed_bench_<label>.txt
#   tools/speed_bench/run.sh ab <a> <b> [rounds]  takes turns, then prints the medians side by side
#   tools/speed_bench/run.sh clean                removes the builds
set -u
PORT="${PORT:-45313}"
BYOND_BIN="${BYOND_BIN:-/c/Program Files (x86)/BYOND/bin}"
HERE="$(cd "$(dirname "$0")" && pwd -W)"
cd "$(dirname "$0")/../.."

build() {
	sed 's/^#include "hippiestation\\code\\modules\\bots_ai\\bot_brain.dm"/#include "speed_bench_tmp.dm"\r\n&/' hippiestation.dme > "speedbench_$1.dme"
	cp "$HERE/speed_bench.dm" speed_bench_tmp.dm
	"$BYOND_BIN/dm.exe" "speedbench_$1.dme" | grep -E "error|warning|dmb -"
	rm -f speed_bench_tmp.dm "speedbench_$1.dme" "speedbench_$1.int" "speedbench_$1.lk"
	[ -f "speedbench_$1.dmb" ] || { echo "Build failed"; exit 1; }
}

run() {
	rm -f data/speed_bench.txt
	rm -rf data/speed_bench_config
	cp -r config data/speed_bench_config
	sed -i '/^BOT_CREW/d' data/speed_bench_config/hippiestation_config.txt
	"$BYOND_BIN/dd.exe" "speedbench_$1.dmb" "$PORT" -trusted -invisible -params "config=data/speed_bench_config${SPEED_PARAMS:+&$SPEED_PARAMS}" > data/speed_bench_dd.log 2>&1 &
	local DD=$! i
	for i in $(seq 1 300); do
		kill -0 "$DD" 2>/dev/null || break
		grep -q "^done" data/speed_bench.txt 2>/dev/null && break
		sleep 1
	done
	sleep 2
	kill "$DD" 2>/dev/null
	rm -rf data/speed_bench_config
	cp data/speed_bench.txt "data/speed_bench_$2.txt" 2>/dev/null
	echo "runtimes in $2: $(grep -c "runtime error" data/speed_bench_dd.log)"
}

case "$1" in
	build) build "$2" ;;
	run) run "$2" "${3:-$2}"; cat "data/speed_bench_${3:-$2}.txt" ;;
	ab)
		ROUNDS="${4:-3}"
		for i in $(seq 1 "$ROUNDS"); do
			run "$2" "$2_$i"
			run "$3" "$3_$i"
		done
		python "$HERE/compare.py" "$2" "$3" "$ROUNDS"
		;;
	clean) rm -f speedbench_*.dmb speedbench_*.rsc speedbench_*.dyn.rsc speedbench_*.lk speedbench_*.int speedbench_*.dme ;;
esac
