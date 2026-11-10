// The tone curve on the light map, and eye adaptation (hippiestation/code/modules/lighting/eye_adapt.dm)

/// Where the tone curve starts. A corner's light, by its brightest channel, is drawn as it is up to this. Past it the light
/// eases toward full brightness instead of being cut off at 1, so where lamps overlap it still looks brighter than under one.
/// 1 is tg's cut-off. The DM corners (lighting_corner/update_objects()) and the lighting engine (tone_factor() in
/// tools/lighting_engine/src/engine.rs) both go by GLOB.lighting_tone_knee, set from this.
#define LIGHTING_TONE_KNEE 0.75

/// How often each player's eyes adjust
#define EYE_ADAPT_WAIT (0.5 SECONDS)
/// What eyes get used to: where what a player can see looks dimmer than this on average, their lighting is turned up toward it...
#define EYE_ADAPT_KEY 0.45
/// ...to at most this many times as bright. A tile with no light on it stays black whatever this is
#define EYE_ADAPT_MAX 1.5
/// How long eyes take to get used to the dark, and to bright light again: the time to make up about two thirds of the difference
#define EYE_ADAPT_DARK_TIME (3 SECONDS)
#define EYE_ADAPT_LIGHT_TIME (0.4 SECONDS)
/// Exposure changes smaller than this aren't sent to the client
#define EYE_ADAPT_STEP 0.01
