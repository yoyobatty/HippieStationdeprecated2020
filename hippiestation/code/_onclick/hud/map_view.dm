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

/**
  * Plane masters for a map control of the world (the camera console's picture). The main map's can't be reused: render targets
  * are named per client, so a second set with the same names would cross the two maps' masks. These have names of their own.
  * Floors and objects draw as usual, the darkness is cut by the map's own emissives and their bloom is added, and the goggles'
  * thermal and T-ray overlays and the AI's camera static are hidden (they don't come through a camera).
  */
/proc/map_view_plane_masters(map_name)
	var/suffix = "_[map_name]"
	var/list/masters = list()
	var/obj/screen/plane_master/P

	P = new
	P.name = "floor plane master"
	P.plane = FLOOR_PLANE
	masters += P

	P = new
	P.name = "game world plane master"
	P.plane = GAME_PLANE
	masters += P

	P = new
	P.name = "emissive blocker plane master"
	P.plane = EMISSIVE_BLOCKER_PLANE
	P.render_target = "*cam_blocker[suffix]"
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
	P.name = "lighting plane master"
	P.plane = LIGHTING_PLANE
	P.blend_mode = BLEND_MULTIPLY
	P.filters += filter(type = "alpha", render_source = "*cam_emissive[suffix]", flags = MASK_INVERSE)
	P.filters += filter(type = "alpha", render_source = "*cam_unblockable[suffix]", flags = MASK_INVERSE)
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

	for(var/hidden in list(SPACE_UNLIT_MASK_PLANE, THERMAL_GLOW_PLANE, THERMAL_TINT_PLANE, T_RAY_GLOW_PLANE, CAMERA_STATIC_PLANE))
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
	return masters
