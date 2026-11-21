"""Mining shuttle ping-pong finder.

A bot that rides the mining shuttle somewhere and sends it straight back the moment it arrives, with nobody getting on or off, is a
loop, not a trip. This lists, per run, each bot's sends of the mining shuttle that came within N seconds of its own arrival.

    python tools/bot_gym/shuttle_pingpong.py <batch dir or run dir> [seconds=3]
"""
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import logread  # noqa: E402

ARRIVE = re.compile(r"^\[[\d-]+ ([\d:.]+)\] ADMIN: BOT AI: (.+?): arrived at (mining_\w+)")
SEND = re.compile(r"^\[[\d-]+ ([\d:.]+)\] ADMIN: BOT AI: (.+?): sent the mining shuttle to (mining_\w+)")


def secs(t):
    h, m, s = t.split(":")
    return int(h) * 3600 + int(m) * 60 + float(s)


def runs_of(path):
    if os.path.isdir(os.path.join(path, "run1")) or any(n.startswith("run") for n in os.listdir(path)):
        subs = sorted((os.path.join(path, n) for n in os.listdir(path) if n.startswith("run")), key=lambda p: int(re.sub(r"\D", "", os.path.basename(p)) or 0))
        if subs:
            return subs
    return [path]


def main():
    path = sys.argv[1]
    window = float(sys.argv[2]) if len(sys.argv) > 2 else 3.0
    total = 0
    for run in runs_of(path):
        game = logread.find(run, "game")
        if not game:
            continue
        arrived = {}
        quick = {}
        for line in logread.lines(game):
            m = ARRIVE.match(line)
            if m:
                arrived[m.group(2)] = secs(m.group(1))
                continue
            m = SEND.match(line)
            if m:
                t = secs(m.group(1))
                a = arrived.get(m.group(2))
                if a is not None and t - a <= window:
                    quick[m.group(2)] = quick.get(m.group(2), 0) + 1
        for name, n in sorted(quick.items(), key=lambda kv: -kv[1]):
            print(f"{os.path.basename(run)}  {name}: {n} sends within {window:g} s of arriving")
            total += n
    print(f"total quick sends: {total}")


if __name__ == "__main__":
    main()
