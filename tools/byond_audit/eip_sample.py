"""User-mode instruction-pointer sampler for a 32-bit dd.exe (no admin needed).

Suspends each thread of the target about every INTERVAL ms, reads EIP with
Wow64GetThreadContext, resumes, and buckets the hit by module + offset.

usage: python -I eip_sample.py <pid> <seconds> <out.json> [interval_ms]
"""
import ctypes, ctypes.wintypes as wt, json, sys, time, collections

k32 = ctypes.WinDLL("kernel32", use_last_error=True)
psapi = ctypes.WinDLL("psapi", use_last_error=True)

PROCESS_QUERY_INFORMATION = 0x0400
PROCESS_VM_READ = 0x0010
THREAD_SUSPEND_RESUME = 0x0002
THREAD_GET_CONTEXT = 0x0008
THREAD_QUERY_INFORMATION = 0x0040
TH32CS_SNAPTHREAD = 0x4
WOW64_CONTEXT_CONTROL = 0x00010001
LIST_MODULES_32BIT = 0x01
DEPTH = 24


class THREADENTRY32(ctypes.Structure):
    _fields_ = [("dwSize", wt.DWORD), ("cntUsage", wt.DWORD), ("th32ThreadID", wt.DWORD),
                ("th32OwnerProcessID", wt.DWORD), ("tpBasePri", wt.LONG),
                ("tpDeltaPri", wt.LONG), ("dwFlags", wt.DWORD)]


class WOW64_CONTEXT(ctypes.Structure):
    # Only the leading part matters; pad to the full 716-byte structure.
    _fields_ = [("ContextFlags", wt.DWORD), ("Dr", wt.DWORD * 6),
                ("FloatSave", ctypes.c_byte * 112), ("SegGs", wt.DWORD), ("SegFs", wt.DWORD),
                ("SegEs", wt.DWORD), ("SegDs", wt.DWORD), ("Edi", wt.DWORD), ("Esi", wt.DWORD),
                ("Ebx", wt.DWORD), ("Edx", wt.DWORD), ("Ecx", wt.DWORD), ("Eax", wt.DWORD),
                ("Ebp", wt.DWORD), ("Eip", wt.DWORD), ("SegCs", wt.DWORD), ("EFlags", wt.DWORD),
                ("Esp", wt.DWORD), ("SegSs", wt.DWORD), ("ExtendedRegisters", ctypes.c_byte * 512)]


class MODULEINFO(ctypes.Structure):
    _fields_ = [("lpBaseOfDll", ctypes.c_void_p), ("SizeOfImage", wt.DWORD), ("EntryPoint", ctypes.c_void_p)]


def threads_of(pid):
    snap = k32.CreateToolhelp32Snapshot(TH32CS_SNAPTHREAD, 0)
    te = THREADENTRY32(); te.dwSize = ctypes.sizeof(te)
    out = []
    ok = k32.Thread32First(snap, ctypes.byref(te))
    while ok:
        if te.th32OwnerProcessID == pid:
            out.append(te.th32ThreadID)
        ok = k32.Thread32Next(snap, ctypes.byref(te))
    k32.CloseHandle(snap)
    return out


def modules_of(hproc):
    arr = (ctypes.c_void_p * 1024)(); need = wt.DWORD()
    psapi.EnumProcessModulesEx(hproc, arr, ctypes.sizeof(arr), ctypes.byref(need), LIST_MODULES_32BIT)
    mods = []
    for i in range(need.value // ctypes.sizeof(ctypes.c_void_p)):
        name = ctypes.create_unicode_buffer(260)
        psapi.GetModuleBaseNameW(hproc, ctypes.c_void_p(arr[i]), name, 260)
        mi = MODULEINFO()
        psapi.GetModuleInformation(hproc, ctypes.c_void_p(arr[i]), ctypes.byref(mi), ctypes.sizeof(mi))
        mods.append((mi.lpBaseOfDll or 0, mi.SizeOfImage, name.value))
    return sorted(mods)


def main():
    pid, secs, out = int(sys.argv[1]), float(sys.argv[2]), sys.argv[3]
    interval = float(sys.argv[4]) / 1000 if len(sys.argv) > 4 else 0.001
    hproc = k32.OpenProcess(PROCESS_QUERY_INFORMATION | PROCESS_VM_READ, False, pid)
    mods = modules_of(hproc)
    handles = {}
    core = next(((b, s) for b, s, n in mods if n.lower() == "byondcore.dll"), None)
    stacks = collections.Counter()    # byondcore frames: eip rva, -[esp] rva, return rvas...
    hits = collections.Counter()      # (tid, module, offset & ~0xF)
    per_thread = collections.Counter()
    ctx = WOW64_CONTEXT()
    end = time.perf_counter() + secs
    samples = 0
    only = int(sys.argv[5]) if len(sys.argv) > 5 else 0   # optional: one thread id
    tids, next_refresh = [], 0.0
    while time.perf_counter() < end:
        now = time.perf_counter()
        if now >= next_refresh:   # thread snapshots cost ~30 ms: refresh once a second
            tids = [only] if only else threads_of(pid)
            next_refresh = now + 1.0
        for tid in tids:
            h = handles.get(tid)
            if h is None:
                h = k32.OpenThread(THREAD_SUSPEND_RESUME | THREAD_GET_CONTEXT | THREAD_QUERY_INFORMATION, False, tid)
                handles[tid] = h
            if not h or k32.Wow64SuspendThread(h) == 0xFFFFFFFF:
                continue
            ctx.ContextFlags = WOW64_CONTEXT_CONTROL
            got = k32.Wow64GetThreadContext(h, ctypes.byref(ctx))
            k32.ResumeThread(h)
            if not got:
                continue
            eip = ctx.Eip
            mod, off = "?", eip
            for base, size, name in mods:
                if base <= eip < base + size:
                    mod, off = name, eip - base
                    break
            hits[(tid, mod, off & ~0xF)] += 1
            if core and core[0] <= eip < core[0] + core[1]:
                # EBP chain walk (byondcore keeps frame pointers). A leaf caught before
                # its "push ebp" loses its direct caller; [esp] covers that case.
                frames = [eip - core[0]]
                first = wt.DWORD()
                if k32.ReadProcessMemory(hproc, ctypes.c_void_p(ctx.Esp), ctypes.byref(first), 4, None):
                    frames.append(-(first.value - core[0]))   # negative = [esp] guess
                ebp = ctx.Ebp
                buf = (wt.DWORD * 2)()
                for _ in range(DEPTH):
                    if not ebp or not k32.ReadProcessMemory(hproc, ctypes.c_void_p(ebp), buf, 8, None):
                        break
                    ret = buf[1]
                    if not (core[0] <= ret < core[0] + core[1]):
                        frames.append(0x100000000 + ret)   # absolute: left byondcore
                        break
                    frames.append(ret - core[0])
                    if buf[0] <= ebp:
                        break
                    ebp = buf[0]
                stacks[tuple(frames)] += 1
            per_thread[tid] += 1
            samples += 1
        if interval > 0:
            time.sleep(interval)
    json.dump({"pid": pid, "seconds": secs, "samples": samples,
               "modules": [[hex(b), s, n] for b, s, n in mods],
               "hits": [[t, m, o, c] for (t, m, o), c in hits.most_common()],
               "stacks": [[list(k), c] for k, c in stacks.most_common()]}, open(out, "w"))
    print("samples", samples, "threads", len(per_thread))


if __name__ == "__main__":
    main()
