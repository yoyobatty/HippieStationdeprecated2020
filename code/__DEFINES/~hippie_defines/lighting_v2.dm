// Lighting v2 (hippiestation/code/modules/lighting/lighting_v2.dm): the finish on the light map, contact shadows, starlight

/// Hidden plane: what the light map and the glowing things give off into the dark, blurred, before it's added to the screen
#define LIGHT_V2_GLOW_PLANE 4
#define LIGHT_V2_GLOW_RENDER_TARGET "*LIGHT_V2_GLOW_PLANE"

/// Light map brightness above which a lit floor glows out past its edges
#define LIGHT_V2_BLOOM_THRESHOLD 0.92
/// How much of the light above the threshold glows out
#define LIGHT_V2_BLOOM_STRENGTH 0.45
/// How far the glow spreads, px
#define LIGHT_V2_GLOW_BLUR 5
/// How much of each glowing sprite's colour spreads out round it, on top of the tight emissive bloom
#define LIGHT_V2_EMISSIVE_SPREAD 0.35
/// The colour of the dark: added where the light map is black
#define LIGHT_V2_DARK_TINT list(0.024, 0.031, 0.062)
/// The lighting plane's blur with v2 on (LIGHTING_SOFTEN_SIZE without)
#define LIGHT_V2_SOFTEN_SIZE 2.5
/// Under the floor, over the sky (whose plane multiplies everything under it), cut out where space is: what shows where nothing
/// is drawn (tiles out of sight or too dark to see), in the dark's tint
#define LIGHT_V2_DARK_FILL_PLANE -50
#define LIGHT_V2_DARK_FILL_COLOUR "#060810"
