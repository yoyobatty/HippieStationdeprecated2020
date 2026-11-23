"""A/B a hotpatch.py patch on a live dd.exe: windows off/on in ABBA order, CPU time used per window from GetProcessTimes.

usage: python -I ab_patch.py <pid> <patch> <window_seconds> <rounds>
Each round is off, on, on, off (so a steady drift in load counts the same for both). Leaves the patch off.
"""
import ctypes, ctypes.wintypes as wt, statistics, subprocess, sys, time

k32 = ctypes.WinDLL("kernel32", use_last_error=True)
HERE = __import__("os").path.dirname(__import__("os").path.abspath(__file__))


def cpu_s(h):
    c, e, kt, ut = wt.FILETIME(), wt.FILETIME(), wt.FILETIME(), wt.FILETIME()
    k32.GetProcessTimes(h, ctypes.byref(c), ctypes.byref(e), ctypes.byref(kt), ctypes.byref(ut))
    f = lambda t: (t.dwHighDateTime << 32 | t.dwLowDateTime) / 1e7
    return f(kt) + f(ut)


def setpatch(pid, patch, mode):
    subprocess.run([sys.executable, "-I", f"{HERE}/hotpatch.py", str(pid), patch, mode], check=True, capture_output=True)


def main():
    pid, patch, win, rounds = int(sys.argv[1]), sys.argv[2], float(sys.argv[3]), int(sys.argv[4])
    h = k32.OpenProcess(0x1000, False, pid)
    got = {"off": [], "on": []}
    try:
        for r in range(rounds):
            for mode in ("off", "on", "on", "off"):
                setpatch(pid, patch, mode)
                c0, t0 = cpu_s(h), time.perf_counter()
                time.sleep(win)
                share = (cpu_s(h) - c0) / (time.perf_counter() - t0) * 100
                got[mode].append(share)
                print(f"round {r + 1} {mode:3s}: {share:5.2f}% of a core", flush=True)
    finally:
        setpatch(pid, patch, "off")
    off, on = statistics.mean(got["off"]), statistics.mean(got["on"])
    print(f"mean off {off:.2f}%  on {on:.2f}%  change {(on - off) / off * 100:+.1f}%  "
          f"(sd off {statistics.pstdev(got['off']):.2f}, on {statistics.pstdev(got['on']):.2f})")


if __name__ == "__main__":
    main()
