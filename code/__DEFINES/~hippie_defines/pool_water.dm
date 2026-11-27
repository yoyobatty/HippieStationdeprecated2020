// Pool water (hippiestation/code/modules/pool/pool_water_*.dm), from Paradise (pool-water, 2026-11-26): edges and depth, light
// through the water, waves, reflections and refraction, swimmers waist deep, things that sink or float, and a wave machine.

/// The water sprites
#define POOL_WATER_ICON 'hippiestation/icons/turf/pool_water.dmi'
// Pool water smooths against pool water only (SMOOTH_GROUP_POOL_WATER, code/__HELPERS/icon_smoothing.dm): anything else is dry land

// Hidden planes, read by the ones below
/// Reflections of things standing or floating in water, added in by the reflection plane
#define WATER_SELF_REFLECTION_PLANE -45
#define WATER_SELF_REFLECTION_RENDER_TARGET "*WATER_SELF_REFLECTION_PLANE"
/// What the reflection plane leaves out of its mirror, like things in the water
#define WATER_UNMIRRORED_PLANE -44
#define WATER_UNMIRRORED_RENDER_TARGET "*WATER_UNMIRRORED_PLANE"
/// The waves over things under the water, used to bend them on the game world plane
#define WATER_REFRACT_PLANE -43
#define WATER_REFRACT_RENDER_TARGET "*WATER_REFRACT_PLANE"
/// The slope of the water's waves, rings and wakes, used to bend and light the water
#define WATER_RIPPLE_PLANE -42
#define WATER_RIPPLE_RENDER_TARGET "*WATER_RIPPLE_PLANE"
/// Each water tile's mirror map, which flips the tile above it into the water
#define WATER_MIRROR_PLANE -41
#define WATER_MIRROR_RENDER_TARGET "*WATER_MIRROR_PLANE"
/// How much of a mirror the water is at each pixel, from the slope of its waves
#define WATER_FRESNEL_PLANE -40
#define WATER_FRESNEL_RENDER_TARGET "*WATER_FRESNEL_PLANE"
/// The water's shape, used to cut the water effects to it
#define WATER_MASK_PLANE -39
#define WATER_MASK_RENDER_TARGET "*WATER_MASK_PLANE"
/// A band along the water's edges, made from the water mask, where there's always a little foam
#define WATER_EDGE_BAND_PLANE -38
#define WATER_EDGE_BAND_RENDER_TARGET "*WATER_EDGE_BAND_PLANE"
/// Where foam shows: steep waves and the band along the water's edges
#define WATER_FOAM_DRIVE_PLANE -37
#define WATER_FOAM_DRIVE_RENDER_TARGET "*WATER_FOAM_DRIVE_PLANE"
/// Glints of the light on the water, added over the lighting
#define WATER_SPECULAR_PLANE -36
#define WATER_SPECULAR_RENDER_TARGET "*WATER_SPECULAR_PLANE"

// Drawn planes, under the floor plane, so reflections go between the water and what stands in it
/// The bottom of a pool, seen through the water
#define POOL_FLOOR_PLANE -22
/// Pool water turfs: the pool's edge and the water's colour
#define WATER_EDGE_PLANE -21
/// Shafts of light down through the water, added on top
#define WATER_RAYS_PLANE -20
/// Reflections: the game world mirrored and cut to the water, over the water's colour so they stay clear
#define WATER_REFLECTION_PLANE -19
/// No * at the front, so it's still drawn. The water over plane reads it
#define WATER_REFLECTION_RENDER_TARGET "WATER_REFLECTION_PLANE"
/// Darkens the sides of the waves facing away from the light
#define WATER_RELIEF_SHADE_PLANE -18
/// Brightens the sides of the waves facing the light
#define WATER_RELIEF_LIGHT_PLANE -17
#define WATER_RELIEF_LIGHT_RENDER_TARGET "WATER_RELIEF_LIGHT_PLANE"
/// Foam flecks on the water, shown only where the foam drive plane lets them
#define WATER_FOAM_PLANE -16
/// Glints, wakes and bubbles on the water, on top of its colour
#define WATER_SHINE_PLANE -15
/// The water's reflections again, over swimmers' legs and sunk things, which are on the game world plane
#define WATER_OVER_PLANE 2

/// How many pixels the ripples bend the pool floor and anything under the water
#define POOL_REFRACTION 3
/// How many pixels the ripples bend reflections, a bit more than the floor
#define POOL_REFLECTION_RIPPLE 4
/// How many pixels a mirror map can move a pixel each way. A tile mirrors the one above it, so up to 63
#define POOL_MIRROR_REACH 64
// How hard a pool's wave machine is running
#define POOL_WAVES_OFF 0
#define POOL_WAVES_GENTLE 1
#define POOL_WAVES_STRONG 2
/// How many tiles from dry land pool water is at its darkest
#define POOL_MAX_DEPTH 3
