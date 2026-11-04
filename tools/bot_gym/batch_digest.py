"""What a batch of Bot Shifts came to, one line a shift and the totals, and against an earlier batch if one's given: deaths and where,
who did the killing (a traitor, the wildlife, the crew), runtimes, goals refused for bad air, goals given up on, ruins explored, and
how much pacing (pacing_scan.py). For reading a batch in one go instead of a grep at a time.

Usage: python tools/bot_gym/batch_digest.py <batch dir> [earlier batch dir]
  python tools/bot_gym/batch_digest.py data/logs/shift_batch/night13 data/logs/shift_batch/night12
"""
import collections
import glob
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pacing_scan  # noqa: E402

DIED = re.compile(r"bot-[^/\s]+/\(([^()]+)\) has died")  # crew bots only, not the mice and the goliaths
ATTACKER = re.compile(r"ATTACK: (?:[^/\s]+)/\(([^()]+)\) has (?:attacked|shot|punched|kicked|stabbed|slashed|bashed|hit|bitten)[^(]*\(([^()]+)\)")
PLACE = re.compile(r"died at [0-9:]+ (?:body destroyed, last seen )?in ([A-Za-z' ]+?) \(")


def read(path):
    try:
        return open(path, encoding="utf-8", errors="replace").read()
    except OSError:
        return ""


def digest(run):
    d = {"run": os.path.basename(run.rstrip("/\\"))}
    summary = read(run + "/summary.txt")
    first = summary.splitlines()[0] if summary else ""
    m = re.search(r"shift on ([A-Za-z ]+),", first)
    d["map"] = m.group(1) if m else "?"
    d["places"] = collections.Counter(PLACE.findall(summary))
    d["deaths"] = sum(d["places"].values())
    timeline = read(run + "/timeline.txt")
    traitors = set(re.findall(r"\d+:\d+\s+(.+?) \([^)]*\) is a traitor", timeline))
    attack = read(run + "/attack.log").splitlines()
    hits = collections.defaultdict(collections.Counter)  # victim -> attacker -> hits
    dead = []
    for line in attack:
        m = ATTACKER.search(line)
        if m and m.group(1) != m.group(2):
            hits[m.group(2)][m.group(1)] += 1
        m = DIED.search(line)
        if m and "has died" in line:
            dead.append(m.group(1))
    killers = collections.Counter()
    for victim in dead:
        if not hits[victim]:
            killers["(no attacker: air, fire, radiation...)"] += 1
            continue
        who = hits[victim].most_common(1)[0][0]
        if who in traitors:
            who = "traitor " + who
        killers[who] += 1
    d["killers"] = killers
    runtime = read(run + "/runtime.log")
    d["runtimes"] = runtime.count("runtime error")
    game = read(run + "/game.log")
    d["refused_air"] = game.count("not suited up - not doing")
    d["ruins"] = game.count(": been through ")
    d["gave_up"] = collections.Counter(re.findall(r"gave up on (\S+) \d+ times and never managed it", summary))
    d["pacing"] = sum(len(v) for v in pacing_scan.scan(run).values())
    return d


def batch(path):
    return [digest(r) for r in sorted(glob.glob(path + "/run*"), key=lambda p: int(re.sub(r"\D", "", os.path.basename(p)) or 0))]


def totals(runs):
    t = {"deaths": 0, "runtimes": 0, "refused_air": 0, "ruins": 0, "pacing": 0, "places": collections.Counter(), "killers": collections.Counter(), "gave_up": collections.Counter()}
    for d in runs:
        for k in ("deaths", "runtimes", "refused_air", "ruins", "pacing"):
            t[k] += d[k]
        for k in ("places", "killers", "gave_up"):
            t[k].update(d[k])
    return t


def main(argv):
    if not argv:
        print(__doc__)
        return 2
    runs = batch(argv[0])
    print("%s: %d shifts" % (argv[0], len(runs)))
    for d in runs:
        top = ", ".join("%d %s" % (n, p) for p, n in d["places"].most_common(3))
        print("  %-5s %-15s deaths %2d  runtimes %d  ruins %d  pacing %2d  air-refused %d  | %s" % (d["run"], d["map"], d["deaths"], d["runtimes"], d["ruins"], d["pacing"], d["refused_air"], top))
    t = totals(runs)
    print("TOTAL deaths %d, runtimes %d, ruins %d, pacing %d, refused for air %d" % (t["deaths"], t["runtimes"], t["ruins"], t["pacing"], t["refused_air"]))
    traitor_kills = sum(n for k, n in t["killers"].items() if k.startswith("traitor "))
    print("Killed by traitors %d, by others %d. Top killers: %s" % (traitor_kills, t["deaths"] - traitor_kills, ", ".join("%s %d" % kv for kv in t["killers"].most_common(6))))
    print("Places: %s" % ", ".join("%s %d" % kv for kv in t["places"].most_common(8)))
    if t["gave_up"]:
        print("Given up on again and again: %s" % ", ".join("%s %d" % kv for kv in t["gave_up"].most_common(8)))
    if len(argv) > 1:
        e = totals(batch(argv[1]))
        print("AGAINST %s: deaths %d -> %d, runtimes %d -> %d, pacing %d -> %d, refused for air %d -> %d, ruins %d -> %d" % (argv[1], e["deaths"], t["deaths"], e["runtimes"], t["runtimes"], e["pacing"], t["pacing"], e["refused_air"], t["refused_air"], e["ruins"], t["ruins"]))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
