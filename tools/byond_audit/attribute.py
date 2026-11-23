"""Attribute eip_sample.py hits in byondcore.dll to functions.

Function starts = call targets in the dumpbin disassembly + export RVAs.
Names come from the export table (C++ decorated; undname output if given).

usage: python -I attribute.py <samples.json> <byondcore.asm> <exports.txt> [top] [module]
"""
import bisect, collections, json, re, sys

IMAGE_BASE = 0x10000000


def main():
    samples, asm, exports = sys.argv[1:4]
    top = int(sys.argv[4]) if len(sys.argv) > 4 else 40
    module = sys.argv[5] if len(sys.argv) > 5 else "byondcore.dll"

    names = {}
    for line in open(exports, encoding="latin-1"):
        m = re.match(r"\s+\d+\s+[0-9A-F]+\s+([0-9A-F]{8})\s+(\S+)", line)
        if m:
            names[int(m.group(1), 16)] = m.group(2)

    starts = set(names)
    call = re.compile(r"\s+([0-9A-F]{8}):\s+call\s+([0-9A-F]{8})\s*$")
    for line in open(asm, encoding="latin-1"):
        m = call.match(line)
        if m:
            starts.add(int(m.group(2), 16) - IMAGE_BASE)
    starts = sorted(starts)

    d = json.load(open(samples))
    total = d["samples"]
    busy = sum(c for _, m, _, c in d["hits"] if m not in ("win32u.dll", "ntdll.dll"))
    fn = collections.Counter()
    for _, m, off, c in d["hits"]:
        if m != module:
            continue
        i = bisect.bisect_right(starts, off) - 1
        fn[starts[i] if i >= 0 else -1] += c
    print(f"samples {total}, busy {busy} ({100*busy/total:.1f}%), functions {len(starts)}")
    acc = 0
    for rva, c in fn.most_common(top):
        acc += c
        print(f"{rva:08X} {100*c/busy:5.2f}% cum {100*acc/busy:5.1f}%  {names.get(rva, '')}")


if __name__ == "__main__":
    main()
