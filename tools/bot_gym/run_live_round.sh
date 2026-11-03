#!/bin/bash
unset __COMPAT_LAYER # with this set, dm.exe leaks two kernel handles for every file it opens until the next reboot
# A live round with nobody connected: no harness, the lobby and the round type the way a server has them, and the bot crew topping it
# up (bots_ai/bot_population.dm). For what Bot Gym and Bot Shift skip, which is all of SSticker.setup(): the roll, the antagonists the
# mode picks (bots_ai/bot_round_type.dm), the muster. It stops when the round has ended, or at the limit, which ends it properly so
# the round-end report is written.
# Usage: tools/bot_gym/run_live_round.sh [mode] [minutes] [crew]
#   tools/bot_gym/run_live_round.sh                    # secret, as a server rolls it, up to 60 minutes, 20 crew
#   tools/bot_gym/run_live_round.sh cult 45 30         # a cult round, 30 crew
#   RUNS=3 tools/bot_gym/run_live_round.sh nuclear 40 30   # three at once
# Environment:
#   RUNS=1       rounds, all at once (each wants about 1.6 GB and one core)
#   SPEED=0      timewarp's limit, 0 for none      NAME=label   results in data/logs/live_round/<name>/run<n>/
#   NOCOMPILE=1  use the hippiestation.dmb there   PORT=45300   the first one's port
# The map is the one data/next_map.json names, as on a server. MAPROTATION is off in the copied config, so it isn't changed.
set -u
cd "$(dirname "$0")/../.."
BYOND_BIN="${BYOND_BIN:-/c/Program Files (x86)/BYOND/bin}"
MODE="${1:-secret}"
MINUTES="${2:-60}"
CREW="${3:-20}"
RUNS="${RUNS:-1}"
SPEED="${SPEED:-0}"
PORT="${PORT:-45300}"
STAMP="$(date +%m%d-%H%M%S)"
NAME="${NAME:-$MODE-$STAMP}"
DIR="data/logs/live_round/$NAME"

if [ "${NOCOMPILE:-0}" != "1" ]; then
	echo "Compiling..."
	"$BYOND_BIN/dm.exe" hippiestation.dme | grep -E "error|warning|dmb -" || true
fi
if [ ! -f hippiestation.dmb ]; then echo "Compile failed"; exit 1; fi

rm -rf "$DIR"
mkdir -p "$DIR/config"
cp config/*.txt config/*.json "$DIR/config/"
# What the test sets, out of wherever the real config has it, and then ours.
sed -i -E 's/^(BOT_CREW_TARGET|LOBBY_COUNTDOWN|MAPROTATION|RESUME_AFTER_INITIALIZATIONS)\b/#&/' "$DIR"/config/*.txt
printf '\nBOT_CREW_TARGET %s\nLOBBY_COUNTDOWN 15\nRESUME_AFTER_INITIALIZATIONS\n' "$CREW" >> "$DIR/config/config.txt"
cp -f data/next_map.json "$DIR/next_map.json.bak" 2>/dev/null || true

run_one() {
	local n=$1
	local out="$DIR/run$n"
	mkdir -p "$out"
	cp hippiestation.dmb "live_${STAMP}_$n.dmb"
	cp hippiestation.rsc "live_${STAMP}_$n.rsc"
	local params="config=$DIR/config&log-directory=live_round/$NAME/run$n&bot-mode=$MODE&bot-round-limit=$MINUTES"
	if [ "$SPEED" != "1" ] && [ -f timewarp.dll ]; then params="$params&timewarp=$SPEED"; fi
	local began
	began=$(date +%s)
	"$BYOND_BIN/dd.exe" "live_${STAMP}_$n.dmb" $((PORT + n)) -trusted -invisible -params "$params" > "$out/dd_out.log" 2>&1 &
	local dd=$!
	# The round ends and the world reboots into a new lobby in the same process: stop it once the round's over.
	local limit=$((MINUTES * 75 + 900))
	while kill -0 $dd 2>/dev/null; do
		sleep 5
		if grep -q "The round has ended." "$out/game.log" 2>/dev/null; then
			sleep 10 #the round-end report
			break
		fi
		if [ $(($(date +%s) - began)) -gt $limit ]; then
			echo "run $n: still going after $limit s - stopped"
			break
		fi
	done
	kill $dd 2>/dev/null
	sleep 2
	kill -9 $dd 2>/dev/null
	rm -f "live_${STAMP}_$n".*
	local took=$(($(date +%s) - began))
	echo "run $n took $((took / 60))m $((took % 60))s"
}

echo "Running $RUNS live round(s): $MODE, $CREW crew, up to $MINUTES minutes -> $DIR"
for n in $(seq 1 "$RUNS"); do
	run_one "$n" &
	sleep 3
done
wait
cp -f "$DIR/next_map.json.bak" data/next_map.json 2>/dev/null || true
python tools/bot_gym/live_round_report.py "$DIR" | tee "$DIR/report.txt"
