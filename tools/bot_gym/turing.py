#!/usr/bin/env python3
"""Turing judge for the bot crew: how well a bot's body can be told apart from a real player's, and what gives it away.

The player log (bots_ai/player_log.dm) records one real player (PLAYER_LOG_CKEY) in bot_telemetry's sample format, in the same
rounds as the bots. This tool cuts both into windows of the same length, works out the same features from the fields both
loggers write the same way, and trains a judge (logistic regression) that is always tested on rounds it never trained on. Its
held-out AUC says how human the bots look: 0.5 means it can't tell them apart, 1.0 means it always can. Per-feature AUCs and
group ablation say what gives them away, and the windows the judge is surest about are listed with the death_story.py line to
go and look at them. `score` then puts any run or batch (Bot Shifts too, no player needed) through a saved judge, so a change
can be screened by how human its bots look.

    python tools/bot_gym/turing.py rounds                                    # rounds that can train a judge
    python tools/bot_gym/turing.py train [--win 30] [--out data/bot_turing/w30] [--mlp] [--top 12]
    python tools/bot_gym/turing.py score data/bot_turing/w30 <run or batch dir>... [--by goal|state|job|bot] [--top 10]
    python tools/bot_gym/turing.py slice data/bot_turing/w30 --where "move_frac > 0.6" [--calm]   # the tells inside a slice

`train` writes report.txt (the summary it prints), model.json (what `score` reads) and windows.jsonl (every held-out window's
score and features) to --out. Parsed rounds are cached in data/bot_turing/cache, so a second train takes seconds.

Parity: both loggers must mean the same thing, or the judge learns the logger instead of the player (the SmartBots sim's
"+40" was one code path gated differently in sim and game).
  - Samples only, never events: the player's pickup/click/step events and the bots' come from different hooks.
  - Fields used: x y z d hp inc int ah ih. Not "near", "run", "stat", "zone" (player only) or "g", "st", "act", "pl" (bots only;
    those are kept for grouping scores, never used as features).
  - Live rounds sample bots every 10 ds and the player every 5 ds, test rounds sample bots every 5 ds: everything goes on a
    10 ds grid (the first sample in each tick) and movement is worked out again from positions (Chebyshev, 0 across a z change).
  - Samples at hp <= 0 are left out (the player sampler stops at a ghost, the bot sampler at a corpse; both keep crit).
  - Who is near someone comes from every other body in the round's two files on the same grid tick, for both.
  - `train` prints the sample spacing it found per file kind, so a new logger change that breaks this shows up.

Limits: the only human is the player named by PLAYER_LOG_CKEY, mostly playing antagonists and Captains, so "human" means "like
this player in those rounds". The report splits windows into calm ones and fighting ones (harm intent, hurt, or stunned), so a
fighting style isn't taken for a tell. A judge's score is a meter for screening, not proof that a change works: prove a fix
with its own before/after (ab_gym.sh, batch_digest.py). The SmartBots lab learned this the hard way: a value model fitted on
recordings predicted a goal a match from its picks and the bench showed none, because good outcomes came from good situations.
"""
import argparse
import collections
import glob
import json
import math
import os
import pickle
import random
import re
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import logread  # noqa: E402

VERSION = 2  # 2: windows keep wall_end
GRID = 10  # deciseconds between the samples everything is put on
WALL = re.compile(r'^\[(?:\d+-\d+-\d+ )?(\d+:\d+:\d+)')
CACHE = os.path.join('data', 'bot_turing', 'cache')
NEAR_CAP = 10

# One sample on the grid: position, facing, health, stunned, intent, hands, wall clock, and (bots only) goal and state.
X, Y, Z, D, HP, INC, INT, AH, IH, WALLT, GOAL, STATE = range(12)

GROUPS = collections.OrderedDict([
    ('move', ['move_frac', 'speed_moving', 'speed_cv', 'fast_frac', 'stops_per_min', 'stop_len_mean', 'stop_len_max',
              'move_len_mean']),
    ('path', ['straightness', 'unique_tiles', 'revisit_frac', 'backtrack_frac', 'heading_change']),
    ('facing', ['turns_per_min', 'turn_still_frac', 'face_move_frac']),
    ('hands', ['active_full', 'inactive_full', 'both_full', 'item_changes_per_min', 'swaps_per_min', 'distinct_items']),
    ('intent', ['harm_frac', 'disarm_frac', 'intent_switches_per_min']),
    ('body', ['inc_frac', 'hp_mean', 'hp_min', 'hurt_per_min']),
    ('social', ['near7_mean', 'near2_mean', 'adjacent_frac', 'nearest_mean', 'kept_close_frac']),
])
FEATURES = [f for fs in GROUPS.values() for f in fs]
# What the judge reads. "body" (stunned, health) only says who was in a fight, and the first full train scored better without it
# (0.864 against 0.853 held out), so it stays in the tells table and the calm/fight split but out of the judge.
JUDGED = [f for g, fs in GROUPS.items() if g != 'body' for f in fs]


# ----------------------------------------------------------------------------------------------------------------------------
# Reading rounds
# ----------------------------------------------------------------------------------------------------------------------------

def find_rounds(root='data/logs'):
    """Round folders with both a player log and bot telemetry."""
    found = []
    for p in glob.glob(os.path.join(root, '**', 'player_telemetry.jsonl*'), recursive=True):
        run = os.path.dirname(p)
        if logread.find(run, 'telemetry') and run not in found:
            found.append(run)
    return sorted(found)


def round_id(run):
    parts = run.replace('\\', '/').rstrip('/').split('/')
    return '_'.join(parts[-4:]) if len(parts) >= 4 else parts[-1]


def read_file(path, spacing):
    """Body name -> {grid tick: sample}, plus body name -> job. Fills spacing (raw sample gaps in ds) for the parity check."""
    by = collections.defaultdict(dict)
    jobs = {}
    last_t = {}
    for line in logread.lines(path):
        i = line.find('{')
        if i < 0:
            continue
        if '"k":"s"' not in line:
            if '"ev":"spawn"' in line or '"ev":"role"' in line:
                try:
                    r = json.loads(line[i:])
                except ValueError:
                    continue
                if r.get('job') and r.get('b'):
                    jobs[r['b']] = r['job']
            continue
        try:
            r = json.loads(line[i:])
        except ValueError:
            continue
        b = r.get('b')
        if not b or b == '?' or r.get('x') is None or r.get('hp') is None or r.get('t') is None:
            continue
        t = r['t']
        if b in last_t and len(spacing) < 200000:
            spacing[round(t - last_t[b], 2)] += 1
        last_t[b] = t
        k = int(t // GRID)
        if k in by[b]:
            continue
        m = WALL.match(line)
        by[b][k] = (r['x'], r['y'], r['z'], r.get('d') or 0, r['hp'], r.get('inc') or 0, r.get('int') or 'help',
                    r.get('ah'), r.get('ih'), m.group(1) if m else '', r.get('g') or '', r.get('st') or '')
    return by, jobs


def social(entities):
    """(cls, name) -> {tick: (near7, near2, nearest)} from every body sampled on that tick (crit ones too)."""
    at = collections.defaultdict(list)
    for key, ticks in entities.items():
        for k, s in ticks.items():
            at[k].append((key, s[X], s[Y], s[Z]))
    out = collections.defaultdict(dict)
    for k, rows in at.items():
        if len(rows) == 1:
            out[rows[0][0]][k] = (0, 0, NEAR_CAP)
            continue
        names = [r[0][1] for r in rows]
        xs = np.array([r[1] for r in rows])
        ys = np.array([r[2] for r in rows])
        zs = np.array([r[3] for r in rows])
        dist = np.maximum(np.abs(xs[:, None] - xs[None, :]), np.abs(ys[:, None] - ys[None, :])).astype(float)
        dist[zs[:, None] != zs[None, :]] = np.inf
        same = np.array([[a == b for b in names] for a in names])
        dist[same] = np.inf  # itself, and the same body in both files (a bot driving the player's body while they're away)
        near7 = (dist <= 7).sum(1)
        near2 = (dist <= 2).sum(1)
        nearest = np.minimum(dist.min(1), NEAR_CAP)
        for j, r in enumerate(rows):
            out[r[0]][k] = (int(near7[j]), int(near2[j]), float(nearest[j]))
    return out


def norm(run):
    return run.replace('\\', '/').rstrip('/')


def load_round(run, win):
    """Windows of a round: list of (label 1 human / 0 bot, feature dict, meta dict). Cached per round, version and length."""
    run = norm(run)
    os.makedirs(CACHE, exist_ok=True)
    cache = os.path.join(CACHE, '%s_v%d_w%d.pkl' % (round_id(run), VERSION, win))
    if os.path.exists(cache):
        with open(cache, 'rb') as f:
            result = pickle.load(f)
        for w in result['windows']:
            w[2]['run'] = run
        return result
    entities = {}
    jobs = {}
    spacing = {}
    for cls, kind in (('H', 'player'), ('B', 'telemetry')):
        path = logread.find(run, kind)
        if not path:
            continue
        sp = collections.Counter()
        by, j = read_file(path, sp)
        spacing[kind] = sp
        for name, ticks in by.items():
            entities[(cls, name)] = ticks
            jobs[(cls, name)] = j.get(name, '')
    near = social(entities)
    windows = []
    for key, ticks in entities.items():
        for seq, ks in segments(ticks):
            for a in range(0, len(seq) - win + 1, max(1, win // 2)):
                part = seq[a:a + win]
                soc = [near[key].get(k, (0, 0, NEAR_CAP)) for k in ks[a:a + win]]
                f, ctx = features(part, soc)
                meta = {'run': run, 'name': key[1], 'job': jobs.get(key, ''), 'tick': ks[a], 'wall': part[0][WALLT],
                        'wall_end': part[-1][WALLT],
                        'goal': majority(s[GOAL] for s in part), 'state': majority(s[STATE] for s in part), 'ctx': ctx}
                windows.append((1 if key[0] == 'H' else 0, f, meta))
    result = {'windows': windows, 'spacing': {k: dict(v.most_common(4)) for k, v in spacing.items()}}
    with open(cache, 'wb') as f:
        pickle.dump(result, f)
    return result


def segments(ticks):
    """Runs of consecutive grid ticks with hp > 0: (samples, ticks)."""
    seq, ks = [], []
    prev = None
    for k in sorted(ticks):
        s = ticks[k]
        if s[HP] <= 0 or (prev is not None and k != prev + 1):
            if len(seq) > 1:
                yield seq, ks
            seq, ks = [], []
            if s[HP] <= 0:
                prev = None
                continue
        seq.append(s)
        ks.append(k)
        prev = k
    if len(seq) > 1:
        yield seq, ks


def majority(values):
    c = collections.Counter(v for v in values if v)
    return c.most_common(1)[0][0] if c else ''


# ----------------------------------------------------------------------------------------------------------------------------
# Features of one window
# ----------------------------------------------------------------------------------------------------------------------------

def dir_bits(dx, dy):
    return (1 if dy > 0 else 0) | (2 if dy < 0 else 0) | (4 if dx > 0 else 0) | (8 if dx < 0 else 0)


def streaks(flags, value):
    out, n = [], 0
    for f in flags:
        if f == value:
            n += 1
        elif n:
            out.append(n)
            n = 0
    if n:
        out.append(n)
    return out


def features(seq, soc):
    """Feature dict and context ("calm" or "fight") of one window of grid samples, all on one body."""
    n = len(seq)
    mins = n / 60.0
    steps = []  # (dx, dy, tiles) between grid samples
    for a, b in zip(seq, seq[1:]):
        if a[Z] == b[Z]:
            dx, dy = b[X] - a[X], b[Y] - a[Y]
            steps.append((dx, dy, max(abs(dx), abs(dy))))
        else:
            steps.append((0, 0, 0))
    moving = [s[2] > 0 for s in steps]
    tiles = [s[2] for s in steps if s[2] > 0]
    f = {}
    f['move_frac'] = sum(moving) / len(steps)
    f['speed_moving'] = float(np.mean(tiles)) if tiles else np.nan
    f['speed_cv'] = float(np.std(tiles) / np.mean(tiles)) if len(tiles) > 2 else np.nan
    f['fast_frac'] = sum(1 for t in tiles if t >= 4) / len(steps)
    f['stops_per_min'] = sum(1 for a, b in zip(moving, moving[1:]) if a and not b) / mins
    still = streaks(moving, False)
    went = streaks(moving, True)
    f['stop_len_mean'] = float(np.mean(still)) if still else 0.0
    f['stop_len_max'] = float(max(still)) if still else 0.0
    f['move_len_mean'] = float(np.mean(went)) if went else 0.0

    total = sum(tiles)
    same_z = all(s[Z] == seq[0][Z] for s in seq)
    net = max(abs(seq[-1][X] - seq[0][X]), abs(seq[-1][Y] - seq[0][Y])) if same_z else np.nan
    f['straightness'] = net / total if total >= 3 and same_z else np.nan
    spots = [(s[X], s[Y], s[Z]) for s in seq]
    f['unique_tiles'] = len(set(spots)) / n
    seen, revisits = set(), 0
    for i, p in enumerate(spots):
        if i >= 1 and p != spots[i - 1] and p in seen:
            revisits += 1
        if i >= 1:
            seen.add(spots[i - 1])
    f['revisit_frac'] = revisits / n
    vecs = [(s[0], s[1]) for s in steps if s[2] > 0]
    pairs = list(zip(vecs, vecs[1:]))
    f['backtrack_frac'] = sum(1 for u, v in pairs if u[0] * v[0] + u[1] * v[1] < 0) / len(pairs) if pairs else np.nan
    if pairs:
        angles = []
        for u, v in pairs:
            nu, nv = math.hypot(*u), math.hypot(*v)
            c = max(-1.0, min(1.0, (u[0] * v[0] + u[1] * v[1]) / (nu * nv)))
            angles.append(math.acos(c))
        f['heading_change'] = float(np.mean(angles))
    else:
        f['heading_change'] = np.nan

    turns = [a[D] != b[D] for a, b in zip(seq, seq[1:])]
    f['turns_per_min'] = sum(turns) / mins
    still_turns = [t for t, m in zip(turns, moving) if not m]
    f['turn_still_frac'] = sum(still_turns) / len(still_turns) if still_turns else np.nan
    faced = [bool(b[D] & dir_bits(s[0], s[1])) for (b, s) in zip(seq[1:], steps) if s[2] > 0]
    f['face_move_frac'] = sum(faced) / len(faced) if faced else np.nan

    f['active_full'] = sum(1 for s in seq if s[AH]) / n
    f['inactive_full'] = sum(1 for s in seq if s[IH]) / n
    f['both_full'] = sum(1 for s in seq if s[AH] and s[IH]) / n
    changes = swaps = 0
    for a, b in zip(seq, seq[1:]):
        if (a[AH], a[IH]) == (b[AH], b[IH]):
            continue
        if a[AH] == b[IH] and a[IH] == b[AH]:
            swaps += 1
        else:
            changes += 1
    f['item_changes_per_min'] = changes / mins
    f['swaps_per_min'] = swaps / mins
    f['distinct_items'] = len({s[AH] for s in seq if s[AH]} | {s[IH] for s in seq if s[IH]})

    f['harm_frac'] = sum(1 for s in seq if s[INT] == 'harm') / n
    f['disarm_frac'] = sum(1 for s in seq if s[INT] in ('disarm', 'grab')) / n
    f['intent_switches_per_min'] = sum(1 for a, b in zip(seq, seq[1:]) if a[INT] != b[INT]) / mins

    hps = [s[HP] for s in seq]
    hurt = sum(1 for a, b in zip(hps, hps[1:]) if b < a - 0.5)
    f['inc_frac'] = sum(1 for s in seq if s[INC]) / n
    f['hp_mean'] = float(np.mean(hps))
    f['hp_min'] = float(min(hps))
    f['hurt_per_min'] = hurt / mins

    f['near7_mean'] = float(np.mean([s[0] for s in soc]))
    f['near2_mean'] = float(np.mean([s[1] for s in soc]))
    f['adjacent_frac'] = sum(1 for s in soc if s[2] <= 1) / n
    f['nearest_mean'] = float(np.mean([s[2] for s in soc]))
    kept = [soc[i][2] <= 2 and soc[i - 1][2] <= 2 for i in range(1, n) if moving[i - 1]]
    f['kept_close_frac'] = sum(kept) / len(kept) if kept else np.nan

    fight = f['harm_frac'] > 0 or hurt > 0 or f['inc_frac'] > 0
    return f, ('fight' if fight else 'calm')


# ----------------------------------------------------------------------------------------------------------------------------
# Statistics and the judge
# ----------------------------------------------------------------------------------------------------------------------------

def auc(scores, labels):
    """Area under the ROC curve for label 1 scoring higher, ties counted half. nan without both classes."""
    scores = np.asarray(scores, float)
    labels = np.asarray(labels)
    pos, neg = labels.sum(), len(labels) - labels.sum()
    if pos == 0 or neg == 0:
        return float('nan')
    order = np.argsort(scores, kind='mergesort')
    ranks = np.empty(len(scores))
    s = scores[order]
    i = 0
    while i < len(s):
        j = i
        while j + 1 < len(s) and s[j + 1] == s[i]:
            j += 1
        ranks[order[i:j + 1]] = (i + j) / 2.0 + 1
        i = j + 1
    return float((ranks[labels == 1].sum() - pos * (pos + 1) / 2.0) / (pos * neg))


def matrix(windows, cols):
    return np.array([[w[1][c] for c in cols] for w in windows], float)


class Judge:
    """Logistic regression on standardized features, missing values filled with the training mean, classes weighted equally."""

    def __init__(self, cols, lam=1.0):
        self.cols = cols
        self.lam = lam

    def fit(self, Xm, y):
        self.fill = np.nanmean(Xm, 0)
        self.fill = np.where(np.isnan(self.fill), 0.0, self.fill)
        Xf = np.where(np.isnan(Xm), self.fill, Xm)
        self.mu = Xf.mean(0)
        self.sd = Xf.std(0)
        self.sd[self.sd == 0] = 1.0
        Z = np.hstack([(Xf - self.mu) / self.sd, np.ones((len(Xf), 1))])
        w = np.where(y == 1, 0.5 / max(1, y.sum()), 0.5 / max(1, (1 - y).sum())) * len(y)
        beta = np.zeros(Z.shape[1])
        reg = np.full(Z.shape[1], self.lam)
        reg[-1] = 0.0
        for _ in range(60):
            p = 1 / (1 + np.exp(-np.clip(Z @ beta, -30, 30)))
            g = Z.T @ (w * (p - y)) + reg * beta
            H = (Z * (w * p * (1 - p))[:, None]).T @ Z + np.diag(reg)
            step = np.linalg.solve(H, g)
            beta -= step
            if np.abs(step).max() < 1e-6:
                break
        self.coef = beta[:-1]
        self.bias = beta[-1]
        return self

    def z(self, Xm):
        Xf = np.where(np.isnan(Xm), self.fill, Xm)
        return (Xf - self.mu) / self.sd

    def prob(self, Xm):
        return 1 / (1 + np.exp(-np.clip(self.z(Xm) @ self.coef + self.bias, -30, 30)))

    def reasons(self, xrow, k=3):
        """The k features pulling one window hardest toward "bot", as (name, contribution)."""
        contrib = self.z(xrow[None, :])[0] * self.coef
        order = np.argsort(contrib)[:k]
        return [(self.cols[i], float(contrib[i])) for i in order if contrib[i] < 0]

    def save(self, path, extra):
        out = {'version': VERSION, 'cols': self.cols, 'fill': self.fill.tolist(), 'mu': self.mu.tolist(),
               'sd': self.sd.tolist(), 'coef': self.coef.tolist(), 'bias': float(self.bias), 'lam': self.lam}
        out.update(extra)
        with open(path, 'w') as f:
            json.dump(out, f, indent=1)

    @classmethod
    def load(cls, path):
        with open(path) as f:
            m = json.load(f)
        j = cls(m['cols'], m['lam'])
        for k in ('fill', 'mu', 'sd', 'coef'):
            setattr(j, k, np.array(m[k]))
        j.bias = m['bias']
        j.meta = m
        return j


def balanced_train(windows, rng, ratio=4):
    """Per round, at most `ratio` bot windows for each human window (and at least 50), so no round's crowd outweighs the player."""
    by = collections.defaultdict(lambda: ([], []))
    for w in windows:
        by[w[2]['run']][w[0]].append(w)
    out = []
    for run, (bots, humans) in by.items():
        keep = max(50, ratio * len(humans))
        if len(bots) > keep:
            bots = rng.sample(bots, keep)
        out += bots + humans
    return out


def folds_of(runs, k, seed=7):
    runs = sorted(runs)
    random.Random(seed).shuffle(runs)
    return [runs[i::k] for i in range(k)]


def cross_validate(windows, cols, folds, seed=7, mlp=False):
    """Held-out P(human) for every window, each from a judge that never saw its round."""
    rng = random.Random(seed)
    prob = np.full(len(windows), np.nan)
    index = collections.defaultdict(list)
    for i, w in enumerate(windows):
        index[w[2]['run']].append(i)
    for held in folds:
        held_set = set(held)
        train = balanced_train([w for w in windows if w[2]['run'] not in held_set], rng)
        Xt = matrix(train, cols)
        yt = np.array([w[0] for w in train])
        test_idx = [i for r in held for i in index[r]]
        Xh = matrix([windows[i] for i in test_idx], cols)
        if mlp:
            prob[test_idx] = mlp_fit_predict(Xt, yt, Xh, seed)
        else:
            prob[test_idx] = Judge(cols).fit(Xt, yt).prob(Xh)
    return prob


def mlp_fit_predict(Xt, yt, Xh, seed):
    """A small two-layer network on the same features (torch, CPU): how much a judge that sees combinations could still find."""
    import torch
    torch.manual_seed(seed)
    torch.set_num_threads(2)
    fill = np.nan_to_num(np.nanmean(Xt, 0))
    Xt = np.where(np.isnan(Xt), fill, Xt)
    Xh = np.where(np.isnan(Xh), fill, Xh)
    mu, sd = Xt.mean(0), Xt.std(0)
    sd[sd == 0] = 1
    a = torch.tensor((Xt - mu) / sd, dtype=torch.float32)
    b = torch.tensor(yt, dtype=torch.float32)
    w = torch.where(b == 1, 0.5 / b.sum(), 0.5 / (1 - b).sum()) * len(b)
    net = torch.nn.Sequential(torch.nn.Linear(a.shape[1], 32), torch.nn.ReLU(), torch.nn.Dropout(0.2), torch.nn.Linear(32, 1))
    opt = torch.optim.Adam(net.parameters(), lr=3e-3, weight_decay=1e-3)
    for _ in range(300):
        opt.zero_grad()
        loss = (torch.nn.functional.binary_cross_entropy_with_logits(net(a).squeeze(1), b, reduction='none') * w).mean()
        loss.backward()
        opt.step()
    net.eval()
    with torch.no_grad():
        return torch.sigmoid(net(torch.tensor((Xh - mu) / sd, dtype=torch.float32)).squeeze(1)).numpy()


# ----------------------------------------------------------------------------------------------------------------------------
# Commands
# ----------------------------------------------------------------------------------------------------------------------------

def gather(runs, win, min_human=10, say=print):
    windows, used, spacing = [], [], collections.defaultdict(collections.Counter)
    for run in dict.fromkeys(norm(r) for r in runs):
        r = load_round(run, win)
        for kind, sp in r['spacing'].items():
            spacing[kind].update(sp)
        humans = sum(1 for w in r['windows'] if w[0] == 1)
        bots = sum(1 for w in r['windows'] if w[0] == 0)
        if humans < min_human or bots < min_human:
            say('  skip %s: %d player windows, %d bot windows' % (round_id(run), humans, bots))
            continue
        used.append(run)
        windows += r['windows']
    return windows, used, spacing


def cmd_rounds(args):
    for run in find_rounds(args.logs):
        p = logread.find(run, 'player')
        b = logread.find(run, 'telemetry')
        print('%7d KB player  %7d KB bots  %s' % (os.path.getsize(p) // 1024, os.path.getsize(b) // 1024, run))


def fmt(v):
    return '   -' if v is None or (isinstance(v, float) and math.isnan(v)) else ('%6.2f' % v)


def cmd_train(args):
    out_lines = []

    def say(s=''):
        print(s)
        out_lines.append(s)

    runs = args.rounds or find_rounds(args.logs)
    say('Turing judge v%d, %d s windows (half overlapping), %d candidate rounds' % (VERSION, args.win, len(runs)))
    windows, used, spacing = gather(runs, args.win, say=say)
    if len(used) < 3:
        say('Fewer than 3 usable rounds: nothing to hold out.')
        return
    y = np.array([w[0] for w in windows])
    ctx = np.array([w[2]['ctx'] for w in windows])
    say('Rounds used: %d. Windows: %d player, %d bot (%d calm player, %d calm bot)' % (
        len(used), y.sum(), len(y) - y.sum(), ((y == 1) & (ctx == 'calm')).sum(), ((y == 0) & (ctx == 'calm')).sum()))
    for kind, sp in spacing.items():
        say('Parity: raw %s sample spacing (ds: count) %s' % (kind, ', '.join('%g: %d' % kv for kv in sp.most_common(3))))
    folds = folds_of(used, min(args.folds, len(used)))

    prob = cross_validate(windows, JUDGED, folds)
    full = auc(prob, y)
    calm = ctx == 'calm'
    say()
    say('HELD-OUT AUC (0.5 = can\'t tell bots from the player, 1.0 = always can): %.3f' % full)
    say('  calm windows only: %.3f   fight windows only: %.3f' % (auc(prob[calm], y[calm]), auc(prob[~calm], y[~calm])))
    say('  mean P(human): player windows %.2f, bot windows %.2f; bot windows judged human (P > 0.5): %.1f%%' % (
        prob[y == 1].mean(), prob[y == 0].mean(), 100 * (prob[y == 0] > 0.5).mean()))
    if args.mlp:
        mp = cross_validate(windows, JUDGED, folds, mlp=True)
        say('  a small network on the same features: %.3f (calm %.3f), so combinations add %+.3f' % (
            auc(mp, y), auc(mp[calm], y[calm]), auc(mp, y) - full))

    say()
    say('Per round (held out), by date: does the gap close as the bots get better?')
    for run in sorted(used, key=round_id):
        m = np.array([w[2]['run'] == run for w in windows])
        say('  %-38s AUC %.3f  player %3d  bots %4d' % (round_id(run), auc(prob[m], y[m]), y[m].sum(), (1 - y[m]).sum()))

    say()
    say('TELLS, one feature at a time (AUC > 0.5: the player has more of it). Sorted by how much it gives away in calm windows.')
    say('  %-24s %6s %6s   %6s %6s  %s' % ('feature', 'AUC', 'calm', 'player', 'bots', '(medians, calm windows)'))
    Xall = matrix(windows, FEATURES)
    rows = []
    for j, c in enumerate(FEATURES):
        col = Xall[:, j]
        ok = ~np.isnan(col)
        a_all = auc(col[ok], y[ok])
        okc = ok & calm
        a_calm = auc(col[okc], y[okc])
        med_h = float(np.median(col[okc & (y == 1)])) if (okc & (y == 1)).any() else None
        med_b = float(np.median(col[okc & (y == 0)])) if (okc & (y == 0)).any() else None
        rows.append((abs((a_calm if not math.isnan(a_calm) else 0.5) - 0.5), c, a_all, a_calm, med_h, med_b))
    for _, c, a_all, a_calm, mh, mb in sorted(rows, reverse=True):
        say('  %-24s %6.3f %6.3f   %s %s' % (c, a_all, a_calm, fmt(mh), fmt(mb)))

    say()
    say('ABLATION: held-out AUC with one group of features taken away (a big drop: that group is where the tells are)')
    for g, cols in GROUPS.items():
        if g == 'body':
            p2 = cross_validate(windows, JUDGED + cols, folds)
            label = 'with'
        else:
            p2 = cross_validate(windows, [c for c in JUDGED if c not in cols], folds)
            label = 'without'
        a2 = auc(p2, y)
        say('  %-7s %-8s %.3f (%+.3f)   calm %.3f' % (label, g, a2, a2 - full, auc(p2[calm], y[calm])))
    for g, cols in GROUPS.items():
        p2 = cross_validate(windows, cols, folds)
        say('  only    %-8s %.3f' % (g, auc(p2, y)))

    train = balanced_train(windows, random.Random(7))
    final = Judge(JUDGED).fit(matrix(train, JUDGED), np.array([w[0] for w in train]))
    Xj = matrix(windows, JUDGED)
    say()
    say('JUDGE WEIGHTS (standardized; positive = more of it looks human)')
    order = np.argsort(-np.abs(final.coef))
    say('  ' + ', '.join('%s %+.2f' % (JUDGED[i], final.coef[i]) for i in order[:16]))

    def show(title, idx, n, key):
        """Up to n windows from idx (in order), one per key, so one stuck bot doesn't fill the list."""
        say()
        say(title)
        seen = set()
        for i in idx:
            lab, f, m = windows[i]
            if key(m) in seen:
                continue
            seen.add(key(m))
            if len(seen) > n:
                break
            why = ', '.join('%s %+.1f' % r for r in final.reasons(Xj[i]))
            say('  P(human) %.2f  %-22s %-18s goal %-22s %s  t=%d:%02d  [%s]' % (
                prob[i], m['name'][:22], (m['job'] or '')[:18], (m['goal'] or m['state'] or '-')[:22], m['ctx'],
                m['tick'] * GRID // 600, m['tick'] * GRID // 10 % 60, why))
            say('      ' + story_line(m))

    bot_idx = np.where(y == 0)[0]
    hum_idx = np.where(y == 1)[0]
    calm_bots = bot_idx[calm[bot_idx]]
    def one_a_bot(m):
        return m['run'], m['name']

    def one_a_spell(m):  # the player: one window in each 5 minutes of a round
        return m['run'], m['tick'] // 300

    show('MOST BOT-LIKE CALM BOT WINDOWS (what to go and look at first; one a bot)', calm_bots[np.argsort(prob[calm_bots])],
         args.top, one_a_bot)
    show('MOST HUMAN-LIKE BOT WINDOWS (good plays: what is working)', bot_idx[np.argsort(-prob[bot_idx])],
         max(3, args.top // 2), one_a_bot)
    show('MOST BOT-LIKE PLAYER WINDOWS (where the player looks like a bot: check a tell isn\'t just AFK or a menu)',
         hum_idx[np.argsort(prob[hum_idx])], max(3, args.top // 2), one_a_spell)

    os.makedirs(args.out, exist_ok=True)
    final.save(os.path.join(args.out, 'model.json'), {
        'win': args.win, 'grid': GRID, 'rounds': [round_id(r) for r in used], 'heldout_auc': full,
        'heldout_auc_calm': auc(prob[calm], y[calm]), 'p_player': float(prob[y == 1].mean()),
        'p_bot': float(prob[y == 0].mean())})
    with open(os.path.join(args.out, 'windows.jsonl'), 'w') as f:
        for i, (lab, feat, m) in enumerate(windows):
            f.write(json.dumps({'human': lab, 'p_human': float(prob[i]), **m,
                                'f': {k: (None if isinstance(v, float) and math.isnan(v) else v) for k, v in feat.items()}}) + '\n')
    with open(os.path.join(args.out, 'report.txt'), 'w') as f:
        f.write('\n'.join(out_lines) + '\n')
    say()
    say('Wrote %s (report.txt, model.json, windows.jsonl)' % args.out)


def wall_secs(a, b):
    """Seconds from wall clock a to b (HH:MM:SS), across midnight."""
    if not a or not b:
        return 0
    ta = sum(int(x) * k for x, k in zip(a.split(':'), (3600, 60, 1)))
    tb = sum(int(x) * k for x, k in zip(b.split(':'), (3600, 60, 1)))
    return (tb - ta) % 86400


def story_line(m):
    """The death_story.py call that shows one window: --at is where its view ends, and the span is wall seconds, which a
    timewarped run squeezes (30 s of game can be 3 s of log clock)."""
    end = m.get('wall_end') or m['wall']
    return 'python tools/bot_gym/death_story.py %s "%s" %d --at %s' % (
        m['run'], m['name'], wall_secs(m['wall'], end) + 1, end)


def runs_under(path):
    if logread.find(path, 'telemetry'):
        return [path]
    found = set()
    for p in glob.glob(os.path.join(path, '**', 'bot_telemetry.jsonl*'), recursive=True):
        found.add(os.path.dirname(p))
    return sorted(found)


def mean_ci(values):
    """Mean and 95% half-width over runs (runs, not windows: a bot's windows overlap and a round's bots share its luck)."""
    a = np.array(values, float)
    if len(a) < 2:
        return float(a.mean()) if len(a) else float('nan'), float('nan')
    return float(a.mean()), 1.96 * float(a.std(ddof=1)) / math.sqrt(len(a))


def cmd_score(args):
    judge = Judge.load(os.path.join(args.model, 'model.json'))
    win = judge.meta['win']
    print('Judge %s: %d s windows, trained on %d rounds, held-out AUC %.3f (calm %.3f); held out, player windows scored %.2f '
          'and bot windows %.2f' % (args.model, win, len(judge.meta['rounds']), judge.meta['heldout_auc'],
                                    judge.meta['heldout_auc_calm'], judge.meta['p_player'], judge.meta['p_bot']))
    results = []
    for target in args.dirs:
        bots, probs, per_run = [], [], []
        for run in runs_under(target):
            ws = [w for w in load_round(run, win)['windows'] if w[0] == 0]
            if ws:
                pr = judge.prob(matrix(ws, judge.cols))
                bots += ws
                probs.append(pr)
                per_run.append(pr.mean())
        if not bots:
            print('\n%s: no bot samples (a Bot Gym only writes them with bot-gym-samples=1)' % target)
            continue
        p = np.concatenate(probs)
        calm = np.array([w[2]['ctx'] == 'calm' for w in bots])
        m, ci = mean_ci(per_run)
        print('\n%s: %d runs, %d bot windows. Humanness (mean P(human)) %.3f +- %.3f (95%%, over runs), calm %.3f, fight %.3f; '
              'judged human %.1f%%' % (target, len(per_run), len(bots), m, ci, p[calm].mean() if calm.any() else float('nan'),
                                       p[~calm].mean() if (~calm).any() else float('nan'), 100 * (p > 0.5).mean()))
        groups = collections.defaultdict(list)
        for i, w in enumerate(bots):
            groups[w[2].get(args.by) or '-'].append(p[i])
        results.append({'dir': target, 'bots': bots, 'p': p, 'runs': per_run, 'groups': groups})
    if not results:
        return
    if args.features:
        # The tells themselves, beside the player's (the train's held-out player windows are what model.json's medians came from)
        names = [f.strip() for f in args.features.split(',') if f.strip()]
        for title, keep in (('calm windows', lambda f: True), ('calm, on the move (move_frac > 0.6)', lambda f: (f.get('move_frac') or 0) > 0.6)):
            print('\nMedians, %s:%s' % (title, ''.join('  %10s' % ('#%d' % (i + 1)) for i in range(len(results)))))
            for name in names:
                cells = []
                for r in results:
                    vals = [w[1].get(name) for w in r['bots'] if w[2]['ctx'] == 'calm' and keep(w[1])]
                    vals = [v for v in vals if v is not None and not (isinstance(v, float) and math.isnan(v))]
                    cells.append('  %10.3f' % float(np.median(vals)) if vals else '  %10s' % '-')
                print('    %-28s%s' % (name, ''.join(cells)))
    base = results[0]
    for other in results[1:]:
        a, b = np.array(base['runs']), np.array(other['runs'])
        diff = b.mean() - a.mean()
        se = math.sqrt((a.var(ddof=1) / len(a) if len(a) > 1 else 0) + (b.var(ddof=1) / len(b) if len(b) > 1 else 0))
        print('\n%s against %s: humanness %+.3f, 95%% interval [%+.3f, %+.3f]%s' % (
            other['dir'], base['dir'], diff, diff - 1.96 * se, diff + 1.96 * se,
            '' if abs(diff) > 1.96 * se else ' (can\'t tell them apart yet)'))

    keys = [k for k in base['groups'] if all(len(r['groups'].get(k, ())) >= args.min for r in results)]
    head = ''.join('  %8s' % ('#%d' % (i + 1)) for i in range(len(results)))
    print('\nBy %s, the %d least human-looking (groups of %d+ windows in every set; #1 = %s):' % (
        args.by, args.groups, args.min, base['dir']))
    print('    %-34s%s' % ('', head))
    for k in sorted(keys, key=lambda k: np.mean(base['groups'][k]))[:args.groups]:
        print('    %-34s%s   (%d)' % (k[:34], ''.join('  %8.3f' % np.mean(r['groups'][k]) for r in results),
                                      len(base['groups'][k])))
    if len(results) > 1:
        print('\nBy %s, the biggest changes from #1 to #2:' % args.by)
        moved = sorted(keys, key=lambda k: -abs(np.mean(results[1]['groups'][k]) - np.mean(base['groups'][k])))
        for k in moved[:args.groups]:
            print('    %-34s  %8.3f  %8.3f   %+.3f' % (k[:34], np.mean(base['groups'][k]), np.mean(results[1]['groups'][k]),
                                                       np.mean(results[1]['groups'][k]) - np.mean(base['groups'][k])))

    print('\nMost bot-like windows (one a bot):')
    worst = []
    for r in results:
        for i in np.argsort(r['p'])[:args.top * 20]:
            worst.append((r['p'][i], r['bots'][i]))
    seen = set()
    for pv, (lab, f, m) in sorted(worst, key=lambda t: t[0]):
        if (m['run'], m['name']) in seen:
            continue
        seen.add((m['run'], m['name']))
        xrow = np.array([f[c] for c in judge.cols], float)
        why = ', '.join('%s %+.1f' % r for r in judge.reasons(xrow))
        print('  %.2f %-22s goal %-22s %s [%s]' % (pv, m['name'][:22], (m['goal'] or m['state'] or '-')[:22], m['ctx'], why))
        print('      ' + story_line(m))
        if len(seen) >= args.top:
            break


def cmd_slice(args):
    """The tells inside a slice of a train's windows (windows.jsonl): a condition on the features, for both the player and the bots,
    so a difference that's only what each was doing (travelling against pottering about) can be told from one in how they do it."""
    rows = []
    with open(os.path.join(args.model, 'windows.jsonl')) as f:
        for line in f:
            w = json.loads(line)
            if args.calm and w['ctx'] != 'calm':
                continue
            env = {k: (np.nan if v is None else v) for k, v in w['f'].items()}
            try:
                keep = eval(args.where, {'__builtins__': {}}, env) if args.where else True
            except Exception as e:
                sys.exit('bad --where: %s' % e)
            if keep:
                rows.append(w)
    y = np.array([w['human'] for w in rows])
    print('%s: %d player windows, %d bot windows%s%s' % (args.model, y.sum(), len(y) - y.sum(),
                                                         ' where ' + args.where if args.where else '', ', calm only' if args.calm else ''))
    if y.sum() < 10 or (1 - y).sum() < 10:
        print('too few in the slice')
        return
    out = []
    for c in FEATURES:
        col = np.array([np.nan if w['f'].get(c) is None else w['f'][c] for w in rows], float)
        ok = ~np.isnan(col)
        a = auc(col[ok], y[ok])
        out.append((abs(a - 0.5) if not math.isnan(a) else 0, c, a, float(np.median(col[ok & (y == 1)])) if (ok & (y == 1)).any() else None,
                    float(np.median(col[ok & (y == 0)])) if (ok & (y == 0)).any() else None))
    print('  %-24s %6s   %6s %6s' % ('feature', 'AUC', 'player', 'bots'))
    for _, c, a, mh, mb in sorted(out, reverse=True)[:args.top]:
        print('  %-24s %6.3f   %s %s' % (c, a, fmt(mh), fmt(mb)))


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('--logs', default='data/logs', help='where to look for rounds with a player log')
    sub = ap.add_subparsers(dest='cmd', required=True)
    sub.add_parser('rounds')
    sl = sub.add_parser('slice')
    sl.add_argument('model', help='a train output folder (its windows.jsonl)')
    sl.add_argument('--where', default='', help='a condition on the features, e.g. "move_frac > 0.6"')
    sl.add_argument('--calm', action='store_true', help='calm windows only')
    sl.add_argument('--top', type=int, default=15)
    t = sub.add_parser('train')
    t.add_argument('rounds', nargs='*', help='round folders (default: every round with a player log and bots)')
    t.add_argument('--win', type=int, default=30, help='window length in seconds (default 30)')
    t.add_argument('--out', default=None, help='output folder (default data/bot_turing/w<win>)')
    t.add_argument('--folds', type=int, default=5)
    t.add_argument('--top', type=int, default=12, help='windows to list in each highlight section')
    t.add_argument('--mlp', action='store_true', help='also try a small network (torch) on the same features')
    s = sub.add_parser('score')
    s.add_argument('model', help='a train output folder')
    s.add_argument('dirs', nargs='+', help='run folders or batch folders (every run under them)')
    s.add_argument('--by', default='goal', choices=['goal', 'state', 'job', 'name'])
    s.add_argument('--min', type=int, default=20, help='smallest group to list')
    s.add_argument('--top', type=int, default=10, help='bot-like windows to list')
    s.add_argument('--groups', type=int, default=15, help='groups to list in each table')
    s.add_argument('--features', default='', help='comma-separated features to show medians of per set (calm windows, and calm on the move)')
    args = ap.parse_args()
    if args.cmd == 'rounds':
        cmd_rounds(args)
    elif args.cmd == 'slice':
        cmd_slice(args)
    elif args.cmd == 'train':
        args.out = args.out or os.path.join('data', 'bot_turing', 'w%d' % args.win)
        cmd_train(args)
    else:
        cmd_score(args)


if __name__ == '__main__':
    main()
