#!/bin/bash
unset __COMPAT_LAYER # with this set, dm.exe leaks two kernel handles for every file it opens until the next reboot
# Mob storm (mob_storm.dm): the 2026-11-11 pile of clown cats and ash drakes on one tile, headless, timed.
#   tools/mob_storm/run.sh build <name>          builds mobstorm_<name>.mdme.dmb from the code as it is now
#   tools/mob_storm/run.sh run <name> [label]    one run of it, results in data/mob_storm/<label>.txt
#   tools/mob_storm/run.sh clean                 removes the builds
# SECONDS=180 real seconds from the first spawn (conveyor: measured seconds, default 60), MAP=testbench (any _maps/*.json name),
# PORT=45417, SCENARIO=pile (the ash drake pile) or conveyor (two facing belts, corpses and glass;
# SHARDS=50 a tile)
set -u
cd "$(dirname "$0")/../.."
BYOND_BIN="${BYOND_BIN:-/c/Program Files (x86)/BYOND/bin}"
PORT="${PORT:-45417}"
MAP="${MAP:-testbench}"
SECONDS_RUN="${SECONDS:-180}"

build() {
	cp hippiestation.dme "mobstorm_$1.mdme"
	printf '#include "tools\\mob_storm\\mob_storm.dm"\r\n' >> "mobstorm_$1.mdme"
	"$BYOND_BIN/dm.exe" "mobstorm_$1.mdme" | grep -E "error|warning|dmb -"
	rm -f "mobstorm_$1.mdme" "mobstorm_$1.mdme.int" "mobstorm_$1.mdme.lk"
	[ -f "mobstorm_$1.mdme.dmb" ] || { echo "Build failed"; exit 1; }
}

run() {
	local label="$2" began dd
	mkdir -p data/mob_storm
	rm -f "data/mob_storm/$label.txt"
	rm -rf "data/logs/mob_storm_$label"
	began=$(date +%s)
	"$BYOND_BIN/dd.exe" "mobstorm_$1.mdme.dmb" "$PORT" -trusted -invisible \
		-params "mob-storm=1&mob-storm-label=$label&mob-storm-seconds=$SECONDS_RUN&mob-storm-scenario=${SCENARIO:-pile}&mob-storm-shards=${SHARDS:-50}&mc-watch-all=1&log-directory=mob_storm_$label&bot-map=$MAP" > /dev/null 2>&1 &
	dd=$!
	while kill -0 $dd 2>/dev/null; do
		sleep 2
		grep -q "^done" "data/mob_storm/$label.txt" 2>/dev/null && break
		if [ $(($(date +%s) - began)) -gt $((SECONDS_RUN + 900)) ]; then echo "still going after $((SECONDS_RUN + 900)) s - stopped"; break; fi
	done
	sleep 2
	kill $dd 2>/dev/null; sleep 1; kill -9 $dd 2>/dev/null
	echo "took $(($(date +%s) - began)) s"
	cat "data/mob_storm/$label.txt" 2>/dev/null || echo "no results: see data/logs/mob_storm_$label"
	echo "runtimes: $(grep -c 'runtime error' "data/logs/mob_storm_$label/runtime.log" 2>/dev/null)"
	grep -h 'runtime error' "data/logs/mob_storm_$label/runtime.log" 2>/dev/null | sed 's/^\[[^]]*\] //' | sort | uniq -c | sort -rn | head -10
}

case "$1" in
	build) build "$2" ;;
	run) run "$2" "${3:-$2}" ;;
	clean) rm -f mobstorm_*.mdme* ;;
esac
