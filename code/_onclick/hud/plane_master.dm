/obj/screen/plane_master
	screen_loc = "CENTER"
	icon_state = "blank"
	appearance_flags = PLANE_MASTER|NO_CLIENT_COLOR
	blend_mode = BLEND_OVERLAY
	var/show_alpha = 255
	var/hide_alpha = 0

/obj/screen/plane_master/proc/Show(override)
	alpha = override || show_alpha

/obj/screen/plane_master/proc/Hide(override)
	alpha = override || hide_alpha

//Why do plane masters need a backdrop sometimes? Read https://secure.byond.com/forum/?post=2141928
//Trust me, you need one. Period. If you don't think you do, you're doing something extremely wrong.
/obj/screen/plane_master/proc/backdrop(mob/mymob)

///Things rendered on "openspace"; holes in multi-z
/obj/screen/plane_master/openspace
	name = "open space plane master"
	plane = OPENSPACE_BACKDROP_PLANE
	appearance_flags = PLANE_MASTER
	blend_mode = BLEND_MULTIPLY
	alpha = 255

/obj/screen/plane_master/openspace/backdrop(mob/mymob)
	filters = list()
	filters += filter(type = "drop_shadow", color = "#04080FAA", size = -10)
	filters += filter(type = "drop_shadow", color = "#04080FAA", size = -15)
	filters += filter(type = "drop_shadow", color = "#04080FAA", size = -20)

/obj/screen/plane_master/proc/outline(_size, _color)
	filters += filter(type = "outline", size = _size, color = _color)

/obj/screen/plane_master/proc/shadow(_size, _border, _offset = 0, _x = 0, _y = 0, _color = "#04080FAA")
	filters += filter(type = "drop_shadow", x = _x, y = _y, color = _color, size = _size, offset = _offset)

/obj/screen/plane_master/proc/clear_filters()
	filters = list()

///Contains just the floor
/obj/screen/plane_master/floor
	name = "floor plane master"
	plane = FLOOR_PLANE
	appearance_flags = PLANE_MASTER
	blend_mode = BLEND_OVERLAY
	render_target = FLOOR_PLANE_RENDER_TARGET

/obj/screen/plane_master/floor/backdrop(mob/mymob)
	filters = list()
	if(istype(mymob) && mymob.eye_blurry)
		filters += GAUSSIAN_BLUR(clamp(mymob.eye_blurry*0.1,0.6,3))

///Contains most things in the game world
/obj/screen/plane_master/game_world
	name = "game world plane master"
	plane = GAME_PLANE
	appearance_flags = PLANE_MASTER //should use client color
	blend_mode = BLEND_OVERLAY
	render_target = GAME_PLANE_RENDER_TARGET

/obj/screen/plane_master/game_world/backdrop(mob/mymob)
	filters = list()
	if(istype(mymob) && mymob.client && mymob.client.prefs && mymob.client.prefs.ambientocclusion)
		filters += AMBIENT_OCCLUSION
	if(istype(mymob) && mymob.eye_blurry)
		filters += GAUSSIAN_BLUR(clamp(mymob.eye_blurry*0.1,0.6,3))


///Contains all lighting objects
/obj/screen/plane_master/lighting
	name = "lighting plane master"
	plane = LIGHTING_PLANE
	blend_mode = BLEND_MULTIPLY
	mouse_opacity = MOUSE_OPACITY_TRANSPARENT

/obj/screen/plane_master/lighting/Initialize()
	. = ..()
	filters += filter(type="alpha", render_source=EMISSIVE_RENDER_TARGET, flags=MASK_INVERSE)
	filters += filter(type="alpha", render_source=EMISSIVE_UNBLOCKABLE_RENDER_TARGET, flags=MASK_INVERSE)
	filters += filter(type="alpha", render_source=SPACE_UNLIT_MASK_RENDER_TARGET, flags=MASK_INVERSE)

/**
  * Where space itself is showing. Doesn't render directly - masks the lighting plane, so space is never shaded, as in
  * tgstation (which draws space to its unlit game plate). Starlight still lights whatever sits on top of it
  * (lattices, catwalks, mobs), since those are on the floor/game planes and cut out of this mask.
  */
/obj/screen/plane_master/space_unlit_mask
	name = "unlit space mask plane master"
	plane = SPACE_UNLIT_MASK_PLANE
	mouse_opacity = MOUSE_OPACITY_TRANSPARENT
	render_target = SPACE_UNLIT_MASK_RENDER_TARGET

/obj/screen/plane_master/space_unlit_mask/Initialize()
	. = ..()
	filters += filter(type="alpha", render_source=FLOOR_PLANE_RENDER_TARGET, flags=MASK_INVERSE)
	filters += filter(type="alpha", render_source=GAME_PLANE_RENDER_TARGET, flags=MASK_INVERSE)

///Copies the space plane onto the unlit space mask plane (every client carries one, see /datum/hud/proc/show_hud())
/obj/screen/space_unlit_relay
	name = "unlit space relay"
	plane = SPACE_UNLIT_MASK_PLANE
	// The copy is drawn from this object's bottom-left corner, so it has to sit in the screen's bottom-left tile to line up
	// ("CENTER" put the mask a half-screen up and right). Same as /obj/starlight_appearance
	screen_loc = "1,1"
	mouse_opacity = MOUSE_OPACITY_TRANSPARENT
	appearance_flags = PASS_MOUSE | NO_CLIENT_COLOR | KEEP_TOGETHER
	render_source = PLANE_SPACE_RENDER_TARGET

GLOBAL_DATUM_INIT(space_unlit_relay, /obj/screen/space_unlit_relay, new)

/**
  * Things placed on this mask the lighting plane. Doesn't render directly.
  *
  * Gets masked by blocking plane. Use for things that you want blocked by
  * mobs, items, etc.
  */
/obj/screen/plane_master/emissive
	name = "emissive plane master"
	plane = EMISSIVE_PLANE
	mouse_opacity = MOUSE_OPACITY_TRANSPARENT
	render_target = EMISSIVE_RENDER_TARGET

/obj/screen/plane_master/emissive/Initialize()
	. = ..()
	filters += filter(type="alpha", render_source=EMISSIVE_BLOCKER_RENDER_TARGET, flags=MASK_INVERSE)

/**
  * Things placed on this always mask the lighting plane. Doesn't render directly.
  *
  * Always masks the light plane, isn't blocked by anything. Use for on mob glows,
  * magic stuff, etc.
  */

/obj/screen/plane_master/emissive_unblockable
	name = "unblockable emissive plane master"
	plane = EMISSIVE_UNBLOCKABLE_PLANE
	mouse_opacity = MOUSE_OPACITY_TRANSPARENT
	render_target = EMISSIVE_UNBLOCKABLE_RENDER_TARGET

/**
  * Things placed on this layer mask the emissive layer. Doesn't render directly
  *
  * You really shouldn't be directly using this, use atom helpers instead
  */
/obj/screen/plane_master/emissive_blocker
	name = "emissive blocker plane master"
	plane = EMISSIVE_BLOCKER_PLANE
	mouse_opacity = MOUSE_OPACITY_TRANSPARENT
	render_target = EMISSIVE_BLOCKER_RENDER_TARGET

///Contains space parallax
/obj/screen/plane_master/parallax
	name = "parallax plane master"
	plane = PLANE_SPACE_PARALLAX
	blend_mode = BLEND_MULTIPLY
	mouse_opacity = MOUSE_OPACITY_TRANSPARENT

/obj/screen/plane_master/parallax_white
	name = "parallax whitifier plane master"
	plane = PLANE_SPACE
	render_target = PLANE_SPACE_RENDER_TARGET

/obj/screen/plane_master/lighting/backdrop(mob/mymob)
	mymob.overlay_fullscreen("lighting_backdrop_lit", /obj/screen/fullscreen/lighting_backdrop/lit)
	mymob.overlay_fullscreen("lighting_backdrop_unlit", /obj/screen/fullscreen/lighting_backdrop/unlit)

/obj/screen/plane_master/camera_static
	name = "camera static plane master"
	plane = CAMERA_STATIC_PLANE
	appearance_flags = PLANE_MASTER
	blend_mode = BLEND_OVERLAY
