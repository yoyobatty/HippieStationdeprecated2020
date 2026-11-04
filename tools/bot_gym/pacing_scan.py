"""Bots pacing: eight or more steps inside 20 seconds of game time without leaving two or three tiles, counted by what they were doing
(state, goal, step). Pacing back and forth is one of the things that looks least human (the user, 2026-11-03); this found explorers at
the edge of a lava river and two officers swapping each other off the tile beside a suspect.

Usage: python tools/bot_gym/pacing_scan.py <run dir> [run dir...]
  python tools/bot_gym/pacing_scan.py data/logs/shift_batch/night11/run*
"""
import collections
import json
import sys

WINDOW = 200  # deciseconds of game time (telemetry's "t")
MIN_MOVES = 8
MAX_TILES = 3


def scan(run):
    """(state, goal, step) -> list of "bot t=... tiles" for one run's telemetry."""
    found = collections.defaultdict(list)
    samples = collections.defaultdict(list)
    try:
        f = open(run + "/bot_telemetry.jsonl", encoding="utf-8", errors="replace")
    except OSError:
        return found
    with f:
        for line in f:
            i = line.find("{")
            if i < 0 or '"k":"s"' not in line:
                continue
            try:
                j = json.loads(line[i:])
            except ValueError:
                continue
            samples[j["b"]].append((j["t"], (j["x"], j["y"], j["z"]), j.get("st"), j.get("g"), j.get("step")))
    for bot, seq in samples.items():
        start = 0
        flagged_until = -1
        for end in range(len(seq)):
            while seq[end][0] - seq[start][0] > WINDOW:
                start += 1
            if seq[end][0] < flagged_until:
                continue
            window = seq[start:end + 1]
            moves = sum(1 for a, b in zip(window, window[1:]) if a[1] != b[1])
            tiles = {s[1] for s in window}
            if moves >= MIN_MOVES and len(tiles) <= MAX_TILES:
                key = (window[-1][2], window[-1][3] or "-", window[-1][4] or "-")
                found[key].append("%s t=%.0f %s" % (bot, window[0][0], sorted(tiles)))
                flagged_until = seq[end][0] + WINDOW
    return found


def main(runs):
    if not runs:
        print(__doc__)
        return 2
    total = collections.defaultdict(list)
    for run in runs:
        for key, hits in scan(run).items():
            total[key] += ["%s %s" % (run.replace("\\", "/").rstrip("/").split("/")[-1], h) for h in hits]
    for key, hits in sorted(total.items(), key=lambda kv: -len(kv[1])):
        print(len(hits), key)
        for h in hits[:3]:
            print("     ", h)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
