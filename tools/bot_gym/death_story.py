"""The last minute of one bot in a Bot Shift run, from every log at once, in time order: what it was doing (its bot_log lines), where
it stood and how hurt it was (telemetry samples, only when they change), what it picked up or dropped, what it said, and who hit it
with what. For a death that the summary line doesn't explain.

Usage: python tools/bot_gym/death_story.py <run dir> "<name>" [wall-clock seconds before, default 10] [-v] [--at HH:MM:SS]
  The logs are stamped in wall-clock time, and a timewarped Bot Shift runs 6-10x faster: 10 seconds is a minute or more of the shift.
  python tools/bot_gym/death_story.py data/logs/shift_batch/night9/run5 "Rowan Kessler"
  -v      the verbose bot_log lines too (routes, obstruction checks), less the noisiest
  --at    end the window at that wall-clock time instead of the death (a bot that got stuck, not killed)
"""
import json
import re
import sys
from datetime import datetime, timedelta

STAMP = re.compile(r"^\[(\d{4}-\d\d-\d\d \d\d:\d\d:\d\d\.\d+)\] ")
LINK = re.compile(r"\s*\(?<a href[^>]*>JMP</a>\)?")
NOISY = ("step_next_node", "obstruction check: the", "is_eva_ready", "adjacent fallback", "  pass ", "repath:")


def stamp(line):
    m = STAMP.match(line)
    return datetime.strptime(m.group(1), "%Y-%m-%d %H:%M:%S.%f") if m else None


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 2
    run, name = argv[0], argv[1]
    verbose = "-v" in argv
    secs = 10
    at = None
    rest = [a for a in argv[2:] if a != "-v"]
    if "--at" in rest:
        at = rest[rest.index("--at") + 1]
        rest = [a for a in rest if a not in ("--at", at)]
    if rest:
        secs = float(rest[0])

    # The summary's own lines for it
    try:
        summary = open(run + "/summary.txt", encoding="utf-8", errors="replace").read().splitlines()
        for i, line in enumerate(summary):
            if name in line and (line.startswith("FAIL") or line.startswith("ok") or line.startswith("WARN") or line.startswith("PASS")):
                print(line.strip())
                j = i + 1
                while j < len(summary) and summary[j].startswith(" "):
                    print("  " + summary[j].strip()[:400])
                    j += 1
                break
    except OSError:
        pass

    attack = open(run + "/attack.log", encoding="utf-8", errors="replace").read().splitlines()
    end = None
    for line in attack:
        if "(%s) has died" % name in line:
            end = stamp(line)
    events = []
    if at:
        day = stamp(attack[0]) if attack else datetime.now()
        end = datetime.strptime(day.strftime("%Y-%m-%d ") + at, "%Y-%m-%d %H:%M:%S")
    for line in attack:
        if "(%s)" % name in line:
            t = stamp(line)
            if t:
                events.append((t, "ATK", LINK.sub("", line[STAMP.match(line).end():]).replace("ATTACK: ", "")))
    for line in open(run + "/game.log", encoding="utf-8", errors="replace"):
        if name not in line:
            continue
        t = stamp(line)
        if not t:
            continue
        body = LINK.sub("", line[STAMP.match(line).end():].rstrip())
        if body.startswith("ADMIN: BOT AI VERBOSE: %s:" % name):
            if verbose and not any(n in body for n in NOISY):
                events.append((t, "ai-", body.split(": ", 2)[-1]))
        elif body.startswith("ADMIN: BOT AI: %s:" % name):
            events.append((t, "AI", body.split(": ", 2)[-1]))
        elif ("/(%s)" % name) in body and (body.startswith("SAY:") or body.startswith("EMOTE:") or body.startswith("WHISPER:")):
            events.append((t, body.split(":")[0][:3], body.split(") ", 1)[-1]))
    last = None
    try:
        for line in open(run + "/bot_telemetry.jsonl", encoding="utf-8", errors="replace"):
            if '"b":"%s"' % name not in line:
                continue
            t = stamp(line)
            i = line.find("{")
            if not t or i < 0:
                continue
            try:
                j = json.loads(line[i:])
            except ValueError:
                continue
            if j.get("k") == "s":
                key = (j.get("x"), j.get("y"), j.get("z"), j.get("hp"), j.get("st"), j.get("g"), j.get("step"))
                if key != last:
                    events.append((t, "POS", "(%s,%s,%s) hp %s, %s %s %s%s" % (j.get("x"), j.get("y"), j.get("z"), j.get("hp"), j.get("st"), j.get("g") or "", j.get("step") or "", " moving" if j.get("mv") else "")))
                last = key
            elif j.get("k") == "e" and j.get("ev") not in ("idle",):
                what = " ".join(str(j[k]) for k in ("ev", "item", "action", "machine", "to", "result", "goal") if j.get(k))
                events.append((t, "EVT", what))
    except OSError:
        pass

    if not events:
        print("nothing in the logs for %r" % name)
        return 1
    events.sort(key=lambda e: e[0])
    if not end:
        end = events[-1][0]
        print("(no death in attack.log: the window ends at its last line)")
    start = end - timedelta(seconds=secs)
    print("window %s to %s (wall clock; a timewarped run fits more game time into it)" % (start.strftime("%H:%M:%S"), end.strftime("%H:%M:%S")))
    for t, kind, text in events:
        if start <= t <= end + timedelta(seconds=1):
            print("%s %-3s %s" % (t.strftime("%H:%M:%S.%f")[:-3], kind, text[:260]))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
