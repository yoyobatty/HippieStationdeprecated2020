#!/bin/bash
# Lighting bench: compile, boot headless, time the lighting engine and snapshot the station's lighting, print the results.
# Usage: tools/lighting_bench/run_lighting_bench.sh [profile|starlight|directional|tail]
#   profile: also runs the workloads once more under BYOND's profiler, into data/lighting_bench/profile_<mode>.json
#   starlight: also snapshots starlight as tgstation had it in 2020, as it is, and that with bounce lighting
#              (then: python tools/lighting_bench/render.py --before starlight_2020 --after starlight)
#   directional: also tries out directional lights (then: render.py --before directional_omni --after directional_cone)
#   tail: also tries the soft falloff at a few lengths (then: render.py --before tail_1 --after tail_1.4)
# Then draw the snapshots over the map: python tools/lighting_bench/render.py (needs Pillow and numpy)
# Set BYOND_BIN to override the BYOND path, and BENCH_TIMEOUT to give up on the run after that many seconds (default 3600).
set -u
cd "$(dirname "$0")/../.."
BYOND_BIN="${BYOND_BIN:-/c/Program Files (x86)/BYOND/bin}"
OPTION="${1:-1}"

echo "Compiling..."
"$BYOND_BIN/dm.exe" hippiestation.dme | grep -E "error|warning|dmb -" || true
if [ ! -f hippiestation.dmb ]; then echo "Compile failed"; exit 1; fi

rm -rf data/lighting_bench
echo "Running lighting bench..."
timeout "${BENCH_TIMEOUT:-3600}" "$BYOND_BIN/dd.exe" hippiestation.dmb 45124 -trusted -invisible \
	-params "lighting-bench=$OPTION" > data/lighting_bench_dd.log 2>&1

if [ ! -f data/lighting_bench/results.txt ]; then
	echo "No results written - see data/lighting_bench_dd.log"
	tail -20 data/lighting_bench_dd.log
	exit 1
fi
cat data/lighting_bench/results.txt
echo
echo "Snapshots: data/lighting_bench/snapshot_*.txt"
