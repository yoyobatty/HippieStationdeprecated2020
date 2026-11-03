#!/usr/bin/env python3
"""What the robust traitors did in a batch of rounds, against what the player they're modelled on did.

Usage: tools/bot_gym/robust_report.py <batch folder>     data/logs/shift_batch/<name>

For each run: when each traitor bought and put on the suit, who it killed and how, how it ended, and what the crew did about it.
"""
import json
import os
import re
import sys
from collections import Counter, defaultdict


def stamp(line):
    m = re.match(r"\[\d+-\d+-\d+ (\d+):(\d+):(\d+)\.(\d+)\]", line)
    return (int(m[1]) * 3600 + int(m[2]) * 60 + int(m[3])) * 1000 + int(m[4]) if m else None


def lines(path):
    return open(path, encoding="utf8", errors="replace").read().split("\n") if os.path.exists(path) else []


def minutes(t, ticks=600.0):
    return "%5.1f" % (t / ticks)


def run_report(folder):
    summary = lines(folder + "/summary.txt")
    timeline = lines(folder + "/timeline.txt")
    traitors = {}
    for line in summary + timeline:
        m = re.search(r"([A-Z][\w'-]+(?: [A-Z][\w'-]+)+) \(([^)]*)\) is a traitor", line)
        if m:
            traitors[m[1]] = m[2]
    print("traitors:", traitors or "none named in the timeline")
    events = defaultdict(list)
    goals = defaultdict(Counter)
    ends = defaultdict(Counter)
    samples = defaultdict(int)
    first = None
    for line in lines(folder + "/bot_telemetry.jsonl"):
        i = line.find("{")
        if i < 0:
            continue
        try:
            j = json.loads(line[i:])
        except ValueError:
            continue
        name = j.get("b")
        if first is None:
            first = j.get("t")
        if j.get("k") == "s":
            samples[name] += 1
            continue
        ev = j.get("ev")
        if ev == "goal_start":
            goals[name][j.get("goal")] += 1
        elif ev == "goal_end":
            ends[name][(j.get("goal"), j.get("result"))] += 1
        elif ev == "ui_action":
            events[name].append((j.get("t"), j.get("action")))
    for name, job in traitors.items():
        print("  %s (%s)" % (name, job))
        acts = events.get(name, [])
        print("    actions:", Counter(a for _, a in acts).most_common(10))
        for t, a in acts[:6]:
            print("      %s min %s" % (minutes(t), a))
        print("    goals:", [g for g in goals[name].most_common(12)])
        print("    gave up:", [(k, v) for k, v in ends[name].most_common(30) if k[1] != "success"][:8])

    attack = lines(folder + "/attack.log")
    game = lines(folder + "/game.log")
    deaths = []
    for line in game:
        m = re.search(r"EMOTE: (?:bot-[a-z0-9-]+)/\((.*?)\) seizes up and falls limp", line)
        if m:
            deaths.append((stamp(line), m[1]))
    print("deaths:", len(deaths))
    last = {}
    blows = Counter()
    for line in attack:
        m = re.search(r"ATTACK: (?:bot-[a-z0-9-]+)/\((.*?)\) has (attacked|punched|kicked|shot|stabbed|head stomped|slashed|bashed)\b.*? (?:bot-[a-z0-9-]+)/\((.*?)\)", line)
        if m:
            last[m[3]] = (stamp(line), m[1], m[2])
            blows[m[1]] += 1
    killers = Counter()
    for t, who in deaths:
        hit = last.get(who)
        killers[hit[1] if hit and t - hit[0] < 3000 else "nothing logged"] += 1
    print("killed by:", killers.most_common(8))
    print("blows landed:", blows.most_common(6))
    print("traitor kills: %d of %d deaths, against the player's 25 of 25 in 29 minutes and 6 in 8" % (sum(n for k, n in killers.items() if k in traitors), len(deaths)))
    for line in game:
        if "called the shuttle" in line or "Automatically dispatching" in line:
            print("  ", line[:120])
    for line in summary[:14]:
        if re.search(r"crew|shuttle|alive|dead|traitor|deaths|runtime|exception", line, re.I):
            print("  |", line[:140])
    for line in timeline:
        if re.search(r"called the shuttle|Central Command is sending|nanosuit|took .* off|Command's gone|nobody left", line):
            print("  >", line[:140])


if __name__ == "__main__":
    batch = sys.argv[1].rstrip("/")
    for run in sorted(os.listdir(batch)):
        path = batch + "/" + run
        if os.path.isdir(path):
            print("=========", run)
            run_report(path)
