#!/bin/bash
unset __COMPAT_LAYER # with this set, dm.exe leaks two kernel handles for every file it opens until the next reboot
# Lighting bench: compile, boot headless, time the lighting engine and snapshot the station's lighting, print the results.
# Usage: tools/lighting_bench/run_lighting_bench.sh [profile|starlight|directional|tail]
#   engines: boot with the lighting engine and compare it with the DM code (EXTRA_PARAMS is added to the params)
#   profile: also runs the workloads once more under BYOND's profiler, into data/lighting_bench/profile_<mode>.json
#   starlight: also snapshots starlight as tgstation had it in 2020, as it is, and that with bounce lighting
#              (then: python tools/lighting_bench/render.py --before starlight_2020 --after starlight)
#   directional: also tries out directional lights (then: render.py --before directional_omni --after directional_cone)
#   tail: also tries the soft falloff at a few lengths (then: render.py --before tail_1 --after tail_1.4)
# Then draw the snapshots over the map: python tools/lighting_bench/render.py (needs Pillow and numpy)
# Set BYOND_BIN to override the BYOND path, BENCH_TIMEOUT to give up on the run after that many seconds (default 3600),
# and PORT for the server's port (default 45124).
# Builds its own copy (lightingbench.mdme -> lightingbench.mdme.dmb), so hippiestation.dmb is left alone for whatever else
# is running. A trial lighting library goes in EXTRA_PARAMS: EXTRA_PARAMS="lighting-lib=hippie_lighting_try".
# DMB=data/stress_builds/<label>.dmb runs a build already made (its .rsc beside it) instead of compiling one, and OUT=<dir>
# moves the results to that folder afterwards (data/lighting_bench is the next run's), for before/after runs side by side.
# What differs between two snapshots: python tools/lighting_bench/snapshot_diff.py --a booted --b relit
set -u
cd "$(dirname "$0")/../.."
BYOND_BIN="${BYOND_BIN:-/c/Program Files (x86)/BYOND/bin}"
OPTION="${1:-1}"
PORT="${PORT:-45124}"

if [ -n "${DMB:-}" ]; then
	cp "$DMB" lightingbench.mdme.dmb
	cp "${DMB%.dmb}.rsc" lightingbench.mdme.rsc
else
	cp hippiestation.dme lightingbench.mdme
	echo "Compiling..."
	"$BYOND_BIN/dm.exe" lightingbench.mdme | grep -E "error|warning|dmb -" || true
fi
if [ ! -f lightingbench.mdme.dmb ]; then echo "Compile failed"; rm -f lightingbench.mdme; exit 1; fi

rm -rf data/lighting_bench
echo "Running lighting bench..."
timeout "${BENCH_TIMEOUT:-3600}" "$BYOND_BIN/dd.exe" lightingbench.mdme.dmb "$PORT" -trusted -invisible \
	-params "lighting-bench=$OPTION${EXTRA_PARAMS:+&$EXTRA_PARAMS}" > data/lighting_bench_dd.log 2>&1
rm -f lightingbench.mdme lightingbench.mdme.dmb lightingbench.mdme.rsc lightingbench.mdme.int lightingbench.mdme.lk lightingbench.mdme.dyn.rsc lightingbench.mdme.rsc.lk lightingbench.mdme.dyn.rsc.lk

if [ ! -f data/lighting_bench/results.txt ]; then
	echo "No results written - see data/lighting_bench_dd.log"
	tail -20 data/lighting_bench_dd.log
	exit 1
fi
cat data/lighting_bench/results.txt
echo
if [ -n "${OUT:-}" ]; then
	rm -rf "$OUT"
	mv data/lighting_bench "$OUT"
	echo "Snapshots: $OUT/snapshot_*.txt"
else
	echo "Snapshots: data/lighting_bench/snapshot_*.txt"
fi
