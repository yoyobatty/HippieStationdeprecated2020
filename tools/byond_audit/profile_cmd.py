"""Run a 32-bit command (dm.exe, dreammaker.exe ...) and sample every thread's EIP until it exits.

usage: python -I profile_cmd.py <out.json> <exe> [args...]
Output: same "hits" format as eip_sample.py, plus wall time.
"""
import collections, ctypes, json, subprocess, sys, time

sys.path.insert(0, __file__.rsplit("\\", 1)[0].rsplit("/", 1)[0])
from eip_sample import k32, WOW64_CONTEXT, WOW64_CONTEXT_CONTROL, modules_of, threads_of  # noqa: E402


def main():
    out, cmd = sys.argv[1], sys.argv[2:]
    t0 = time.perf_counter()
    p = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    hproc = k32.OpenProcess(0x0410, False, p.pid)
    mods, mods_t = [], 0
    hits = collections.Counter()
    handles = {}
    tids, tids_t = [], 0
    ctx = WOW64_CONTEXT()
    samples = 0
    while p.poll() is None:
        now = time.perf_counter()
        if now - mods_t > 0.5:
            mods = modules_of(hproc) or mods
            tids = threads_of(p.pid)
            mods_t = now
        for tid in tids:
            h = handles.get(tid) or k32.OpenThread(0x004A, False, tid)
            handles[tid] = h
            if not h or k32.Wow64SuspendThread(h) == 0xFFFFFFFF:
                continue
            ctx.ContextFlags = WOW64_CONTEXT_CONTROL
            ok = k32.Wow64GetThreadContext(h, ctypes.byref(ctx))
            k32.ResumeThread(h)
            if not ok:
                continue
            eip = ctx.Eip
            mod, off = "?", eip
            for b, s, n in mods:
                if b <= eip < b + s:
                    mod, off = n, eip - b
                    break
            hits[(tid, mod, off & ~0xF)] += 1
            samples += 1
    wall = time.perf_counter() - t0
    log = p.stdout.read().decode("latin-1")
    json.dump({"cmd": cmd, "wall": wall, "samples": samples, "log_tail": log[-2000:],
               "modules": [[hex(b), s, n] for b, s, n in mods],
               "hits": [[t, m, o, c] for (t, m, o), c in hits.most_common()]}, open(out, "w"))
    bym = collections.Counter()
    for (t, m, o), c in hits.items():
        bym[m] += c
    print(f"wall {wall:.1f}s samples {samples}")
    for m, c in bym.most_common(8):
        print(f"  {m:24s} {100*c/samples:5.1f}%")
    print(log[-400:])


if __name__ == "__main__":
    main()
