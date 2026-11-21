#!/usr/bin/env python3
"""Who got hit by a shot that wasn't aimed at them: stray hits by Security (or anybody) in a shift batch or round.

attack.log writes "A has fired at T with the W from Area" when a gun goes off at T, and "A has shot V with the W" for each hit. A hit on
somebody other than T, from the same shooter within a moment of the shot, is a stray: a colleague or a bystander stepped into the line, or
the shooter fired through them. This lists them, by shooter job and by victim kind (colleague, wanted, bystander), so a change to
has_clear_shot()/crew_in_the_way() (goals/security_patrol.dm) can be judged on the count.

  python tools/bot_gym/stray_fire.py data/logs/shift_batch/<batch>          every run in a batch
  python tools/bot_gym/stray_fire.py <round dir>...                         one or more rounds
  python tools/bot_gym/stray_fire.py <batch> -v                             and each stray hit

Jobs come from manifest.log: a victim is a colleague if they're Security, otherwise a bystander. Whether they were wanted isn't known here.
"""
import argparse
import collections
import glob
import os
import re
import sys

import logread

STAMP = r"^\[\d{4}-\d\d-\d\d (\d\d:\d\d:\d\d\.\d{3})\] ATTACK: "
NAME = r"(?:bot-[a-z]+-\d+|\*no key\*)/\(([^)]+)\)"
FIRED = re.compile(STAMP + NAME + r" has fired at " + NAME + r" with (?:the )?(.+?) from ")
SHOT = re.compile(STAMP + NAME + r" has shot " + NAME + r" with (?:the )?(.+?) \(NEWHP: ([-\d.]+)\)")
MANIFEST = re.compile(r" \\ ([^\\]+?) \\ ([^\\]+?) \\ ")
SEC = {"Security Officer", "Warden", "Head of Security", "Detective"}
SEC_JOBS = {"Security Officer", "Warden", "Head of Security"}


def seconds(stamp):
    h, m, s = stamp.split(":")
    return int(h) * 3600 + int(m) * 60 + float(s)


def jobs_of(run):
    jobs = {}
    path = logread.find(run, "manifest.log") or os.path.join(run, "manifest.log")
    if not os.path.exists(path):
        return jobs
    for line in logread.lines(path):
        m = MANIFEST.search(line)
        if m:
            jobs[m.group(1).strip()] = m.group(2).strip()
    return jobs


def scan(run, verbose):
    jobs = jobs_of(run)
    path = logread.find(run, "attack.log") or os.path.join(run, "attack.log")
    if not os.path.exists(path):
        return collections.Counter(), []
    last_fired = {}
    count = collections.Counter()
    strays = []
    for line in logread.lines(path):
        m = FIRED.match(line)
        if m:
            t, shooter, target, weapon = m.groups()
            last_fired[shooter] = (seconds(t), target)
            continue
        m = SHOT.match(line)
        if not m:
            continue
        t, shooter, victim, weapon, hp = m.groups()
        count["shots hit"] += 1
        fired = last_fired.get(shooter)
        if not fired or seconds(t) - fired[0] > 0.5 or fired[1] == victim or shooter == victim:
            continue
        count["stray"] += 1
        sjob = jobs.get(shooter, "?")
        vjob = jobs.get(victim, "?")
        kind = "colleague" if vjob in SEC_JOBS else "bystander"
        count["stray by " + ("Security" if sjob in SEC_JOBS else "others")] += 1
        count["stray on a " + kind] += 1
        if sjob in SEC_JOBS:
            count["Security stray on a " + kind] += 1
        strays.append("%s %s (%s) shot at %s, hit %s (%s) with the %s" % (os.path.basename(run), shooter, sjob, fired[1], victim, vjob, weapon))
    return count, strays


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("paths", nargs="+")
    ap.add_argument("-v", action="store_true")
    args = ap.parse_args()
    runs = []
    for p in args.paths:
        if os.path.exists(os.path.join(p, "attack.log")) or glob.glob(os.path.join(p, "attack.log*")):
            runs.append(p)
        else:
            runs += sorted(glob.glob(os.path.join(p, "run*")), key=lambda r: int(re.sub(r"\D", "", os.path.basename(r)) or 0))
    total = collections.Counter()
    for run in runs:
        count, strays = scan(run, args.v)
        total.update(count)
        if args.v:
            for s in strays:
                print(s)
    print("%d round(s): %s" % (len(runs), ", ".join("%s %d" % (k, v) for k, v in sorted(total.items()))))


if __name__ == "__main__":
    main()
