#!/usr/bin/env python3
"""Reads a round's logs, plain or zstd-compressed (.zst), for the other tools and from the command line.

Since 2026-11-10 the machine-read logs are written compressed by hippie_log.dll's thread (tools/log_writer):
  bot_trace.log.zst          the bots' step-by-step trace, "[time] Name: line" (was "ADMIN: BOT AI VERBOSE:" lines in game.log)
  bot_telemetry.jsonl.zst    bot telemetry, the same JSON lines as before
  player_telemetry.jsonl.zst the player log, the same JSON lines as before
game.log keeps the bots' decisions in plain English ("ADMIN: BOT AI: Name: line"), and every other log stays plain text.
Older rounds have the plain files; everything here reads either.

  python tools/bot_gym/logread.py <file>...                print it (several: merged in time order)
  python tools/bot_gym/logread.py <round dir>              list the round's logs, with sizes
  python tools/bot_gym/logread.py <round dir> trace game   the round's bot_trace and game.log, merged in time order
     -b NAME   only lines about that bot      -g REGEX  only lines matching it
     --from HH:MM:SS / --to HH:MM:SS (wall clock, as the logs are)      -n N  only the last N lines

Names in a round dir: trace, telemetry, player, game, attack, or any file name (".zst" optional).
Reading .zst needs the zstandard package: python -m pip install zstandard
"""
import collections
import heapq
import io
import os
import re
import sys

ALIASES = {
    "trace": "bot_trace.log",
    "telemetry": "bot_telemetry.jsonl",
    "player": "player_telemetry.jsonl",
    "game": "game.log",
    "attack": "attack.log",
}
STAMP = re.compile(r"^\[(\d{4}-\d\d-\d\d \d\d:\d\d:\d\d\.\d{3})\] ")
TRACE_LINE = re.compile(r"^(\[[^\]]+\] )(.*)$")


class _ToEnd(io.RawIOBase):
    """A zstd stream that ends where the file does: a server that was killed leaves its last frame without an end, and zstandard
    raises there. What was flushed (all but the last second or so) reads as normal."""

    def __init__(self, raw):
        self.raw = raw

    def readable(self):
        return True

    def readinto(self, buffer):
        try:
            data = self.raw.read(len(buffer))
        except Exception:  # zstandard.ZstdError: the end of a frame that was never finished
            return 0
        buffer[: len(data)] = data
        return len(data)


def find(run, name):
    """The path of a round's log, compressed or not, or None. `name` may be an alias (trace, telemetry, ...)."""
    name = ALIASES.get(name, name)
    if name.endswith(".zst"):
        name = name[:-4]
    for candidate in (name + ".zst", name):
        path = os.path.join(run, candidate)
        if os.path.isfile(path):
            return path
    return None


def open_log(path):
    """A text stream of the log at `path`; `path` + ".zst" is tried when `path` isn't there"""
    if not os.path.isfile(path) and os.path.isfile(path + ".zst"):
        path = path + ".zst"
    if not path.endswith(".zst"):
        return open(path, encoding="utf-8", errors="replace")
    try:
        import zstandard
    except ImportError:
        raise SystemExit("%s is zstd-compressed: python -m pip install zstandard" % path)
    raw = zstandard.ZstdDecompressor().stream_reader(open(path, "rb"), read_across_frames=True)
    return io.TextIOWrapper(io.BufferedReader(_ToEnd(raw), 1 << 20), encoding="utf-8", errors="replace")


def lines(path):
    """The lines of a log, plain or compressed, without their line ends; nothing when it isn't there"""
    if not path or not (os.path.isfile(path) or os.path.isfile(path + ".zst")):
        return
    with open_log(path) as f:
        for line in f:
            yield line.rstrip("\n")


def read(path):
    """A whole log as one string ("" when it isn't there)"""
    if not path or not (os.path.isfile(path) or os.path.isfile(path + ".zst")):
        return ""
    with open_log(path) as f:
        return f.read()


def _timed(path, tag):
    """(timestamp, tag, n, line) for each line; a line without a timestamp (rust_g's " - " continuation) goes with the one before"""
    stamp = ""
    for n, line in enumerate(lines(path)):
        found = STAMP.match(line)
        if found:
            stamp = found.group(1)
        yield (stamp, tag, n, line)


def merged(paths):
    """The lines of several logs in time order, as (tag, line) with tag the file's index in `paths`. Lines of the same millisecond
    come in the order of `paths` (the files don't say which came first within one)."""
    for _stamp, tag, _n, line in heapq.merge(*(_timed(p, i) for i, p in enumerate(paths))):
        yield tag, line


def bot_lines(run):
    """game.log and the bot trace in time order, every trace line as game.log had it before 2026-11-10 ("[time] ADMIN: BOT AI VERBOSE:
    Name: line"), so a reader of game.log's bot lines sees the trace where it used to be"""
    game = find(run, "game")
    trace = find(run, "trace")
    if not trace:  # an older round: the trace is in game.log
        yield from lines(game)
        return
    for tag, line in merged([game, trace]):
        if tag == 1:
            found = TRACE_LINE.match(line)
            line = "%sADMIN: BOT AI VERBOSE: %s" % found.groups() if found else line
        yield line


def _size(n):
    for unit in ("B", "KB", "MB", "GB"):
        if n < 1024 or unit == "GB":
            return "%.0f %s" % (n, unit) if unit == "B" else "%.1f %s" % (n, unit)
        n /= 1024.0


def main(argv):
    args = list(argv)
    bot = grep = since = until = None
    last = 0
    paths = []
    while args:
        a = args.pop(0)
        if a in ("-b", "--bot"):
            bot = args.pop(0)
        elif a in ("-g", "--grep"):
            grep = re.compile(args.pop(0))
        elif a == "--from":
            since = args.pop(0)
        elif a == "--to":
            until = args.pop(0)
        elif a == "-n":
            last = int(args.pop(0))
        elif a in ("-h", "--help"):
            print(__doc__)
            return 0
        else:
            paths.append(a)
    if not paths:
        print(__doc__)
        return 2
    if os.path.isdir(paths[0]):
        run, names = paths[0], paths[1:]
        if not names:
            for name in sorted(os.listdir(run)):
                full = os.path.join(run, name)
                if os.path.isfile(full):
                    print("%10s  %s" % (_size(os.path.getsize(full)), name))
            return 0
        paths = []
        for name in names:
            found = find(run, name)
            if not found:
                print("no %s in %s" % (name, run), file=sys.stderr)
                return 1
            paths.append(found)
    for p in paths:
        if not (os.path.isfile(p) or os.path.isfile(p + ".zst")):
            print("no such file: %s" % p, file=sys.stderr)
            return 1
    bot_marks = None
    if bot:
        # game.log "/(Name)" and "BOT AI: Name:", the trace "] Name:", telemetry "b":"Name"
        bot_marks = ("(%s)" % bot, ": %s:" % bot, "] %s:" % bot, '"b":"%s"' % bot)
    out = collections.deque(maxlen=last or None)
    for _tag, line in merged(paths):
        if bot_marks and not any(m in line for m in bot_marks):
            continue
        if grep and not grep.search(line):
            continue
        if since or until:
            found = STAMP.match(line)
            clock = found.group(1)[11:19] if found else ""
            if (since and clock < since) or (until and clock > until):
                continue
        if last:
            out.append(line)
        else:
            try:
                print(line)
            except BrokenPipeError:
                return 0
    for line in out:
        print(line)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except BrokenPipeError:
        sys.exit(0)
