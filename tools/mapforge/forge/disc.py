"""Discriminator v1 (plan C2): a small network that tells human-made map crops from generated ones, read off the
semantic tile tensors (forge/tensor.py). It is a judge, not a generator: where it is sure a crop is generated, its
per-tile heatmap points at what gave the crop away.

    python tools/mapforge/forge/disc.py smoke                          # CPU, a few steps: checks the code runs
    python tools/mapforge/forge/disc.py tensors                        # build every tensor (cached, one process)
    python tools/mapforge/forge/disc.py train --device cuda [--steps 3000] [--crop 48] [--gen DIR ...]
    python tools/mapforge/forge/disc.py heat <run dir> <map> [<map> ...]

The network is fully convolutional: dilated 3x3 convolutions, then a 1x1 convolution that gives one logit per tile
(above 0: "looks generated"). A crop's score is the mean tile logit over its station tiles, so the tile logits are the
heatmap with no extra step (class activation map).

Training data: human maps are parse.humans() (the 9 tg maps plus the corpus); generated maps are
_maps/map_files/Generated/*.dmm and every .dmm in each --gen directory. Crops are centred on a random station tile, the
two classes drawn equally and every map equally within its class (a big map is not worth more than a small one), each
crop turned or mirrored at random (tensor.dihedral, 8 ways).

Held-out test: k folds by family. A family is a map with its remakes (corpus_index.py: bee's MetaStation and tg's
current MetaStation are one family), so a fold never trains on a copy of a map it is tested on. Generated maps go to
folds by layout (pinwheel, spine, ring, ...) for the same reason. Each fold writes the held-out crop scores and the
area under the ROC curve (0.5 = chance) to data/mapforge/disc/<run>/report.txt; heat writes heatmaps to
data/previews/mapforge/disc/.
"""
import argparse
import glob
import json
import os
import random
import re
import sys
import time

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, ".."))
from forge import parse, tensor  # noqa: E402

ROOT = parse.ROOT
OUT = os.path.join(ROOT, "data", "mapforge", "disc")
PICS = os.path.join(ROOT, "data", "previews", "mapforge", "disc")
GEN_DIR = os.path.join(ROOT, "_maps", "map_files", "Generated")


# ---------------------------------------------------------------------------------------------------- the maps

def generated(dirs=()):
    out = sorted(glob.glob(os.path.join(GEN_DIR, "*.dmm")))
    for d in dirs:
        out += sorted(glob.glob(os.path.join(d, "*.dmm")))
    return out


def family(name):
    """Remakes of one map share a family; generated maps share one per layout."""
    base = os.path.splitext(os.path.basename(name))[0]
    g = re.match(r"gen_([a-z]+)_", base)
    if g:
        return "gen:" + g.group(1)
    cm = parse.corpus_maps().get(name)
    if cm:
        return cm.get("family", name)
    return "MetaStation" if name == "MetaLake" else name


def load_all(gen_dirs=(), quiet=False):
    """[(name, label, family, planes, mask)], label 1 = generated."""
    out = []
    names = [(n, 0) for n in parse.humans()] + [(p, 1) for p in generated(gen_dirs)]
    for n, lab in names:
        t0 = time.time()
        planes, mask = tensor.load(n)
        if mask.sum() < 500:
            if not quiet:
                print("  skip %s: %d station tiles" % (n, int(mask.sum())))
            continue
        out.append((n, lab, family(n), planes, mask))
        if not quiet:
            print("  %-40s %s %-22s %s floor %6d (%.1fs)" % (os.path.basename(n)[:40], "GEN" if lab else "hum",
                                                          family(n)[:22], planes.shape, int(mask.sum()), time.time() - t0))
    return out


def folds(maps, k):
    """k folds of families: human families spread round-robin by size, generated layouts likewise."""
    fams = {}
    for i, (n, lab, fam, planes, mask) in enumerate(maps):
        fams.setdefault((lab, fam), []).append(i)
    out = [[] for _ in range(k)]
    for lab in (0, 1):
        fl = sorted((f for f in fams if f[0] == lab), key=lambda f: -len(fams[f]))
        for j, f in enumerate(fl):
            out[j % k] += fams[f]
    return [sorted(f) for f in out]


# ---------------------------------------------------------------------------------------------------- crops

class Sampler:
    """Balanced random crops: half human, half generated, every map equally likely within its class."""

    def __init__(self, maps, idx, crop, rng):
        self.crop, self.rng = crop, rng
        self.by_lab = {0: [], 1: []}
        self.maps = maps
        self.centres = {}
        for i in idx:
            n, lab, fam, planes, mask = maps[i]
            ys, xs = np.nonzero(mask)
            self.centres[i] = np.stack([ys, xs], 1)
            self.by_lab[lab].append(i)

    def one(self, lab, aug=True):
        i = self.rng.choice(self.by_lab[lab])
        return self.crop_at(i, self.centres[i][self.rng.randrange(len(self.centres[i]))], aug)

    def crop_at(self, i, yx, aug=True, k=None):
        n, lab, fam, planes, mask = self.maps[i]
        s, h = self.crop, self.crop // 2
        C, H, W = planes.shape
        y0, x0 = int(yx[0]) - h, int(yx[1]) - h
        out = np.zeros((C + 1, s, s), dtype=np.uint8)
        out[tensor.CI["space"]] = 1  # off the map edge reads as space
        sy0, sx0, sy1, sx1 = max(0, y0), max(0, x0), min(H, y0 + s), min(W, x0 + s)
        out[:C, sy0 - y0:sy1 - y0, sx0 - x0:sx1 - x0] = planes[:, sy0:sy1, sx0:sx1]
        out[C, sy0 - y0:sy1 - y0, sx0 - x0:sx1 - x0] = mask[sy0:sy1, sx0:sx1]
        if aug:
            k = self.rng.randrange(8) if k is None else k
            body = tensor.dihedral(out[:C], k)
            m = tensor.dihedral(out[C:][[0] * tensor.C], k)[0]  # the mask turns the same way (any channel will do)
            out = np.concatenate([body, m[None]], 0)
        return out, lab

    def batch(self, size, aug=True):
        xs, ys = [], []
        for j in range(size):
            x, y = self.one(j % 2, aug)
            xs.append(x)
            ys.append(y)
        return np.stack(xs), np.array(ys, dtype=np.float32)

    def fixed(self, per_map, seed=1):
        """Held-out crops: per_map from each map, centres fixed by seed, no turning."""
        r = random.Random(seed)
        xs, ys, who = [], [], []
        for lab in (0, 1):
            for i in self.by_lab[lab]:
                c = self.centres[i]
                for _ in range(per_map):
                    x, y = self.crop_at(i, c[r.randrange(len(c))], aug=False)
                    xs.append(x)
                    ys.append(y)
                    who.append(i)
        return np.stack(xs), np.array(ys, dtype=np.float32), who


# ---------------------------------------------------------------------------------------------------- the network

def net(width=64):
    import torch.nn as nn

    class Disc(nn.Module):
        """Dilated convolutions (receptive field 61 tiles: a room and its neighbours), one logit per tile."""

        def __init__(self):
            super().__init__()
            layers, cin = [], tensor.C
            for d in (1, 1, 2, 4, 8, 8, 4, 1):
                layers += [nn.Conv2d(cin, width, 3, padding=d, dilation=d), nn.GroupNorm(8, width), nn.SiLU()]
                cin = width
            self.body = nn.Sequential(*layers)
            self.head = nn.Conv2d(width, 1, 1)

        def forward(self, x, mask):
            """x [B, C, H, W] float, mask [B, H, W] float -> (crop logit [B], tile logits [B, H, W])."""
            tiles = self.head(self.body(x))[:, 0]
            m = mask + 1e-6
            return (tiles * m).sum((1, 2)) / m.sum((1, 2)), tiles

    return Disc()


def to_torch(xb, device):
    import torch
    t = torch.from_numpy(xb).to(device).float()
    return t[:, :tensor.C], t[:, tensor.C]


def auc(scores, labels):
    """Area under the ROC curve: the chance a random generated crop scores above a random human one."""
    s, l = np.asarray(scores), np.asarray(labels)
    pos, neg = s[l == 1], s[l == 0]
    if not len(pos) or not len(neg):
        return float("nan")
    order = np.argsort(np.concatenate([neg, pos]), kind="mergesort")
    ranks = np.empty(len(order))
    ranks[order] = np.arange(1, len(order) + 1)
    return float((ranks[len(neg):].sum() - len(pos) * (len(pos) + 1) / 2) / (len(pos) * len(neg)))


def train_fold(maps, tr, te, a, device, log):
    import torch
    torch.manual_seed(a.seed)
    rng = random.Random(a.seed)
    S = Sampler(maps, tr, a.crop, rng)
    model = net(a.width).to(device)
    opt = torch.optim.AdamW(model.parameters(), lr=a.lr, weight_decay=1e-4)
    sched = torch.optim.lr_scheduler.OneCycleLR(opt, a.lr, total_steps=a.steps)
    lossf = torch.nn.BCEWithLogitsLoss()
    t0 = time.time()
    for step in range(1, a.steps + 1):
        xb, yb = S.batch(a.batch)
        x, m = to_torch(xb, device)
        logit, _ = model(x, m)
        loss = lossf(logit, torch.from_numpy(yb).to(device))
        opt.zero_grad()
        loss.backward()
        opt.step()
        sched.step()
        if step % max(1, a.steps // 10) == 0:
            log("    step %5d loss %.3f (%.0fs)" % (step, loss.item(), time.time() - t0))
    res = {}
    if te:
        T = Sampler(maps, te, a.crop, random.Random(a.seed + 1))
        xs, ys, who = T.fixed(a.test_crops)
        model.eval()
        sc = []
        with torch.no_grad():
            for j in range(0, len(xs), 64):
                x, m = to_torch(xs[j:j + 64], device)
                sc += model(x, m)[0].cpu().tolist()
        model.train()
        res = dict(auc=auc(sc, ys), crops=len(ys), per_map={})
        for i in sorted(set(who)):
            v = [s for s, w in zip(sc, who) if w == i]
            res["per_map"][maps[i][0]] = dict(label=maps[i][1], mean=float(np.mean(v)),
                                              gen_share=float(np.mean([s > 0 for s in v])))
    return model, res


def cmd_train(a):
    import torch
    if a.device == "cuda" and not torch.cuda.is_available():
        sys.exit("cuda asked for but torch sees no GPU")
    torch.set_num_threads(a.threads)
    run = os.path.join(OUT, a.run or time.strftime("run_%Y%m%d_%H%M"))
    os.makedirs(run, exist_ok=True)
    rep = open(os.path.join(run, "report.txt"), "w")

    def log(s):
        print(s)
        rep.write(s + "\n")
        rep.flush()

    maps = load_all(a.gen, quiet=a.quiet)
    log("%d maps: %d human, %d generated; crop %d, %d steps x %d, device %s" % (
        len(maps), sum(1 for m in maps if not m[1]), sum(1 for m in maps if m[1]), a.crop, a.steps, a.batch, a.device))
    F = folds(maps, a.folds) if a.folds > 1 else [[]]
    allres = []
    for k, te in enumerate(F):
        tr = [i for i in range(len(maps)) if i not in set(te)]
        if not any(maps[i][1] for i in tr) or (te and not any(maps[i][1] for i in te)):
            log("fold %d: skipped (a side has no generated map; generate more seeds)" % k)
            continue
        log("fold %d: test %s" % (k, ", ".join(os.path.basename(maps[i][0]) for i in te) or "-"))
        model, res = train_fold(maps, tr, te, a, a.device, log)
        torch.save(dict(state=model.state_dict(), width=a.width, crop=a.crop, test=[maps[i][0] for i in te]),
                   os.path.join(run, "fold%d.pt" % k))
        if res:
            log("  held-out AUC %.3f over %d crops" % (res["auc"], res["crops"]))
            for n, r in sorted(res["per_map"].items(), key=lambda kv: (kv[1]["label"], kv[1]["mean"])):
                log("    %-3s %-38s mean %+6.2f  called generated %3.0f%%" % (
                    "GEN" if r["label"] else "hum", os.path.basename(n)[:38], r["mean"], 100 * r["gen_share"]))
            allres.append(res)
    if allres:
        log("mean held-out AUC %.3f over %d folds" % (np.mean([r["auc"] for r in allres]), len(allres)))
    json.dump(dict(args=vars(a), folds=allres), open(os.path.join(run, "report.json"), "w"), indent=1)
    log("-> %s" % run)


# ---------------------------------------------------------------------------------------------------- heatmaps

def heat_map(model, planes, mask, device, tile=4):
    """Whole-map tile logits, then a picture: the map in greys, tiles the network calls generated in red, human in
    blue, strength by logit."""
    import torch
    from PIL import Image
    with torch.no_grad():
        x = torch.from_numpy(planes[None]).to(device).float()
        m = torch.from_numpy(mask[None]).to(device).float()
        _, tiles = model(x, m)
    L = tiles[0].cpu().numpy()
    H, W = mask.shape
    base = np.full((H, W, 3), 12, dtype=np.float32)
    ci = tensor.CI
    base[planes[ci["floor"]] > 0] = 150
    base[planes[ci["door"]] > 0] = (190, 170, 90)
    base[planes[ci["wall"]] > 0] = 70
    base[planes[ci["glass"]] > 0] = (90, 120, 150)
    base[planes[ci["dense"]] > 0] *= 0.75
    a = np.clip(np.abs(L) / 4.0, 0, 1)[..., None] * (mask[..., None] > 0)
    tint = np.where(L[..., None] > 0, np.array([235, 40, 30], np.float32), np.array([40, 90, 235], np.float32))
    img = (base * (1 - 0.7 * a) + tint * 0.7 * a).astype(np.uint8)[::-1]  # row 0 is the south edge: flip for north up
    im = Image.fromarray(img).resize((W * tile, H * tile), Image.NEAREST)
    return im, L


def cmd_heat(a):
    import torch
    os.makedirs(PICS, exist_ok=True)
    pts = sorted(glob.glob(os.path.join(a.run, "fold*.pt")))
    if not pts:
        sys.exit("no fold*.pt in %s" % a.run)
    ck = {p: torch.load(p, map_location=a.device) for p in pts}
    for name in a.maps:
        # the fold that held this map out, so the heatmap is from a network that never saw it
        held = [p for p, c in ck.items() if name in c["test"] or os.path.abspath(name) in map(os.path.abspath, c["test"])]
        p = held[0] if held else pts[0]
        model = net(ck[p]["width"]).to(a.device)
        model.load_state_dict(ck[p]["state"])
        model.eval()
        planes, mask = tensor.load(name)
        im, L = heat_map(model, planes, mask, a.device)
        out = os.path.join(PICS, "heat_%s.png" % os.path.splitext(os.path.basename(name))[0].replace(":", "_"))
        im.save(out)
        on = L[mask > 0]
        print("%-36s %s mean %+.2f, %.0f%% of tiles called generated -> %s" % (
            os.path.basename(name)[:36], "(held out)" if held else "(SEEN IN TRAINING)",
            on.mean(), 100 * (on > 0).mean(), out))


# ---------------------------------------------------------------------------------------------------- checks

def cmd_smoke(a):
    """CPU only, a few steps on 2 human and the generated maps: shapes, the mask turning with the crop, the loss."""
    import torch
    torch.set_num_threads(2)
    maps = [m for m in load_all(quiet=True) if m[1] or m[0] in ("MetaStation", "BoxStation")]
    rng = random.Random(0)
    S = Sampler(maps, range(len(maps)), 48, rng)
    xb, yb = S.batch(8)
    assert xb.shape == (8, tensor.C + 1, 48, 48), xb.shape
    # the mask must stay on floor after a turn
    for k in range(8):
        x, _ = S.crop_at(0, S.centres[0][len(S.centres[0]) // 2], aug=True, k=k)
        assert (x[tensor.C] <= x[tensor.CI["floor"]]).all(), "mask left the floor at turn %d" % k
    model = net(32)
    opt = torch.optim.AdamW(model.parameters(), 1e-3)
    lossf = torch.nn.BCEWithLogitsLoss()
    t0 = time.time()
    for step in range(a.steps):
        xb, yb = S.batch(8)
        x, m = to_torch(xb, "cpu")
        logit, tiles = model(x, m)
        loss = lossf(logit, torch.from_numpy(yb))
        opt.zero_grad()
        loss.backward()
        opt.step()
    print("smoke ok: %d maps, %d params, tiles %s, last loss %.3f, %.2fs/step on CPU" % (
        len(maps), sum(p.numel() for p in model.parameters()), tuple(tiles.shape), loss.item(), (time.time() - t0) / a.steps))
    assert abs(auc([0, 1, 2, 3], [0, 0, 1, 1]) - 1.0) < 1e-9 and abs(auc([3, 2, 1, 0], [0, 0, 1, 1])) < 1e-9


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("smoke")
    s.add_argument("--steps", type=int, default=5)
    sub.add_parser("tensors").add_argument("--gen", nargs="*", default=[])
    t = sub.add_parser("train")
    t.add_argument("--device", default="cpu")
    t.add_argument("--gen", nargs="*", default=[], help="more directories of generated .dmm maps")
    t.add_argument("--steps", type=int, default=3000)
    t.add_argument("--batch", type=int, default=32)
    t.add_argument("--crop", type=int, default=48)
    t.add_argument("--width", type=int, default=64)
    t.add_argument("--lr", type=float, default=2e-3)
    t.add_argument("--folds", type=int, default=5)
    t.add_argument("--test-crops", type=int, default=40)
    t.add_argument("--seed", type=int, default=1)
    t.add_argument("--threads", type=int, default=4)
    t.add_argument("--run", default="")
    t.add_argument("--quiet", action="store_true")
    h = sub.add_parser("heat")
    h.add_argument("run")
    h.add_argument("maps", nargs="+")
    h.add_argument("--device", default="cpu")
    a = ap.parse_args()
    if a.cmd == "smoke":
        cmd_smoke(a)
    elif a.cmd == "tensors":
        load_all(a.gen)
    elif a.cmd == "train":
        cmd_train(a)
    else:
        cmd_heat(a)


if __name__ == "__main__":
    main()
