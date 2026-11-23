"""Watch a live dd.exe for main-thread stalls and say what ran in each.

Samples the main thread's EIP as fast as it can, groups samples into WINDOW ms windows,
and reports every run of >= STALL_MS of windows that were >= 90% busy (not in the
win32u/ntdll wait), with the top byondcore functions in it. Logs string count
(byondcore rva 0x430BF4, 516.1688) and private bytes once a second.

usage: python -I spike_watch.py <pid> <main_tid> <seconds> <asm> <out.json>
"""
import bisect, collections, ctypes, ctypes.wintypes as wt, json, re, sys, time

sys.path.insert(0, __file__.rsplit("\\", 1)[0].rsplit("/", 1)[0])
from eip_sample import k32, psapi, WOW64_CONTEXT, WOW64_CONTEXT_CONTROL, modules_of  # noqa: E402

WINDOW = 0.050
STALL_MS = 100
IMAGE_BASE = 0x10000000


class PMC(ctypes.Structure):
    _fields_ = [("cb", wt.DWORD), ("PageFaultCount", wt.DWORD), ("PeakWorkingSetSize", ctypes.c_size_t),
                ("WorkingSetSize", ctypes.c_size_t), ("QuotaPeakPagedPoolUsage", ctypes.c_size_t),
                ("QuotaPagedPoolUsage", ctypes.c_size_t), ("QuotaPeakNonPagedPoolUsage", ctypes.c_size_t),
                ("QuotaNonPagedPoolUsage", ctypes.c_size_t), ("PagefileUsage", ctypes.c_size_t),
                ("PeakPagefileUsage", ctypes.c_size_t), ("PrivateUsage", ctypes.c_size_t)]


def main():
    pid, tid, secs, asm, out = int(sys.argv[1]), int(sys.argv[2]), float(sys.argv[3]), sys.argv[4], sys.argv[5]
    starts = set()
    for line in open(asm, encoding="latin-1"):
        m = re.match(r"\s+[0-9A-F]{8}:\s+call\s+([0-9A-F]{8})\s*$", line)
        if m:
            starts.add(int(m.group(1), 16) - IMAGE_BASE)
    starts = sorted(starts)
    hproc = k32.OpenProcess(0x0410, False, pid)
    mods = modules_of(hproc)
    core = next((b, s) for b, s, n in mods if n.lower() == "byondcore.dll")
    idle = [(b, s) for b, s, n in mods if n.lower() in ("win32u.dll", "ntdll.dll")]
    h = k32.OpenThread(0x004A, False, tid)
    ctx = WOW64_CONTEXT()
    cnt = wt.DWORD()
    pmc = PMC(); pmc.cb = ctypes.sizeof(pmc)

    def fn(off):
        i = bisect.bisect_right(starts, off) - 1
        return starts[i] if i >= 0 else -1

    windows = []          # (t, busy_frac, Counter of fns)
    memlog = []
    t_start = time.perf_counter()
    next_mem = t_start
    win_t = t_start
    win_n = win_busy = 0
    win_fns = collections.Counter()
    while True:
        now = time.perf_counter()
        if now - t_start > secs:
            break
        if now >= next_mem:
            k32.ReadProcessMemory(hproc, ctypes.c_void_p(core[0] + 0x430BF4), ctypes.byref(cnt), 4, None)
            psapi.GetProcessMemoryInfo(hproc, ctypes.byref(pmc), pmc.cb)
            memlog.append([round(now - t_start, 2), cnt.value, pmc.PrivateUsage // 1048576])
            next_mem = now + 1.0
        if now - win_t >= WINDOW:
            windows.append((round(win_t - t_start, 3), win_busy / max(1, win_n), win_fns))
            win_t, win_n, win_busy, win_fns = now, 0, 0, collections.Counter()
        if k32.Wow64SuspendThread(h) == 0xFFFFFFFF:
            break
        ctx.ContextFlags = WOW64_CONTEXT_CONTROL
        ok = k32.Wow64GetThreadContext(h, ctypes.byref(ctx))
        k32.ResumeThread(h)
        if not ok:
            continue
        eip = ctx.Eip
        win_n += 1
        if any(b <= eip < b + s for b, s in idle):
            continue
        win_busy += 1
        if core[0] <= eip < core[0] + core[1]:
            win_fns[fn(eip - core[0])] += 1
        else:
            win_fns[-1] += 1

    stalls = []
    run = []
    for w in windows + [(0, 0, None)]:
        if w[1] >= 0.9:
            run.append(w)
            continue
        if len(run) * WINDOW * 1000 >= STALL_MS:
            tot = collections.Counter()
            for _, _, f in run:
                tot.update(f)
            n = sum(tot.values())
            stalls.append({"t": run[0][0], "ms": round(len(run) * WINDOW * 1000),
                           "top": [[f"{k:06X}" if k >= 0 else "other-module", round(100 * c / n, 1)] for k, c in tot.most_common(8)]})
        run = []
    busy = sum(w[1] for w in windows) / max(1, len(windows))
    json.dump({"seconds": secs, "mean_busy": busy, "stalls": stalls, "mem": memlog}, open(out, "w"), indent=1)
    print(f"mean busy {100*busy:.1f}%, stalls >= {STALL_MS} ms: {len(stalls)}")
    for s in stalls[:30]:
        print(f"  t={s['t']:7.2f}s {s['ms']:5d} ms  " + "  ".join(f"{k}:{v}%" for k, v in s["top"][:5]))
    print("strings/mem first, last:", memlog[0], memlog[-1])


if __name__ == "__main__":
    main()
