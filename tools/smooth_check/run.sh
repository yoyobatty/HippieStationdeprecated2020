#!/bin/bash
unset __COMPAT_LAYER # with this set, dm.exe leaks two kernel handles for every file it opens until the next reboot
# Headless smoothing snapshot/check, its own build so hippiestation.dmb is left alone.
#   tools/smooth_check/run.sh build <name> <harness.dm>   builds smoothcheck_<name>.dmb with the harness included
#   tools/smooth_check/run.sh run <name> [params]         one boot; the harness writes data/smooth_check/ and ends the world
#   tools/smooth_check/run.sh clean
set -u
PORT="${PORT:-45317}"
BYOND_BIN="${BYOND_BIN:-/c/Program Files (x86)/BYOND/bin}"
cd "$(dirname "$0")/../.."

build() {
	sed 's/^#include "hippiestation\\code\\modules\\bots_ai\\bot_brain.dm"/#include "smooth_check_tmp.dm"\r\n&/' hippiestation.dme > "smoothcheck_$1.dme"
	cp "$2" smooth_check_tmp.dm
	"$BYOND_BIN/dm.exe" "smoothcheck_$1.dme" | grep -E "error|warning|dmb -"
	rm -f smooth_check_tmp.dm "smoothcheck_$1.dme" "smoothcheck_$1.int" "smoothcheck_$1.lk"
	[ -f "smoothcheck_$1.dmb" ] || { echo "Build failed"; exit 1; }
}

run() {
	mkdir -p data/smooth_check
	rm -f data/smooth_check/*_summary.txt
	rm -rf data/smooth_check_config
	cp -r config data/smooth_check_config
	sed -i '/^BOT_CREW/d' data/smooth_check_config/hippiestation_config.txt
	local start=$SECONDS
	"$BYOND_BIN/dd.exe" "smoothcheck_$1.dmb" "$PORT" -trusted -invisible -params "config=data/smooth_check_config${2:+&$2}" > "data/smooth_check/dd_$1.log" 2>&1 &
	local DD=$! i
	for i in $(seq 1 900); do
		kill -0 "$DD" 2>/dev/null || break
		grep -q "^done" data/smooth_check/*_summary.txt 2>/dev/null && break
		sleep 1
	done
	sleep 2
	kill "$DD" 2>/dev/null
	rm -rf data/smooth_check_config
	echo "took $((SECONDS - start)) s, runtimes: $(grep -c "runtime error" "data/smooth_check/dd_$1.log")"
	cat data/smooth_check/*_summary.txt 2>/dev/null
}

case "$1" in
	build) build "$2" "$3" ;;
	run) run "$2" "${3:-}" ;;
	clean) rm -f smoothcheck_*.dmb smoothcheck_*.rsc smoothcheck_*.dyn.rsc smoothcheck_*.lk smoothcheck_*.int smoothcheck_*.dme ;;
esac
