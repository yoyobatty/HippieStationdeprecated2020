"""Inclusive costs and caller chains from eip_sample.py stack walks.

usage: python -I stacks.py <samples.json> <byondcore.asm> [--callers RVA[,RVA]] [top]
"""
import bisect, collections, json, re, sys

IMAGE_BASE = 0x10000000


def load_starts(asm):
    starts = set()
    call = re.compile(r"\s+[0-9A-F]{8}:\s+call\s+([0-9A-F]{8})\s*$")
    for line in open(asm, encoding="latin-1"):
        m = call.match(line)
        if m:
            starts.add(int(m.group(1), 16) - IMAGE_BASE)
    return sorted(starts)


def main():
    d = json.load(open(sys.argv[1]))
    starts = load_starts(sys.argv[2])
    args = sys.argv[3:]
    callers_of = None
    if "--callers" in args:
        i = args.index("--callers")
        callers_of = {int(x, 16) for x in args[i + 1].split(",")}
        del args[i:i + 2]
    top = int(args[0]) if args else 40

    def fn(rva):
        i = bisect.bisect_right(starts, rva) - 1
        return starts[i] if i >= 0 else -1

    busy = sum(c for _, m, _, c in d["hits"] if m not in ("win32u.dll", "ntdll.dll"))
    incl, self_ = collections.Counter(), collections.Counter()
    chains = collections.Counter()
    for frames, c in d["stacks"]:
        eip = frames[0]
        rets = [f for f in frames[2:]]      # skip the [esp] guess
        fns = [fn(eip)] + [fn(r) for r in rets]
        self_[fns[0]] += c
        for f in set(fns):
            incl[f] += c
        if callers_of and fns[0] in callers_of:
            chains[tuple(f"{x:06X}" for x in fns[1:6])] += c
    if callers_of:
        tot = sum(chains.values())
        print(f"samples in {', '.join(f'{x:06X}' for x in callers_of)}: {tot} ({100*tot/busy:.2f}% of busy)")
        for ch, c in chains.most_common(top):
            print(f"{100*c/busy:5.2f}%  " + " <- ".join(ch))
        return
    print(f"busy {busy}")
    for f, c in incl.most_common(top):
        print(f"{f:08X} incl {100*c/busy:5.1f}%  self {100*self_[f]/busy:5.2f}%")


if __name__ == "__main__":
    main()
