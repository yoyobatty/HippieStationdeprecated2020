"""DMM model for mapforge: read, edit and write classic (and TGM) .dmm files.

A tile is a list of Atom (path, vars). vars is an ordered list of (name, raw_value_string), kept raw so
round-tripping a map changes nothing we didn't touch. Coordinates are DM's: x west->east, y south->north, z.

Writing back into an existing map (merge_write) keeps every key the map already had and only adds keys for new
tile contents, so a git diff shows just the tiles we changed.
"""
import re
import string

KEY_DEF = re.compile(r'^"([a-zA-Z]+)" = \((.*?)\)\s*$', re.M | re.S)
BLOCK = re.compile(r'^\((\d+),(\d+),(\d+)\) = \{"\r?\n(.*?)\r?\n?"\}', re.M | re.S)


def split_top(text, sep=","):
    parts, depth, cur, quote = [], 0, [], False
    i = 0
    while i < len(text):
        ch = text[i]
        if quote:
            cur.append(ch)
            if ch == "\\" and i + 1 < len(text):
                cur.append(text[i + 1])
                i += 2
                continue
            if ch == '"':
                quote = False
        elif ch == '"':
            quote = True
            cur.append(ch)
        elif ch in "{(":
            depth += 1
            cur.append(ch)
        elif ch in "})":
            depth -= 1
            cur.append(ch)
        elif ch == sep and depth == 0:
            parts.append("".join(cur).strip())
            cur = []
        else:
            cur.append(ch)
        i += 1
    if "".join(cur).strip():
        parts.append("".join(cur).strip())
    return parts


def key_defs(head):
    """'"key" = (body)' entries, scanning brackets and strings (TGM puts each var on its own line, so a line can
    end in ')' that belongs to list(...) rather than the key)."""
    i, n = 0, len(head)
    while True:
        i = head.find('"', i)
        if i < 0:
            return
        j = head.find('"', i + 1)
        key = head[i + 1:j]
        k = head.find("(", j)
        if k < 0 or head[j + 1:k].strip() != "=":
            i = j + 1
            continue
        depth, quote, p = 1, False, k + 1
        while p < n and depth:
            ch = head[p]
            if quote:
                if ch == "\\":
                    p += 2
                    continue
                if ch == '"':
                    quote = False
            elif ch == '"':
                quote = True
            elif ch in "({":
                depth += 1
            elif ch in ")}":
                depth -= 1
            p += 1
        yield key, head[k + 1:p - 1]
        i = p


class Atom:
    __slots__ = ("path", "vars")

    def __init__(self, path, vars=None):
        self.path = path
        if isinstance(vars, dict):
            vars = [(k, fmt(v)) for k, v in vars.items()]
        self.vars = list(vars or [])

    @classmethod
    def parse(cls, text):
        text = text.strip()
        if "{" in text:
            path, block = text.split("{", 1)
            block = block.rsplit("}", 1)[0]
            vs = []
            for v in split_top(block, ";"):
                if "=" in v:
                    k, val = v.split("=", 1)
                    vs.append((k.strip(), val.strip()))
            return cls(path.strip(), vs)
        return cls(text)

    def get(self, name, default=None):
        for k, v in self.vars:
            if k == name:
                return v
        return default

    def num(self, name, default=0):
        v = self.get(name)
        try:
            return int(v) if v is not None else default
        except ValueError:
            return default

    def text(self):
        if not self.vars:
            return self.path
        return self.path + "{" + "; ".join("%s = %s" % kv for kv in self.vars) + "}"

    def __repr__(self):
        return self.text()

    def copy(self):
        return Atom(self.path, list(self.vars))

    def isa(self, prefix):
        return self.path == prefix or self.path.startswith(prefix + "/")


def fmt(v):
    """Python value -> DM literal."""
    if isinstance(v, bool):
        return "1" if v else "0"
    if isinstance(v, (int, float)):
        return str(v)
    if isinstance(v, str) and (v.startswith("/") or v.startswith("list(") or v.startswith('"')):
        return v
    return '"%s"' % str(v).replace('"', '\\"')


class Tile:
    """objs in DMM order (bottom first), then turf, then area."""
    __slots__ = ("objs", "turf", "area")

    def __init__(self, objs=None, turf=None, area=None):
        self.objs = objs or []
        self.turf = turf
        self.area = area

    @classmethod
    def parse(cls, body):
        atoms = [Atom.parse(a) for a in split_top(body.replace("\r", "").replace("\n", "").replace("\t", ""))]
        t = cls()
        for a in atoms:
            if a.path.startswith("/area"):
                t.area = a
            elif a.path.startswith("/turf"):
                t.turf = a
            else:
                t.objs.append(a)
        return t

    def text(self):
        parts = [a.text() for a in self.objs]
        if self.turf:
            parts.append(self.turf.text())
        if self.area:
            parts.append(self.area.text())
        return ",".join(parts)

    def copy(self):
        return Tile([a.copy() for a in self.objs], self.turf.copy() if self.turf else None,
                    self.area.copy() if self.area else None)

    def has(self, prefix):
        return any(o.isa(prefix) for o in self.objs)

    def find(self, prefix):
        return [o for o in self.objs if o.isa(prefix)]

    def remove(self, prefix):
        self.objs = [o for o in self.objs if not o.isa(prefix)]

    def add(self, path, vars=None):
        a = path if isinstance(path, Atom) else Atom(path, vars)
        self.objs.append(a)
        return a

    @property
    def tpath(self):
        return self.turf.path if self.turf else ""

    @property
    def apath(self):
        return self.area.path if self.area else ""


class Map:
    def __init__(self, maxx=0, maxy=0, maxz=1):
        self.maxx, self.maxy, self.maxz = maxx, maxy, maxz
        self.tiles = {}  # (x, y, z) -> Tile
        self.keys = {}  # original key -> body text (for merge writes)
        self.keyof = {}  # (x,y,z) -> original key
        self.keylen = 3
        self.crlf = True
        self.path = None

    def get(self, x, y, z=1):
        return self.tiles.get((x, y, z))

    def __getitem__(self, xy):
        return self.tiles[xy if len(xy) == 3 else (xy[0], xy[1], 1)]

    def set(self, x, y, tile, z=1):
        self.tiles[(x, y, z)] = tile

    def region(self, x1, y1, x2, y2, z=1):
        for y in range(y1, y2 + 1):
            for x in range(x1, x2 + 1):
                t = self.tiles.get((x, y, z))
                if t is not None:
                    yield x, y, t


def read(path):
    raw = open(path, "rb").read().decode("utf-8", errors="replace")
    m = Map()
    m.path = path
    m.crlf = "\r\n" in raw[:4000]
    text = raw.replace("\r\n", "\n")
    head = text.split("\n(1,1,1)", 1)[0]
    cache = {}
    for key, body in key_defs(head):
        m.keys[key] = body
    m.keylen = len(next(iter(m.keys)))
    for bx, by, bz, grid in BLOCK.findall(text):
        bx, by, bz = int(bx), int(by), int(bz)
        rows = grid.split("\n")
        h = len(rows)
        for ri, row in enumerate(rows):
            y = by + h - 1 - ri
            for col in range(len(row) // m.keylen):
                x = bx + col
                k = row[col * m.keylen:(col + 1) * m.keylen]
                if k not in cache:
                    cache[k] = Tile.parse(m.keys[k])
                m.tiles[(x, y, bz)] = cache[k].copy()
                m.keyof[(x, y, bz)] = k
                m.maxx, m.maxy = max(m.maxx, x), max(m.maxy, y)
        m.maxz = max(m.maxz, bz)
    return m


def _keygen(n, length):
    chars = string.ascii_letters
    out = []
    for i in range(length):
        out.append(chars[n % 52])
        n //= 52
    return "".join(reversed(out))


def write(m, path, keylen=None):
    """Fresh classic DMM (new keys). For templates and standalone builds."""
    bodies = {}
    for pos in sorted(m.tiles):
        b = m.tiles[pos].text()
        if b not in bodies:
            bodies[b] = None
    need = len(bodies)
    keylen = keylen or max(1, 1 + (need - 1).bit_length() // 5)
    while 52 ** keylen < need:
        keylen += 1
    for i, b in enumerate(bodies):
        bodies[b] = _keygen(i, keylen)
    _emit(m, path, {v: k for k, v in bodies.items()}, {pos: bodies[t.text()] for pos, t in m.tiles.items()}, keylen)


def merge_write(m, path):
    """Write m back keeping original keys for unchanged tile bodies; new bodies get new keys."""
    body_to_key = {}
    for k, b in m.keys.items():
        nb = Tile.parse(b).text()
        body_to_key.setdefault(nb, k)
    used = set(m.keys)
    n = 0
    keyof = {}
    new_keys = dict(m.keys)
    for pos, t in m.tiles.items():
        orig = m.keyof.get(pos)
        b = t.text()
        if orig and Tile.parse(m.keys[orig]).text() == b:
            keyof[pos] = orig
            continue
        k = body_to_key.get(b)
        if not k:
            while True:
                k = _keygen(n, m.keylen)
                n += 1
                if k not in used:
                    break
            used.add(k)
            body_to_key[b] = k
            new_keys[k] = b
        keyof[pos] = k
    live = set(keyof.values())
    new_keys = {k: v for k, v in new_keys.items() if k in live}
    _emit(m, path, new_keys, keyof, m.keylen, sort_keys=False)


def _emit(m, path, keys, keyof, keylen, sort_keys=True):
    nl = "\r\n" if m.crlf else "\n"
    out = []
    order = list(keys) if not sort_keys else sorted(keys)
    for k in order:
        out.append('"%s" = (%s)' % (k, keys[k]))
    out.append("")
    for z in range(1, m.maxz + 1):
        out.append('(1,1,%d) = {"' % z)
        for y in range(m.maxy, 0, -1):
            out.append("".join(keyof[(x, y, z)] for x in range(1, m.maxx + 1)))
        out.append('"}')
    with open(path, "w", encoding="utf-8", newline="") as f:
        f.write(nl.join(out) + nl)
