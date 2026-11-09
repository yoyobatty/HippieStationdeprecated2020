"""Before/after review data for icon_merge: which changed states are already Hippie in game, and which are new.

Needs data/icon_merge/types.txt from a side build with type_dump.dm (preview.sh does that).
Writes data/previews/icon_merge/icon_review.html (review_template.html with the frames embedded);
strikes made on the published page are read back into skip.txt.
"""
import base64
import io
import json
import os
from collections import defaultdict

import icon_merge as m
from PIL import Image

OUT = m.rel('data', 'previews', 'icon_merge')
STAGE = m.rel('data', 'icon_merge', 'stage')

# worn sheet -> type prefixes whose worn sprite comes from it (None = any item)
WORN = {
    'icons/mob/head.dmi': ('/obj/item/clothing/head',),
    'icons/mob/suit.dmi': ('/obj/item/clothing/suit',),
    'icons/mob/uniform.dmi': ('/obj/item/clothing/under',),
    'icons/mob/mask.dmi': ('/obj/item/clothing/mask',),
    'icons/mob/feet.dmi': ('/obj/item/clothing/shoes',),
    'icons/mob/hands.dmi': ('/obj/item/clothing/gloves',),
    'icons/mob/eyes.dmi': ('/obj/item/clothing/glasses',),
    'icons/mob/ears.dmi': ('/obj/item/clothing/ears', '/obj/item/radio/headset'),
    'icons/mob/neck.dmi': ('/obj/item/clothing/neck',),
    'icons/mob/back.dmi': None,
    'icons/mob/belt.dmi': None,
}


def read_types():
    rows = []
    for line in open(m.rel('data', 'icon_merge', 'types.txt'), encoding='utf-8', errors='replace'):
        f = line.rstrip('\n').split('\t')
        f += [''] * (8 - len(f))
        rows.append(dict(zip(('type', 'icon', 'state', 'hippie', 'item_state', 'worn', 'left', 'right'), f)))
    return rows


def png(frame, scale):
    im = frame.resize((frame.width * scale, frame.height * scale), Image.NEAREST)
    buf = io.BytesIO()
    im.save(buf, 'png', optimize=True)
    return base64.b64encode(buf.getvalue()).decode()


def south(state):
    return state.frames[0]


def main():
    reports = m.build(out_dir=os.path.relpath(STAGE, m.ROOT), quiet=True)
    types = read_types()
    hippie_states = {}

    def states_of(path):
        if path not in hippie_states:
            hippie_states[path] = {s.name for s in m.load(m.rel(path)).states} if os.path.exists(m.rel(path)) else set()
        return hippie_states[path]

    sheets = []
    for tg, r in sorted(reports.items()):
        if r.get('problem') or not r['replaced']:
            continue
        twin = m.HIPPIE_DIR + tg[len('icons'):]
        old = {m.label(s): s for s in m.load(m.tg_original(tg, {}, store=False)).states}
        new = {m.label(s): s for s in m.load(os.path.join(STAGE, tg)).states}
        users = defaultdict(lambda: {'already': [], 'new': []})
        for t in types:
            # object sprite
            if t['icon'] == tg and t['state']:
                if t['hippie'] == twin:
                    users[t['state']]['already'].append(t['type'])
                elif not (t['hippie'] and t['state'] in states_of(t['hippie'])):
                    users[t['state']]['new'].append(t['type'])
            elif t['icon'] == twin and t['state']:
                users[t['state']]['already'].append(t['type'])
            # worn and inhand sprites
            worn_state = t['item_state'] or t['state']
            if not t['type'].startswith('/obj/item') or not worn_state:
                continue
            if tg in WORN and (WORN[tg] is None or t['type'].startswith(WORN[tg])):
                if t['worn'] == twin:
                    users[worn_state]['already'].append(t['type'])
                elif not t['worn']:
                    users[worn_state]['new'].append(t['type'])
            for hand in ('left', 'right'):
                if t[hand] == tg:
                    users[t['item_state']]['new'].append(t['type'])
                elif t[hand] == twin:
                    users[t['item_state']]['already'].append(t['type'])
        scale = 2 if max(old[r['replaced'][0]].dmi.width, old[r['replaced'][0]].dmi.height) <= 32 else 1
        wired = sorted({t['type'] for t in types if twin in (t['hippie'], t['icon'], t['worn'], t['left'], t['right'])})
        entries = []
        for name in r['replaced']:
            plain = name.replace(' (movement)', '')
            u = users.get(plain, {'already': [], 'new': []})
            if u['new']:
                group = 'new'
            elif u['already'] or wired:
                group = 'already'
            else:
                group = 'new'
            entries.append({
                'state': name, 'group': group, 'starts': bool(u['new'] or u['already']),
                'new_types': sorted(set(u['new'])), 'already_types': sorted(set(u['already'])),
                'tg': png(south(old[name]), scale), 'hippie': png(south(new[name]), scale),
            })
        sheets.append({'sheet': tg, 'wired': len(wired), 'wired_example': wired[:3], 'states': entries})
    os.makedirs(OUT, exist_ok=True)
    data = json.dumps(sheets, separators=(',', ':')).replace('</', '<\\/')
    template = open(os.path.join(m.HERE, 'review_template.html'), encoding='utf-8').read()
    with open(os.path.join(OUT, 'icon_review.html'), 'w', encoding='utf-8', newline='\n') as f:
        f.write(template.replace('/*REVIEW_DATA*/[]', data))
    counts = defaultdict(int)
    for s in sheets:
        for e in s['states']:
            counts[e['group']] += 1
    print(f'{len(sheets)} sheets, ' + ', '.join(f'{k} {v}' for k, v in sorted(counts.items())))


if __name__ == '__main__':
    main()
