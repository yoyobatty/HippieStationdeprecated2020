#!/usr/bin/env python3
"""Raw proc references: `.proc/foo`, `/type/.proc/foo`, `/type.proc/foo` (and .verb/) outside the macros that wrap them.

Since BYOND 515 a raw reference is bound to that exact proc at compile time, so call()ing it on an object whose type
overrides foo() runs the parent's version and silently skips the override. PROC_REF(foo), TYPE_PROC_REF(/type, foo)
and GLOBAL_PROC_REF(foo) (code/__DEFINES/callbacks.dm) dispatch by name. Prints one NEW error per use; exit 1 if any.

  python tools/lint/raw_proc_refs.py
"""
import os
import re
import sys

ROOTS = ["code", "hippiestation", "goon"]
ALLOWED = {"code/__DEFINES/callbacks.dm"}  # the macros themselves
RAW = re.compile(r"(?:/[\w/]+?/?)?\.(?:proc|verb)/\w+")
STRING = re.compile(r'"(?:\\.|[^"\\])*"')


def main():
    os.chdir(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
    found = 0
    for root in ROOTS:
        for dirpath, _, files in os.walk(root):
            for name in files:
                if not name.endswith(".dm"):
                    continue
                path = os.path.join(dirpath, name).replace("\\", "/")
                if path in ALLOWED:
                    continue
                with open(path, encoding="latin-1") as f:
                    text = f.read()
                if ".proc/" not in text and ".verb/" not in text:
                    continue
                in_block = False
                for number, line in enumerate(text.split("\n"), 1):
                    code = ""
                    i = 0
                    while i < len(line):  # drop /* */ and // comments
                        if in_block:
                            end = line.find("*/", i)
                            if end < 0:
                                i = len(line)
                            else:
                                in_block = False
                                i = end + 2
                            continue
                        start_block = line.find("/*", i)
                        start_line = line.find("//", i)
                        if start_line >= 0 and (start_block < 0 or start_line < start_block):
                            code += line[i:start_line]
                            break
                        if start_block >= 0:
                            code += line[i:start_block]
                            in_block = True
                            i = start_block + 2
                            continue
                        code += line[i:]
                        break
                    code = STRING.sub('""', code)
                    for m in RAW.finditer(code):
                        found += 1
                        print(f"NEW error: {path}:{number}: raw proc reference {m.group(0)} runs that exact proc, skipping "
                              "overrides (BYOND 515+): use PROC_REF / TYPE_PROC_REF / GLOBAL_PROC_REF")
    return 1 if found else 0


if __name__ == "__main__":
    sys.exit(main())
