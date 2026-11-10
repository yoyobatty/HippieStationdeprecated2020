// Screen objects shown in a second map control inside a window, such as the camera console's picture (ported from tgstation's
// code/_onclick/hud/map_popups.dm, 2020). Each names the map control it belongs to; a client keeps them by map, so closing the
// window can take them all off its screen again.

/obj/screen
	/// The map control this is shown in, when it isn't the main one
	var/assigned_map
	/// Whether it's deleted when its map is cleared from a client
	var/del_on_map_removal = TRUE

/// Puts a fill of this one icon over the map's tiles from x1,y1 to x2,y2
/obj/screen/proc/fill_rect(x1, y1, x2, y2)
	screen_loc = "[assigned_map]:[x1],[y1] to [x2],[y2]"

/client
	/// Map control name -> the screen objects shown in it
	var/list/screen_maps = list()

/client/proc/register_map_obj(obj/screen/screen_obj)
	if(!screen_obj.assigned_map)
		CRASH("Can't register [screen_obj] without an assigned_map")
	var/list/screen_map = screen_maps[screen_obj.assigned_map]
	if(!screen_map)
		screen_map = list()
		screen_maps[screen_obj.assigned_map] = screen_map
	screen_map |= screen_obj
	screen |= screen_obj

/client/proc/clear_map(map_name)
	if(!map_name || !(map_name in screen_maps))
		return FALSE
	for(var/obj/screen/screen_obj as anything in screen_maps[map_name])
		screen -= screen_obj
		if(screen_obj.del_on_map_removal)
			qdel(screen_obj)
	screen_maps -= map_name
	return TRUE

/client/proc/clear_all_maps()
	for(var/map_name in screen_maps)
		clear_map(map_name)

/// The smallest box around these atoms, as list(lowest x, lowest y, highest x, highest y)
/proc/get_bbox_of_atoms(list/atoms)
	var/list/box = list(world.maxx, world.maxy, 1, 1)
	for(var/atom/A as anything in atoms)
		box[1] = min(box[1], A.x)
		box[2] = min(box[2], A.y)
		box[3] = max(box[3], A.x)
		box[4] = max(box[4], A.y)
	return box

/// The planes a camera doesn't pass on: the goggles' thermal and T-ray overlays, the AI's static
GLOBAL_LIST_INIT(map_view_hidden_planes, list(THERMAL_GLOW_PLANE, THERMAL_TINT_PLANE, T_RAY_GLOW_PLANE, CAMERA_STATIC_PLANE))
/// Every map_view_starlight, retinted with the main one (set_starlight())
GLOBAL_LIST_EMPTY(map_view_starlights)

/**
  * The starlight a map of the world's space tiles mirror: what lights lattices, catwalks and grilles out in space. Their overlays
  * read the "*starlight" render target, and the one on the main map (GLOB.starlight_object) doesn't reach another map: seen
  * 2026-11-10, a camera's picture had them dark. A copy on the map itself, kept the main one's colour.
  */
/obj/screen/map_view_starlight
	mouse_opacity = MOUSE_OPACITY_TRANSPARENT

/obj/screen/map_view_starlight/Initialize(mapload)
	. = ..()
	appearance = GLOB.starlight_object.appearance
	GLOB.map_view_starlights += src

/obj/screen/map_view_starlight/Destroy()
	GLOB.map_view_starlights -= src
	return ..()

/**
  * A viewer's own plane masters copied for a map control of the world, so a camera's picture looks the way the viewer's own view
  * would from where the camera is, with their preferences: ambient occlusion, bloom, the softened light, parallax on or off.
  * Render targets are named per client and every map of the client shares them, so each copy's is renamed for this map, and so is
  * every filter that reads one. What the viewer's own eyes add is left off: goggles' overlays and the AI's static are hidden,
  * night vision's darkness and blurred eyes go back to plain sight. With the black behind the light and the relay that cuts space
  * out of the darkness, as the main view has. Null for a viewer with no HUD to copy (map_view_plane_masters() is for them).
  */
/proc/map_view_planes_for(mob/viewer, map_name)
	var/datum/hud/hud = viewer?.hud_used
	if(!length(hud?.plane_masters))
		return null
	var/suffix = "_[map_name]"
	var/list/renamed = list()
	for(var/key in hud.plane_masters)
		var/obj/screen/plane_master/from = hud.plane_masters[key]
		if(from.render_target)
			renamed[from.render_target] = "[from.render_target][suffix]"
	. = list()
	for(var/key in hud.plane_masters)
		var/obj/screen/plane_master/from = hud.plane_masters[key]
		var/obj/screen/plane_master/P = new
		P.appearance = from.appearance
		P.render_target = renamed[from.render_target]
		var/list/kept = list()
		for(var/F in P.filters)
			if(P.plane == GAME_PLANE && F:type == "blur") //the viewer's blurred eyes (game_world/backdrop())
				continue
			kept += F
		P.filters = kept
		for(var/F in P.filters)
			if(!(F:type in list("alpha", "layer", "displace"))) // the kinds with a render_source: reading it on the rest is a runtime
				continue
			if(F:render_source && renamed[F:render_source])
				F:render_source = renamed[F:render_source]
		if(P.plane in GLOB.map_view_hidden_planes)
			P.alpha = 0
		else if(P.plane == LIGHTING_PLANE)
			P.alpha = LIGHTING_PLANE_ALPHA_VISIBLE
			P.color = null //eye adaptation: the camera's own is put on by map_view_expose()
		P.mouse_opacity = MOUSE_OPACITY_TRANSPARENT
		P.screen_loc = "[map_name]:CENTER"
		. += P

	// The darkness behind the light map (fullscreen.dm lighting_backdrop/lit)
	var/obj/screen/backdrop = new
	backdrop.name = "lighting backdrop"
	backdrop.icon = 'icons/mob/screen_gen.dmi'
	backdrop.icon_state = "flash"
	backdrop.color = "#000"
	backdrop.transform = matrix(200, 0, 0, 0, 200, 0)
	backdrop.plane = LIGHTING_PLANE
	backdrop.layer = BACKGROUND_LAYER + 21
	backdrop.mouse_opacity = MOUSE_OPACITY_TRANSPARENT
	backdrop.screen_loc = "[map_name]:CENTER"
	. += backdrop

	// Where space shows, copied onto the unlit space mask (plane_master.dm space_unlit_relay), from the map's bottom-left tile
	var/obj/screen/relay = new
	relay.name = "unlit space relay"
	relay.plane = SPACE_UNLIT_MASK_PLANE
	relay.appearance_flags = PASS_MOUSE | NO_CLIENT_COLOR | KEEP_TOGETHER
	relay.render_source = renamed[PLANE_SPACE_RENDER_TARGET]
	relay.mouse_opacity = MOUSE_OPACITY_TRANSPARENT
	relay.screen_loc = "[map_name]:1,1"
	. += relay

	var/obj/screen/map_view_starlight/starlight = new
	starlight.screen_loc = "[map_name]:1,1"
	. += starlight

	for(var/obj/screen/S as anything in .)
		S.assigned_map = map_name

/// Turns a copied lighting plane (map_view_planes_for()) up as eye adaptation does for a player who's stood a while at `eye`, if the
/// viewer's eyes adapt (Graphics Medium and up). Animated over `time`: the picture refreshes every couple of seconds.
/proc/map_view_expose(obj/screen/plane_master/lighting_copy, mob/viewer, turf/eye, time = 0)
	var/exposure = 1
	if(eye && (!viewer?.client?.prefs || viewer.client.prefs.graphics_quality() >= GRAPHICS_QUALITY_MEDIUM) && !(SSeye_adapt.engine_cant && SSlighting.native))
		var/brightness = SSeye_adapt.eye_brightness_at(eye, 7, 7)
		if(brightness >= 0)
			exposure = clamp(EYE_ADAPT_KEY / max(brightness, 0.01), 1, EYE_ADAPT_MAX)
	var/list/matrix = exposure == 1 ? null : list(exposure, 0, 0, 0, exposure, 0, 0, 0, exposure, 0, 0, 0)
	if(time)
		animate(lighting_copy, color = matrix, time = time)
	else
		lighting_copy.color = matrix

/**
  * The viewer's own sky for a map control of the world: the round's layers as their Parallax and Graphics preferences pick them, in
  * a holder like their screen's (parallax.dm). Null with parallax off. map_view_place_sky() puts it where the camera is.
  */
/proc/map_view_sky_for(mob/viewer, map_name)
	var/client/C = viewer?.client
	if(!C || !SSparallax.theme)
		return null
	var/detail = C.prefs?.parallax
	if(isnull(detail))
		detail = PARALLAX_HIGH
	if(detail == PARALLAX_DISABLE)
		return null
	var/quality = C.prefs ? C.prefs.graphics_quality() : GRAPHICS_QUALITY_HIGH
	var/obj/screen/parallax_home/home = new
	home.assigned_map = map_name
	var/list/layers = list()
	for(var/obj/screen/parallax_layer/L as anything in SSparallax.theme.build_layers())
		if(detail > L.detail || quality < L.quality)
			qdel(L)
			continue
		L.set_quality(quality)
		layers += L
	home.vis_contents = layers
	return home

/// Lays a sky from map_view_sky_for() out as a player's would be with their eye on `eye`: the holder 7 tiles down and left of it, as
/// on a screen, in a map whose tile 1,1 shows map tile (corner_x, corner_y). Repeating layers sit at the same place in their repeat
/// for everyone at that spot; a camera on a shuttle in flight has its sky streaming past.
/proc/map_view_place_sky(obj/screen/parallax_home/home, turf/eye, corner_x, corner_y)
	if(!home || !eye)
		return
	var/px = (eye.x - 7 - corner_x) * world.icon_size
	var/py = (eye.y - 7 - corner_y) * world.icon_size
	home.screen_loc = "[home.assigned_map]:1:[px],1:[py]"
	var/area/A = eye.loc
	for(var/obj/screen/parallax_layer/L as anything in home.vis_contents)
		L.update_status(eye)
		var/new_x
		var/new_y
		if(L.absolute)
			new_x = L.place_x(eye.x)
			new_y = L.place_y(eye.y)
		else
			// From the middle of the map, so the same spot shows the same sky to all; the art repeats, so only where in a repeat counts
			var/half = L.period / 2
			new_x = initial(L.offset_x) - (eye.x - world.maxx / 2) * L.speed
			new_y = initial(L.offset_y) - (eye.y - world.maxy / 2) * L.speed
			if(istype(L, /obj/screen/parallax_layer/nebula))
				var/obj/screen/parallax_layer/nebula/cloud = L
				var/list/shift = SSparallax.nebula_shifts[cloud.index]
				new_x += shift[1]
				new_y += shift[2]
			new_x -= round((new_x + half) / L.period) * L.period
			new_y -= round((new_y + half) / L.period) * L.period
		L.offset_x = new_x
		L.offset_y = new_y
		L.pixel_w = round(new_x, 1)
		L.pixel_z = round(new_y, 1)
		if(A?.parallax_movedir) // as set_parallax_movedir() loops it once up to speed
			var/matrix/away = L.one_repeat_away(A.parallax_movedir)
			animate(L, transform = away, time = 0, loop = -1, flags = ANIMATION_END_NOW)
			animate(transform = matrix(), time = L.loop_time() / 2)
		else
			animate(L, transform = matrix(), time = 0, flags = ANIMATION_END_NOW)

/**
  * Plane masters for a map control of the world (the camera console's picture), for a viewer with no HUD of their own to copy
  * (map_view_planes_for()). The main map's can't be reused: render targets
  * are named per client, so a second set with the same names would cross the two maps' masks. These have names of their own.
  * Floors and objects draw as usual, the darkness is cut by the map's own emissives and their bloom is added, and the goggles'
  * thermal and T-ray overlays and the AI's camera static are hidden (they don't come through a camera). Space is cut out of the
  * darkness as in the main view (plane_master.dm space_unlit_mask): without that, every space tile in the picture was black.
  */
/proc/map_view_plane_masters(map_name)
	var/suffix = "_[map_name]"
	var/list/masters = list()
	var/obj/screen/plane_master/P

	// Named without a "*" so they still draw: the space mask below is cut by them
	P = new
	P.name = "floor plane master"
	P.plane = FLOOR_PLANE
	P.render_target = "cam_floor[suffix]"
	masters += P

	P = new
	P.name = "game world plane master"
	P.plane = GAME_PLANE
	P.render_target = "cam_game[suffix]"
	masters += P

	P = new
	P.name = "space plane master"
	P.plane = PLANE_SPACE
	P.render_target = "cam_space[suffix]"
	masters += P

	// Where space shows, less what's on it (lattices, catwalks, mobs, which starlight still lights): keeps the darkness off it
	P = new
	P.name = "unlit space mask plane master"
	P.plane = SPACE_UNLIT_MASK_PLANE
	P.render_target = "*cam_space_unlit[suffix]"
	P.filters += filter(type = "alpha", render_source = "cam_floor[suffix]", flags = MASK_INVERSE)
	P.filters += filter(type = "alpha", render_source = "cam_game[suffix]", flags = MASK_INVERSE)
	masters += P

	// Copies the space plane onto the mask, from the map's bottom-left tile as the main view's relay does
	var/obj/screen/relay = new
	relay.name = "unlit space relay"
	relay.plane = SPACE_UNLIT_MASK_PLANE
	relay.appearance_flags = PASS_MOUSE | NO_CLIENT_COLOR | KEEP_TOGETHER
	relay.render_source = "cam_space[suffix]"
	relay.mouse_opacity = MOUSE_OPACITY_TRANSPARENT
	relay.assigned_map = map_name
	relay.del_on_map_removal = FALSE
	relay.screen_loc = "[map_name]:1,1"

	P = new
	P.name = "emissive blocker plane master"
	P.plane = EMISSIVE_BLOCKER_PLANE
	P.render_target = "*cam_blocker[suffix]"
	P.filters += filter(type = "alpha", render_source = "*cam_unblockable[suffix]", flags = MASK_INVERSE) // as the main view's (emissive_glow.dm)
	masters += P

	P = new
	P.name = "emissive plane master"
	P.plane = EMISSIVE_PLANE
	P.render_target = "*cam_emissive[suffix]"
	P.filters += filter(type = "alpha", render_source = "*cam_blocker[suffix]", flags = MASK_INVERSE)
	masters += P

	P = new
	P.name = "unblockable emissive plane master"
	P.plane = EMISSIVE_UNBLOCKABLE_PLANE
	P.render_target = "*cam_unblockable[suffix]"
	masters += P

	P = new
	P.name = "light glow plane master" // the pools of light that pulse: hidden, and added into the lighting below (light_glow.dm)
	P.plane = LIGHT_GLOW_PLANE
	P.render_target = "*cam_glow[suffix]"
	masters += P

	P = new
	P.name = "lighting plane master"
	P.plane = LIGHTING_PLANE
	P.blend_mode = BLEND_MULTIPLY
	P.filters += filter(type = "layer", render_source = "*cam_glow[suffix]", blend_mode = BLEND_ADD)
	P.filters += filter(type = "alpha", render_source = "*cam_emissive[suffix]", flags = MASK_INVERSE)
	P.filters += filter(type = "alpha", render_source = "*cam_unblockable[suffix]", flags = MASK_INVERSE)
	P.filters += filter(type = "alpha", render_source = "*cam_space_unlit[suffix]", flags = MASK_INVERSE)
	masters += P

	P = new
	P.name = "emissive bloom plane master"
	P.plane = EMISSIVE_BLOOM_PLANE
	P.blend_mode = BLEND_ADD
	P.filters += filter(type = "alpha", render_source = "*cam_blocker[suffix]", flags = MASK_INVERSE)
	P.filters += filter(type = "bloom", threshold = COLOR_BLACK, size = 2, offset = 1)
	P.filters += filter(type = "alpha", render_source = "*cam_emissive[suffix]", flags = MASK_INVERSE)
	P.filters += filter(type = "alpha", render_source = "*cam_unblockable[suffix]", flags = MASK_INVERSE)
	masters += P

	for(var/hidden in list(THERMAL_GLOW_PLANE, THERMAL_TINT_PLANE, T_RAY_GLOW_PLANE, CAMERA_STATIC_PLANE))
		P = new
		P.name = "hidden plane master"
		P.plane = hidden
		P.alpha = 0
		masters += P

	for(var/obj/screen/plane_master/master as anything in masters)
		master.mouse_opacity = MOUSE_OPACITY_TRANSPARENT
		master.assigned_map = map_name
		master.del_on_map_removal = FALSE
		master.screen_loc = "[map_name]:CENTER"
	masters += relay
	return masters
