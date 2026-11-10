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

// Particles (hippiestation/code/modules/particles/particle_fx.dm)
/// Every particle is drawn on this plane: over the game world, under the lighting, and not at all for a client on Low graphics
#define PARTICLE_PLANE 9
/// Wind this strong shows as a gust on its tile (the pressure difference that starts shoving things about is 20 or so)
#define PARTICLE_GUST_PRESSURE 25
/// Tiles showing a gust at once, at most: a big breach is hundreds of windy tiles
#define PARTICLE_GUST_TILES 120
/// A vent letting this many moles into a room in one go puffs: about 8 kPa short of what it's set to
#define PARTICLE_VENT_PUFF_MOLES 8

// Dust in the air (hippiestation/code/modules/particles/air_dust.dm)
/// Its own plane, so a client can mask it to the floor and out from behind walls and things: over the game world, under the lighting
#define AIR_DUST_PLANE 8
/// An area's air_dust
#define AIR_DUST_NONE 0
#define AIR_DUST_LIGHT 1
#define AIR_DUST_HEAVY 2
/// One emitter every this many tiles each way, on the tiles where x and y are 2 more than a multiple of it. It covers the square round it
#define AIR_DUST_SPACING 4
/// The share of a speck's speed the air takes off it each tick: what holds a speck in wind to the wind's speed
#define AIR_DUST_FRICTION 0.025
/// Wind (an SSair pressure difference) this strong over a dust square's floor carries its specks: gently, briskly from the second,
/// and fast from the third (where a breach starts shoving things about, the gust's PARTICLE_GUST_PRESSURE)
#define AIR_DUST_WIND_PRESSURE 1
#define AIR_DUST_WIND_BRISK 8
#define AIR_DUST_WIND_STRONG 25
/// How long specks keep going with the wind after it stops
#define AIR_DUST_WIND_HOLD (2 SECONDS)
/// How far from a scrubber, in pixels, the specks it draws in come from
#define AIR_DUST_PULL_REACH 40

// The sky (hippiestation/code/_onclick/hud/sky.dm). The first two match tools/sky_gen/sky_gen.py, which draws the art.
/// Nebula clouds are drawn this many times their sprite's size: they're soft, so the pixels aren't missed, and they repeat half as often
#define SKY_NEBULA_SCALE 2
/// How many groups the twinkling stars are in (twinkle1.. in sky.dmi)
#define SKY_TWINKLE_GROUPS 3
/// Something crosses the sky this often: mostly shooting stars, now and then a comet or a far-off ship
#define SKY_FLYBY_MIN (50 SECONDS)
#define SKY_FLYBY_MAX (170 SECONDS)
