#!/usr/bin/env python3
"""Compare dreamchecker output with the known diagnostics in tools/lint/baseline.txt.

Reads dreamchecker's text output on stdin. A diagnostic is keyed by severity, file and message, not by line number,
so moving code around doesn't make old diagnostics look new. Prints what is new since the baseline and what has
gone; exits 1 if there is a new error or the parse stopped early, 0 otherwise (new warnings don't fail).

  dreamchecker -e hippiestation.dme | python tools/lint/lint_diff.py tools/lint/baseline.txt
  ... | python tools/lint/lint_diff.py tools/lint/baseline.txt --update   (rewrite the baseline from this run)
"""
import collections
import re
import sys

ANSI = re.compile(r"\x1b\[[0-9;]*m")
LOCATION = re.compile(r"^(?P<file>.+?), line (?P<line>\d+), column (?P<col>\d+):$")
DIAGNOSTIC = re.compile(r"^(?P<severity>error|warning|info|hint): (?P<message>.*)$")
BLOCKING = {"error"}


def parse(text):
    diagnostics = []
    location = None
    current = None
    for raw in text.splitlines():
        line = ANSI.sub("", raw).rstrip()
        m = LOCATION.match(line)
        if m:
            location = (m["file"].replace("\\", "/"), int(m["line"]))
            current = None
            continue
        m = DIAGNOSTIC.match(line)
        if m and location:
            current = {"file": location[0], "line": location[1], "severity": m["severity"], "message": m["message"], "notes": []}
            diagnostics.append(current)
            continue
        if current is not None and line.startswith("- "):
            current["notes"].append(line[2:])
    return diagnostics


def key(d):
    return f"{d['severity']}\t{d['file']}\t{d['message']}"


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    baseline_path = sys.argv[1]
    update = "--update" in sys.argv[2:]
    text = sys.stdin.read()
    if "Found " not in text:
        print("lint: dreamchecker didn't finish:")
        print("\n".join(ANSI.sub("", text).splitlines()[-15:]))
        return 1
    fatal = "fatal error" in text
    diagnostics = parse(text)

    if update:
        if fatal:
            print("lint: the parse stopped early (fatal error), not writing a baseline from it")
            return 1
        lines = sorted(key(d) for d in diagnostics)
        with open(baseline_path, "w", encoding="utf-8", newline="\n") as f:
            f.write("# Known dreamchecker diagnostics: severity<TAB>file<TAB>message, one per occurrence.\n")
            f.write("# Written by tools/lint/run_lint.sh --update-baseline. Remove a line when its diagnostic is fixed.\n")
            for line in lines:
                f.write(line + "\n")
        print(f"lint: baseline written, {len(lines)} known diagnostics")
        return 0

    known = collections.Counter()
    try:
        with open(baseline_path, encoding="utf-8") as f:
            for line in f:
                line = line.rstrip("\n")
                if line and not line.startswith("#"):
                    known[line] += 1
    except FileNotFoundError:
        print(f"lint: no baseline at {baseline_path}, everything counts as new")

    current = collections.defaultdict(list)
    for d in diagnostics:
        current[key(d)].append(d)

    new = []  # (key, how many new, occurrences)
    for k, occurrences in current.items():
        extra = len(occurrences) - known.get(k, 0)
        if extra > 0:
            new.append((k, extra, occurrences))
    gone = sum(max(0, n - len(current.get(k, []))) for k, n in known.items())

    new_errors = sum(extra for k, extra, _ in new if k.split("\t")[0] in BLOCKING)
    new_warnings = sum(extra for k, extra, _ in new if k.split("\t")[0] not in BLOCKING)
    for severity_group in (BLOCKING, None):
        for k, extra, occurrences in sorted(new, key=lambda n: n[0]):
            is_blocking = k.split("\t")[0] in BLOCKING
            if (severity_group is None) == is_blocking:
                continue
            severity, file, message = k.split("\t")
            where = ", ".join(str(o["line"]) for o in occurrences)
            count = f" ({extra} new of {len(occurrences)})" if len(occurrences) > extra else ""
            print(f"NEW {severity}: {file}:{where}: {message}{count}")
            for note in occurrences[0]["notes"][:4]:
                print(f"    - {note}")

    summary = f"lint: {new_errors} new error{'s' if new_errors != 1 else ''}, {new_warnings} new warning{'s' if new_warnings != 1 else ''}"
    summary += f" ({sum(known.values())} known)"
    if gone:
        summary += f"; {gone} known gone - run tools/lint/run_lint.sh --update-baseline"
    if fatal:
        summary += "; THE PARSE STOPPED EARLY (fatal error above), so this run is incomplete"
    print(summary)
    return 1 if new_errors or fatal else 0


if __name__ == "__main__":
    sys.exit(main())
