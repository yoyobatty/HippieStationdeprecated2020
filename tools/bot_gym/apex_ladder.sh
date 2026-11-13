#!/bin/bash
unset __COMPAT_LAYER # with this set, dm.exe leaks two kernel handles for every file it opens until the next reboot
# The duel ladder (hippiestation/code/modules/bots_ai/gym/scenarios_duels.dm): every "duel:" pairing run RUNS times, and the share each
# first bot came out ahead in. The pairings come in twos (with what's being measured, and without), so read them side by side.
# Usage: tools/bot_gym/apex_ladder.sh [runs=8] [filter="duel: "]
#   NOCOMPILE=1 tools/bot_gym/apex_ladder.sh 10
set -u
cd "$(dirname "$0")/../.."
RUNS="${1:-8}"
FILTER="${2:-duel: }"
OUT_DIR="${OUT:-data/apex_ladder}"
NOCOMPILE="${NOCOMPILE:-0}" OUT="$OUT_DIR" RERUN=0 tools/bot_gym/run_bot_gym.sh "$FILTER" "$RUNS" > "$OUT_DIR.out" 2>&1
echo "Duel ladder, $RUNS runs each (first bot's wins):"
python - "$OUT_DIR/results.json" <<'PY'
import json, sys, collections
runs = collections.Counter()
wins = collections.Counter()
for r in json.load(open(sys.argv[1])):
    runs[r["name"]] += 1
    wins[r["name"]] += r["outcome"] == "PASS"
for name in sorted(runs):
    print("  %3d%%  %d/%d  %s" % (100 * wins[name] // runs[name], wins[name], runs[name], name))
PY
