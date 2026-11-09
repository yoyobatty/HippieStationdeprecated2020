"""Small, fast reader/writer for classic (non-TGM) single-z DMM files.

Grid coordinates are DM's: x 1..maxx west to east, y 1..maxy south to north.
"""
import re

_KEY_LINE = re.compile(r'^"([A-Za-z]+)" = \((.*)\)\s*$')


def split_atoms(body):
    """Split '/a{x = 1; y = "a,b"},/b' into atoms, respecting braces and quotes."""
    atoms, cur, depth, quote = [], [], 0, False
    i = 0
    while i < len(body):
        c = body[i]
        if quote:
            cur.append(c)
            if c == "\\" and i + 1 < len(body):
                cur.append(body[i + 1])
                i += 2
                continue
            if c == '"':
                quote = False
        elif c == '"':
            quote = True
            cur.append(c)
        elif c in "{(":
            depth += 1
            cur.append(c)
        elif c in "})":
            depth -= 1
            cur.append(c)
        elif c == "," and depth == 0:
            atoms.append("".join(cur))
            cur = []
        else:
            cur.append(c)
        i += 1
    if cur:
        atoms.append("".join(cur))
    return atoms


class Map:
    def __init__(self, maxx, maxy):
        self.maxx, self.maxy = maxx, maxy
        self.tiles = {}  # (x, y) -> list of atom strings

    def get(self, x, y):
        return self.tiles.get((x, y))


def read(path):
    keys = {}
    rows = []
    with open(path, encoding="utf-8") as f:
        text = f.read()
    grid_start = text.index("(1,1,1)")
    for line in text[:grid_start].splitlines():
        m = _KEY_LINE.match(line)
        if m:
            keys[m.group(1)] = split_atoms(m.group(2))
    body = text[grid_start:]
    body = body[body.index('{"') + 2: body.rindex('"}')]
    rows = [r for r in body.split("\n") if r.strip()]
    klen = len(next(iter(keys)))
    maxy = len(rows)
    maxx = len(rows[0]) // klen
    mp = Map(maxx, maxy)
    for ri, row in enumerate(rows):
        y = maxy - ri
        for xi in range(maxx):
            mp.tiles[(xi + 1, y)] = keys[row[xi * klen:(xi + 1) * klen]]
    return mp


_B52 = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"


def _key(n, length):
    s = ""
    for _ in range(length):
        s = _B52[n % 52] + s
        n //= 52
    return s


def write(mp, path):
    """Write classic DMM with CRLF-free newlines."""
    content = {}
    for y in range(1, mp.maxy + 1):
        for x in range(1, mp.maxx + 1):
            t = tuple(mp.tiles[(x, y)])
            if t not in content:
                content[t] = len(content)
    klen = 1
    while 52 ** klen < len(content):
        klen += 1
    names = {t: _key(i, klen) for t, i in content.items()}
    out = []
    for t, k in sorted(names.items(), key=lambda kv: kv[1]):
        out.append('"%s" = (%s)' % (k, ",".join(t)))
    out.append("")
    out.append('(1,1,1) = {"')
    for y in range(mp.maxy, 0, -1):
        out.append("".join(names[tuple(mp.tiles[(x, y)])] for x in range(1, mp.maxx + 1)))
    out.append('"}')
    out.append("")
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(out))
    return len(content), klen


def attrs(atom):
    """'/path{a = 1; b = "x"}' -> (path, {a: '1', b: '"x"'})."""
    if "{" not in atom:
        return atom, {}
    path, rest = atom.split("{", 1)
    rest = rest.rsplit("}", 1)[0]
    out = {}
    for part in split_semis(rest):
        if "=" in part:
            k, v = part.split("=", 1)
            out[k.strip()] = v.strip()
    return path, out


def split_semis(s):
    parts, cur, quote, depth = [], [], False, 0
    for c in s:
        if quote:
            cur.append(c)
            if c == '"':
                quote = False
        elif c == '"':
            quote = True
            cur.append(c)
        elif c in "({":
            depth += 1
            cur.append(c)
        elif c in ")}":
            depth -= 1
            cur.append(c)
        elif c == ";" and depth == 0:
            parts.append("".join(cur))
            cur = []
        else:
            cur.append(c)
    if cur:
        parts.append("".join(cur))
    return parts


DIRS = {"NORTH": 1, "SOUTH": 2, "EAST": 4, "WEST": 8}


def port_coords(x, y, d, width, height, dwidth, dheight):
    """DM's /obj/docking_port/proc/return_coords."""
    cos, sin = 1, 0
    if d == 8:
        cos, sin = 0, 1
    elif d == 2:
        cos, sin = -1, 0
    elif d == 4:
        cos, sin = 0, -1
    return (x + (-dwidth * cos) - (-dheight * sin),
            y + (-dwidth * sin) + (-dheight * cos),
            x + (-dwidth + width - 1) * cos - (-dheight + height - 1) * sin,
            y + (-dwidth + width - 1) * sin + (-dheight + height - 1) * cos)
