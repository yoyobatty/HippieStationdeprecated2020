"""Side by side: compare.py <a> <b> <rounds>. Each figure is the median of that build's boots."""
import re
import statistics
import sys

a, b, rounds = sys.argv[1], sys.argv[2], int(sys.argv[3])
line = re.compile(r"^(.+?): ([\d.]+) (us|ms) \(best")


def read(name):
    seen = {}
    for i in range(1, rounds + 1):
        try:
            text = open(f"data/speed_bench_{name}_{i}.txt").read()
        except OSError:
            continue
        for row in text.splitlines():
            m = line.match(row)
            if m:
                key = re.sub(r" \(.*", "", m.group(1))
                seen.setdefault(key, []).append(float(m.group(2)))
    return seen


first, second = read(a), read(b)
print(f"{'':44}{a:>10}{b:>10}{'change':>9}   (microseconds, median of {rounds} boots)")
for key, values in first.items():
    was = statistics.median(values)
    now = statistics.median(second.get(key, [0]))
    change = f"{(now - was) / was * 100:+.0f}%" if was else "?"
    print(f"{key:44}{was:>10.1f}{now:>10.1f}{change:>9}")
