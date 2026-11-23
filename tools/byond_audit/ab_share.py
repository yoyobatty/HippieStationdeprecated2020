"""A/B a hotpatch.py patch by where the main thread's busy time goes, not by total CPU (which swings with the round).

usage: python -I ab_share.py <pid> <patch> <window_seconds> <rounds> <out_dir>
Rounds of off, on, on, off windows, each sampled by eip_sample.py on the busiest thread. Prints per window: busy samples
(not waiting in win32u), and the share of them inside the patched functions (and in stub memory outside any module).
"""
import collections, json, os, statistics, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from hotpatch import PATCHES  # noqa: E402

# byte ranges (rva) of each patched function: entry to its jump table
RANGES = {"refcount": [(0x2250C0, 0x225440), (0x224810, 0x224D50)]}
RANGES["refcount2"] = RANGES["refcount"]
RANGES["refcount3"] = RANGES["refcount"]
# string lookup 213580 and rebuild 213890 (to 213AD0), the compare function 24C110, and proto/string_hash.dll itself
RANGES["strings"] = [(0x213580, 0x213AD0), (0x24C110, 0x24C150)]
# var read 2030D0/2031F0 (to 2032DC), override list 202500, type default search 213470, type of 162790, 24CBC0
RANGES["vars"] = [(0x2030D0, 0x2032DC), (0x202500, 0x202614), (0x213470, 0x213546), (0x162790, 0x162815),
                  (0x24CBC0, 0x24CBD4)]
# "in" 17F8B0; obj enters a loc 1EF940 and leaves it 2149F0; sleep queue insert 16D7B0
RANGES["in"] = [(0x17F8B0, 0x17FE70)]
RANGES["turf"] = [(0x1EF940, 0x1EFAD3), (0x2149F0, 0x214B84)]
RANGES["sleepq"] = [(0x16D7B0, 0x16D910)]
# patches that are prototype DLLs (proto/<name>.dll, injected) rather than hotpatch.py byte patches
PROTO = {"strings": "string_hash.dll", "vars": "var_cache.dll", "in": "in_index.dll", "turf": "turf_chain.dll",
         "sleepq": "sleep_queue.dll"}


def setpatch(pid, patch, mode):
    if patch in PROTO:
        run(f"{HERE}/proto/inject.py", str(pid), f"{HERE}/proto/{PROTO[patch]}",
            "thread_install" if mode == "on" else "thread_uninstall")
    else:
        run(f"{HERE}/hotpatch.py", str(pid), patch, mode)


def run(*args):
    subprocess.run([sys.executable, "-I", *args], check=True, capture_output=True)


def main():
    pid, patch, win, rounds, out = int(sys.argv[1]), sys.argv[2], sys.argv[3], int(sys.argv[4]), sys.argv[5]
    os.makedirs(out, exist_ok=True)
    probe = f"{out}/probe.json"
    run(f"{HERE}/eip_sample.py", str(pid), "3", probe)
    per = collections.Counter()
    for t, m, o, c in json.load(open(probe))["hits"]:
        if m.lower() == "byondcore.dll":
            per[t] += c
    tid = per.most_common(1)[0][0]
    got = {"off": [], "on": []}
    try:
        for r in range(rounds):
            for i, mode in enumerate(("off", "on", "on", "off")):
                setpatch(pid, patch, mode)
                path = f"{out}/{patch}_{r}_{i}_{mode}.json"
                run(f"{HERE}/eip_sample.py", str(pid), win, path, "0", str(tid))
                busy = inside = 0
                for t, m, o, c in json.load(open(path))["hits"]:
                    if m.lower() == "win32u.dll":
                        continue
                    busy += c
                    if m == "?" or (patch in PROTO and m.lower() == PROTO[patch]) or (m.lower() == "byondcore.dll" and any(a <= o < b for a, b in RANGES[patch])):
                        inside += c
                share = inside / busy * 100
                got[mode].append(share)
                print(f"round {r + 1} {mode:3s}: busy {busy:6d} samples, in {patch} {share:5.2f}%", flush=True)
    finally:
        setpatch(pid, patch, "off")
    off, on = statistics.mean(got["off"]), statistics.mean(got["on"])
    print(f"{patch} share of busy time: off {off:.2f}%  on {on:.2f}%  (sd {statistics.pstdev(got['off']):.2f} / "
          f"{statistics.pstdev(got['on']):.2f})")


if __name__ == "__main__":
    main()
