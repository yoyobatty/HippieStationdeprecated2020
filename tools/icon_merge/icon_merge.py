"""Hippie art overrides, merged at build time.

A Hippie .dmi at hippiestation/icons/<path> overrides tg's icons/<path>: each Hippie state
replaces tg's state of the same name (and movement flag), and Hippie-only states are added.
The merged sheet is written at tg's own path, because DM always resolves 'icons/...' from the
project root first (FILE_DIR entries and files beside the source lose to it), so code keeps
writing 'icons/obj/storage.dmi' and gets Hippie art. tg's untouched sheets live in
tools/icon_merge/tg/ as the merge input.

  python tools/icon_merge/icon_merge.py build [--out DIR]   merge every twin (default: into the tree)
  python tools/icon_merge/icon_merge.py check               lint: fail if a merged sheet is stale
  python tools/icon_merge/icon_merge.py adopt icons/x.dmi   a tg port replaced icons/x.dmi: keep it as the new tg original
  python tools/icon_merge/icon_merge.py preview             before/after sheets in data/previews/icon_merge/

skip.txt strikes a whole sheet ("icons/obj/storage.dmi") or one state ("icons/obj/storage.dmi:box").
extra.txt merges named Hippie states into a tg sheet that isn't their twin.
"""
import hashlib
import json
import os
import shutil
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, '..', '..'))
sys.path.insert(0, os.path.join(ROOT, 'tools', 'mapmerge2'))
import dmi  # noqa: E402

HIPPIE_DIR = 'hippiestation/icons'
TG_STORE = 'tools/icon_merge/tg'
MANIFEST = os.path.join(HERE, 'manifest.json')
SKIP_FILE = os.path.join(HERE, 'skip.txt')
EXTRA_FILE = os.path.join(HERE, 'extra.txt')


def rel(*parts):
    return os.path.join(ROOT, *parts)


def sha(path):
    with open(path, 'rb') as f:
        return hashlib.sha1(f.read()).hexdigest()


def load(path):
    sheet = dmi.Dmi.from_file(path)
    for state in sheet.states:
        state.frames = [frame.convert('RGBA') for frame in state.frames]
    return sheet


def key(state):
    return (state.name, bool(state.movement))


def label(state):
    return state.name + (' (movement)' if state.movement else '')


def read_skips():
    files, states = set(), set()
    if os.path.exists(SKIP_FILE):
        for line in open(SKIP_FILE, encoding='utf-8'):
            line = line.split('#', 1)[0].strip()
            if not line:
                continue
            if '.dmi:' in line:
                path, name = line.split('.dmi:', 1)
                states.add((path + '.dmi', name))
            else:
                files.add(line)
    return files, states


def twins():
    """tg paths (icons/...) that have a Hippie sheet at the mirrored path."""
    found = []
    for dirpath, _, filenames in os.walk(rel(HIPPIE_DIR)):
        for name in filenames:
            if not name.endswith('.dmi'):
                continue
            hippie = os.path.relpath(os.path.join(dirpath, name), ROOT).replace(os.sep, '/')
            tg = 'icons/' + hippie[len(HIPPIE_DIR) + 1:]
            if os.path.exists(rel(TG_STORE, tg)) or os.path.exists(rel(tg)):
                found.append(tg)
    return sorted(found)


def load_manifest():
    if os.path.exists(MANIFEST):
        with open(MANIFEST, encoding='utf-8') as f:
            return json.load(f)
    return {}


def tg_original(tg, manifest, store=True):
    """Path of tg's untouched sheet; stores it on first sight."""
    stored = rel(TG_STORE, tg)
    if os.path.exists(stored):
        return stored
    entry = manifest.get(tg)
    if entry and sha(rel(tg)) == entry.get('out'):
        raise SystemExit(f'{tg}: tree holds a merged sheet but {TG_STORE}/{tg} is missing')
    if not store:
        return rel(tg)
    os.makedirs(os.path.dirname(stored), exist_ok=True)
    shutil.copyfile(rel(tg), stored)
    return stored


def read_extras():
    """{tg sheet: [(hippie sheet, [states])]} from extra.txt."""
    extras = {}
    if os.path.exists(EXTRA_FILE):
        for line in open(EXTRA_FILE, encoding='utf-8'):
            line = line.split('#', 1)[0].strip()
            if not line:
                continue
            tg, rest = [x.strip() for x in line.split('<-', 1)]
            hippie, names = [x.strip() for x in rest.split(':', 1)]
            extras.setdefault(tg, []).append((hippie, names.split()))
    return extras


def plan():
    """{tg sheet: [(hippie sheet, states or None for all)]}: the twin first, then extra.txt."""
    sources = {tg: [(HIPPIE_DIR + tg[len('icons'):], None)] for tg in twins()}
    for tg, extra in read_extras().items():
        sources.setdefault(tg, []).extend(extra)
    return dict(sorted(sources.items()))


def merge(tg_path, sources, skipped_states):
    """Returns (merged Dmi or None, report dict)."""
    base = load(tg_path)
    report = {'replaced': [], 'same': [], 'added': [], 'skipped': [], 'problem': None}
    index = {}
    for i, state in enumerate(base.states):
        index.setdefault(key(state), i)
    for hippie_path, only in sources:
        over = load(rel(hippie_path))
        if (base.width, base.height) != (over.width, over.height):
            report['problem'] = f'{hippie_path} is {over.width}x{over.height}, tg {base.width}x{base.height}'
            return None, report
        for state in over.states:
            if only is not None and state.name not in only:
                continue
            if state.name in skipped_states:
                report['skipped'].append(label(state))
                continue
            state.dmi = base
            i = index.get(key(state))
            if i is None:
                index[key(state)] = len(base.states)
                base.states.append(state)
                report['added'].append(label(state))
                continue
            old = base.states[i]
            same = (old.dirs == state.dirs and len(old.frames) == len(state.frames)
                    and all(a.tobytes() == b.tobytes() for a, b in zip(old.frames, state.frames)))
            base.states[i] = state
            report['same' if same else 'replaced'].append(label(state))
    return base, report


def build(out_dir=None, quiet=False):
    manifest = load_manifest()
    skip_files, skip_states = read_skips()
    reports = {}
    new_manifest = {}
    for tg, sources in plan().items():
        if tg in skip_files:
            reports[tg] = {'problem': 'skip.txt'}
            continue
        original = tg_original(tg, manifest, store=not out_dir)
        skipped = sorted(n for p, n in skip_states if p == tg)
        sheet, report = merge(original, sources, set(skipped))
        reports[tg] = report
        if sheet is None:
            continue
        target = rel(out_dir, tg) if out_dir else rel(tg)
        os.makedirs(os.path.dirname(target), exist_ok=True)
        sheet.to_file(target)
        new_manifest[tg] = {
            'tg': sha(original), 'sources': {h: sha(rel(h)) for h, _ in sources},
            'only': {h: only for h, only in sources if only is not None},
            'skip': skipped, 'replaced': report['replaced'], 'added': report['added'],
        }
        if not out_dir:
            new_manifest[tg]['out'] = sha(target)
    if not out_dir:
        # sheets no longer overridden go back to tg's original
        for tg in manifest:
            if tg not in new_manifest and os.path.exists(rel(TG_STORE, tg)):
                shutil.copyfile(rel(TG_STORE, tg), rel(tg))
        with open(MANIFEST, 'w', encoding='utf-8', newline='\n') as f:
            json.dump(new_manifest, f, indent=1, sort_keys=True)
            f.write('\n')
    if not quiet:
        for tg, r in reports.items():
            if r.get('problem'):
                print(f'{tg}: left alone ({r["problem"]})')
        print(f'{len(new_manifest)} sheets merged: '
              f'{sum(len(r.get("replaced", [])) for r in reports.values())} states replaced, '
              f'{sum(len(r.get("added", [])) for r in reports.values())} added, '
              f'{sum(len(r.get("same", [])) for r in reports.values())} identical')
    return reports


def check():
    manifest = load_manifest()
    skip_files, skip_states = read_skips()
    errors = []
    for tg, sources in plan().items():
        entry = manifest.get(tg)
        if tg in skip_files:
            if entry:
                errors.append(f'{tg}: struck in skip.txt but still merged, run icon_merge.py build')
            continue
        if not entry:
            # size mismatches are never merged; anything else is new
            if os.path.exists(rel(TG_STORE, tg)) or not os.path.exists(rel(tg)):
                continue
            base = load(rel(tg))
            if any((lambda o: (o.width, o.height) != (base.width, base.height))(load(rel(h))) for h, _ in sources):
                continue
            errors.append(f'{tg}: new Hippie override, run icon_merge.py build')
            continue
        only = {h: o for h, o in sources if o is not None}
        if {h: sha(rel(h)) for h, _ in sources} != entry['sources'] or only != entry.get('only', {}):
            errors.append(f'{tg}: its Hippie sprites changed since the last merge, run icon_merge.py build')
        if sha(rel(TG_STORE, tg)) != entry['tg']:
            errors.append(f'{TG_STORE}/{tg}: changed since the last merge, run icon_merge.py build')
        if sha(rel(tg)) != entry.get('out'):
            errors.append(f'{tg}: not the merged sheet (a tg port? run icon_merge.py adopt {tg})')
        if entry.get('skip', []) != sorted(n for p, n in skip_states if p == tg):
            errors.append(f'skip.txt changed for {tg}, run icon_merge.py build')
    for tg in manifest:
        if tg not in plan():
            errors.append(f'{tg}: no Hippie override any more, run icon_merge.py build')
    for line in errors:
        print(line)
    print(f'icon_merge: {len(manifest)} merged sheets, {len(errors)} problems')
    return 1 if errors else 0


def adopt(paths):
    for tg in paths:
        tg = tg.replace('\\', '/')
        os.makedirs(os.path.dirname(rel(TG_STORE, tg)), exist_ok=True)
        shutil.copyfile(rel(tg), rel(TG_STORE, tg))
        print(f'{tg}: kept as the new tg original')
    build()


if __name__ == '__main__':
    args = sys.argv[1:]
    cmd = args[0] if args else 'check'
    if cmd == 'build':
        build(args[args.index('--out') + 1] if '--out' in args else None)
    elif cmd == 'check':
        sys.exit(check())
    elif cmd == 'adopt':
        adopt(args[1:])
    elif cmd == 'preview':
        import preview
        preview.main()
    else:
        print(__doc__)
        sys.exit(2)
