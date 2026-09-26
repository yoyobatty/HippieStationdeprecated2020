SUBSYSTEM_DEF(vis_overlays)
	name = "Vis contents overlays"
	wait = 1 MINUTES
	priority = FIRE_PRIORITY_VIS
	init_order = INIT_ORDER_VIS

	var/list/vis_overlay_cache
	var/list/currentrun

/datum/controller/subsystem/vis_overlays/Initialize()
	vis_overlay_cache = list()
	return ..()

/datum/controller/subsystem/vis_overlays/fire(resumed = FALSE)
	if(!resumed)
		currentrun = vis_overlay_cache.Copy()
	var/list/current_run = currentrun

	while(current_run.len)
		var/key = current_run[current_run.len]
		var/obj/effect/overlay/vis/overlay = current_run[key]
		current_run.len--
		if(!overlay.unused && !length(overlay.vis_locs))
			overlay.unused = world.time
		else if(overlay.unused && overlay.unused + overlay.cache_expiration < world.time)
			vis_overlay_cache -= key
			qdel(overlay)
		if(MC_TICK_CHECK)
			return

//the "thing" var can be anything with vis_contents which includes images
/datum/controller/subsystem/vis_overlays/proc/add_vis_overlay(atom/movable/thing, icon, iconstate, layer, plane, dir, alpha = 255, add_appearance_flags = NONE, unique = FALSE, bloom = TRUE)
	//hippie edit -- every emissive gets an identical twin on the bloom plane, which is what makes it glow
	if(bloom && (plane == EMISSIVE_PLANE || plane == EMISSIVE_UNBLOCKABLE_PLANE))
		add_vis_overlay(thing, icon, iconstate, layer, EMISSIVE_BLOOM_PLANE, dir, alpha, add_appearance_flags, unique, FALSE)
	var/obj/effect/overlay/vis/overlay
	if(!unique)
		. = "[icon]|[iconstate]|[layer]|[plane]|[dir]|[alpha]|[add_appearance_flags]"
		overlay = vis_overlay_cache[.]
		if(!overlay)
			overlay = _create_new_vis_overlay(icon, iconstate, layer, plane, dir, alpha, add_appearance_flags)
			vis_overlay_cache[.] = overlay
		else
			overlay.unused = 0
	else
		overlay = _create_new_vis_overlay(icon, iconstate, layer, plane, dir, alpha, add_appearance_flags)
		overlay.cache_expiration = -1 //also how rotate_vis_overlay() tells a unique overlay apart
		var/cache_id = "\ref[overlay]@{[world.time]}"
		vis_overlay_cache[cache_id] = overlay
		. = overlay
	thing.vis_contents += overlay

	if(!isatom(thing)) // Automatic rotation is not supported on non atoms
		return

	if(!thing.managed_vis_overlays)
		thing.managed_vis_overlays = list(overlay)
		RegisterSignal(thing, COMSIG_ATOM_DIR_CHANGE, PROC_REF(rotate_vis_overlay))
	else
		thing.managed_vis_overlays += overlay

/datum/controller/subsystem/vis_overlays/proc/_create_new_vis_overlay(icon, iconstate, layer, plane, dir, alpha, add_appearance_flags)
	var/obj/effect/overlay/vis/overlay = new
	overlay.icon = icon
	overlay.icon_state = iconstate
	overlay.layer = layer
	overlay.plane = plane
	overlay.dir = dir
	overlay.alpha = alpha
	overlay.appearance_flags |= add_appearance_flags
	return overlay


/datum/controller/subsystem/vis_overlays/proc/remove_vis_overlay(atom/movable/thing, list/overlays)
	thing.vis_contents -= overlays
	if(!isatom(thing))
		return
	thing.managed_vis_overlays -= overlays
	if(!length(thing.managed_vis_overlays))
		thing.managed_vis_overlays = null
		UnregisterSignal(thing, COMSIG_ATOM_DIR_CHANGE)

/datum/controller/subsystem/vis_overlays/proc/rotate_vis_overlay(atom/thing, old_dir, new_dir)
	if(old_dir == new_dir)
		return
	var/rotation = dir2angle(old_dir) - dir2angle(new_dir)
	var/list/overlays_to_remove = list()
	// Unique overlays (cache_expiration -1) are turned in place, shared cached ones swapped for a turned copy.
	// This used to check a global unique_vis_overlays list, which never let go of them - once one stopped being
	// displayed, fire() deleted it and that list's reference forced a hard delete (tgstation removed it too, #59371).
	for(var/obj/effect/overlay/vis/overlay as anything in thing.managed_vis_overlays)
		if(overlay.cache_expiration == -1)
			overlay.dir = turn(overlay.dir, rotation)
			continue
		add_vis_overlay(thing, overlay.icon, overlay.icon_state, overlay.layer, overlay.plane, turn(overlay.dir, rotation), overlay.alpha, overlay.appearance_flags, bloom = FALSE) //hippie edit -- the bloom twins are managed overlays too, so they get turned themselves
		overlays_to_remove += overlay
	remove_vis_overlay(thing, overlays_to_remove)
