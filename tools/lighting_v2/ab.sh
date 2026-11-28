#!/bin/bash
unset __COMPAT_LAYER
# Lighting v2 before/after in one boot: pictures of each scene with v2 off, lighting_v2_set(1), the same again, then sheets.
# The server must have started with lighting-v2=0. Usage: tools/lighting_v2/ab.sh PORT BEFORE_TAG AFTER_TAG [scene ...]
# ABKIT=N then also measures the server's cost of v2 with devkit's abkit (~/devkit, or DEVKIT_ROOT), in the same boot:
# N rounds of v2 off/on/on/off windows (one warm-up pair first, dropped), world.map_cpu and world.cpu averaged over each
# window with the client connected, then medians, a confidence interval and a verdict; saved in
# devkit/data/abkit/lighting_v2_ab/<time>/. ABKIT_SECONDS (20) per window, ABKIT_SETTLE (15) after each switch.
cd "$(dirname "$0")/../.."
PORT=$1; BEFORE=$2; AFTER=$3; shift 3
SCENES="${*:-bar maint engine planet breach}"
while tasklist | grep -qi dreamseeker; do echo "waiting for DreamSeeker to close"; sleep 20; done
python tools/lighting_v2/shot.py --port "$PORT" --tag "$BEFORE" $SCENES || exit 1
python -c "
import sys,time; sys.path.insert(0,'tools/testkit'); import tk; s=tk.load_server($PORT); t=time.time()
print('v2 on:', s.call('call', ref='global', proc='lighting_v2_set', args=[1]), '%.1f s' % (time.time()-t))"
python tools/lighting_v2/shot.py --port "$PORT" --tag "$AFTER" --wait 22 $SCENES || exit 1
python tools/lighting_v2/pair.py "$BEFORE" "$AFTER" $SCENES
if [ "${ABKIT:-0}" != "0" ]; then
python - "$PORT" "$ABKIT" <<'PY'
import os, statistics, sys, time
sys.path[:0] = ["tools/testkit", "tools/lighting_v2", os.environ.get("DEVKIT_ROOT", os.path.expanduser("~/devkit"))]
import tk, shot
from devkit.tools.abkit import api
s = tk.load_server(int(sys.argv[1]))
shot.connect(s)
shot.crew_sight(s)
state = [None]
def set_arm(arm):  # A: v2 off, B: v2 on; a switch only when the state changes
    if state[0] != arm:
        s.call("call", ref="global", proc="lighting_v2_set", args=[1 if arm == "B" else 0])
        state[0] = arm
        time.sleep(float(os.environ.get("ABKIT_SETTLE", 15)))
def measure(arm):
    cpu, mcpu = [], []
    for _ in range(int(os.environ.get("ABKIT_SECONDS", 20))):
        st = s.call("status")
        cpu.append(st["cpu"])
        mcpu.append(st["map_cpu"])
        time.sleep(1)
    return {"map_cpu": statistics.mean(mcpu), "cpu": statistics.mean(cpu)}
api.abba("lighting_v2_ab", set_arm, measure, rounds=int(sys.argv[2]), warmups=1, meta={"port": sys.argv[1], "A": "v2 off", "B": "v2 on"})
PY
fi
python -c "
import sys,time; sys.path.insert(0,'tools/testkit'); import tk; s=tk.load_server($PORT); print('v2 off:', s.call('call', ref='global', proc='lighting_v2_set', args=[0]))"
python tools/testkit/client_lane.py close --port "$PORT" 2>/dev/null
