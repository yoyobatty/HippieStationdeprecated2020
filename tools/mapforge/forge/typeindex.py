"""Index of every type path declared in the codebase (code/ + hippiestation/ + _maps/*.dm), cached.

    python tools/mapforge/forge/typeindex.py [regex]     # list matching types

Types made by macros (pipes' /hidden/layer1 etc.) aren't declared literally; known() also accepts any path
already used in a .dmm under _maps, so valid macro types still pass.
"""
import glob
import os
import re
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
CACHE = os.path.join(ROOT, "data", "mapforge", "types.txt")
DECL = re.compile(r"^(/(?:area|turf|obj|mob|datum/[a-z_]+)?[A-Za-z0-9_/]*)\s*(?:$|//|\{|\s)")


def build():
    found = set()
    files = glob.glob(os.path.join(ROOT, "code", "**", "*.dm"), recursive=True)
    files += glob.glob(os.path.join(ROOT, "hippiestation", "code", "**", "*.dm"), recursive=True)
    files += glob.glob(os.path.join(ROOT, "_maps", "*.dm"))
    for f in files:
        for line in open(f, encoding="utf-8", errors="replace"):
            if not line.startswith("/"):
                continue
            m = DECL.match(line)
            if not m:
                continue
            p = m.group(1).rstrip("/")
            if "/proc" in p or "/verb" in p or not p.startswith(("/obj", "/turf", "/area", "/mob")):
                continue
            found.add(p)
            parts = p.split("/")
            for i in range(2, len(parts)):
                found.add("/".join(parts[:i]))
    for f in glob.glob(os.path.join(ROOT, "_maps", "**", "*.dmm"), recursive=True):
        for m in re.finditer(r"(/(?:obj|turf|area|mob)/[A-Za-z0-9_/]+)", open(f, encoding="utf-8", errors="replace").read()):
            found.add(m.group(1))
    os.makedirs(os.path.dirname(CACHE), exist_ok=True)
    with open(CACHE, "w") as fh:
        fh.write("\n".join(sorted(found)))
    return found


_TYPES = None


def types():
    global _TYPES
    if _TYPES is None:
        if os.path.exists(CACHE):
            _TYPES = set(open(CACHE).read().split("\n"))
        else:
            _TYPES = build()
    return _TYPES


def known(path):
    return path in types()


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "--rebuild":
        build()
        sys.exit()
    rx = re.compile(sys.argv[1] if len(sys.argv) > 1 else ".")
    for t in sorted(types()):
        if rx.search(t):
            print(t)
