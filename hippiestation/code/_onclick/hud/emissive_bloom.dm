#define EMISSIVE_BLOOM_SIZE 2 // blur of the glow in pixels, from tgstation/tgstation#91456
#define EMISSIVE_BLOOM_OFFSET 1 // how far the glow grows out from the sprite before it's blurred, also from #91456. Together they give about 100% / 66% / 33% brightness out to 3 pixels

/**
  * Colored bloom for emissives, adapted from tgstation/tgstation#91456.
  *
  * Anything drawn on the emissive planes glows out a bit, in its own colors. The PR itself can't be applied here since it builds
  * on tg's later rendering plates, relay planes and overlay lighting plane, none of which this codebase has. But emissives here
  * are simpler to bloom: they're vis overlays drawn in their own colors on the emissive planes, which are only ever used as
  * masks for the lighting plane.
  *
  * So every emissive vis overlay gets an identical twin on the bloom plane (see SSvis_overlays.add_vis_overlay). The twin sits in
  * the world exactly where the emissive does, so it can't end up in the wrong place on screen. This plane master then, in order:
  * hides whatever the emissive blockers hide, exactly like the emissive plane does, blooms what's left, and cuts out the original
  * sprites with an inverse mask so only the halo is added and the sprite doesn't just get twice as bright. It's drawn additively.
  */
/obj/screen/plane_master/emissive_bloom
	name = "emissive bloom plane master"
	plane = EMISSIVE_BLOOM_PLANE
	appearance_flags = PLANE_MASTER|NO_CLIENT_COLOR
	blend_mode = BLEND_ADD
	mouse_opacity = MOUSE_OPACITY_TRANSPARENT

/obj/screen/plane_master/emissive_bloom/Initialize()
	. = ..()
	filters += filter(type = "alpha", render_source = EMISSIVE_BLOCKER_RENDER_TARGET, flags = MASK_INVERSE)
	filters += filter(type = "bloom", threshold = COLOR_BLACK, size = EMISSIVE_BLOOM_SIZE, offset = EMISSIVE_BLOOM_OFFSET)
	filters += filter(type = "alpha", render_source = EMISSIVE_RENDER_TARGET, flags = MASK_INVERSE)
	filters += filter(type = "alpha", render_source = EMISSIVE_UNBLOCKABLE_RENDER_TARGET, flags = MASK_INVERSE)
