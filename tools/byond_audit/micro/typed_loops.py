"""Typed for-in loops (no `as anything`) ranked by how often their proc runs in a profiled round.
python tools/byond_audit/micro/typed_loops.py data/byond_audit/round_counts.json [top]
A typed loop over a list tests every item's type (~52 ns an item on 516.1688, micro.dm); `as anything` doesn't.
Loops over view()/range()/turfs/contents are listed too but marked: those mix types and need the test.
"""
import json, os, re, sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
prof = json.load(open(sys.argv[1]))
top = int(sys.argv[2]) if len(sys.argv) > 2 else 60
calls = {}
for row in prof:
    calls[row["name"]] = calls.get(row["name"], 0) + row["calls"]

# included files, in dme order
dme = open(os.path.join(ROOT, "hippiestation.dme"), encoding="utf-8", errors="replace").read()
files = [m.group(1).replace("\\", "/") for m in re.finditer(r'#include "([^"]+\.dm)"', dme)]

proc_re = re.compile(r'^(/[\w/]+?)(?:/(proc|verb))?/(\w+)\(')
loop_re = re.compile(r'for\s*\(\s*var/((?:\w+/)*\w+)/(\w+)\s+in\s+(.+?)\)\s*$')
MIXED = re.compile(r'\b(view|range|orange|oview|hearers|ohearers|viewers|contents|block|world|loc|src|T|turf|get_turf|GetAllContents|get_hearers|area)\b')
rows = []
for f in files:
    p = os.path.join(ROOT, f)
    if not os.path.exists(p):
        continue
    cur = None
    for n, line in enumerate(open(p, encoding="utf-8", errors="replace"), 1):
        m = proc_re.match(line)
        if m:
            base, kind, name = m.groups()
            cur = f"{base}/{kind}/{name}" if kind else f"{base}/{name}"
            continue
        s = line.strip()
        if not s.startswith("for") or "as anything" in s or " in " not in s:
            continue
        lm = loop_re.match(s)
        if not lm or not cur:
            continue
        typ, var, expr = lm.groups()
        c = calls.get(cur, 0)
        if not c:
            c = calls.get(cur.replace("/proc/", "/"), 0)
        rows.append((c, f"{f}:{n}", cur, typ, expr.strip(), bool(MIXED.search(expr))))
rows.sort(key=lambda r: -r[0])
for c, where, proc, typ, expr, mixed in rows[:top]:
    print(f"{c:8d} {'MIXED ' if mixed else '      '}{where}  {proc}  ({typ} in {expr})")
