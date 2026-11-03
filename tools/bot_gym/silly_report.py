#!/usr/bin/env python3
"""What the silly bots broke (bots_ai/gym/bot_silly.dm).

Usage: tools/bot_gym/silly_report.py <batch folder> [how many sites, default 40]     data/logs/shift_batch/<name>

Every runtime from every round in the batch, by the line it happened on, most common first, with what a silly bot was doing the first time.
"""
import os
import re
import sys
from collections import Counter, defaultdict

batch = sys.argv[1].rstrip("/")
show = int(sys.argv[2]) if len(sys.argv) > 2 else 40
sites = Counter()
runs = defaultdict(set)
error = {}
stack = {}
doing = {}
exceptions = Counter()
for run in sorted(os.listdir(batch)):
    folder = batch + "/" + run + "/"
    if not os.path.isdir(folder):
        continue
    if os.path.exists(folder + "runtime.log"):
        lines = open(folder + "runtime.log", encoding="utf8", errors="replace").read().split("\n")
        i = 0
        while i < len(lines):
            m = re.search(r"runtime error: (.*)", lines[i])
            if not m:
                x = re.search(r"BOT AI EXCEPTION \(([^)]*)\): (.*)", lines[i])
                if x and "!" not in lines[i][:40]:
                    exceptions[re.sub(r"^.*?\): ", "", lines[i])[:110]] += 1
                i += 1
                continue
            block = lines[i:i + 14]
            where = next((re.search(r"source file: (\S+)", l) for l in block if "source file:" in l), None)
            where = where[1].rstrip(",") if where else "unknown"
            line = next((re.search(r"source file: \S+?,(\d+)", l) for l in block if "source file:" in l), None)
            key = where + ":" + (line[1] if line else "?")
            sites[key] += 1
            runs[key].add(run)
            error.setdefault(key, m[1][:90])
            stack.setdefault(key, [l.strip(" -\t")[:90] for l in block if " - " in l and "(" in l and "proc name" not in l and "source file" not in l and "usr" not in l and "src:" not in l][:4])
            i += 1
    if os.path.exists(folder + "silly.log"):
        for l in open(folder + "silly.log", encoding="utf8", errors="replace"):
            m = re.search(r"\] (\S+:\d+) (.*?) \| (.*?) \| ", l)
            if m:
                key = re.sub(r",", ":", m[1])
                doing.setdefault(key, m[3][:110])
                sites[key] += 1
                runs[key].add(run)
                error.setdefault(key, m[2][:90])
print("%d runtime sites, %d runtimes" % (len(sites), sum(sites.values())))
for key, n in sites.most_common(show):
    print("%5d x in %d runs  %s" % (n, len(runs[key]), key))
    print("        %s" % error.get(key))
    if key in doing:
        print("        doing: %s" % doing[key])
    for s in stack.get(key, [])[:3]:
        print("        < %s" % s)
print("bot exceptions:", exceptions.most_common(10))
