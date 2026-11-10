#!/usr/bin/env python3
"""Icon check: every type that names an icon_state its .dmi doesn't have.

A type with icon = 'x.dmi' and icon_state = "y" where x.dmi has no state y draws nothing: invisible in the map editor, and in
the game unless code gives it another state before anybody looks. The compiler says nothing, and the lint doesn't read .dmi
files. This reads the types out of every file hippiestation.dme includes (the plain `/path` + tab-indented `var = value`
form, which is all but a handful of files), works out each type's icon and icon_state from its own lines and its parents',
and looks the state up in the sheet.

Usage: python tools/icon_check/icon_check.py [--update-baseline] [--all]
  Known misses are in tools/icon_check/baseline.txt (plenty are deliberate: a state only ever set by code, a parent type
  nobody places). Only what's new is listed, and only that fails (exit 1). --all lists the lot. After fixing old ones,
  --update-baseline rewrites the baseline from this run.
"""
import os
import re
import struct
import sys
import zlib

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..'))
DME = os.path.join(ROOT, 'hippiestation.dme')
BASELINE = os.path.join(ROOT, 'tools', 'icon_check', 'baseline.txt')

INCLUDE = re.compile(r'^#include "(.+\.dm)"')
TYPE_LINE = re.compile(r'^(/[A-Za-z0-9_/]+)\s*(?://.*)?$')
ICON = re.compile(r"^\ticon\s*=\s*'([^']+)'")
STATE = re.compile(r'^\ticon_state\s*=\s*"([^"\[\]]*)"\s*(?://.*)?$')
STATE_NULL = re.compile(r'^\ticon_state\s*=\s*null\b')


def dmi_states(path, cache={}):
    """The icon_state names in a .dmi, or None if it can't be read."""
    if path in cache:
        return cache[path]
    states = None
    try:
        data = open(path, 'rb').read()
        at = 8
        while at < len(data):
            length, kind = struct.unpack('>I4s', data[at:at + 8])
            body = data[at + 8:at + 8 + length]
            if kind == b'zTXt':
                keyword, rest = body.split(b'\0', 1)
                if keyword == b'Description':
                    text = zlib.decompress(rest[1:]).decode('latin1')
                    states = set(re.findall(r'^state = "(.*)"$', text, re.M))
                    break
            at += 12 + length
    except (OSError, zlib.error, struct.error, ValueError):
        states = None
    cache[path] = states
    return states


def included_files():
    for line in open(DME, encoding='latin1'):
        m = INCLUDE.match(line.strip())
        if m:
            yield m.group(1).replace('\\', '/')


def read_types():
    """type path -> {'icon': (value, file, line), 'state': (value, file, line)}, later definitions winning as in DM."""
    types = {}
    for rel in included_files():
        path = os.path.join(ROOT, rel)
        try:
            lines = open(path, encoding='latin1').read().split('\n')
        except OSError:
            continue
        current = None
        in_comment = False
        for number, raw in enumerate(lines, 1):
            line = raw.rstrip('\r')
            if in_comment:
                if '*/' in line:
                    in_comment = False
                continue
            if line.lstrip().startswith('/*') and '*/' not in line:
                in_comment = True
                continue
            if not line.strip():
                continue
            if line[0] not in '\t ':
                m = TYPE_LINE.match(line)
                # a proc or verb definition, a define, a global: not a type's body
                current = m.group(1).rstrip('/') if m and '/proc/' not in line and '/verb/' not in line else None
                continue
            if current is None:
                continue
            m = ICON.match(line)
            if m:
                types.setdefault(current, {})['icon'] = (m.group(1), rel, number)
                continue
            m = STATE.match(line)
            if m:
                types.setdefault(current, {})['state'] = (m.group(1), rel, number)
            elif STATE_NULL.match(line):
                types.setdefault(current, {})['state'] = ('', rel, number)
    return types


def inherited(types, path, key):
    while path:
        entry = types.get(path)
        if entry and key in entry:
            return entry[key]
        path = path.rsplit('/', 1)[0]
    return None


def main():
    update = '--update-baseline' in sys.argv
    show_all = '--all' in sys.argv
    types = read_types()
    misses = {}
    checked = 0
    for path, entry in types.items():
        if 'state' not in entry and 'icon' not in entry:
            continue
        if path.startswith('/datum/sprite_accessory'):
            continue  # their icon_state is half a name: the game adds the layer and the part to it
        icon = inherited(types, path, 'icon')
        state = inherited(types, path, 'state')
        if not icon or not state or not state[0]:
            continue
        states = dmi_states(os.path.join(ROOT, icon[0]))
        if states is None:
            continue  # a missing sheet is the compiler's to report
        checked += 1
        if state[0] not in states:
            where = entry.get('state') or entry.get('icon')
            key = '%s: "%s" not in %s' % (path, state[0], icon[0])
            misses[key] = '%s:%d' % (where[1], where[2])
    known = set()
    if os.path.exists(BASELINE):
        known = set(line.rstrip('\n') for line in open(BASELINE, encoding='utf-8') if line.strip())
    if update:
        with open(BASELINE, 'w', encoding='utf-8', newline='\n') as out:
            for key in sorted(misses):
                out.write(key + '\n')
        print('icon check: baseline rewritten, %d known' % len(misses))
        return 0
    new = sorted(k for k in misses if k not in known)
    gone = len([k for k in known if k not in misses])
    for key in (sorted(misses) if show_all else new):
        print('%s  (%s)' % (key, misses[key]))
    print('icon check: %d types checked, %d new missing state%s (%d known%s)' % (
        checked, len(new), '' if len(new) == 1 else 's', len(known), ', %d of them fixed since' % gone if gone else ''))
    return 1 if new else 0


if __name__ == '__main__':
    sys.exit(main())
