"""Summarise functions in a dumpbin /disasm listing: size, callees, strings, jump tables.

usage: python -I fninfo.py <dll> <asm> <rva_hex> [rva_hex ...] [--dump]
"""
import bisect, re, struct, sys

IMAGE_BASE = 0x10000000


def sections(dll):
    b = open(dll, "rb").read()
    pe = struct.unpack_from("<I", b, 0x3C)[0]
    n = struct.unpack_from("<H", b, pe + 6)[0]
    opt = struct.unpack_from("<H", b, pe + 20)[0]
    secs = []
    for i in range(n):
        o = pe + 24 + opt + 40 * i
        name = b[o:o + 8].rstrip(b"\0").decode()
        vsize, va, rsize, raw = struct.unpack_from("<IIII", b, o + 8)
        secs.append((name, va, max(vsize, rsize), raw))
    return b, secs


def read_str(b, secs, va):
    rva = va - IMAGE_BASE
    for name, sva, size, raw in secs:
        if sva <= rva < sva + size and name != ".text":
            off = raw + rva - sva
            end = b.find(b"\0", off, off + 120)
            s = b[off:end if end > 0 else off + 120]
            if len(s) >= 4 and all(32 <= c < 127 for c in s):
                return s.decode()
    return None


def main():
    dll, asm = sys.argv[1], sys.argv[2]
    dump = "--dump" in sys.argv
    want = [int(a, 16) for a in sys.argv[3:] if not a.startswith("--")]
    b, secs = sections(dll)
    lines = []
    starts = set()
    for line in open(asm, encoding="latin-1"):
        m = re.match(r"\s+([0-9A-F]{8}):\s+(.*)$", line)
        if not m:
            continue
        a = int(m.group(1), 16) - IMAGE_BASE
        lines.append((a, m.group(2).strip()))
        c = re.match(r"call\s+([0-9A-F]{8})$", m.group(2).strip())
        if c:
            starts.add(int(c.group(1), 16) - IMAGE_BASE)
    starts = sorted(starts)
    addrs = [a for a, _ in lines]
    for w in want:
        i = bisect.bisect_right(starts, w)
        end = starts[i] if i < len(starts) else w + 0x1000
        j0, j1 = bisect.bisect_left(addrs, w), bisect.bisect_left(addrs, end)
        body = lines[j0:j1]
        callees, strs, jtab = {}, [], 0
        for a, ins in body:
            c = re.match(r"call\s+([0-9A-F]{8})$", ins)
            if c:
                callees[c.group(1)] = callees.get(c.group(1), 0) + 1
            if "*4+" in ins and ins.startswith("jmp"):
                jtab += 1
            for h in re.findall(r"\b(1[0-9A-F]{7})h\b", ins):
                s = read_str(b, secs, int(h, 16))
                if s:
                    strs.append(s)
        print(f"== {w:08X} size {end - w:#x} ins {len(body)} jumptables {jtab} callees {len(callees)}")
        print("   callees:", " ".join(f"{int(k,16)-IMAGE_BASE:06X}x{v}" for k, v in sorted(callees.items(), key=lambda x: -x[1])[:12]))
        if strs:
            print("   strings:", " | ".join(dict.fromkeys(strs))[:600])
        if dump:
            for a, ins in body[:400]:
                print(f"   {a:06X}: {ins}")


if __name__ == "__main__":
    main()
