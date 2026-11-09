"""Puts a Bot Gym split across servers back together (tools/bot_gym/run_bot_gym.sh JOBS=N).

Usage: python tools/bot_gym/merge_gym_shards.py <out dir> <work dir> [--wall SECONDS]

Each server wrote its part into <work dir>/shard<i>/ (summary.txt, results.json, load.json, transcripts/, or only planned.json if it
never finished) and its output to <work dir>/shard<i>.log. This writes <out dir>/summary.txt and results.json in the suite's order, as
one server would have, moves the transcripts across, keeps the server logs in <out dir>/servers/, and records how long each scenario
took in data/bot_gym_times.json, which the next split shares the scenarios out by.
"""
import json
import os
import re
import shutil
import sys

TIMES_FILE = "data/bot_gym_times.json"
OUTCOMES = ("PASS", "FAIL", "XFAIL", "XPASS", "PENDING")


def shard_dirs(work):
    found = []
    for name in os.listdir(work):
        m = re.fullmatch(r"shard(\d+)", name)
        if m and os.path.isdir(os.path.join(work, name)):
            found.append((int(m.group(1)), os.path.join(work, name)))
    return sorted(found)


def read_json(path):
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return None


def result_lines(summary_path):
    """The per-run lines of a summary.txt, in the order the server wrote them (the same order as its results.json)."""
    with open(summary_path, encoding="utf-8", errors="replace") as f:
        text = f.read().splitlines()
    lines = []
    started = False
    for line in text:
        if line.startswith("FAILED:"):
            break
        if not started:
            started = line == ""
            continue
        if line.split(" ", 1)[0] in OUTCOMES:
            lines.append(line)
    return lines


def load_from_summary(summary_path):
    """A build from before split gyms writes no load.json: its summary's load line, near enough."""
    try:
        with open(summary_path, encoding="utf-8", errors="replace") as f:
            head = f.read(2000)
    except OSError:
        return {}
    m = re.search(r"Server load averaged (\d+)% of a tick, peak (\d+)%, (\d+) of (\d+) seconds over 100%", head)
    if not m:
        return {}
    average, peak, over, seconds = map(int, m.groups())
    return {"seconds": seconds, "sum": average * seconds, "peak": peak, "over": over}


def pad(text, width):
    return text + " " * max(0, width - len(text))


def main():
    args = sys.argv[1:]
    wall = None
    if "--wall" in args:
        i = args.index("--wall")
        wall = int(args[i + 1])
        del args[i:i + 2]
    if len(args) != 2:
        print(__doc__)
        sys.exit(2)
    out, work = args
    os.makedirs(os.path.join(out, "transcripts"), exist_ok=True)
    os.makedirs(os.path.join(out, "servers"), exist_ok=True)

    shards = shard_dirs(work)
    entries = []  # (order, line, result)
    load_total = {"seconds": 0, "sum": 0, "peak": 0, "over": 0}
    slow_servers = []
    elsewhere = 0
    problems = []
    for index, path in shards:
        log = os.path.join(work, f"shard{index}.log")
        if os.path.exists(log):
            shutil.copy(log, os.path.join(out, "servers", f"shard{index}.log"))
        results = read_json(os.path.join(path, "results.json"))
        if results is None:
            planned = read_json(os.path.join(path, "planned.json"))
            if planned is None:
                problems.append(f"WARNING: server {index} never got as far as its scenarios - see {out}/servers/shard{index}.log")
                continue
            problems.append(f"WARNING: server {index} wrote no results (crashed or timed out) - its {len(planned)} run(s) are unfinished; see {out}/servers/shard{index}.log")
            for p in planned:
                label = p["name"] + (f" #{p['run']}" if p["run"] > 1 else "")
                line = f"{pad('PENDING', 7)}{pad(label, 54)}   its server wrote no results"
                entries.append((p["order"], line, {"name": p["name"], "run": p["run"], "outcome": "PENDING", "seconds": None,
                                                  "reason": "its server wrote no results", "desc": "", "order": p["order"]}))
            continue
        lines = result_lines(os.path.join(path, "summary.txt"))
        if len(lines) != len(results):
            problems.append(f"WARNING: server {index}'s summary has {len(lines)} lines for {len(results)} results; lines rebuilt from results.json")
            lines = [f"{pad(r['outcome'], 7)}{pad(r['name'] + (' #' + str(r['run']) if r['run'] > 1 else ''), 54)}"
                     f"{str(r['seconds']) + 's' if r['seconds'] is not None else ''}{'   ' + r['reason'] if r.get('reason') else ''}"
                     for r in results]
        for line, r in zip(lines, results):
            entries.append((r.get("order") or 0, line, r))
        load = read_json(os.path.join(path, "load.json")) or load_from_summary(os.path.join(path, "summary.txt"))
        if load.get("seconds"):
            load_total["seconds"] += load["seconds"]
            load_total["sum"] += load["sum"]
            load_total["peak"] = max(load_total["peak"], load["peak"])
            load_total["over"] += load["over"]
            if load["over"] > load["seconds"] * 0.1:
                slow_servers.append(index)
        elsewhere += load.get("elsewhere") or 0
        transcripts = os.path.join(path, "transcripts")
        if os.path.isdir(transcripts):
            for name in os.listdir(transcripts):
                os.replace(os.path.join(transcripts, name), os.path.join(out, "transcripts", name))

    entries.sort(key=lambda e: e[0])
    counts = {k: 0 for k in OUTCOMES}
    for _, _, r in entries:
        counts[r["outcome"]] = counts.get(r["outcome"], 0) + 1
    header = (f"BOT GYM  {counts['PASS']} passed, {counts['FAIL']} failed, {counts['XFAIL']} expected failures, "
              f"{counts['XPASS']} unexpected passes" + (f", {counts['PENDING']} unfinished" if counts["PENDING"] else ""))
    servers = len(shards)
    if load_total["seconds"]:
        average = round(load_total["sum"] / load_total["seconds"])
        if servers > 1:
            header += (f"\nServer load averaged {average}% of a tick over {servers} servers, peak {round(load_total['peak'])}%, "
                       f"{load_total['over']} of {load_total['seconds']} server-seconds over 100%.")
        else:
            header += (f"\nServer load averaged {average}% of a tick, peak {round(load_total['peak'])}%, "
                       f"{load_total['over']} of {load_total['seconds']} seconds over 100%.")
        if slow_servers:
            which = "The server" if servers == 1 else "Server" + ("s " if len(slow_servers) > 1 else " ") + ", ".join(map(str, slow_servers))
            header += f" {which} couldn't keep up, so bots ran slow in game time - timeouts and idle tells in this run may not be their doing."
    if wall is not None:
        header += f"\nTook {wall} s" + (f" on {servers} servers." if servers > 1 else ".")
    if elsewhere:
        header += (f"\nWARNING: {elsewhere} of {len(entries)} arenas didn't fit on the reserved map level and were built on an extra one, "
                   "where results can't be trusted. Run fewer passes at once.")
    for p in problems:
        header += "\n" + p
    failed = counts["FAIL"] + counts["PENDING"]
    summary = header + "\n\n" + "\n".join(line for _, line, _ in entries) + f"\nFAILED: {failed}\n"
    with open(os.path.join(out, "summary.txt"), "w", encoding="utf-8", newline="\n") as f:
        f.write(summary)
    with open(os.path.join(out, "results.json"), "w", encoding="utf-8", newline="\n") as f:
        json.dump([r for _, _, r in entries], f)

    # Game seconds each scenario took, its slowest run, for the next split.
    times = read_json(TIMES_FILE)
    if not isinstance(times, dict):
        times = {}
    took = {}
    for _, _, r in entries:
        if isinstance(r.get("seconds"), (int, float)):
            took[r["name"]] = max(took.get(r["name"], 0), r["seconds"])
    if took:
        times.update(took)
        tmp = TIMES_FILE + ".tmp"
        with open(tmp, "w", encoding="utf-8", newline="\n") as f:
            json.dump(times, f, indent=0, sort_keys=True)
        os.replace(tmp, TIMES_FILE)


if __name__ == "__main__":
    main()
