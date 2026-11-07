#!/bin/bash
unset __COMPAT_LAYER # with this set, dm.exe leaks two kernel handles for every file it opens until the next reboot
# The CPU stress bench (hippiestation/code/modules/bots_ai/gym/stress_bench.dm): Hippie Station with 40 bot crew, two traitors, random
# events and a fixed list of disasters (aurora, grid check, rad storm, plasma fire, hull breaches, meteors, maxcap, tesla), timed phase
# by phase. A run is about 27 game minutes; with timewarp that's several real minutes, more while the disasters are on.
#
# Usage:
#   tools/bot_gym/run_stress_bench.sh run <label> [runs]          compile, then [runs] (3) runs of this build (BUILD=<saved label>
#                                                                 runs a saved build instead)
#   tools/bot_gym/run_stress_bench.sh save <label>                compile a side copy and keep it as data/stress_builds/<label>.dmb
#   tools/bot_gym/run_stress_bench.sh ab <labelA> <labelB> [runs] two saved builds side by side, [runs] (3) each, running at the
#                                                                 same time so both see the same machine load. BUILD_A/BUILD_B
#                                                                 run another saved build under that label
# Environment: JOBS (servers at once for each build: 3 for run, 2 each for ab), NOCOMPILE=1, PROFILE=1, BASE_PORT, EXTRA_PARAMS,
#   EVENTS=0/1 random events (on for run, off for ab: they change from run to run and blur small gains; the disasters always happen)
#   EXTRA_A, EXTRA_B  world params for one side of an ab only, like EXTRA_B="lighting-engine=native" to set one build against itself
#   EXTRA_PARAMS=stress-calm=1  an ordinary shift of the same length instead of the disasters (see stress_bench.dm)
# Results: data/logs/shift_batch/stress-<label>/run<n>/stress.txt and stress.json; the report at the end is
#   python tools/bot_gym/stress_report.py <label> [--vs <label>]
set -u
cd "$(dirname "$0")/../.."
BYOND_BIN="${BYOND_BIN:-/c/Program Files (x86)/BYOND/bin}"
MINUTES=27

# Compiles a side copy of the .dme (stressbench.mdme, gitignored) and keeps the build as data/stress_builds/<label>.dmb: another
# session compiling hippiestation.dme at the same time can't hand a run half of one build and half of another. With NOCOMPILE=1
# it keeps hippiestation.dmb as it is instead.
save_build() { # label
	mkdir -p data/stress_builds
	if [ "${NOCOMPILE:-0}" = "1" ]; then
		cp hippiestation.dmb "data/stress_builds/$1.dmb"
		cp hippiestation.rsc "data/stress_builds/$1.rsc"
	else
		cp hippiestation.dme stressbench.mdme
		local out
		out="$("$BYOND_BIN/dm.exe" stressbench.mdme | grep -E "error|warning|dmb -")"
		echo "$out"
		echo "$out" | grep -q "dmb - 0 errors" || { echo "Compile failed"; rm -f stressbench.mdme*; exit 1; }
		mv stressbench.mdme.dmb "data/stress_builds/$1.dmb"
		mv stressbench.mdme.rsc "data/stress_builds/$1.rsc"
		rm -f stressbench.mdme stressbench.mdme.*
	fi
	echo "Saved data/stress_builds/$1.dmb"
}

batch() { # label runs port [dmb] [more params]
	local params="stress-bench=1"
	if [ -n "${EXTRA_PARAMS:-}" ]; then params="$params&$EXTRA_PARAMS"; fi
	if [ -n "${5:-}" ]; then params="$params&$5"; fi
	NAME="stress-$1" MAPS=hippiestation EVENTS="$EVENTS_ON" QUIET=1 ANTAGS='traitor*2' NOCOMPILE=1 BASE_PORT="$3" DMB="${4:-}" \
		EXTRA_PARAMS="$params" tools/bot_gym/run_shift_batch.sh "$2" "$MINUTES" fill:40
}

case "${1:-}" in
	run)
		LABEL="${2:?a label}"
		RUNS="${3:-3}"
		BUILD="${BUILD:-}"
		if [ -z "$BUILD" ]; then
			BUILD="run-$LABEL"
			save_build "$BUILD"
		fi
		EVENTS_ON="${EVENTS:-1}" JOBS="${JOBS:-3}" batch "$LABEL" "$RUNS" "${BASE_PORT:-46000}" "data/stress_builds/$BUILD.dmb"
		python tools/bot_gym/stress_report.py "$LABEL"
		;;
	save)
		save_build "${2:?a label}"
		;;
	ab)
		A="${2:?label A}"
		B="${3:?label B}"
		RUNS="${4:-3}"
		for L in "${BUILD_A:-$A}" "${BUILD_B:-$B}"; do
			[ -f "data/stress_builds/$L.dmb" ] || { echo "No data/stress_builds/$L.dmb: save it first"; exit 1; }
		done
		export JOBS="${JOBS:-2}"
		export EVENTS_ON="${EVENTS:-0}" # random events blur small gains: off for comparisons unless EVENTS=1
		START=$(date +%s)
		batch "$A" "$RUNS" "${BASE_PORT:-46000}" "data/stress_builds/${BUILD_A:-$A}.dmb" "${EXTRA_A:-}" > "data/stress-$A.out" 2>&1 &
		sleep 2
		batch "$B" "$RUNS" "$((${BASE_PORT:-46000} + 100))" "data/stress_builds/${BUILD_B:-$B}.dmb" "${EXTRA_B:-}" > "data/stress-$B.out" 2>&1 &
		wait
		echo "Both builds done in $((($(date +%s) - START) / 60))m $((($(date +%s) - START) % 60))s"
		python tools/bot_gym/stress_report.py "$A" --vs "$B"
		;;
	*)
		sed -n '2,16p' "$0"
		exit 1
		;;
esac
