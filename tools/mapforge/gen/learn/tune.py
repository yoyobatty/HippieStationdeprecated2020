"""The fast loop for the room synthesizer: held-out rooms from several map families, numbers only, in parallel.

    python tools/mapforge/gen/learn/tune.py                    # score now (Meta, Box, Delta held out in turn)
    python tools/mapforge/gen/learn/tune.py --pics             # and the human | generated pictures
    python tools/mapforge/gen/learn/tune.py --set W_WALL=6 CONNECT=0.9   # try settings of gen/learn/synth.py

Prints each room's numbers and one score (heldout.score: function problems over the humans', furnished-share and
wall-share gaps, groups left out); lower is better.
"""
import argparse
import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "..", ".."))
import heldout  # noqa: E402

FAMILIES = ("MetaStation.dmm", "BoxStation.dmm", "DeltaStation2.dmm")


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("--pics", action="store_true")
    ap.add_argument("--set", nargs="*", default=[])
    ap.add_argument("--jobs", type=int, default=4)
    ap.add_argument("--families", default=",".join(FAMILIES))
    a = ap.parse_args(argv)
    if a.set:
        # settings go to the workers through the environment (synth reads SYNTH_SET at import)
        os.environ["SYNTH_SET"] = ";".join(a.set)
    t0 = time.time()
    res = heldout.run(a.families.split(","), seed=1, pics=a.pics, jobs=a.jobs)
    for r in res:
        print("%-14s %-34s prob h%d g%d fill h%.2f g%.2f wall h%.2f g%.2f left %d %s" % (
            r["map"][:14], r["area"].replace("/area/", "")[:34], r["probs_h"], r["probs_g"], r["fill_h"], r["fill_g"],
            r["wall_h"], r["wall_g"], r["left"], ",".join(r["rules_g"])))
    n = float(len(res))
    print("rooms %d  probs h%d g%d  fill h%.3f g%.3f  wall h%.3f g%.3f  left %d  SCORE %.3f  (%.0fs)" % (
        len(res), sum(r["probs_h"] for r in res), sum(r["probs_g"] for r in res),
        sum(r["fill_h"] for r in res) / n, sum(r["fill_g"] for r in res) / n,
        sum(r["wall_h"] for r in res) / n, sum(r["wall_g"] for r in res) / n,
        sum(r["left"] for r in res), heldout.score(res), time.time() - t0))
    if a.pics:
        from forge import render
        pics, caps = [], []
        for r in res:
            pics += [r["pic_h"], r["pic_g"]]
            caps += ["%s human" % r["area"].rsplit("/", 1)[-1], "generated (%d)" % r["probs_g"]]
        print(render.sheet(pics, caps, os.path.join(heldout.OUT, "tune_sheet.png"), title="held out: human | generated"))


if __name__ == "__main__":
    main()
