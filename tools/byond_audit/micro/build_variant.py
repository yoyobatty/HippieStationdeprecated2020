"""Builds a side dmb with some files swapped for their copies at a git revision, without touching the working tree.
python tools/byond_audit/micro/build_variant.py <label> <rev> <file>... [--drop "<#include line part>"]...
Writes data/stress_builds/<label>.dmb/.rsc (for run_stress_bench.sh ab). Sources go to data/stress_builds/src_<label>/.
"""
import os, subprocess, sys, shutil

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
args = sys.argv[1:]
label, rev = args[0], args[1]
files, drops = [], []
i = 2
while i < len(args):
    if args[i] == "--drop":
        drops.append(args[i + 1]); i += 2
    else:
        files.append(args[i].replace("\\", "/")); i += 1
os.chdir(ROOT)
src = os.path.join("data", "stress_builds", f"src_{label}")
os.makedirs(src, exist_ok=True)
dme = open("hippiestation.dme", encoding="utf-8", newline="").read()
for f in files:
    # "path@copy": that file's text from a local copy instead of the revision (a working tree minus one change)
    f, _, copy = f.partition("@")
    if copy:
        body = open(copy, "rb").read()
    else:
        body = subprocess.run(["git", "show", f"{rev}:{f}"], capture_output=True, check=True).stdout
    dest = os.path.join(src, f.replace("/", "_"))
    open(dest, "wb").write(body)
    inc = '#include "' + f.replace("/", "\\") + '"'
    assert dme.count(inc) == 1, (inc, dme.count(inc))
    dme = dme.replace(inc, '#include "' + dest.replace("/", "\\") + '"')
for d in drops:
    lines = dme.split("\n")
    hit = [l for l in lines if d in l]
    assert len(hit) == 1, (d, hit)
    dme = "\n".join(l for l in lines if d not in l)
mdme = f"variant_{label}.mdme"
open(mdme, "w", encoding="utf-8", newline="").write(dme)
env = dict(os.environ)
env.pop("__COMPAT_LAYER", None)
out = subprocess.run([r"C:\Program Files (x86)\BYOND\bin\dm.exe", mdme], capture_output=True, text=True, env=env).stdout
print("\n".join(l for l in out.splitlines() if "error" in l or "dmb -" in l))
ok = "0 errors" in out
if ok:
    shutil.move(mdme + ".dmb", os.path.join("data", "stress_builds", f"{label}.dmb"))
    shutil.move(mdme + ".rsc", os.path.join("data", "stress_builds", f"{label}.rsc"))
for ext in ("", ".dmb", ".rsc", ".int", ".lk", ".dyn.rsc"):
    try:
        os.remove(mdme + ext)
    except OSError:
        pass
print("saved" if ok else "FAILED", label)
sys.exit(0 if ok else 1)
