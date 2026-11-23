"""Census of a live dd.exe's interned strings (516.1688 layout, see string_tree.py), and what's new between two snapshots.

usage: python -I string_census.py <pid> <gap_seconds> <out.json>
Classes are by shape (ref text, timestamps, paths, html, numbers, ...). Prints the count per class at the first snapshot,
the strings added between the two by class, with examples, and the deepest-landing classes.
"""
import collections, ctypes, ctypes.wintypes as wt, json, re, sys, time

sys.path.insert(0, __file__.rsplit("\\", 1)[0].rsplit("/", 1)[0])
from string_tree import core_base, k32  # noqa: E402

CLASSES = [
    ("ref", re.compile(r"\[0x[0-9a-f]+\]")),
    ("timestamp", re.compile(r"^\d\d:\d\d(:\d\d)?\b")),
    ("html", re.compile(r"<[a-z/!]")),
    ("coords", re.compile(r"\(\d+,\d+,\d+\)")),
    ("number", re.compile(r"^-?[\d.e+]+$")),
    ("typepath", re.compile(r"^/[a-z_/]+$")),
    ("icon_or_file", re.compile(r"\.(dmi|ogg|wav|png|dmm|json|txt)$")),
]


def classify(s):
    for name, rx in CLASSES:
        if rx.search(s):
            return name
    return "other"


def snapshot(h, base):
    buf = (wt.DWORD * 4)()
    sbuf = ctypes.create_string_buffer(64)

    def rd(a, n=1):
        k32.ReadProcessMemory(h, ctypes.c_void_p(a), buf, 4 * n, None)
        return list(buf[:n])

    table, _ = rd(base + 0x430BF0, 2)
    stack = [(rd(table)[0], 1)]
    out = {}
    while stack:
        node, depth = stack.pop()
        if not node:
            continue
        sp, _, left, right = rd(node, 4)
        k32.ReadProcessMemory(h, ctypes.c_void_p(sp), sbuf, 63, None)
        out[sbuf.value.decode("latin-1")] = depth
        stack.append((left, depth + 1))
        stack.append((right, depth + 1))
    return out


def main():
    pid, gap, path = int(sys.argv[1]), float(sys.argv[2]), sys.argv[3]
    h = k32.OpenProcess(0x0410, False, pid)
    base = core_base(h)
    a = snapshot(h, base)
    time.sleep(gap)
    b = snapshot(h, base)
    count = collections.Counter(classify(s) for s in a)
    deep = collections.Counter(classify(s) for s, d in a.items() if d > 40)
    new = [s for s in b if s not in a]
    gone = sum(1 for s in a if s not in b)
    newc = collections.Counter(classify(s) for s in new)
    ex = collections.defaultdict(list)
    for s in new:
        c = classify(s)
        if len(ex[c]) < 6:
            ex[c].append(s)
    print(f"strings {len(a)} -> {len(b)}; new {len(new)}, gone {gone} in {gap:.0f}s")
    print(f"{'class':14s}{'count':>9s}{'deep>40':>9s}{'new':>8s}  examples of new")
    for c in sorted(set(count) | set(newc), key=lambda c: -newc[c]):
        print(f"{c:14s}{count[c]:9d}{deep[c]:9d}{newc[c]:8d}  {ex[c][:4]}")
    json.dump({"count": count, "deep": deep, "new": newc, "examples": ex, "gone": gone}, open(path, "w"), indent=1)


if __name__ == "__main__":
    main()
