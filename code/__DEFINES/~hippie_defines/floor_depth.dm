// Floor depth: plating where a tile came off sits a little lower than the floor round it (floor_depth.dm)

/// The holes' shapes, which cut the depth drawing to them. Not drawn
#define FLOOR_DEPTH_MASK_PLANE -8
#define FLOOR_DEPTH_MASK_RENDER_TARGET "*FLOOR_DEPTH_MASK"
/// Plating that lost its tile, what lies flat on it or under the floor there, and what's under the tiles beside it. Drawn as
/// it is; the plane above covers it
#define FLOOR_DEPTH_PLANE -7
#define FLOOR_DEPTH_RENDER_TARGET "FLOOR_DEPTH_PLANE"
/// Draws those holes with depth: the plating pulled towards the middle of the screen, the rims' edges
#define FLOOR_DEPTH_DRAW_PLANE -6
/// The rims' soft shadow in the holes. Its own plane so the blur is the plane master's: a filter on a screen object pads it past
/// the edge of the screen, and BYOND moves the whole map to fit it in
#define FLOOR_DEPTH_SHADOW_PLANE -5

/// How much smaller the plating is drawn, around the middle of the screen. 0.025 is 6 px at the edge of a 15 wide view
#define FLOOR_DEPTH_SCALE 0.975

/// Is this a turf whose plating sits low?
#define IS_SUNKEN_FLOOR(T) (T?.floor_sunken)
