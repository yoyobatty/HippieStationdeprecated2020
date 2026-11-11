#!/bin/bash
unset __COMPAT_LAYER # with this set, dm.exe leaks two kernel handles for every file it opens until the next reboot
# Atmos bench: compile, boot headless, time every stage of SSair over a calm station, a gas release, a plasma fire and
# hull breaches, print the results. See hippiestation/code/modules/atmospherics/atmos_bench.dm.
# Usage: tools/atmos_bench/run_atmos_bench.sh [profile | series | shadow | trace | failover | machine-times | idle-check |
#   blocker-check | toxins-check | door-check | machines]
#   profile: also profiles the scenes, into data/atmos_bench/profile.json (read it with tools/bot_gym/shift_profile.py)
#   series: also prints where a fire's heat is every 5 seconds of each scene
#   shadow: LINDA runs the round and the engine has to predict every tick; says how many turfs it got wrong and shows some.
#     Turfs with a reaction on them are left out, since the engine leaves those to DM.
#   trace: every burning tile tick by tick from the moment of ignition, to compare two runs line by line
#   failover: turns the engine off during the gas release, to check LINDA can carry on from it at any time
#   machine-times: also times SSair's machines by type and its pipe networks one by one
#   idle-check: checks idle vents and scrubbers still wake up when their air changes (run it with ENGINE=linda too)
#   blocker-check: checks every kind of air blocker lets air through once deleted, wrecked or taken apart, and walls too
#   toxins-check: lights the real toxins lab and deletes its firelocks
#   door-check: what shut doors do with the air on their tiles, on the real map (door_seals.dm); EXTRA_PARAMS="door-seals=off" for how it was
#   machines: just counts what's in SSair.atmos_machinery
# Compare runs: tools/atmos_bench/scorecard.py (everything, against LINDA), tools/atmos_bench/compare_runs.py (two builds)
# Environment: SPEED=0 no speed limit (default), SPEED=1 real time; BYOND_BIN, PORT to override the defaults;
#   SKIP_BUILD=1 to run the build that's already there; OUT=<dir> to copy the results somewhere after;
#   ENGINE=linda to run LINDA instead of the tile engine.
#   EXTRA_PARAMS="atmos-bench-seed=3" changes the luck in a run, the spots stay the same. Fires depend a lot on luck, so
#   compare a few seeds of each build. EXTRA_PARAMS="atmos-idle=off" runs every machine every tick.
set -u
cd "$(dirname "$0")/../.."
BYOND_BIN="${BYOND_BIN:-/c/Program Files (x86)/BYOND/bin}"
OPTION="${1:-1}"
SPEED="${SPEED:-0}"
PORT="${PORT:-45126}"

# DMB=<label> runs data/stress_builds/<label>.dmb (tools/bot_gym/run_stress_bench.sh save <label>) instead, from a copy of its own
WORLD=hippiestation
if [ -n "${DMB:-}" ]; then
	WORLD="atmosbench_${DMB//[^A-Za-z0-9_-]/_}"
	cp "data/stress_builds/$DMB.dmb" "$WORLD.dmb" && cp "data/stress_builds/$DMB.rsc" "$WORLD.rsc" || exit 1
	trap 'rm -f "$WORLD".dmb "$WORLD".rsc "$WORLD".dyn.rsc "$WORLD".*.lk' EXIT
elif [ -z "${SKIP_BUILD:-}" ]; then
	echo "Compiling..."
	"$BYOND_BIN/dm.exe" hippiestation.dme | grep -E "error|warning|dmb -" || true
fi
if [ ! -f "$WORLD.dmb" ]; then echo "Compile failed"; exit 1; fi

PARAMS="atmos-bench=$OPTION"
if [ "$SPEED" != "1" ] && [ -f timewarp.dll ]; then PARAMS="$PARAMS&timewarp=$SPEED"; fi
# ENGINE=linda runs LINDA instead of the tile engine, for comparing the two
if [ -n "${ENGINE:-}" ]; then PARAMS="$PARAMS&atmos-engine=$ENGINE"; fi
# EXTRA_PARAMS="a=1&b=2" adds more world params, like atmos-bench-seed=3
if [ -n "${EXTRA_PARAMS:-}" ]; then PARAMS="$PARAMS&$EXTRA_PARAMS"; fi

rm -rf data/atmos_bench
mkdir -p data
echo "Running atmos bench ($PARAMS)..."
timeout "${BENCH_TIMEOUT:-1800}" "$BYOND_BIN/dd.exe" "$WORLD.dmb" "$PORT" -trusted -invisible \
	-params "$PARAMS" > data/atmos_bench_dd.log 2>&1

if [ ! -f data/atmos_bench/results.txt ]; then
	echo "No results written - see data/atmos_bench_dd.log"
	tail -20 data/atmos_bench_dd.log
	exit 1
fi
cat data/atmos_bench/results.txt
echo
echo "runtimes: $(grep -c 'runtime error\|Runtime in' data/atmos_bench_dd.log)"
if [ -n "${OUT:-}" ]; then mkdir -p "$OUT" && cp -r data/atmos_bench/. "$OUT/" && cp data/atmos_bench_dd.log "$OUT/"; fi
