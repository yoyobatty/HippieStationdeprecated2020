#!/usr/bin/env python3
"""Runtime ledger: every runtime in the logs that are kept, as one table by where it happens.

Each round writes its own runtime.log, and a runtime that shows up once a round in forty rounds is never looked at twice.
This reads them all (data/logs/<year>/<month>/<day>/round-*/ and the test runs under data/logs/shift_batch, bot_gym and
the rest), and counts by source file and line: how many times, in how many rounds, when first and last seen, and the
message, with the changing parts (names in quotes, numbers) taken out so one bug is one row.

Usage: python tools/runtime_ledger/ledger.py [options] [log folder...]        (default: data/logs)
  --since 2026-11-08    only rounds from that day on (by the time in the log)
  --new 2026-11-10      only what was first seen on or after that day: what a change brought in
  --top 40              how many rows (default 40; 0 for all)
  --ours                only runtimes in hippiestation/ code
  --csv out.csv         write every row to a file as well
Slimmed "Skipped N runtimes" lines aren't counted: the game stops logging one line's runtimes after a few a minute.
"""
import csv
import os
import re
import sys

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..'))
STAMP = re.compile(r'^\[(\d{4}-\d{2}-\d{2}) [\d:.]+\] runtime error: (.*)$')
SOURCE = re.compile(r'^ - +source file: (.+?),(\d+)')
PROC = re.compile(r'^ - proc name: (.+)$')


def tidy(message):
    """One bug, one row: quoted names, references and numbers come out."""
    message = re.sub(r'"[^"]*"', '"..."', message)
    message = re.sub(r"'[^']*'", "'...'", message)
    message = re.sub(r'\[0x[0-9a-f]+\]', '[ref]', message)
    message = re.sub(r'\b\d+(\.\d+)?\b', 'N', message)
    return message[:110]


def runtime_logs(folders):
    for folder in folders:
        for where, _, files in os.walk(folder):
            if 'runtime.log' in files:
                yield os.path.join(where, 'runtime.log')


def read(path, rows, since):
    try:
        lines = open(path, encoding='latin1').read().split('\n')
    except OSError:
        return 0
    seen = 0
    at = 0
    while at < len(lines):
        m = STAMP.match(lines[at])
        at += 1
        if not m:
            continue
        day, message = m.group(1), m.group(2)
        proc = source = None
        for ahead in lines[at:at + 4]:
            p = PROC.match(ahead)
            s = SOURCE.match(ahead)
            if p:
                proc = p.group(1)
            if s:
                # a build made somewhere else gives the whole path: from code/ or hippiestation/ on, so one line is one row
                where = re.sub(r'^.*?/(?=(hippiestation/code|code|tools)/)', '', s.group(1).replace('\\', '/'))
                source = '%s:%s' % (where, s.group(2))
        if since and day < since:
            continue
        if not source:
            # the bots' own net logs what it catches as "BOT AI EXCEPTION (...): message at file:line"
            caught = re.search(r' at ([\w/.~-]+\.dm):(\d+)$', message)
            source = '%s:%s' % (caught.group(1), caught.group(2)) if caught else '(no source)'
        key = (source, tidy(message))
        row = rows.setdefault(key, {'count': 0, 'rounds': set(), 'first': day, 'last': day, 'proc': proc or ''})
        row['count'] += 1
        row['rounds'].add(os.path.dirname(path))
        row['first'] = min(row['first'], day)
        row['last'] = max(row['last'], day)
        seen += 1
    return seen


def main():
    args = sys.argv[1:]
    options = {'--since': None, '--new': None, '--top': '40', '--csv': None}
    ours = False
    folders = []
    while args:
        arg = args.pop(0)
        if arg in options:
            options[arg] = args.pop(0)
        elif arg == '--ours':
            ours = True
        elif arg in ('-h', '--help'):
            print(__doc__)
            return 0
        else:
            folders.append(arg)
    folders = folders or [os.path.join(ROOT, 'data', 'logs')]
    rows = {}
    logs = 0
    for path in runtime_logs(folders):
        if read(path, rows, options['--since']):
            logs += 1
    listed = []
    for (source, message), row in rows.items():
        if ours and not source.startswith('hippiestation/'):
            continue
        if options['--new'] and row['first'] < options['--new']:
            continue
        listed.append((row['count'], len(row['rounds']), row['first'], row['last'], source, message, row['proc']))
    listed.sort(key=lambda r: (-r[1], -r[0]))
    if options['--csv']:
        with open(options['--csv'], 'w', newline='', encoding='utf-8') as out:
            writer = csv.writer(out)
            writer.writerow(['times', 'rounds', 'first seen', 'last seen', 'source', 'message', 'proc'])
            writer.writerows(listed)
    top = int(options['--top'])
    print('%6s %6s  %-10s %-10s  %s' % ('times', 'rounds', 'first', 'last', 'where and what'))
    for row in (listed[:top] if top else listed):
        print('%6d %6d  %-10s %-10s  %s  %s' % row[:6])
    print('runtime ledger: %d different runtimes in %d logs with any%s' % (len(listed), logs, ', %d shown' % top if top and len(listed) > top else ''))
    return 0


if __name__ == '__main__':
    sys.exit(main())
