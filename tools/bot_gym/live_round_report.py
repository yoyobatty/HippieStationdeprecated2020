"""What happened in live test rounds (tools/bot_gym/run_live_round.sh): the round type, who it made antagonists and whether
they were bots, the antagonists' objectives from the round-end report, deaths, the shuttle, how it ended, and runtimes.
Usage: python tools/bot_gym/live_round_report.py data/logs/live_round/<name>"""
import collections
import glob
import html
import os
import re
import sys


def read(path):
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            return f.read()
    except OSError:
        return ""


def is_bot(key_name):
    # A bot's mob has a made-up key ("bot-alexreyes-3"); its mind has none at all. A player's has theirs.
    return key_name.startswith("bot-") or key_name.startswith("*no key*")


def report_run(run):
    game = read(os.path.join(run, "game.log"))
    attack = read(os.path.join(run, "attack.log"))
    runtime = read(os.path.join(run, "runtime.log"))
    end_report = read(os.path.join(run, "round_end_report.html"))
    lines = []
    name = os.path.basename(run)

    mode = re.search(r"BOT ROLES: mode '([^']+)'", game)
    picked = re.search(r"BOT ROLES: (.+?), (\d+) of its antagonists bots, (\d+) bots stood in", game)
    failed = re.findall(r"GAME: ([^\n]+?) failed pre_setup, cause: (.*)", game)  # anchored: with the bot logs on, game.log is huge
    head = "%s: %s" % (name, mode.group(1) if mode else "?")
    if picked:
        head += " -> %s, %s of its antagonists bots (%s bots stood in)" % picked.groups()
    lines.append(head)
    for m, cause in failed:
        lines.append("  failed to set up: %s (%s)" % (m, cause))

    gained = collections.Counter()
    for key, antag in re.findall(r"GAME: ([^/\n]+?)/\([^)\n]*\) has gained antag datum (.+?)\(", game):
        gained[(antag, "bot" if is_bot(key) else "player")] += 1
    if gained:
        parts = ["%s %d %s" % (antag, n, who) for (antag, who), n in sorted(gained.items())]
        lines.append("  antagonists: " + ", ".join(parts))
    else:
        lines.append("  antagonists: none")
    nobody = re.findall(r"BOT ROLES: nobody to be the (.*)", game)
    if nobody:
        lines.append("  roles with no bot to take them: %d (%s)" % (len(nobody), nobody[0]))

    deaths = re.findall(r"ATTACK: ([^/\n]+?)/\([^)\n]*\) .*?has died", attack)
    if deaths:
        bots = sum(1 for k in deaths if k.startswith("bot-"))  # a mob's key: a bot's is made up, a corpse in a ruin has none
        players = sum(1 for k in deaths if not is_bot(k))
        lines.append("  deaths: %d crew (%d bots, %d players), %d with no key (ruins, mobs)" % (bots + players, bots, players, len(deaths) - bots - players))
    else:
        lines.append("  deaths: 0")
    calls = re.findall(r"has called the shuttle|Central Command sends the shuttle|called the emergency shuttle", game)
    lines.append("  shuttle called: %d time(s)" % len(calls))
    if "time is up" in game:
        lines.append("  ended: at the time limit")
    elif "The round has ended." in game:
        lines.append("  ended: by itself")
    else:
        lines.append("  ended: NOT ENDED (stopped)")

    if end_report:
        text = re.sub(r"<br\s*/?>", "\n", end_report, flags=re.I)
        text = re.sub(r"<span class='(greentext|redtext)'>", lambda m: "[%s]" % ("WIN" if m.group(1) == "greentext" else "FAIL"), text)
        text = html.unescape(re.sub(r"<[^>]+>", "", text))
        for line in text.splitlines():
            line = line.strip()
            if not line or line.startswith("The ") and "survived" in line:
                continue
            if re.search(r"Objective #|\[WIN\]|\[FAIL\]|were:|was:|the (traitor|changeling|cultist|wizard|operative|revolution)", line, re.I):
                lines.append("    " + line[:160])
    else:
        lines.append("  no round-end report")

    loads = [(float(a), float(w)) for a, w in re.findall(r"LIVE LOAD: average ([\d.]+)%, worst ([\d.]+)%", game)]
    if loads:
        lines.append("  server load: %.1f%% of a tick on average, worst second %.1f%%, %d minutes" % (
            sum(a for a, _ in loads) / len(loads), max(w for _, w in loads), len(loads)))

    errors = re.findall(r"runtime error: (.*)", runtime)
    exceptions = runtime.count("BOT AI EXCEPTION")
    lines.append("  runtimes: %d, bot AI exceptions: %d" % (len(errors), exceptions))
    for text, n in collections.Counter(errors).most_common(5):
        lines.append("    %dx %s" % (n, text[:140]))
    return lines


def main():
    base = sys.argv[1] if len(sys.argv) > 1 else "data/logs/live_round"
    runs = sorted(glob.glob(os.path.join(base, "run*")), key=lambda p: int(re.sub(r"\D", "", os.path.basename(p)) or 0))
    if not runs:
        print("no runs in", base)
        return
    for run in runs:
        print("\n".join(report_run(run)))
        print()


main()
