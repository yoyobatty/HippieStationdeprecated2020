#!/usr/bin/env python3
"""Find the procs registered as signal handlers and check each is marked SIGNAL_HANDLER.

SIGNAL_HANDLER sets SpacemanDMM_should_not_sleep, so dreamchecker reports a handler that can sleep: a sleeping handler
puts whatever sent the signal to sleep with it (an area's power update, an attack, a move), every other handler of
that signal waiting behind it. A base proc that must keep SHOULD_CALL_PARENT(TRUE) can use SHOULD_NOT_SLEEP(TRUE).

  python tools/lint/signal_handlers.py            list registered handlers missing SIGNAL_HANDLER (exit 0)
  python tools/lint/signal_handlers.py --apply    add SIGNAL_HANDLER to them
  python tools/lint/signal_handlers.py --verbose  also list registrations it couldn't resolve to a proc

Each RegisterSignal(target, signal, handler) is resolved against the type of the proc it's in (TYPE_PROC_REF and
GLOBAL_PROC_REF name their own), to the nearest proc/ declaration up the type path. Overrides inherit the marking in
dreamchecker, so only the declaration is marked. Handlers held in variables can't be followed and are skipped.
"""
import os
import re
import sys

ROOTS = ["code", "hippiestation", "goon"]
MARK = "SIGNAL_HANDLER"

DEF_ABS = re.compile(r"^(/[\w/]*?)(?:/(proc|verb))?/(\w+)\((.*)$")
TYPE_LINE = re.compile(r"^(/[\w/]+)\s*(//.*)?$")
DEF_REL = re.compile(r"^\t(?:(proc|verb)/)?(\w+)\((.*)$")
HANDLER = re.compile(
    r"^\s*(?:"
    r"\"(?P<str>\w+)\""
    r"|\.proc/(?P<dot>\w+)"
    r"|PROC_REF\(\s*(?P<pref>\w+)\s*\)"
    r"|TYPE_PROC_REF\(\s*(?P<ttype>/[\w/]+)\s*,\s*(?P<tname>\w+)\s*\)"
    r"|GLOBAL_PROC_REF\(\s*(?P<gname>\w+)\s*\)"
    r"|(?P<tpath>/[\w/]+?)/proc/(?P<tpname>\w+)"
    r")\s*$")
NOT_PROC_NAMES = {"if", "for", "while", "switch", "spawn", "return", "else", "do", "var", "set", "new", "del"}


def dm_files():
    for root in ROOTS:
        for dirpath, _, files in os.walk(root):
            for f in files:
                if f.endswith(".dm"):
                    yield os.path.join(dirpath, f).replace("\\", "/")


def read_lines(path):
    with open(path, encoding="utf-8", errors="replace", newline="") as f:
        return f.read().splitlines(keepends=True)


def index_definitions(files):
    """(type, name) -> list of (file, line index, is_declaration); type '' is a global proc."""
    defs = {}
    for path, lines in files.items():
        block_type = None
        for i, raw in enumerate(lines):
            line = raw.rstrip("\r\n")
            m = DEF_ABS.match(line)
            if m and m.group(3) not in NOT_PROC_NAMES:
                t, kind, name = m.group(1), m.group(2), m.group(3)
                if t == "/" or t == "":
                    t = ""
                if t == "" and kind is None:
                    block_type = None
                    continue  # "/name(" alone is a global proc only with /proc/
                defs.setdefault((t, name), []).append((path, i, kind is not None))
                block_type = None
                continue
            m = TYPE_LINE.match(line)
            if m:
                block_type = m.group(1)
                continue
            if line and not line[0].isspace():
                block_type = None
                continue
            if block_type:
                m = DEF_REL.match(line)
                if m and m.group(2) not in NOT_PROC_NAMES and "=" not in line.split("(")[0]:
                    defs.setdefault((block_type, m.group(2)), []).append((path, i, m.group(1) is not None))
    return defs


def enclosing_type(lines, i):
    for j in range(i, -1, -1):
        m = DEF_ABS.match(lines[j].rstrip("\r\n"))
        if m:
            return m.group(1) if m.group(1) not in ("/", "") else None
        if lines[j][:1] == "/" or (lines[j][:1].isalpha()):
            return None
    return None


def split_args(text):
    """Top-level comma split of an argument list (text after the opening paren, up to its close)."""
    args, depth, cur, quote = [], 0, "", None
    for ch in text:
        if quote:
            cur += ch
            if ch == quote:
                quote = None
            continue
        if ch in "\"'":
            quote = ch
            cur += ch
            continue
        if ch in "([{":
            depth += 1
        elif ch in ")]}":
            if depth == 0:
                args.append(cur)
                return args
            depth -= 1
        if ch == "," and depth == 0:
            args.append(cur)
            cur = ""
            continue
        cur += ch
    return None


def registrations(files):
    """Yield (path, line, owner type or None for global, handler name, raw handler text)."""
    for path, lines in files.items():
        for i, raw in enumerate(lines):
            col = raw.find("RegisterSignal(")
            if col < 0 or raw.lstrip().startswith("//") or "proc/RegisterSignal" in raw or "UnregisterSignal(" in raw[:col + 15]:
                continue
            # something.RegisterSignal(...) registers another datum: followed only when the handler names its type
            remote = raw[col - 1:col] == "."
            if not remote and raw[col - 1:col] not in ("", "\t", " ", "(", "!", ","):
                continue
            text = "".join(lines[i:i + 12])
            start = text.find("RegisterSignal(") + len("RegisterSignal(")
            args = split_args(text[start:].replace("\r", "").replace("\\\n", " "))
            if not args or len(args) < 3:
                yield path, i + 1, None, None, "(unparsed)"
                continue
            handler = args[2].strip()
            m = HANDLER.match(handler)
            if not m:
                yield path, i + 1, None, None, handler
                continue
            if m.group("gname"):
                yield path, i + 1, "", m.group("gname"), handler
            elif m.group("ttype"):
                yield path, i + 1, m.group("ttype"), m.group("tname"), handler
            elif m.group("tpath"):
                yield path, i + 1, m.group("tpath"), m.group("tpname"), handler
            elif remote:
                continue  # another datum's proc named relative to it: can't tell its type from here
            else:
                name = m.group("str") or m.group("dot") or m.group("pref")
                yield path, i + 1, enclosing_type(lines, i), name, handler


def resolve(defs, owner, name):
    """The declaration of name nearest owner up its type path, or a global proc."""
    if owner == "":
        hits = defs.get(("", name), [])
        return [h for h in hits if h[2]][:1] or hits[:1]
    t = owner
    while t:
        hits = defs.get((t, name), [])
        decl = [h for h in hits if h[2]]
        if decl:
            return decl[:1]
        t = t.rsplit("/", 1)[0]
    # an override only: builtin procs like Moved()/Bumped() have no declaration in the code
    t = owner
    while t:
        hits = defs.get((t, name), [])
        if hits:
            return hits[:1]
        t = t.rsplit("/", 1)[0]
    return []


def header_end(lines, i):
    depth = 0
    for j in range(i, min(i + 10, len(lines))):
        for ch in lines[j]:
            if ch == "(":
                depth += 1
            elif ch == ")":
                depth -= 1
        if depth <= 0:
            return j
    return i


def is_marked(lines, i):
    """SIGNAL_HANDLER, or SHOULD_NOT_SLEEP(TRUE), among the set lines at the top of the body."""
    j = header_end(lines, i) + 1
    for line in lines[j:j + 6]:
        s = line.split("//")[0].strip()
        if s in (MARK, "SHOULD_NOT_SLEEP(TRUE)"):
            return True
        if s and not s.startswith("//") and not s.startswith("SHOULD_") and not s.startswith("set ") and s != "RETURN_TYPE":
            return False
    return False


def main():
    apply = "--apply" in sys.argv
    verbose = "--verbose" in sys.argv
    os.chdir(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
    files = {p: read_lines(p) for p in dm_files()}
    defs = index_definitions(files)

    targets = {}  # (path, line) -> (owner, name, where registered)
    unresolved = []
    for path, line, owner, name, raw in registrations(files):
        if name is None or owner is None:
            unresolved.append(f"{path}:{line}: {raw}")
            continue
        found = resolve(defs, owner, name)
        if not found:
            unresolved.append(f"{path}:{line}: {raw} (no proc {name} on {owner or 'global'})")
            continue
        dpath, di, _ = found[0]
        targets.setdefault((dpath, di), (owner, name, f"{path}:{line}"))

    missing = sorted(k for k in targets if not is_marked(files[k[0]], k[1]))
    if apply:
        by_file = {}
        for path, i in missing:
            by_file.setdefault(path, []).append(i)
        for path, idxs in by_file.items():
            lines = files[path]
            newline = "\r\n" if lines and lines[0].endswith("\r\n") else "\n"
            for i in sorted(idxs, reverse=True):
                end = header_end(lines, i)
                # the body's own indent (some files indent with spaces), else one tab in from the header
                indent = re.match(r"^(\s*)", lines[i]).group(1) + "\t"
                for body in lines[end + 1:end + 6]:
                    if body.strip() and not body.strip().startswith("//"):
                        body_indent = re.match(r"^(\s*)", body).group(1)
                        if len(body_indent) > len(re.match(r"^(\s*)", lines[i]).group(1)):
                            indent = body_indent
                        break
                lines.insert(end + 1, f"{indent}{MARK}{newline}")
            with open(path, "w", encoding="utf-8", newline="") as f:
                f.writelines(lines)
        print(f"signal handlers: marked {len(missing)} in {len(by_file)} files ({len(targets)} handlers found)")
    else:
        for path, i in missing:
            owner, name, where = targets[(path, i)]
            print(f"UNMARKED handler: {path}:{i + 1}: {name} (registered at {where})")
        print(f"signal handlers: {len(targets)} found, {len(missing)} without {MARK}, {len(unresolved)} registrations not followed")
    if verbose:
        for u in unresolved:
            print(f"not followed: {u}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
