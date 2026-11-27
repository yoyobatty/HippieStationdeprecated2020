"""Scratch: print study.json side by side, one fact per line (maps as columns).

    python table.py [fact prefix ...]
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
S = json.load(open(os.path.join(HERE, "study.json")))
names = list(S)
short = {n: n[:6] for n in names}
pre = sys.argv[1:]
keys = sorted({k for v in S.values() for k in v})
for k in keys:
    if pre and not any(k.startswith(p) for p in pre):
        continue
    print("== %s" % k)
    for n in names:
        v = S[n].get(k)
        if isinstance(v, dict):
            v = ", ".join("%s:%s" % (a, b) for a, b in sorted(v.items(), key=lambda kv: str(kv[0])))
        print("   %-8s %s" % (short[n], v))
