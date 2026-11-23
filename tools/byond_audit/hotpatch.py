"""Prototype fixes for byondcore.dll 516.1688, patched into a running dd.exe from outside (no file is changed).

usage: python -I hotpatch.py <pid> <patch> on|off|status
patches:
  refcount  IncRefCount/DecRefCount return at once for the 34 value types that have no reference count (null, numbers,
            ...), before the exception frame and /GS cookie are set up. The type map is read from the DLL itself, so it's
            the same set the function's own jump table sends to its empty handler; eax = 0 on return, as there.
  refcount2 the same, and for types whose handler is only "push value; call X; add esp,4" (strings, lists, datums, objs,
            mobs, ...) the stub calls X itself with no frame. Those handlers run at try-state -1, so the frame never
            does anything for them. The handlers are matched byte for byte in the running process; any other type
            goes through the original function.
  refcount3 refcount2, and every "call IncRefCount/DecRefCount" in byondcore (179 + 511, found in the disassembly
            data/byond_audit/byondcore_1688.asm and checked byte for byte) calls the stub directly, so the jmp at the
            entry is only for anything that reaches it some other way. Closest to inlining the check at the callers.

How: a stub is put in fresh memory in the process. With the whole process suspended (and no thread part-way through
the bytes being changed) the function's first 5 bytes (push ebp / mov ebp,esp / push -1) become a jmp to the stub;
the stub's slow path runs those 3 instructions and jumps back to entry+5. "off" puts the 5 bytes back; the stub is
left allocated, so a thread inside it still finishes.
"""
import ctypes, ctypes.wintypes as wt, os, struct, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from eip_sample import threads_of, WOW64_CONTEXT, WOW64_CONTEXT_CONTROL  # noqa: E402
from string_tree import core_base  # noqa: E402

k32 = ctypes.WinDLL("kernel32", use_last_error=True)
ntdll = ctypes.WinDLL("ntdll")
k32.VirtualAllocEx.restype = ctypes.c_void_p
k32.VirtualAllocEx.argtypes = [wt.HANDLE, ctypes.c_void_p, ctypes.c_size_t, wt.DWORD, wt.DWORD]
PROLOGUE = bytes.fromhex("558bec6aff")  # push ebp; mov ebp,esp; push -1

# rva of entry, rva of its byte type map (0..0x59 -> handler index; 0 = nothing to do), rva of its handler table
REFCOUNT = [("IncRefCount", 0x2250C0, 0x225490, 0x225440), ("DecRefCount", 0x224810, 0x224DA0, 0x224D50)]
PATCHES = {"refcount": REFCOUNT, "refcount2": REFCOUNT, "refcount3": REFCOUNT}
ASM = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "data", "byond_audit", "byondcore_1688.asm")


def call_sites(entry_rva):
    """rvas of every "call <entry>" in the disassembly"""
    want = "call        %08X" % (0x10000000 + entry_rva)
    out = []
    for line in open(ASM):
        if line.rstrip().endswith(want):
            out.append(int(line[2:10], 16) - 0x10000000)
    return out


def retarget(h, base, sites, old_target, new_target):
    """(addr, bytes) writes turning "call old_target" at each site into "call new_target"; checks every site first"""
    writes = []
    for rva in sites:
        at = base + rva
        b = rd(h, at, 5)
        target = (at + 5 + struct.unpack_from("<i", b, 1)[0]) & 0xFFFFFFFF
        if b[0] != 0xE8 or target != old_target:
            sys.exit(f"call site {at:#x} isn't a call to {old_target:#x}: {b.hex()}")
        writes.append((at + 1, struct.pack("<i", new_target - (at + 5))))
    return writes


def rd(h, addr, n):
    buf = ctypes.create_string_buffer(n)
    if not k32.ReadProcessMemory(h, ctypes.c_void_p(addr), buf, n, None):
        raise OSError(f"read {addr:#x}: {ctypes.get_last_error()}")
    return buf.raw


def wr(h, addr, data, code=False):
    old = wt.DWORD()
    if code:
        k32.VirtualProtectEx(h, ctypes.c_void_p(addr), len(data), 0x40, ctypes.byref(old))
    if not k32.WriteProcessMemory(h, ctypes.c_void_p(addr), data, len(data), None):
        raise OSError(f"write {addr:#x}: {ctypes.get_last_error()}")
    if code:
        k32.VirtualProtectEx(h, ctypes.c_void_p(addr), len(data), old.value, ctypes.byref(old))
        k32.FlushInstructionCache(h, ctypes.c_void_p(addr), len(data))


def jmp_back(base_addr, at, entry):
    """prologue then jmp entry+5, placed at base_addr+at"""
    return PROLOGUE + b"\xe9" + struct.pack("<i", entry + 5 - (base_addr + at + len(PROLOGUE) + 5))


def refcount_stub(base_addr, entry, typemap):
    """movzx eax,[esp+4]; cmp byte [eax+table],0; je slow; xor eax,eax; ret; slow: prologue; jmp entry+5"""
    table = base_addr + 0x40
    code = bytes.fromhex("0fb6442404") + b"\x80\xb8" + struct.pack("<I", table) + b"\x00" + bytes.fromhex("740333c0c3")
    code += jmp_back(base_addr, len(code), entry)
    fast = bytes(1 if i < len(typemap) and typemap[i] == 0 else 0 for i in range(256))
    return code.ljust(0x40, b"\xcc") + fast


def refcount2_stub(base_addr, entry, typemap, handlers, h):
    """dword per type: 0 = original function, 1 = nothing to do, else X to call with the value and return from.
    movzx eax,[esp+4]; mov eax,[eax*4+table]; test eax,eax; je slow; cmp eax,1; je noop;
    push [esp+8]; call eax; add esp,4; ret; noop: xor eax,eax; ret; slow: prologue; jmp entry+5"""
    table = base_addr + 0x40
    code = bytes.fromhex("0fb6442404") + b"\x8b\x04\x85" + struct.pack("<I", table)
    code += bytes.fromhex("85c07412" "83f801740a" "ff742408ffd083c404c3" "33c0c3")
    assert len(code) == 34
    code += jmp_back(base_addr, len(code), entry)
    targets = {}
    for i, hand in enumerate(handlers):
        b = rd(h, hand, 14)  # push dword ptr [ebp+0Ch]; call rel32; add esp,4; mov ecx,[ebp-0Ch]
        if b[:4] == b"\xff\x75\x0c\xe8" and b[8:11] == b"\x83\xc4\x04" and b[11:14] == b"\x8b\x4d\xf4":
            targets[i] = (hand + 8 + struct.unpack_from("<i", b, 4)[0]) & 0xFFFFFFFF
    slots = []
    for ty in range(256):
        hi = typemap[ty] if ty < len(typemap) else None
        slots.append(0 if hi is None else 1 if hi == 0 else targets.get(hi, 0))
    return code.ljust(0x40, b"\xcc") + struct.pack("<256I", *slots), sum(1 for v in slots if v > 1)


def with_process_suspended(h, pid, entries, fn):
    """Run fn() with every thread of pid suspended and none of them inside entry+1..entry+4 of any entry."""
    for _ in range(50):
        ntdll.NtSuspendProcess(h)
        bad = False
        for tid in threads_of(pid):
            th = k32.OpenThread(0x0008 | 0x0040, False, tid)
            ctx = WOW64_CONTEXT(); ctx.ContextFlags = WOW64_CONTEXT_CONTROL
            if th and k32.Wow64GetThreadContext(th, ctypes.byref(ctx)):
                bad |= any(e < ctx.Eip < e + 5 for e in entries)
            if th:
                k32.CloseHandle(th)
        if not bad:
            try:
                return fn()
            finally:
                ntdll.NtResumeProcess(h)
        ntdll.NtResumeProcess(h)
    raise RuntimeError("a thread kept sitting in a patched prologue")


def main():
    pid, name, mode = int(sys.argv[1]), sys.argv[2], sys.argv[3]
    h = k32.OpenProcess(0x1F0FFF, False, pid)
    base = core_base(h)
    todo = []
    for label, entry_rva, map_rva, tbl_rva in PATCHES[name]:
        entry = base + entry_rva
        now = rd(h, entry, 5)
        state = "on" if now[0] == 0xE9 else "off" if now == PROLOGUE else f"unknown bytes {now.hex()}"
        print(f"{label} at {entry:#x}: {state}")
        if state.startswith("unknown"):
            sys.exit("not the 516.1688 code this patch was written for")
        todo.append((label, entry, base + map_rva, base + tbl_rva, state))
    if mode == "status":
        return
    writes = []
    for label, entry, map_addr, tbl_addr, state in todo:
        if mode == "on" and state == "off":
            stub = k32.VirtualAllocEx(h, None, 0x1000, 0x3000, 0x40)
            typemap = rd(h, map_addr, 0x5A)
            if name in ("refcount2", "refcount3"):
                n = max(typemap) + 1
                handlers = struct.unpack("<%dI" % n, rd(h, tbl_addr, 4 * n))
                body, direct = refcount2_stub(stub, entry, typemap, handlers, h)
                print(f"{label}: {direct} types called directly")
            else:
                body = refcount_stub(stub, entry, typemap)
            wr(h, stub, body)
            writes.append((entry, b"\xe9" + struct.pack("<i", stub - (entry + 5))))
            if name == "refcount3":
                sites = retarget(h, base, call_sites(entry - base), entry, stub)
                writes += sites
                print(f"{label}: {len(sites)} call sites to the stub")
        elif mode == "off" and state == "on":
            writes.append((entry, PROLOGUE))
            if name == "refcount3":
                stub = (entry + 5 + struct.unpack_from("<i", rd(h, entry, 5), 1)[0]) & 0xFFFFFFFF
                writes += retarget(h, base, call_sites(entry - base), stub, entry)
    with_process_suspended(h, pid, [e for e, d in writes if len(d) == 5], lambda: [wr(h, e, d, code=True) for e, d in writes])
    print(f"{name}: {mode} ({len(writes)} functions changed)")


if __name__ == "__main__":
    main()
