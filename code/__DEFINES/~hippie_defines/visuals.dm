// Graphics quality, in the Display preferences. Two bits of hippie_toggles, and neither set is High, so savefiles from before it get High.
#define GRAPHICS_MEDIUM			(1<<5)
#define GRAPHICS_LOW			(1<<6)

/// What /datum/preferences/proc/graphics_quality() gives. Things ask for the lowest one that still shows them.
#define GRAPHICS_QUALITY_LOW	0 // nothing that moves by itself: no twinkle, drift or fly-bys
#define GRAPHICS_QUALITY_MEDIUM	1 // stars twinkle, nebulae drift
#define GRAPHICS_QUALITY_HIGH	2 // and near dust, comets, shooting stars, ships

/// A parallax tile, in pixels: tg's sheets and ours are this size, and layers repeat this far apart unless they say otherwise
#define PARALLAX_TILE 480

// Lights that move (hippiestation/code/modules/lighting/light_glow.dm)
/// Hidden plane of the soft pools of light that pulse by themselves. Each client's lighting plane adds it into itself, so where
/// it sits among the planes doesn't matter: 10 was free
#define LIGHT_GLOW_PLANE 10
#define LIGHT_GLOW_RENDER_TARGET "*LIGHT_GLOW_PLANE"
/// How far, in pixels, light and shadow are blurred into each other on Medium graphics and up
#define LIGHTING_SOFTEN_SIZE 1.5
/// The soft halo round whatever is bright on the floor and game planes, on Medium graphics and up. It's put on before the
/// lighting darkens the screen, so white tiles under a lamp glow a little and the same tiles in the dark don't
#define SCENE_BLOOM filter(type = "bloom", threshold = "#d0d0d0", size = 3, offset = 0, alpha = 45)

// The sky (hippiestation/code/_onclick/hud/sky.dm). The first two match tools/sky_gen/sky_gen.py, which draws the art.
/// Nebula clouds are drawn this many times their sprite's size: they're soft, so the pixels aren't missed, and they repeat half as often
#define SKY_NEBULA_SCALE 2
/// How many groups the twinkling stars are in (twinkle1.. in sky.dmi)
#define SKY_TWINKLE_GROUPS 3
/// Something crosses the sky this often: mostly shooting stars, now and then a comet or a far-off ship
#define SKY_FLYBY_MIN (50 SECONDS)
#define SKY_FLYBY_MAX (170 SECONDS)
