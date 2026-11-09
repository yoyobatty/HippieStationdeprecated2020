// Graphics quality, in the Display preferences. Two bits of hippie_toggles, and neither set is High, so savefiles from before it get High.
#define GRAPHICS_MEDIUM			(1<<5)
#define GRAPHICS_LOW			(1<<6)

/// What /datum/preferences/proc/graphics_quality() gives. Things ask for the lowest one that still shows them.
#define GRAPHICS_QUALITY_LOW	0 // nothing that moves by itself: no twinkle, drift or fly-bys
#define GRAPHICS_QUALITY_MEDIUM	1 // stars twinkle, nebulae drift
#define GRAPHICS_QUALITY_HIGH	2 // and near dust, comets, shooting stars, ships

/// A parallax tile, in pixels: tg's sheets and ours are this size, and layers repeat this far apart unless they say otherwise
#define PARALLAX_TILE 480

// The sky (hippiestation/code/_onclick/hud/sky.dm). The first two match tools/sky_gen/sky_gen.py, which draws the art.
/// Nebula clouds are drawn this many times their sprite's size: they're soft, so the pixels aren't missed, and they repeat half as often
#define SKY_NEBULA_SCALE 2
/// How many groups the twinkling stars are in (twinkle1.. in sky.dmi)
#define SKY_TWINKLE_GROUPS 3
/// Something crosses the sky this often: mostly shooting stars, now and then a comet or a far-off ship
#define SKY_FLYBY_MIN (50 SECONDS)
#define SKY_FLYBY_MAX (170 SECONDS)
