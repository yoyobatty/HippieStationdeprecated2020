#!/bin/bash
# Does the tesla survive losing its power? Runs short shifts with the standard crew, knocks the engine's power out at 7 minutes
# with it running, and says what happened. Takes about 6 minutes.
#   cable1     cuts the cable under one emitter, the way a mouse would
#   cable4     cuts the cable under all four at once
#   gridcheck  the real Grid Check random event
#   blackout   power_failure(), the admin button: every SMES emptied and switched off
# Usage: tools/bot_gym/engine_tests.sh [runs of each] [tests]    results in data/logs/shift_batch/engine_<test>/
set -u
cd "$(dirname "$0")/../.."
RUNS="${1:-3}"
TESTS="${2:-cable1 cable4 gridcheck blackout}"
CREW="Chief Engineer,Station Engineer*2,Atmospheric Technician,Botanist,Medical Doctor,Chemist,Security Officer,Assistant*2,Janitor,Cook,Bartender,Scientist,Cargo Technician,Quartermaster"
for t in $TESTS; do
	NAME="engine_$t" JOBS=3 NOCOMPILE=1 EXTRA_PARAMS="engine-test=$t" tools/bot_gym/run_shift_batch.sh "$RUNS" 12 "$CREW" > /dev/null 2>&1
	echo "=== $t"
	for r in $(seq 1 "$RUNS"); do
		S="data/logs/shift_batch/engine_$t/run$r/summary.txt"
		T="data/logs/shift_batch/engine_$t/run$r/timeline.txt"
		echo "run$r dead=$(grep -c 'died at' "$S") | $(grep -E 'tesla still contained' "$S" | cut -c8-120)"
		grep -E "engine test: cutting" "$T" | cut -c1-80
		grep -E "emitters are down|cable's fixed|turned on|activated the" "data/logs/shift_batch/engine_$t/run$r/game.log" | tail -2 | sed -E 's/^\[[^ ]+ ([0-9:]+)\.[0-9]+\] [A-Z]+: (BOT AI: )?/\1 /; s/\(<a href[^)]*\)//g' | cut -c1-80
		# Emitters and the ring through the test
		grep -E " engine: " "$T" | sed -E 's/  engine: field generators/ fg/; s/ online holding / hold /; s/ of [0-9]+; emitters / em /; s/ firing; / /; s/ W on their grid against a load of /W, load /; s/ W; / /; s/ full set to / out /; s/ W out;.*//' | tail -7 | cut -c1-80
	done
done
