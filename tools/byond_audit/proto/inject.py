"""Load a prototype DLL into a running 32-bit dd.exe and run one of its thread_* exports at a safe moment.

usage: python -I inject.py <pid> <dll path> <export>      e.g. thread_install, thread_stats, thread_uninstall
The DLL is loaded once (LoadLibraryA in a remote thread). The export then runs in a remote thread while every other
thread of dd.exe is suspended, and only when the main thread (the one most often sampled in byondcore) is in its
tick wait in win32u.dll, so no string is part-way through being made. Prints the text whose address the export
returns.
"""
import ctypes, ctypes.wintypes as wt, os, struct, sys, time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
from eip_sample import threads_of, modules_of, WOW64_CONTEXT, WOW64_CONTEXT_CONTROL  # noqa: E402

k32 = ctypes.WinDLL("kernel32", use_last_error=True)
k32.VirtualAllocEx.restype = ctypes.c_void_p
k32.VirtualAllocEx.argtypes = [wt.HANDLE, ctypes.c_void_p, ctypes.c_size_t, wt.DWORD, wt.DWORD]
k32.CreateRemoteThread.restype = wt.HANDLE
k32.CreateRemoteThread.argtypes = [wt.HANDLE, ctypes.c_void_p, ctypes.c_size_t, ctypes.c_void_p, ctypes.c_void_p,
                                   wt.DWORD, ctypes.c_void_p]


def export_rva(path, name):
    d = open(path, "rb").read()
    pe = struct.unpack_from("<I", d, 0x3C)[0]
    ns = struct.unpack_from("<H", d, pe + 6)[0]
    oh = struct.unpack_from("<H", d, pe + 20)[0]
    secs = [struct.unpack_from("<8sIIII", d, pe + 24 + oh + i * 40) for i in range(ns)]

    def off(rva):
        for _, vs, va, rs, ro in secs:
            if va <= rva < va + max(vs, rs):
                return ro + rva - va
    exp = struct.unpack_from("<I", d, pe + 24 + 96)[0]  # PE32 optional header: data directory 0
    _, _, _, _, _, _, nfun, nnames, afun, anames, aords = struct.unpack_from("<IIHHIIIIIII", d, off(exp))
    for i in range(nnames):
        nm = d[off(struct.unpack_from("<I", d, off(anames) + 4 * i)[0]):].split(b"\0", 1)[0].decode()
        if nm == name or nm.startswith(f"_{name}@"):  # stdcall exports are decorated: _thread_install@4
            ordn = struct.unpack_from("<H", d, off(aords) + 2 * i)[0]
            return struct.unpack_from("<I", d, off(afun) + 4 * ordn)[0]
    raise KeyError(name)


def run_thread(h, start, param=0):
    th = k32.CreateRemoteThread(h, None, 0, ctypes.c_void_p(start), ctypes.c_void_p(param), 0, None)
    if not th:
        raise OSError(f"CreateRemoteThread: {ctypes.get_last_error()}")
    k32.WaitForSingleObject(th, 60000)
    code = wt.DWORD()
    k32.GetExitCodeThread(th, ctypes.byref(code))
    k32.CloseHandle(th)
    return code.value


def module_base(h, name):
    for base, size, n in modules_of(h):
        if n.lower() == name.lower():
            return base


def main():
    pid, dll, export = int(sys.argv[1]), os.path.abspath(sys.argv[2]), sys.argv[3]
    h = k32.OpenProcess(0x1F0FFF, False, pid)
    base = module_base(h, os.path.basename(dll))
    if not base:
        k32base = module_base(h, "kernel32.dll")
        lla = k32base + export_rva(os.path.join(os.environ["WINDIR"], "SysWOW64", "kernel32.dll"), "LoadLibraryA")
        mem = k32.VirtualAllocEx(h, None, 4096, 0x3000, 0x04)
        k32.WriteProcessMemory(h, ctypes.c_void_p(mem), dll.encode("mbcs") + b"\0", len(dll) + 1, None)
        if not run_thread(h, lla, mem):
            sys.exit("LoadLibraryA failed in the target")
        base = module_base(h, os.path.basename(dll))
    start = base + export_rva(dll, export)
    core = module_base(h, "byondcore.dll")
    wait_mod = next((b, s) for b, s, n in modules_of(h) if n.lower() == "win32u.dll")
    tids = threads_of(pid)
    # the main thread: the one most often found in byondcore
    hits = dict.fromkeys(tids, 0)
    ctx = WOW64_CONTEXT()
    for _ in range(300):
        for tid in tids:
            th = k32.OpenThread(0x0002 | 0x0008 | 0x0040, False, tid)
            if th and k32.Wow64SuspendThread(th) != 0xFFFFFFFF:
                ctx.ContextFlags = WOW64_CONTEXT_CONTROL
                if k32.Wow64GetThreadContext(th, ctypes.byref(ctx)) and core <= ctx.Eip < core + 0x500000:
                    hits[tid] += 1
                k32.ResumeThread(th)
            if th:
                k32.CloseHandle(th)
    main_tid = max(hits, key=hits.get)
    for attempt in range(200):
        held = []
        for tid in tids:
            th = k32.OpenThread(0x0002 | 0x0008 | 0x0040, False, tid)
            if th and k32.Wow64SuspendThread(th) != 0xFFFFFFFF:
                held.append((tid, th))
        ctx = WOW64_CONTEXT(); ctx.ContextFlags = WOW64_CONTEXT_CONTROL
        mth = dict(held).get(main_tid)
        # safe only in the tick wait: anywhere else (even malloc) it may be part-way through making a string
        safe = bool(mth) and k32.Wow64GetThreadContext(mth, ctypes.byref(ctx)) and \
            wait_mod[0] <= ctx.Eip < wait_mod[0] + wait_mod[1]
        if safe:
            try:
                addr = run_thread(h, start)
            finally:
                for _, th in held:
                    k32.ResumeThread(th); k32.CloseHandle(th)
            buf = ctypes.create_string_buffer(512)
            k32.ReadProcessMemory(h, ctypes.c_void_p(addr), buf, 511, None)
            print(f"{export} (after {attempt} tries): {buf.value.decode()}")
            return
        for _, th in held:
            k32.ResumeThread(th); k32.CloseHandle(th)
        time.sleep(0.003)
    sys.exit("main thread never caught outside byondcore")


if __name__ == "__main__":
    main()
