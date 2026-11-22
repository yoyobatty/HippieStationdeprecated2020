"""The regression set: fixed (shape, crew, seed) builds the gate keeps an accepted baseline for (plan section 3).
Every milestone's exit test runs over this set. A shape joins when its stage is built (M6 adds donut, spine...)."""

CREWS = (40, 80, 120)
SEEDS = (1, 2, 3, 4, 5)
SHAPES = ("hub",)


def regression_set(shapes=SHAPES):
    return [(s, c, k) for s in shapes for c in CREWS for k in SEEDS]


def name(shape, crew, seed):
    return "gen_%s_c%d_s%d" % (shape, crew, seed)
