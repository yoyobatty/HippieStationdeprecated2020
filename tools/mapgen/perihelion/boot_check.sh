#!/bin/bash
unset __COMPAT_LAYER # with this set, dm.exe leaks two kernel handles for every file it opens until the next reboot
# Boot Perihelion headless with a bot crew and stop when the round ends (or at the limit).
# Usage: tools/mapgen/perihelion/boot_check.sh [label] [minutes] [crew] [mode]
#   NOCOMPILE=1 reuses perihelion.mdme.dmb from the last run.  SPEED=0 timewarp limit (0 = none).
# Logs: data/logs/perihelion/<label>/ (game.log, runtime.log, world.log ...), dd output in dd_out.log there.
set -u
cd "$(dirname "$0")/../../.."
BYOND_BIN="${BYOND_BIN:-/c/Program Files (x86)/BYOND/bin}"
LABEL="${1:-boot}"
MINUTES="${2:-15}"
CREW="${3:-20}"
MODE="${4:-extended}"
PORT="${PORT:-45390}"
SPEED="${SPEED:-0}"
DIR="data/logs/perihelion/$LABEL"
START=$(date +%s)

if [ "${NOCOMPILE:-0}" != "1" ] || [ ! -f perihelion.mdme.dmb ]; then
	cp hippiestation.dme perihelion.mdme
	"$BYOND_BIN/dm.exe" perihelion.mdme | grep -E "error|warning|dmb -" || true
fi
[ -f perihelion.mdme.dmb ] || { echo "Build failed"; exit 1; }
echo "built after $(( $(date +%s) - START )) s"

rm -rf "$DIR"
mkdir -p "$DIR/config"
cp config/*.txt config/*.json "$DIR/config/"
sed -i -E 's/^(BOT_CREW_TARGET|LOBBY_COUNTDOWN|MAPROTATION|RESUME_AFTER_INITIALIZATIONS)\b/#&/' "$DIR"/config/*.txt
printf '\nBOT_CREW_TARGET %s\nLOBBY_COUNTDOWN 15\nRESUME_AFTER_INITIALIZATIONS\n' "$CREW" >> "$DIR/config/config.txt"
cp -f data/next_map.json "$DIR/next_map.json.bak" 2>/dev/null || true

params="config=$DIR/config&log-directory=perihelion/$LABEL&bot-map=perihelion&bot-mode=$MODE&bot-round-limit=$MINUTES"
if [ "$SPEED" != "1" ] && [ -f timewarp.dll ]; then params="$params&timewarp=$SPEED"; fi
cp perihelion.mdme.dmb "peri_$LABEL.dmb"
cp perihelion.mdme.rsc "peri_$LABEL.rsc"
"$BYOND_BIN/dd.exe" "peri_$LABEL.dmb" "$PORT" -trusted -invisible -params "$params" > "$DIR/dd_out.log" 2>&1 &
DD=$!
limit=$(( MINUTES * 75 + 600 ))
while kill -0 $DD 2>/dev/null; do
	sleep 5
	if grep -q "The round has ended." "$DIR/game.log" 2>/dev/null; then sleep 10; break; fi
	if [ "${STOP_AT_START:-0}" = "1" ] && grep -q "Round started\|The round has started\|Welcome to Perihelion" "$DIR/game.log" 2>/dev/null; then sleep "${AFTER_START:-60}"; break; fi
	if [ $(( $(date +%s) - START )) -gt $limit ]; then echo "still going after $limit s - stopped"; break; fi
done
kill $DD 2>/dev/null; sleep 2; kill -9 $DD 2>/dev/null
rm -f "peri_$LABEL.dmb" "peri_$LABEL.rsc"
cp -f "$DIR/next_map.json.bak" data/next_map.json 2>/dev/null || true
echo "took $(( $(date +%s) - START )) s; logs in $DIR"
