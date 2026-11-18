"""What the discriminator reads (plan C2): blank one channel at a time on each fold's held-out crops and see how far
the score gap between generated and human crops falls. A channel whose loss closes the gap is the tell.

    python tools/mapforge/forge/disc_ablate.py data/mapforge/disc/v1 [--gen data/mapforge/genset]
"""
import argparse
import glob
import os
import random
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, ".."))
from forge import disc, tensor  # noqa: E402


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("run")
    ap.add_argument("--gen", nargs="*", default=[])
    ap.add_argument("--device", default="cuda")
    a = ap.parse_args()
    import torch
    maps = disc.load_all(a.gen, quiet=True)
    idx = {os.path.abspath(m[0]) if os.path.exists(m[0]) else m[0]: i for i, m in enumerate(maps)}
    rows = {c: [] for c in ["(none)"] + tensor.CHANNELS}
    for p in sorted(glob.glob(os.path.join(a.run, "fold*.pt"))):
        ck = torch.load(p, map_location=a.device)
        te = [idx[os.path.abspath(n) if os.path.exists(n) else n] for n in ck["test"]]
        if not any(maps[i][1] for i in te):
            continue
        model = disc.net(ck["width"]).to(a.device)
        model.load_state_dict(ck["state"])
        model.eval()
        xs, ys, who = disc.Sampler(maps, te, ck["crop"], random.Random(2)).fixed(40)
        for ch in rows:
            x = xs.copy()
            if ch != "(none)":
                x[:, tensor.CI[ch]] = 0
            sc = []
            with torch.no_grad():
                for j in range(0, len(x), 128):
                    xt, mt = disc.to_torch(x[j:j + 128], a.device)
                    sc += model(xt, mt)[0].cpu().tolist()
            sc = np.array(sc)
            rows[ch].append((sc[ys == 1].mean() - sc[ys == 0].mean(), disc.auc(sc, ys)))
    base = np.mean([g for g, _ in rows["(none)"]])
    print("%-11s %8s %6s   (gap = mean generated score - mean human score, over the folds)" % ("blanked", "gap", "AUC"))
    for ch, r in sorted(rows.items(), key=lambda kv: np.mean([g for g, _ in kv[1]])):
        g, u = np.mean([g for g, _ in r]), np.mean([u for _, u in r])
        print("%-11s %8.2f %6.3f  %s" % (ch, g, u, "#" * int(max(0, base - g) / base * 40)))


if __name__ == "__main__":
    main()
