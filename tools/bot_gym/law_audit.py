#!/usr/bin/env python3
"""Space Law audit of a Bot Shift batch or round: how bots carried out the user's rulings, from game.log, attack.log, manifest.log and
timeline.txt of each round.

  python tools/bot_gym/law_audit.py data/logs/shift_batch/<batch>        every run in a batch
  python tools/bot_gym/law_audit.py <round dir>...                       one or more rounds
  python tools/bot_gym/law_audit.py <batch> -v                           and each line it counts

It reports:
  waits    how long each arrest waited between "suspect restrained" and the sentence starting (game minutes, from the run's speed). A
           full brig makes prisoners wait cuffed in a hallway: the number over three minutes and the longest.
  lethal   shots with a laser or other killing weapon by Security (Security Officer, Warden, Head of Security, Detective) at somebody
           who isn't a traitor of that round. The user's rulings: stun and cuff by default, lethal only in Space Law's cases, greytiders
           never killed. Shots at the nanosuit or a known killer land among the traitors, so what's left is worth reading.
  killed   non-traitors who died within 30 seconds of a Security hit.
  cells    "no free brig cell" lines and "All the cells are full" shouts.
  cases    capital cases opened, ruled, and carried out (permabrigged or injected), and "can't take ... out of the cell" refusals.
  calls    how many officers answered each call for help on the radio ("Responding to a call from X"), grouped by caller within a moment:
           the number of calls, and how many drew four or more officers off their posts at once.

Traitors come from timeline.txt ("X (job) is a traitor"), jobs from manifest.log. Nothing here reads the game: only logs.
"""
import argparse
import collections
import glob
import json
import os
import re

import logread

SEC = ("Security Officer", "Warden", "Head of Security", "Detective")
NAME = r"(?:bot-[a-z]+-\d+|\*no key\*)/\(([^)]+)\)"
STAMP = re.compile(r"^\[\d{4}-\d\d-\d\d (\d\d):(\d\d):(\d\d\.\d+)\] ADMIN: BOT AI: ([^:]+): (.*)$")
SHOT = re.compile(r"ATTACK: " + NAME + r" has shot " + NAME + r" with (?:the )?(.+?) \(NEWHP: ([-\d.]+)\)")
DIED = re.compile(r"\(([^()]+)\) has died \((.*?)\) \((.*?)\)")
NOT_LETHAL = ("electrode", "disabler beam", "ion bolt", "kinetic accelerator", "beanbag slug")
CALL = re.compile(r"^\[\d{4}-\d\d-\d\d (\d\d):(\d\d):(\d\d\.\d+)\] SAY: bot-([a-z]+)-\d+/\(([^)]+)\) \"(?i:responding to a call from (.+?) in )")


def secs(h, m, s):
    return int(h) * 3600 + int(m) * 60 + float(s)


def jobs_and_traitors(run):
    jobs = {}
    path = os.path.join(run, "manifest.log")
    if os.path.exists(path):
        for line in logread.lines(path):
            m = re.search(r" \\ ([^\\]+?) \\ ([^\\]+?) \\ ", line)
            if m:
                jobs[m.group(1).strip()] = m.group(2).strip()
    traitors = set()
    path = os.path.join(run, "timeline.txt")
    if os.path.exists(path):
        for line in logread.lines(path):
            m = re.match(r"\d+:\d+\s+(.+?) \(.*?\) is a traitor", line)
            if m:
                traitors.add(m.group(1))
    return jobs, traitors


def audit(run, verbose, total):
    jobs, traitors = jobs_and_traitors(run)
    speed = 10.0
    try:
        speed = json.load(open(os.path.join(run, "results.json")))["speed"] or 10.0
    except Exception:
        pass
    restrained = {}
    waits = []
    calls = []
    game = os.path.join(run, "game.log")
    if os.path.exists(game):
        for line in logread.lines(game):
            m = CALL.match(line)
            if m:
                calls.append((secs(m.group(1), m.group(2), m.group(3)), m.group(5), m.group(6).lower()))
            if "no free brig cell" in line:
                total["no free brig cell"] += 1
            elif "All the cells are full" in line and "SAY:" in line:
                total["cells full shouts"] += 1
            elif "capital case opened" in line:
                total["capital cases opened"] += 1
            elif "BOT LAW:" in line and "ruled" in line:
                total["capital cases ruled"] += 1
            elif "BOT LAW:" in line and ("permabrigged" in line or "carried out a lethal injection" in line):
                total["capital cases carried out"] += 1
            elif "can't take" in line and "out of the cell for the Prison Wing" in line:
                total["lifer collection refused"] += 1
            elif "let them off with a warning" in line:
                total["let off for lack of cells"] += 1
            m = STAMP.match(line)
            if not m:
                continue
            h, mi, s, who, what = m.groups()
            t = secs(h, mi, s)
            r = re.match(r"ending arrest of (.+?): suspect restrained", what)
            if r:
                restrained.setdefault(r.group(1), t)
            r = re.match(r"sentenced (.+?) to (\d+) minutes? in (.+?) for (.+)", what)
            if r and r.group(1) in restrained:
                waits.append(((t - restrained.pop(r.group(1))) * speed / 60, r.group(1), r.group(4)))
    calls.sort()
    taken = set()
    for i, c in enumerate(calls):
        if i in taken:
            continue
        who = {c[1]}
        for j in range(i + 1, len(calls)):
            if calls[j][0] - c[0] > 6:
                break
            if calls[j][2] == c[2]:
                who.add(calls[j][1])
                taken.add(j)
        total["calls answered"] += 1
        if len(who) >= 4:
            total["calls drawing 4+ officers"] += 1
    total["arrests sentenced"] += len(waits)
    total["waited over 3 game minutes"] += sum(1 for w in waits if w[0] > 3)
    if waits:
        worst = max(waits)
        total["longest wait (game minutes)"] = max(total["longest wait (game minutes)"], round(worst[0], 1))
        if verbose:
            print("%s longest wait %.1f min: %s, %s" % (os.path.basename(run), worst[0], worst[1], worst[2]))
    attack = os.path.join(run, "attack.log")
    if not os.path.exists(attack):
        return
    for line in logread.lines(attack):
        m = SHOT.search(line)
        if m:
            shooter, victim, weapon, hp = m.groups()
            if weapon.lower() in NOT_LETHAL or jobs.get(shooter) not in SEC:
                continue
            if victim in traitors:
                total["lethal shots at traitors"] += 1
            else:
                total["LETHAL SHOTS AT NON-TRAITORS"] += 1
                if verbose:
                    print("%s %s (%s) shot %s (%s) with the %s -> %s" % (os.path.basename(run), shooter, jobs.get(shooter), victim, jobs.get(victim), weapon, hp))
            continue
        m = DIED.search(line)
        if m:
            k = re.search(r"last hurt by [^/]*/\(([^)]+)\), (\d+) s before", m.group(2))
            if k and jobs.get(k.group(1)) in SEC and int(k.group(2)) <= 30 and m.group(1) not in traitors:
                total["NON-TRAITORS KILLED BY SECURITY"] += 1
                if verbose:
                    print("%s %s died after a hit from %s" % (os.path.basename(run), m.group(1), k.group(1)))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("paths", nargs="+")
    ap.add_argument("-v", action="store_true")
    args = ap.parse_args()
    runs = []
    for p in args.paths:
        if os.path.exists(os.path.join(p, "game.log")):
            runs.append(p)
        else:
            runs += sorted(glob.glob(os.path.join(p, "run*")), key=lambda r: int(re.sub(r"\D", "", os.path.basename(r)) or 0))
    total = collections.Counter()
    for run in runs:
        audit(run, args.v, total)
    print("%d round(s):" % len(runs))
    for key in ("arrests sentenced", "waited over 3 game minutes", "longest wait (game minutes)", "no free brig cell", "cells full shouts",
                "let off for lack of cells", "capital cases opened", "capital cases ruled", "capital cases carried out", "lifer collection refused",
                "calls answered", "calls drawing 4+ officers",
                "lethal shots at traitors", "LETHAL SHOTS AT NON-TRAITORS", "NON-TRAITORS KILLED BY SECURITY"):
        print("  %-34s %s" % (key, total.get(key, 0)))


if __name__ == "__main__":
    main()
