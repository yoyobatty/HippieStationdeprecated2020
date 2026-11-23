"""Which DM procs run the slow engine paths: samples the game thread of a 32-bit dd.exe, and for each sample pairs the
instruction pointer (bucketed into the byondcore paths in FINDINGS.md) with the DM proc on top of hippie_prof.dll's
shadow stack (and the one under it). Both are read while the thread is suspended, so they agree.

Needs hippie_prof.dll loaded and hooked in the server (AUTO_PROFILE). byondcore 516.1688 only.

usage: python -I proc_paths.py <pid> <seconds> <out.json> [top N per path, default 25]
       python -I proc_paths.py <pid> probe      (prints the hook bytes and the addresses found)
"""
import collections, ctypes, ctypes.wintypes as wt, json, struct, sys, time

sys.path.insert(0, __file__.rsplit("\\", 1)[0] if "\\" in __file__ else ".")
from eip_sample import k32, modules_of, threads_of, WOW64_CONTEXT, PROCESS_QUERY_INFORMATION, PROCESS_VM_READ, \
    THREAD_SUSPEND_RESUME, THREAD_GET_CONTEXT, THREAD_QUERY_INFORMATION, WOW64_CONTEXT_CONTROL

EXEC_PROC = 0x13E750
STRINGS, STRINGS_LEN, PROCDEFS, PROCDEFS_LEN = 0x430BF0, 0x430BF4, 0x430C10, 0x430C14
PROCDEF_SIZE, PROCDEF_PATH = 0x2C, 0x00  # hippie_prof procdef_desc 0x001C002C: size low byte, path next byte

# byondcore rva ranges, from FINDINGS.md (self time only: a path's callees outside these ranges aren't counted)
PATHS = {
    "vars": [(0x2030D0, 0x2032DC), (0x202500, 0x202614), (0x213470, 0x213546), (0x162790, 0x162815), (0x24CBC0, 0x24CBD4)],
    "datum hash walk": [(0x202590, 0x202614)],
    "refcount": [(0x2250C0, 0x225440), (0x224810, 0x224D50)],
    "strings": [(0x213580, 0x213AD0), (0x24C110, 0x24C150), (0x2455C0, 0x245640)],
    "in": [(0x17F8B0, 0x17FE70)],
    "assoc new key": [(0x12F2F0, 0x12F3A0)],
    "number text": [(0x108A40, 0x108B00), (0x1824D0, 0x182800), (0x1DDB0, 0x1E000)],
    "turf enter/leave": [(0x1EF940, 0x1EFAD3), (0x2149F0, 0x214B84)],
    "sleep queue": [(0x16D7B0, 0x16D910)],
}
# "datum hash walk" sits inside "vars"; check it first
ORDER = ["datum hash walk"] + [p for p in PATHS if p != "datum hash walk"]


def rd(h, addr, n):
    buf = ctypes.create_string_buffer(n)
    if not k32.ReadProcessMemory(h, ctypes.c_void_p(addr), buf, n, None):
        return None
    return buf.raw


def u32(h, addr):
    b = rd(h, addr, 4)
    return struct.unpack("<I", b)[0] if b else None


def find_stack(h, core):
    """depth and shadow addresses, from the hook's code: exec_proc jumps to hook_exec_proc, which reads depth with
    an absolute load and writes shadow[depth] with an absolute-based store."""
    head = rd(h, core + EXEC_PROC, 5)
    if head[0] != 0xE9:
        raise SystemExit("exec_proc isn't hooked: is hippie_prof running (AUTO_PROFILE)?")
    hook = core + EXEC_PROC + 5 + struct.unpack("<i", head[1:])[0]
    code = rd(h, hook, 64)
    depth = shadow = None
    for i in range(len(code) - 6):
        if code[i] == 0xA1 and depth is None:                       # mov eax, [depth]
            depth = struct.unpack("<I", code[i + 1:i + 5])[0]
        elif code[i] == 0x8B and code[i + 1] in (0x0D, 0x15, 0x1D, 0x35, 0x3D) and depth is None:  # mov r32, [depth]
            depth = struct.unpack("<I", code[i + 2:i + 6])[0]
        elif code[i] == 0x89 and (code[i + 1] & 0xC7) == 0x04 and (code[i + 2] & 0x07) == 0x05 and shadow is None:
            shadow = struct.unpack("<I", code[i + 3:i + 7])[0]     # mov [r*4 + shadow], r32
    return hook, code, depth, shadow


def proc_names(h, core):
    n = u32(h, core + PROCDEFS_LEN)
    pd = rd(h, u32(h, core + PROCDEFS), n * PROCDEF_SIZE)
    sn = u32(h, core + STRINGS_LEN)
    stab = rd(h, u32(h, core + STRINGS), sn * 4)
    cache = {}

    def name(pid_):
        if pid_ in cache:
            return cache[pid_]
        s = "?"
        if pid_ < n:
            sid = struct.unpack_from("<I", pd, pid_ * PROCDEF_SIZE + PROCDEF_PATH)[0]
            if sid < sn:
                sp = struct.unpack_from("<I", stab, sid * 4)[0]
                data = u32(h, sp) if sp else None
                raw = rd(h, data, 160) if data else None
                if raw:
                    s = raw.split(b"\0", 1)[0].decode("latin-1")
        cache[pid_] = s
        return s
    return name


def main():
    pid = int(sys.argv[1])
    h = k32.OpenProcess(PROCESS_QUERY_INFORMATION | PROCESS_VM_READ, False, pid)
    mods = modules_of(h)
    core = next(b for b, s, n in mods if n.lower() == "byondcore.dll")
    hook, code, depth_at, shadow_at = find_stack(h, core)
    if sys.argv[2] == "probe":
        print("hook", hex(hook), code.hex(" "))
        print("depth", depth_at and hex(depth_at), "shadow", shadow_at and hex(shadow_at), "depth now", depth_at and u32(h, depth_at))
        return
    if not depth_at or not shadow_at:
        raise SystemExit("couldn't find depth/shadow in the hook's code: run with probe")
    secs, out = float(sys.argv[2]), sys.argv[3]
    top_n = int(sys.argv[4]) if len(sys.argv) > 4 else 25
    # the game thread: the one with most byondcore samples in a quick look
    tids = threads_of(pid)
    ctx = WOW64_CONTEXT()
    handles = {t: k32.OpenThread(THREAD_SUSPEND_RESUME | THREAD_GET_CONTEXT | THREAD_QUERY_INFORMATION, False, t) for t in tids}
    depth_seen = collections.Counter()
    for _ in range(300):
        for t, th in handles.items():
            if k32.Wow64SuspendThread(th) == 0xFFFFFFFF:
                continue
            ctx.ContextFlags = WOW64_CONTEXT_CONTROL
            ok = k32.Wow64GetThreadContext(th, ctypes.byref(ctx))
            k32.ResumeThread(th)
            if ok and core <= ctx.Eip < core + 0x500000:
                depth_seen[t] += 1
        time.sleep(0.002)
    tid = depth_seen.most_common(1)[0][0]
    th = handles[tid]
    name = proc_names(h, core)
    per = {p: collections.Counter() for p in PATHS}
    path_total = collections.Counter()
    busy = idle = 0
    end = time.perf_counter() + secs
    while time.perf_counter() < end:
        if k32.Wow64SuspendThread(th) == 0xFFFFFFFF:
            break
        ctx.ContextFlags = WOW64_CONTEXT_CONTROL
        ok = k32.Wow64GetThreadContext(th, ctypes.byref(ctx))
        d = u32(h, depth_at) if ok else None
        frames = rd(h, shadow_at + 4 * (d - 2), 8) if d and 2 <= d <= 1024 else (rd(h, shadow_at, 4) if d == 1 else None)
        k32.ResumeThread(th)
        time.sleep(0.001)
        if not ok:
            continue
        eip = ctx.Eip
        mod = next((n for b, s, n in mods if b <= eip < b + s), "?")
        if mod.lower() == "win32u.dll":
            idle += 1
            continue
        busy += 1
        if not (core <= eip < core + 0x500000) or not frames:
            continue
        rva = eip - core
        path = next((p for p in ORDER if any(a <= rva < b for a, b in PATHS[p])), None)
        if not path:
            continue
        ids = struct.unpack("<%dI" % (len(frames) // 4), frames)
        top = name(ids[-1])
        under = name(ids[-2]) if len(ids) > 1 else ""
        per[path][(top, under)] += 1
        path_total[path] += 1
    report = {"pid": pid, "seconds": secs, "busy": busy, "idle": idle, "paths": {}}
    print(f"busy {busy} samples, idle {idle}")
    for p in ORDER:
        n = path_total[p]
        report["paths"][p] = {"samples": n, "share": n / max(busy, 1) * 100,
                              "procs": [[t, u, c] for (t, u), c in per[p].most_common(top_n)]}
        print(f"\n== {p}: {n / max(busy, 1) * 100:.2f}% of busy")
        for (t, u), c in per[p].most_common(12):
            print(f"  {c / max(n, 1) * 100:5.1f}%  {t}   <- {u}")
    json.dump(report, open(out, "w"), indent=1)


if __name__ == "__main__":
    main()
