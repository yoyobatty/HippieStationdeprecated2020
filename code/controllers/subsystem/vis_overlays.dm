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
/// hippie -- inherit_dir: the overlay faces whichever way its thing does (VIS_INHERIT_DIR), so turning the thing needs nothing
/// done to it. It's what an emissive blocker wants: every item and simple mob has one, and swapping it for a turned copy at
/// every turn was most of what a thrown item zig-zagging along a diagonal cost.
/datum/controller/subsystem/vis_overlays/proc/add_vis_overlay(atom/movable/thing, icon, iconstate, layer, plane, dir, alpha = 255, add_appearance_flags = NONE, unique = FALSE, bloom = TRUE, inherit_dir = FALSE)
	//hippie edit -- every emissive gets an identical twin on the bloom plane, which is what makes it glow
	if(bloom && (plane == EMISSIVE_PLANE || plane == EMISSIVE_UNBLOCKABLE_PLANE))
		add_vis_overlay(thing, icon, iconstate, layer, EMISSIVE_BLOOM_PLANE, dir, alpha, add_appearance_flags, unique, FALSE, inherit_dir)
	var/obj/effect/overlay/vis/overlay
	if(!unique)
		. = "[icon]|[iconstate]|[layer]|[plane]|[inherit_dir ? "inherit" : dir]|[alpha]|[add_appearance_flags]"
		overlay = vis_overlay_cache[.]
		if(!overlay)
			overlay = _create_new_vis_overlay(icon, iconstate, layer, plane, inherit_dir ? SOUTH : dir, alpha, add_appearance_flags)
			if(inherit_dir)
				overlay.vis_flags |= VIS_INHERIT_DIR
			vis_overlay_cache[.] = overlay
		else
			overlay.unused = 0
	else
		overlay = _create_new_vis_overlay(icon, iconstate, layer, plane, dir, alpha, add_appearance_flags)
		if(inherit_dir)
			overlay.vis_flags |= VIS_INHERIT_DIR
		overlay.cache_expiration = -1 //also how rotate_vis_overlay() tells a unique overlay apart
		var/cache_id = "\ref[overlay]@{[world.time]}"
		vis_overlay_cache[cache_id] = overlay
		. = overlay
	thing.vis_contents += overlay

	if(!isatom(thing)) // Automatic rotation is not supported on non atoms
		return
	if(QDELETED(thing)) // hippie -- its signals were already cleared, so this one stayed in signal_procs for good: a hard delete
		return

	if(!thing.managed_vis_overlays)
		thing.managed_vis_overlays = list(overlay)
	else
		thing.managed_vis_overlays += overlay
	// hippie -- only overlays that have to be turned by hand listen for the thing turning
	if(!(overlay.vis_flags & VIS_INHERIT_DIR) && !thing.vis_overlays_turned++)
		RegisterSignal(thing, COMSIG_ATOM_DIR_CHANGE, PROC_REF(rotate_vis_overlay))

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
	for(var/obj/effect/overlay/vis/overlay in overlays) //not `as anything`: a deleted one leaves a null
		if(!(overlay.vis_flags & VIS_INHERIT_DIR) && (overlay in thing.managed_vis_overlays))
			thing.vis_overlays_turned--
	thing.managed_vis_overlays -= overlays
	if(!length(thing.managed_vis_overlays))
		thing.managed_vis_overlays = null
		thing.vis_overlays_turned = 0
	if(thing.vis_overlays_turned <= 0)
		thing.vis_overlays_turned = 0
		UnregisterSignal(thing, COMSIG_ATOM_DIR_CHANGE)

/datum/controller/subsystem/vis_overlays/proc/rotate_vis_overlay(atom/thing, old_dir, new_dir)
	if(old_dir == new_dir)
		return
	var/rotation = dir2angle(old_dir) - dir2angle(new_dir)
	if(!(rotation % 360)) // hippie -- setDir(null) gets here: each overlay would be swapped for itself, which takes it out of vis_contents and leaves it on managed_vis_overlays for a hard delete later
		return
	var/list/overlays_to_remove = list()
	// Unique overlays (cache_expiration -1) are turned in place, shared cached ones swapped for a turned copy.
	// This used to check a global unique_vis_overlays list, which never let go of them - once one stopped being
	// displayed, fire() deleted it and that list's reference forced a hard delete (tgstation removed it too, #59371).
	for(var/obj/effect/overlay/vis/overlay in thing.managed_vis_overlays) //not `as anything`: a deleted one leaves a null
		if(overlay.vis_flags & VIS_INHERIT_DIR) // hippie -- faces the way its thing does by itself
			continue
		if(overlay.cache_expiration == -1)
			overlay.dir = turn(overlay.dir, rotation)
			continue
		add_vis_overlay(thing, overlay.icon, overlay.icon_state, overlay.layer, overlay.plane, turn(overlay.dir, rotation), overlay.alpha, overlay.appearance_flags, bloom = FALSE) //hippie edit -- the bloom twins are managed overlays too, so they get turned themselves
		overlays_to_remove += overlay
	remove_vis_overlay(thing, overlays_to_remove)
