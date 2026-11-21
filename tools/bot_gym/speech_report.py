#!/usr/bin/env python3
"""How the bot crew talked in a round or a batch of Bot Shifts: volume, repeats, bursts, the same stock line from several mouths.

Usage: python tools/bot_gym/speech_report.py <run dir | batch dir>... [--mins 40] [--top 25] [--grep REGEX] [--show N] [--bursts N] [--brief]
A live round isn't timewarped: --mins is then its real length.

Reads each run's game.log (spoken lines: `SAY: bot-x/(Name) "text"`) and telecomms.log (radio: `TCOMMS: bot-x/(Name) [Channel] "text"`).
Timewarp makes the logs' wall clock run 8-15x fast, so game time is scaled: the round's wall span is taken to be --mins of game
(default 40, a Bot Shift). Reports, per batch:
  - lines per bot per game minute (spoken, radio), and the loudest bots
  - a bot's own line said again (same bot, same text), and the same text from different bots (stock lines)
  - echoes: the same line from a different bot within 20 game seconds (all of them, and the ones said aloud within 9 tiles, which is
    what the bots' worth_saying() keeps back since 2026-11-21)
  - bursts: 3+ lines from one bot in 10 game seconds (--bursts N shows N of them), 4+ radio lines in 5 game seconds
  - radio by channel
  - --grep: print every matching line (time, bot, text) for reading them in context; --show caps how many
HTML entities in the logs are unescaped; names are kept.
"""
import collections
import html
import os
import re
import sys

SAY = re.compile(r"^\[(\d+)-(\d+)-(\d+) (\d+):(\d+):(\d+)\.(\d+)\] SAY: bot-[^/]+/\(([^)]+)\) (?:\(([^)]*)\) )?\"(.*?)\"(?: FORCED by \S+)? \(.*?\((\d+), (\d+), (\d+)\)\)")
TC = re.compile(r"^\[(\d+)-(\d+)-(\d+) (\d+):(\d+):(\d+)\.(\d+)\] TCOMMS: bot-[^/]+/\(([^)]+)\) \[([^\]]+)\] \(spans:[^)]*\) \"(.*?)\" \(language")


def secs(m):
    return (int(m[3]) * 86400 + int(m[4]) * 3600 + int(m[5]) * 60 + int(m[6])) + int(m[7]) / 1000.0


def norm(text):
    t = html.unescape(text).lower()
    t = re.sub(r"[^a-z0-9 ]+", "", t)
    return re.sub(r"\s+", " ", t).strip()


def read_run(run):
    """(spoken, radio): lists of (wall secs, name, text[, channel])"""
    spoken, radio = [], []
    g = os.path.join(run, "game.log")
    if os.path.exists(g):
        for line in open(g, encoding="utf8", errors="replace"):
            if "SAY: bot-" not in line:
                continue
            m = SAY.match(line)
            if m:
                spoken.append((secs(m), m[8], html.unescape(m[10]), (int(m[11]), int(m[12]), int(m[13]))))
    t = os.path.join(run, "telecomms.log")
    if os.path.exists(t):
        for line in open(t, encoding="utf8", errors="replace"):
            if "TCOMMS: bot-" not in line:
                continue
            m = TC.match(line)
            if m:
                radio.append((secs(m), m[8], html.unescape(m[10]), m[9]))
    # A radio line is in game.log as a SAY as well, and a numbered frequency (an ambient relay of the room's speech) logs twice
    tc = collections.defaultdict(list)
    for r in radio:
        tc[(r[1], norm(r[2]))].append(r[0])
    real_spoken = []
    for s in spoken:
        near = tc.get((s[1], norm(s[2])))
        if near and any(abs(t - s[0]) < 1.5 for t in near):
            continue
        real_spoken.append(s)
    radio = [r for r in radio if not re.match(r"^\d+\.\d+$", r[3])]
    return real_spoken, radio


def runs_in(path):
    path = path.rstrip("/\\")
    if os.path.exists(os.path.join(path, "game.log")):
        return [path]
    out = []
    for d in sorted(os.listdir(path)):
        p = os.path.join(path, d)
        if os.path.isdir(p) and os.path.exists(os.path.join(p, "game.log")):
            out.append(p)
    return out


def main():
    args = sys.argv[1:]
    if not args or args[0] in ("-h", "--help"):
        print(__doc__)
        return
    mins, top, grep, show, burst_show = 40.0, 25, None, 60, 6
    brief = False
    paths = []
    i = 0
    while i < len(args):
        a = args[i]
        if a == "--mins":
            mins = float(args[i + 1]); i += 2
        elif a == "--top":
            top = int(args[i + 1]); i += 2
        elif a == "--grep":
            grep = re.compile(args[i + 1], re.I); i += 2
        elif a == "--brief":
            brief = True; i += 1
        elif a == "--bursts":
            burst_show = int(args[i + 1]); i += 2
        elif a == "--show":
            show = int(args[i + 1]); i += 2
        else:
            paths.append(a); i += 1
    if not paths:
        print(__doc__)
        return
    runs = []
    for p in paths:
        runs += runs_in(p)
    per_bot = collections.defaultdict(lambda: [0, 0])  # name -> spoken, radio
    own_repeat = collections.Counter()
    stock = collections.defaultdict(set)
    stock_n = collections.Counter()
    stock_example = {}
    bursts = []
    rbursts = []
    echoes = collections.Counter()
    near_echo = collections.Counter()
    echo_total = 0
    chan = collections.Counter()
    total_s = total_r = 0
    game_min = 0.0
    shown = 0
    for run in runs:
        spoken, radio = read_run(run)
        allv = [(s[0], s[1], s[2], None, s[3]) for s in spoken] + [(r[0], r[1], r[2], r[3], None) for r in radio]
        if not allv:
            continue
        t0 = min(x[0] for x in allv)
        t1 = max(x[0] for x in allv)
        # Scale: the wall span of the speech is `mins` game minutes (the round is 40 min and speech starts at its start)
        scale = (mins * 60.0) / max(1.0, t1 - t0)
        game_min += mins
        total_s += len(spoken)
        total_r += len(radio)
        last_by_bot = {}
        last_text = {}
        by_bot_times = collections.defaultdict(list)
        for t, name, text, ch, pos in sorted(allv, key=lambda x: x[0]):
            gt = (t - t0) * scale
            if ch:
                per_bot[name][1] += 1
                chan[ch] += 1
            else:
                per_bot[name][0] += 1
            n = norm(text)
            key = (name, n)
            if n and key in last_by_bot and gt - last_by_bot[key] < 600:
                own_repeat[(name, n, text)] += 1
            last_by_bot[key] = gt
            if n and n in last_text and last_text[n][1] != name and gt - last_text[n][0] < 20:
                echoes[n] += 1
                echo_total += 1
                if pos and last_text[n][2] and last_text[n][2][2] == pos[2] and max(abs(last_text[n][2][0] - pos[0]), abs(last_text[n][2][1] - pos[1])) <= 9:
                    near_echo[n] += 1
            if n:
                last_text[n] = (gt, name, pos)
            if n:
                stock[n].add(name)
                stock_n[n] += 1
                stock_example.setdefault(n, text)
            by_bot_times[name].append(gt)
            if grep and grep.search(text) and shown < show:
                shown += 1
                m, s = divmod(int(gt), 60)
                print("%s %2d:%02d %-18s %s%s" % (os.path.basename(run), m, s, name, "[%s] " % ch if ch else "", text))
        lines_by_bot = collections.defaultdict(list)
        for t, name, text, ch, pos in allv:
            lines_by_bot[name].append(((t - t0) * scale, ("[%s] " % ch if ch else "") + text))
        for name, ts in lines_by_bot.items():
            ts.sort()
            j = 0
            while j < len(ts) - 2:
                if ts[j + 2][0] - ts[j][0] <= 10:
                    k = j + 3
                    while k < len(ts) and ts[k][0] - ts[j][0] <= 10:
                        k += 1
                    bursts.append((os.path.basename(run), name, ts[j][0], [x[1] for x in ts[j:k]]))
                    j = k
                else:
                    j += 1
        rt = sorted(x[0] for x in allv if x[3])
        k = 0
        while k + 3 < len(rt):
            if (rt[k + 3] - rt[k]) * scale <= 5:
                rbursts.append((os.path.basename(run), (rt[k] - t0) * scale))
                k += 4
            else:
                k += 1
    n_bots = max(1, len(per_bot))
    if brief:
        # One line, for comparing two batches: shifts, spoken and radio lines per bot per game minute, repeats of a bot's own line, echoes
        # within 20 game s (and the ones said aloud within 9 tiles), bursts
        nb0 = 30.0
        print("%s: %d runs, spoken %.2f radio %.2f per bot-min, own repeats %d, echoes %d (aloud near %d), bursts %d, radio bursts %d" % (
            ",".join(os.path.basename(p.rstrip("/\\")) for p in paths), len(runs), total_s / max(1.0, game_min) / nb0,
            total_r / max(1.0, game_min) / nb0, sum(own_repeat.values()), echo_total, sum(near_echo.values()), len(bursts), len(rbursts)))
        return
    print("runs %d, game minutes %.0f; %d spoken, %d radio" % (len(runs), game_min, total_s, total_r))
    nb = 30.0 # a Bot Shift's crew
    print("per bot per game minute (30 bots a run): spoken %.2f, radio %.2f" % (
        total_s / max(1.0, game_min) / nb, total_r / max(1.0, game_min) / nb))
    print("\nbusiest names (spoken+radio lines, whole batch):")
    for name, (s, r) in sorted(per_bot.items(), key=lambda kv: -(kv[1][0] + kv[1][1]))[:10]:
        print("  %-22s %4d spoken %4d radio" % (name, s, r))
    print("\nradio by channel:", ", ".join("%s %d" % kv for kv in chan.most_common()))
    print("\nown line said again within 10 game minutes (bot, line, times):")
    for (name, n, text), c in own_repeat.most_common(top):
        print("  %3d  %-18s %s" % (c, name, text[:90]))
    print("  total repeats: %d" % sum(own_repeat.values()))
    print("\nsame line from different bots (distinct bots, total, line):")
    rows = [(len(v), stock_n[k], stock_example[k]) for k, v in stock.items() if len(v) >= 3]
    for nbots, tot, text in sorted(rows, reverse=True)[:top]:
        print("  %3d bots %4d  %s" % (nbots, tot, text[:90]))
    print("\nthe same line from another bot within 20 game s (%d in all):" % echo_total)
    for n, c in echoes.most_common(top):
        print("  %3d  %s" % (c, stock_example[n][:90]))
    print("\nof those, said aloud (not radio, so only the ones in earshot) within 9 tiles: %d" % sum(near_echo.values()))
    for n, c in near_echo.most_common(top):
        print("  %3d  %s" % (c, stock_example[n][:90]))
    print("\nbursts: %d bots said 3+ lines in 10 game s; %d radio bursts of 4+ lines in 5 game s" % (len(bursts), len(rbursts)))
    for b in bursts[:burst_show]:
        print("  %s %s %d:%02d" % (b[0], b[1], b[2] // 60, b[2] % 60))
        for x in b[3]:
            print("       ", x[:110])


if __name__ == "__main__":
    main()
