#!/bin/bash
unset __COMPAT_LAYER # with this set, dm.exe leaks two kernel handles for every file it opens until the next reboot
# The CPU stress bench (hippiestation/code/modules/bots_ai/gym/stress_bench.dm): Hippie Station with 40 bot crew, two traitors, random
# events and a fixed list of disasters (aurora, grid check, rad storm, plasma fire, hull breaches, meteors, maxcap, tesla), timed phase
# by phase. A run is about 27 game minutes; with timewarp that's several real minutes, more while the disasters are on.
#
# Usage:
#   tools/bot_gym/run_stress_bench.sh run <label> [runs]          compile, then [runs] (3) runs of this build
#   tools/bot_gym/run_stress_bench.sh save <label>                compile and keep the build as data/stress_builds/<label>.dmb
#   tools/bot_gym/run_stress_bench.sh ab <labelA> <labelB> [runs] two saved builds side by side, [runs] (3) each, running at the
#                                                                 same time so both see the same machine load
# Environment: JOBS (servers at once for each build: 3 for run, 2 each for ab), NOCOMPILE=1, PROFILE=1, BASE_PORT, EXTRA_PARAMS,
#   EVENTS=0/1 random events (on for run, off for ab: they change from run to run and blur small gains; the disasters always happen)
# Results: data/logs/shift_batch/stress-<label>/run<n>/stress.txt and stress.json; the report at the end is
#   python tools/bot_gym/stress_report.py <label> [--vs <label>]
set -u
cd "$(dirname "$0")/../.."
BYOND_BIN="${BYOND_BIN:-/c/Program Files (x86)/BYOND/bin}"
MINUTES=27

compile() {
	local out
	out="$("$BYOND_BIN/dm.exe" hippiestation.dme | grep -E "error|warning|dmb -")"
	echo "$out"
	echo "$out" | grep -q "dmb - 0 errors" || { echo "Compile failed"; exit 1; }
}

batch() { # label runs port [dmb]
	local params="stress-bench=1"
	if [ -n "${EXTRA_PARAMS:-}" ]; then params="$params&$EXTRA_PARAMS"; fi
	NAME="stress-$1" MAPS=hippiestation EVENTS="$EVENTS_ON" QUIET=1 ANTAGS='traitor*2' NOCOMPILE=1 BASE_PORT="$3" DMB="${4:-}" \
		EXTRA_PARAMS="$params" tools/bot_gym/run_shift_batch.sh "$2" "$MINUTES" fill:40
}

case "${1:-}" in
	run)
		LABEL="${2:?a label}"
		RUNS="${3:-3}"
		if [ "${NOCOMPILE:-0}" != "1" ]; then compile; fi
		EVENTS_ON="${EVENTS:-1}" JOBS="${JOBS:-3}" batch "$LABEL" "$RUNS" "${BASE_PORT:-46000}"
		python tools/bot_gym/stress_report.py "$LABEL"
		;;
	save)
		LABEL="${2:?a label}"
		if [ "${NOCOMPILE:-0}" != "1" ]; then compile; fi
		mkdir -p data/stress_builds
		cp hippiestation.dmb "data/stress_builds/$LABEL.dmb"
		cp hippiestation.rsc "data/stress_builds/$LABEL.rsc"
		echo "Saved data/stress_builds/$LABEL.dmb"
		;;
	ab)
		A="${2:?label A}"
		B="${3:?label B}"
		RUNS="${4:-3}"
		for L in "$A" "$B"; do
			[ -f "data/stress_builds/$L.dmb" ] || { echo "No data/stress_builds/$L.dmb: save it first"; exit 1; }
		done
		export JOBS="${JOBS:-2}"
		export EVENTS_ON="${EVENTS:-0}" # random events blur small gains: off for comparisons unless EVENTS=1
		START=$(date +%s)
		batch "$A" "$RUNS" "${BASE_PORT:-46000}" "data/stress_builds/$A.dmb" > "data/stress-$A.out" 2>&1 &
		sleep 2
		batch "$B" "$RUNS" "$((${BASE_PORT:-46000} + 100))" "data/stress_builds/$B.dmb" > "data/stress-$B.out" 2>&1 &
		wait
		echo "Both builds done in $((($(date +%s) - START) / 60))m $((($(date +%s) - START) % 60))s"
		python tools/bot_gym/stress_report.py "$A" --vs "$B"
		;;
	*)
		sed -n '2,16p' "$0"
		exit 1
		;;
esac
