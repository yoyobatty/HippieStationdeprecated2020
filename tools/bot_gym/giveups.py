#!/usr/bin/env python3
"""Why bots gave up: every "giving up on" line in a round's game.log, by goal, target and the reason
the bot logged just before it.

  python tools/bot_gym/giveups.py                      the newest round
  python tools/bot_gym/giveups.py data/logs/.../round-x   one round (or several)
  python tools/bot_gym/giveups.py --goal mop_mess      with the lead-up to the first few of a goal
  python tools/bot_gym/giveups.py --min 3              only goals given up at least this often

A Bot Shift only warns about goals that never once worked, so a job that fails two times in three
passes. This is for reading those, and needs bot_ai_verbose on (Bot Shift and the gym turn it on).
"""
import argparse
import collections
import glob
import os
import re
import sys

LINE = re.compile(r"^\[[^\]]+\] ADMIN: BOT AI( VERBOSE)?: ([^:]+): (.*)$")
TAG = re.compile(r"<[^>]+>")
COORDS = re.compile(r"\s*@ \(\d+,\s*\d+,\s*\d+\)(\s*\(JMP\))?")
NUMBER = re.compile(r"\d+(\.\d+)?")
GIVE_UP = re.compile(r"^giving up on (\S+)(?: \(target: (.*)\))?")
# Lines that say where the bot is in its goal rather than what went wrong.
NOISE = re.compile(
    r"^(trying /|pursue\(|repath: |on_goal_pursuit_finished|run_current_step|resuming |need something for |"
    r"goal /|is_eva_ready|going to |picked up |/datum/bot_strategy/\S+ failed)"
)
HISTORY = 12


def clean(text):
    return COORDS.sub("", TAG.sub("", text)).strip()


def shape(text):
    """Takes the numbers out, so the same complaint at two places counts as one."""
    return NUMBER.sub("N", text)[:150]


def short_goal(path):
    return path.replace("/datum/bot_goal/", "")


def newest_round():
    rounds = [d for d in glob.glob("data/logs/*/*/*/round-*") if os.path.isfile(os.path.join(d, "game.log"))]
    return max(rounds, key=os.path.getmtime) if rounds else None


def read_round(directory, counts, targets, reasons, by_bot, lead_ups, goal_filter, keep):
    history = collections.defaultdict(lambda: collections.deque(maxlen=HISTORY))
    path = os.path.join(directory, "game.log")
    with open(path, encoding="utf-8", errors="replace") as log:
        for raw in log:
            found = LINE.match(raw)
            if not found:
                continue
            bot, text = found.group(2), clean(found.group(3))
            given_up = GIVE_UP.match(text)
            if not given_up:
                history[bot].append(text)
                continue
            goal = short_goal(given_up.group(1))
            counts[goal] += 1
            by_bot[(goal, bot)] += 1
            target = given_up.group(2) or "nothing"
            targets[goal][shape(target)] += 1
            reason = next((t for t in reversed(history[bot]) if not NOISE.match(t)), "(nothing logged)")
            reasons[goal][shape(reason)] += 1
            if goal_filter and goal_filter in goal and len(lead_ups) < keep:
                lead_ups.append((bot, target, list(history[bot])))
            history[bot].clear()


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("rounds", nargs="*", help="round log directories (default: the newest)")
    parser.add_argument("--goal", help="show the lead-up to give-ups of goals with this in their name")
    parser.add_argument("--keep", type=int, default=4, help="how many lead-ups --goal shows")
    parser.add_argument("--min", type=int, default=1, help="leave out goals given up fewer times than this")
    args = parser.parse_args()

    directories = args.rounds or [newest_round()]
    if not directories or not directories[0]:
        sys.exit("No round logs found")
    counts = collections.Counter()
    targets = collections.defaultdict(collections.Counter)
    reasons = collections.defaultdict(collections.Counter)
    by_bot = collections.Counter()
    lead_ups = []
    for directory in directories:
        read_round(directory, counts, targets, reasons, by_bot, lead_ups, args.goal, args.keep)

    print(f"{sum(counts.values())} give-ups in {len(directories)} round(s), {len(counts)} kinds of goal")
    for goal, count in counts.most_common():
        if count < args.min or (args.goal and args.goal not in goal):
            continue
        print(f"\n{count:6} {goal}")
        bots = [(bot, n) for (g, bot), n in by_bot.most_common() if g == goal][:3]
        print("       bots:    " + ", ".join(f"{bot} {n}" for bot, n in bots))
        for target, n in targets[goal].most_common(3):
            print(f"       target:  {n:5} {target}")
        for reason, n in reasons[goal].most_common(4):
            print(f"       reason:  {n:5} {reason}")
    for bot, target, lines in lead_ups:
        print(f"\n--- {bot} gave up on {target}")
        for line in lines:
            print("    " + line[:170])


if __name__ == "__main__":
    main()
