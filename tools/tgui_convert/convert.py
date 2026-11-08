"""Turn BYOND input()/alert() calls into the tgui prompts (hippiestation/code/modules/tgui/tgui_prompt.dm).

    python tools/tgui_convert/convert.py [--write] [--report out.tsv] paths...

Without --write it only reports. Each call is either converted or left with a reason (the "manual" list):
file uploads, colour pickers, a list expression the parser can't be sure where it ends, a first argument that might be
the user or the message, etc. Files keep their own line endings and bytes; only the call text changes.

Native argument order: input(Usr = usr, Message, Title, Default) and alert(Usr = usr, Message, Title, Button1 = "Ok",
Button2, Button3). Whether the first argument is the user is decided by BYOND at run time (mob or client); here: a
string literal first means no user; a name that reads as a message (msg, message, text...) means no user; any other
first argument with at least two arguments is the user.
"""
import os
import re
import sys

EXCLUDE = (
    'hippiestation/code/modules/integrated_electronics/core/',  # session -28 is moving these to tgui (2026-11-07)
    'hippiestation/code/modules/tgui/',
    'tools/',
)

IDENT = re.compile(r'[A-Za-z_][A-Za-z0-9_]*')
MESSAGEY = re.compile(r'(msg|message|text|txt|desc|question|prompt|warning|info|body|str|string|title)', re.I)
TYPE_PATHS = {'mob': '/mob', 'obj': '/obj', 'turf': '/turf', 'area': '/area', 'atom': '/atom'}


def skip_string(s, i):
    """s[i] is the opening quote of "...", or { of {"..."}. Returns the index after the string. Handles [expr] inside."""
    if s.startswith('{"', i):
        end = '"}'
        i += 2
    else:
        end = '"'
        i += 1
    while i < len(s):
        c = s[i]
        if c == '\\':
            i += 2
            continue
        if s.startswith(end, i):
            return i + len(end)
        if c == '[':
            i = skip_brackets(s, i, '[', ']')
            continue
        i += 1
    return i


def skip_rsc(s, i):
    i += 1
    while i < len(s) and s[i] != "'":
        if s[i] == '\\':
            i += 1
        i += 1
    return i + 1


def skip_comment(s, i):
    if s.startswith('//', i):
        j = s.find('\n', i)
        return len(s) if j < 0 else j
    if s.startswith('/*', i):
        j = s.find('*/', i + 2)
        return len(s) if j < 0 else j + 2
    return i


def skip_brackets(s, i, op, cl):
    """s[i] == op. Returns the index after the matching cl, skipping strings and comments."""
    depth = 0
    while i < len(s):
        c = s[i]
        if c == '"' or s.startswith('{"', i):
            i = skip_string(s, i)
            continue
        if c == "'":
            i = skip_rsc(s, i)
            continue
        if s.startswith('//', i) or s.startswith('/*', i):
            i = skip_comment(s, i)
            continue
        if c in '([':
            depth += 1
        elif c in ')]':
            depth -= 1
            if depth == 0:
                return i + 1
        i += 1
    return i


def split_args(s, start, stop):
    """Top-level comma split of s[start:stop]."""
    args = []
    i = start
    cur = start
    while i < stop:
        c = s[i]
        if c == '"' or s.startswith('{"', i):
            i = skip_string(s, i)
            continue
        if c == "'":
            i = skip_rsc(s, i)
            continue
        if c in '([':
            i = skip_brackets(s, i, c, ')' if c == '(' else ']')
            continue
        if c == ',':
            args.append(s[cur:i].strip())
            cur = i + 1
        i += 1
    last = s[cur:stop].strip()
    if last or args:
        args.append(last)
    return args


def find_calls(s, name):
    """Yields the start of each `name(` that is real code (not a string, comment, proc definition or member call)."""
    i = 0
    n = len(s)
    while i < n:
        c = s[i]
        if c == '"' or s.startswith('{"', i):
            i = skip_string(s, i)
            continue
        if c == "'":
            i = skip_rsc(s, i)
            continue
        if s.startswith('//', i) or s.startswith('/*', i):
            i = skip_comment(s, i)
            continue
        if s.startswith(name, i):
            prev = s[i - 1] if i else ' '
            after = i + len(name)
            j = after
            while j < n and s[j] in ' \t':
                j += 1
            if not (prev.isalnum() or prev in '_./:') and j < n and s[j] == '(' and (after == n or not (s[after].isalnum() or s[after] == '_')):
                yield i, j
                i = j
                continue
        i += 1


def parse_chain(s, i):
    """A postfix expression from i: a name, /type/path, list(...), (...), then .x :x ?.x [..] (..). Returns the end or None."""
    n = len(s)
    if i < n and s[i] == '(':
        i = skip_brackets(s, i, '(', ')')
    elif i < n and s[i] == '/':
        m = re.compile(r'(/[A-Za-z0-9_]+)+').match(s, i)
        if not m:
            return None
        i = m.end()
    elif i < n and (s[i] == '"' or s.startswith('{"', i)):
        return skip_string(s, i)
    else:
        m = IDENT.match(s, i)
        if not m:
            return None
        i = m.end()
        if m.group(0) == 'list':  # `list (...)`
            j = i
            while j < n and s[j] in ' \t':
                j += 1
            if j < n and s[j] == '(':
                i = j
    while i < n:
        if s[i] == '(':
            i = skip_brackets(s, i, '(', ')')
        elif s[i] == '[':
            i = skip_brackets(s, i, '[', ']')
        elif s[i] in '.:' and i + 1 < n and (s[i + 1].isalpha() or s[i + 1] == '_'):
            i = IDENT.match(s, i + 1).end()
        elif s.startswith('?.', i):
            m = IDENT.match(s, i + 2)
            if not m:
                break
            i = m.end()
        else:
            break
    return i


def is_literal_string(a):
    return a.startswith('"') or a.startswith('{"')


def split_user(args):
    """(user, rest) per the module's rule, or (None, None) when unsure."""
    if not args:
        return 'usr', []
    first = args[0]
    if is_literal_string(first):
        return 'usr', args
    if len(args) == 1:
        return 'usr', args
    if first in ('usr', 'src', 'user', 'M', 'C', 'H', 'L', 'U', 'owner', 'target', 'mob', 'client', 'holder', 'O', 'A', 'B', 'S', 'P', 'R', 'G', 'X', 'Y', 'K', 'T', 'D', 'N', 'W', 'Z', 'V', 'I', 'E', 'F', 'J', 'Q'):
        return first, args[1:]
    if MESSAGEY.search(first.split('.')[-1]) and not re.search(r'(user|mob|owner|client)', first, re.I):
        return 'usr', args
    if IDENT.fullmatch(first) or re.fullmatch(r'[A-Za-z_][A-Za-z0-9_]*(\.|\?\.|:)[A-Za-z_][A-Za-z0-9_.?:]*', first):
        return first, args[1:]
    return None, None


def fmt_call(proc, positional, named):
    # trailing nulls dropped; named args after
    while positional and positional[-1] in ('null', ''):
        positional.pop()
    positional = [p if p != '' else 'null' for p in positional]
    parts = positional + ['%s = %s' % kv for kv in named]
    return '%s(%s)' % (proc, ', '.join(parts))


def convert_input(s, start, paren):
    close = skip_brackets(s, paren, '(', ')')
    args = split_args(s, paren + 1, close - 1)
    user, rest = split_user(args)
    if user is None:
        return None, 'first argument could be the user or the message: %s' % args[0][:40]
    while len(rest) < 3:
        rest.append('null')
    if len(rest) == 4 and rest[3] == 'null':
        rest = rest[:3]  # input("msg", "title", default, null): the null is a no-op
    if len(rest) > 3:
        return None, 'more than 4 arguments'
    message, title, default = rest[0], rest[1], rest[2]
    m = re.compile(r'[ \t]*as[ \t]+((?:[a-z]+[ \t]*\|[ \t]*)*[a-z]+)').match(s, close)
    types = []
    end = close
    if m:
        types = [t.strip() for t in m.group(1).split('|')]
        end = m.end()
    m_in = re.compile(r'[ \t]+in[ \t]+').match(s, end)
    list_expr = None
    if m_in:
        ls = m_in.end()
        m_null = re.compile(r'null[ \t]*\|[ \t]*').match(s, ls)  # in null|L
        if m_null:
            types.append('null')
            ls = m_null.end()
        le = parse_chain(s, ls)
        if le is None:
            return None, 'list expression not understood'
        # L + "x" + M - y: a sum of lists, which the code means as the list
        operands_end = le
        sum_re = re.compile(r'[ \t]*[+-][ \t]*')
        while True:
            m_op = sum_re.match(s, operands_end)
            if not m_op:
                break
            nxt = parse_chain(s, m_op.end())
            if nxt is None:
                break
            operands_end = nxt
        list_expr = s[ls:operands_end]
        if operands_end != le:
            list_expr = '(%s)' % list_expr
        end = operands_end
        m_tail = re.compile(r'[ \t]*\|[ \t]*null\b').match(s, end)  # in L|null
        if m_tail:
            types.append('null')
            end = m_tail.end()
        after = s[end:end + 40].lstrip(' \t')
        ok_after = (not after or after[0] in '\r\n),];' or after.startswith('//')
                    or (after[0] in ':?' and after[1:2] in (' ', '\t')))
        if not ok_after:
            return None, 'list expression continues: %s' % after[:20].strip()
    nullable = 'null' in types
    kinds = [t for t in types if t != 'null']
    named = []
    if list_expr is not None:
        if not kinds or kinds == ['anything']:
            items = list_expr
        elif len(kinds) == 1 and kinds[0] in TYPE_PATHS:
            items = 'tgui_list_of_type(%s, %s)' % (list_expr, TYPE_PATHS[kinds[0]])
        else:
            return None, 'list of %s' % '|'.join(kinds)
        if not nullable:
            named.append(('allow_cancel', 'FALSE'))
        return (start, end, fmt_call('tgui_input_list', [user, message, title, items, default], named)), None
    if not kinds:
        kinds = ['text']
    if len(kinds) != 1:
        return None, 'as %s' % '|'.join(kinds)
    kind = kinds[0]
    if not nullable:
        named.append(('allow_cancel', 'FALSE'))
    if kind == 'text':
        return (start, end, fmt_call('tgui_input_text', [user, message, title, default], named)), None
    if kind == 'message':
        named.insert(0, ('multiline', 'TRUE'))
        return (start, end, fmt_call('tgui_input_text', [user, message, title, default], named)), None
    if kind == 'num':
        return (start, end, fmt_call('tgui_input_number', [user, message, title, default], named)), None
    return None, 'as %s (native picker)' % kind


def convert_alert(s, start, paren):
    close = skip_brackets(s, paren, '(', ')')
    args = split_args(s, paren + 1, close - 1)
    user, rest = split_user(args)
    if user is None:
        return None, 'first argument could be the user or the message: %s' % args[0][:40]
    if not rest:
        return None, 'no message'
    message = rest[0]
    title = rest[1] if len(rest) > 1 else 'null'
    buttons = [b for b in rest[2:] if b not in ('', 'null')]
    if len(buttons) > 3:
        return None, 'too many buttons'
    positional = [user, message, title]
    if buttons:
        positional.append('list(%s)' % ', '.join(buttons))
    return (start, close, fmt_call('tgui_alert', positional, [])), None


def line_of(s, i):
    return s.count('\n', 0, i) + 1


def process(path, write, report):
    raw = open(path, 'rb').read()
    s = raw.decode('latin-1')
    edits = []
    for name, fn in (('input', convert_input), ('alert', convert_alert)):
        for start, paren in find_calls(s, name):
            edit, why = fn(s, start, paren)
            if edit:
                edits.append(edit)
                report.append((path, line_of(s, start), name, 'converted', s[start:edit[1]].replace('\n', ' ')[:140], edit[2][:140]))
            else:
                report.append((path, line_of(s, start), name, 'manual', why, s[start:start + 140].split('\n')[0]))
    if write and edits:
        edits.sort()
        out = []
        last = 0
        for a, b, text in edits:
            if a < last:
                continue  # a call inside another call's arguments: the outer one already holds it as text
            out.append(s[last:a])
            out.append(text)
            last = b
        out.append(s[last:])
        new = ''.join(out)
        if new != s:
            open(path, 'wb').write(new.encode('latin-1'))
    return len(edits)


def main():
    args = sys.argv[1:]
    write = '--write' in args
    out = None
    if '--report' in args:
        out = args[args.index('--report') + 1]
    paths = [a for a in args if not a.startswith('--') and a != out]
    files = []
    for p in paths:
        if os.path.isdir(p):
            for root, _, names in os.walk(p):
                for f in names:
                    if f.endswith('.dm'):
                        files.append(os.path.join(root, f).replace('\\', '/'))
        else:
            files.append(p.replace('\\', '/'))
    files = [f for f in sorted(files) if not any(f.startswith(e) or ('/' + e) in f for e in EXCLUDE)]
    report = []
    total = 0
    for f in files:
        total += process(f, write, report)
    conv = sum(1 for r in report if r[3] == 'converted')
    man = [r for r in report if r[3] == 'manual']
    if out:
        with open(out, 'w', encoding='utf-8') as fh:
            for r in report:
                fh.write('\t'.join(re.sub(r'\s+', ' ', str(x)) for x in r) + '\n')
    print('%d calls: %d converted, %d manual, in %d files' % (len(report), conv, len(man), len(set(r[0] for r in report))))
    reasons = {}
    for r in man:
        key = re.sub(r':.*', '', r[4])
        reasons[key] = reasons.get(key, 0) + 1
    for k, v in sorted(reasons.items(), key=lambda kv: -kv[1]):
        print('  %4d  %s' % (v, k))


if __name__ == '__main__':
    main()
