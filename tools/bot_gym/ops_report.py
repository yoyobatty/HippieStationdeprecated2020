"""How the nuclear operatives did in a batch of Bot Shifts (bot-nukeops=N) or live rounds: who they were, what they bought, what they
fired and what hit them, cuffs, deaths, the disk, and the nuke.
Usage: python tools/bot_gym/ops_report.py data/logs/shift_batch/<name>"""
import collections
import glob
import os
import re
import sys


def read(path):
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            return f.read()
    except OSError:
        return ""


def report(run):
    game = read(os.path.join(run, "game.log"))
    attack = read(os.path.join(run, "attack.log"))
    ops = set(re.findall(r"BOT AI: ([^:\n]+): bought the C-20r", game))
    ops |= set(re.findall(r"BOT OPS: (.+?) joins the operatives", game))
    if not ops:
        return ["%s: no operatives found" % os.path.basename(run)]
    names = "|".join(re.escape(n) for n in ops)
    by_op = re.compile(r"/\((%s)\) has (fired at|attacked|stripped|handcuffed) [^\n]*?/\(([^)]*)\)(?: with ([^(\n]*))?" % names)
    at_op = re.compile(r"/\(([^)]*)\) has (shot|attacked|handcuffed|stunned) [^\n]*?/\((%s)\)(?: with ([^(\n]*))?" % names)
    fired = collections.Counter()
    for _op, verb, victim, what in by_op.findall(attack):
        if victim not in ops:
            fired["%s %s" % (verb, (what or "").split(" from ")[0].strip())] += 1
    hit = collections.Counter()
    cuffs = 0
    for who, verb, _op, what in at_op.findall(attack):
        if who in ops:
            hit["by another operative: %s" % verb] += 1
            continue
        if verb == "handcuffed":
            cuffs += 1
        else:
            hit["%s %s" % (verb, (what or "").strip())] += 1
    deaths = len(re.findall(r"/\((%s)\) [^\n]*has died" % names, attack))
    reloads = len(re.findall(r"BOT AI: (%s): reloaded" % names, game))
    disk = len(re.findall(r"BOT AI: (%s): picked up the nuclear" % names, game))
    armed = re.findall(r"BOT OPS: (.+?) armed the nuke", game)
    exploded = "Station destroyed" in game or "nuclear device detonated" in game.lower()
    lines = ["%s: %d operatives, %d dead, %d cuffed, %d disk pickups, %d reloads, nuke %s" % (
        os.path.basename(run), len(ops), deaths, cuffs, disk, reloads, ("ARMED by " + armed[0]) if armed else "not armed")]
    if exploded:
        lines.append("  the nuke went off")
    lines.append("  fired/struck: " + (", ".join("%s x%d" % (k, n) for k, n in fired.most_common(6)) or "nothing"))
    lines.append("  hit by: " + (", ".join("%s x%d" % (k, n) for k, n in hit.most_common(6)) or "nothing"))
    return lines


def main():
    base = sys.argv[1]
    runs = sorted(glob.glob(os.path.join(base, "run*")), key=lambda p: int(re.sub(r"\D", "", os.path.basename(p)) or 0))
    for run in runs:
        print("\n".join(report(run)))


main()
