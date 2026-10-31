#!/usr/bin/env python3
"""One report for a batch of Bot Shifts (tools/bot_gym/run_shift_batch.sh).

  python tools/bot_gym/batch_report.py data/logs/shift_batch/<name>
  python tools/bot_gym/batch_report.py <batch> --compare <older batch>     goals given up, side by side

Lists what failed and how often, which goals bots gave up on and why (giveups.py), and every runtime.
"""
import argparse
import collections
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import giveups  # noqa: E402


def read_batch(directory):
    runs = []
    missing = []
    for name in sorted(os.listdir(directory), key=lambda n: (len(n), n)):
        path = os.path.join(directory, name)
        if not (name.startswith("run") and os.path.isdir(path)):
            continue
        results = os.path.join(path, "results.json")
        if not os.path.isfile(results):
            missing.append(name)
            continue
        with open(results, encoding="utf-8", errors="replace") as handle:
            data = json.load(handle)
        data["run"] = name
        data["path"] = path
        runs.append(data)
    return runs, missing


def tally_goals(runs):
    done = collections.Counter()
    gave_up = collections.Counter()
    for data in runs:
        for member in data["members"]:
            for goal, tally in (member.get("goals") or {}).items():
                done[goal] += tally[0]
                gave_up[goal] += tally[1]
    return done, gave_up


def report(directory, compare):
    runs, missing = read_batch(directory)
    if not runs:
        sys.exit(f"No results in {directory}")
    count = len(runs)
    print(f"\nBATCH {directory}: {count} shifts")
    maps = collections.Counter(data.get("map") or "?" for data in runs)
    print("Maps: " + ", ".join(f"{name} x{n}" for name, n in maps.most_common()))
    speeds = [data["speed"] for data in runs]
    print(f"Speed {min(speeds)}x to {max(speeds)}x. Load: average {sum(d['load_avg'] for d in runs) / count:.0f}% of a tick, "
          f"worst peak {max(d['load_max'] for d in runs)}%, {sum(d['overloaded_seconds'] for d in runs)} seconds over 100%.")
    search = collections.Counter()
    for data in runs:
        search.update(data["pathfinding"])
    print(f"Pathfinding per shift: {search['searches'] // count} searches, {search['turfs'] // count} turfs, "
          f"{search['failed'] // count} failed.")

    failed_runs = [data for data in runs if data["failures"]]
    if failed_runs or missing:
        print(f"\nFAILED SHIFTS: {len(failed_runs)} of {count}" + (f", and no results from {', '.join(missing)}" if missing else ""))
        for data in failed_runs:
            print(f"  {data['run']}: {data['failures']} failure(s) ({data.get('map')}) - {data['path']}/summary.txt")

    checks = collections.defaultdict(collections.Counter)
    details = collections.defaultdict(list)
    for data in runs:
        for check in data["checks"]:
            if check["outcome"] == "SKIP":
                continue  # nothing to judge on this map, or the shift was too short
            checks[check["name"]][check["outcome"]] += 1
            if check["outcome"] != "PASS":
                details[check["name"]].append(f"{data['run']}: {check.get('detail', '')}")
    print("\nDEPARTMENT WORK (passed/judged)")
    for name, outcomes in sorted(checks.items(), key=lambda item: item[1]["PASS"] / sum(item[1].values())):
        total = sum(outcomes.values())
        print(f"  {outcomes['PASS']:3}/{total:<3} {name}")
        for detail in details[name][:3]:
            print(f"          {detail[:130]}")

    trouble = collections.Counter()
    jobs = collections.Counter()
    deaths = collections.Counter()
    for data in runs:
        for member in data["members"]:
            jobs[member["job"]] += 1
            if member.get("died_at") is not None:
                deaths[member["job"]] += 1
            for problem in member.get("problems") or []:
                trouble["FAIL " + giveups.shape(problem)] += 1
            for warning in member.get("warnings") or []:
                trouble["warn " + giveups.shape(warning)] += 1
    if deaths:
        print("\nDEATHS: " + ", ".join(f"{job} {n}/{jobs[job]}" for job, n in deaths.most_common()))
    if trouble:
        print("\nCREW TROUBLE")
        for text, n in trouble.most_common(25):
            print(f"  {n:4} {text}")

    sites = collections.Counter()
    errors = {}
    bot_exceptions = collections.Counter()
    for data in runs:
        for entry in data["runtimes"]:
            sites[entry["site"]] += entry["count"]
            errors[entry["site"]] = entry["error"]
        for text in data["bot_exceptions"]:
            bot_exceptions[giveups.shape(text)] += 1
    if sites:
        print("\nRUNTIMES")
        for site, n in sites.most_common(30):
            print(f"  {n:5} {site}: {errors[site][:100]}")
    if bot_exceptions:
        print("\nBOT AI EXCEPTIONS")
        for text, n in bot_exceptions.most_common(15):
            print(f"  {n:5} {text}")

    done, gave_up = tally_goals(runs)
    print(f"\nGOALS (per shift: {sum(done.values()) / count:.0f} done, {sum(gave_up.values()) / count:.0f} given up)")
    old_gave_up = old_done = None
    old_count = 0
    if compare:
        old_runs, _ = read_batch(compare)
        old_count = len(old_runs)
        old_done, old_gave_up = tally_goals(old_runs)
    print("  given up per shift / done per shift" + ("   (the other batch)" if compare else ""))
    for goal, n in gave_up.most_common(24):
        line = f"  {n / count:7.1f} / {done[goal] / count:<7.1f} {goal}"
        if compare:
            line += f"   ({old_gave_up[goal] / max(old_count, 1):.1f} / {old_done[goal] / max(old_count, 1):.1f})"
        print(line)

    counts = collections.Counter()
    targets = collections.defaultdict(collections.Counter)
    reasons = collections.defaultdict(collections.Counter)
    by_bot = collections.Counter()
    for data in runs:
        if os.path.isfile(os.path.join(data["path"], "game.log")):
            giveups.read_round(data["path"], counts, targets, reasons, by_bot, [], None, 0)
    if counts:
        print("\nWHY (the bot's last words before giving up, whole batch)")
        for goal, n in counts.most_common(14):
            print(f"  {n:5} {goal}")
            for reason, times in reasons[goal].most_common(3):
                print(f"          {times:5} {reason[:120]}")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("batch")
    parser.add_argument("--compare", help="an older batch to show alongside")
    args = parser.parse_args()
    report(args.batch, args.compare)


if __name__ == "__main__":
    main()
