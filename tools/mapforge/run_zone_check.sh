#!/bin/bash
unset __COMPAT_LAYER # with this set, dm.exe leaks two kernel handles for every file it opens until the next reboot
# Boot a mapforge build headless and check its zone in the engine.
# Usage: tools/mapforge/run_zone_check.sh <name> x1,y1,x2,y2 [base]
#   name: data/mapforge/<name>.dmm (a whole-map copy written by mapforge.py build)
#   base: also run the untouched map json (e.g. hippiestation) for a before/after
# Results: data/mapforge/zone_check_<name>.txt (and _base.txt)
set -u
cd "$(dirname "$0")/../.."
NAME="$1"; ZONE="$2"; BASE="${3:-}"
START=$(date +%s)
cat > "data/mapforge/preview_$NAME.json" <<EOF
{
    "map_name": "mapforge preview $NAME",
    "map_path": "../data/mapforge",
    "map_file": "$NAME.dmm",
    "shuttles": {"emergency": "${EMERGENCY:-emergency_box}", "ferry": "ferry_fancy", "cargo": "cargo_box", "whiteship": "whiteship_meta"}
}
EOF
run() {
	HARNESS=../mapforge/zone_check.dm EXTRA_PARAMS="bot-map=$1&mapforge-zone=$ZONE&mapforge-wait=${WAIT:-90}&mapforge-name=$2" WAIT_SECONDS=600 \
		PORT="${PORT:-45377}" bash tools/power_check/run.sh "mapforge_$2" > /dev/null
	cp "data/update_check_mapforge_$2.txt" "data/mapforge/zone_check_$2.txt" 2>/dev/null
	echo "== $2"; cat "data/mapforge/zone_check_$2.txt" 2>/dev/null || tail -20 data/update_check_dd.log
	echo "runtimes: $(grep -c 'runtime error' data/update_check_dd.log)"
	grep -A4 "runtime error" data/update_check_dd.log | head -40
}
run "../data/mapforge/preview_$NAME" "$NAME"
[ -n "$BASE" ] && run "$BASE" "${NAME}_base"
echo "took $(( $(date +%s) - START )) s"
