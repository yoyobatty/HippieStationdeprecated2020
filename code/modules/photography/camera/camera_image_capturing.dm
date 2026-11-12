/obj/effect/appearance_clone

/obj/effect/appearance_clone/New(loc, atom/A)			//Intentionally not Initialize(), to make sure the clone assumes the intended appearance in time for the camera getFlatIcon.
	if(istype(A))
		appearance = A.appearance
		dir = A.dir
		if(ismovable(A))
			var/atom/movable/AM = A
			step_x = AM.step_x
			step_y = AM.step_y
	. = ..()

// hippie start -- a photo of a pile drew every thing in it: an appearance clone, an insertion sort and a getFlatIcon() each, and
// 2,000 shards on a tile are 2,000 flattens for pixels the top of the pile covers. Each tile now draws its top CAMERA_TILE_DRAWN
// movables: the highest layers first and, within a layer, the last to arrive (BYOND draws those on top).
#define CAMERA_TILE_DRAWN 16

/// The movables on T a photo draws, in no particular order (camera_get_icon() sorts them by layer)
/obj/item/camera/proc/photo_draws_on(turf/T)
	. = list()
	var/list/by_layer = list()
	var/count = 0
	for(var/atom/movable/A as anything in LOOP_CONTENTS(T))
		if(A.invisibility && !(see_ghosts && isobserver(A)))
			continue
		count++
		var/key = "[A.layer]"
		var/list/these = by_layer[key]
		if(!these)
			these = list()
			by_layer[key] = these
		these += A
	if(count <= CAMERA_TILE_DRAWN)
		for(var/key in by_layer)
			. += by_layer[key]
		return
	var/list/layers = list()
	for(var/key in by_layer)
		layers += text2num(key)
	sortTim(layers, GLOBAL_PROC_REF(cmp_numeric_dsc))
	var/left = CAMERA_TILE_DRAWN
	for(var/layer in layers)
		var/list/these = by_layer["[layer]"]
		if(length(these) > left)
			these = these.Copy(length(these) - left + 1)
		. += these
		left -= length(these)
		if(left <= 0)
			break

#undef CAMERA_TILE_DRAWN

/// getFlatIcon() of what a photo draws, kept by appearance. Every photo flattened every dressed crewmember in it afresh, ~20
/// Blend()s apiece: most of a photo's cost. BYOND appearances are shared, so two atoms that look the same have the same one, an
/// appearance clone has its original's, and anything that changes how it looks has a new one. The oldest half goes at 512.
GLOBAL_LIST_EMPTY(photo_flat_icons)

/obj/item/camera/proc/photo_flat_icon(atom/A)
	var/key = A.appearance
	var/icon/flat = GLOB.photo_flat_icons[key]
	if(flat)
		return flat
	flat = getFlatIcon(A)
	if(!flat)
		return
	if(length(GLOB.photo_flat_icons) >= 512)
		GLOB.photo_flat_icons.Cut(1, 257)
	GLOB.photo_flat_icons[key] = flat
	return flat
// hippie end

/obj/item/camera/proc/camera_get_icon(list/turfs, turf/center, psize_x = 96, psize_y = 96, datum/turf_reservation/clone_area, size_x, size_y, total_x, total_y)
	var/list/atoms = list()
	var/skip_normal = FALSE
	var/wipe_atoms = FALSE

	if(istype(clone_area) && total_x == clone_area.width && total_y == clone_area.height && size_x >= 0 && size_y > 0)
		var/cloned_center_x = round(clone_area.bottom_left_coords[1] + ((total_x - 1) / 2))
		var/cloned_center_y = round(clone_area.bottom_left_coords[2] + ((total_y - 1) / 2))
		for(var/t in turfs)
			var/turf/T = t
			var/offset_x = T.x - center.x
			var/offset_y = T.y - center.y
			var/turf/newT = locate(cloned_center_x + offset_x, cloned_center_y + offset_y, clone_area.bottom_left_coords[3])
			if(!(newT in clone_area.reserved_turfs))		//sanity check so we don't overwrite other areas somehow
				continue
			atoms += new /obj/effect/appearance_clone(newT, T)
			if(T.loc.icon_state)
				atoms += new /obj/effect/appearance_clone(newT, T.loc)
			for(var/atom/A as anything in photo_draws_on(T)) // hippie -- the top of a pile, not all of it
				atoms += new /obj/effect/appearance_clone(newT, A)
		skip_normal = TRUE
		wipe_atoms = TRUE
		center = locate(cloned_center_x, cloned_center_y, clone_area.bottom_left_coords[3])

	if(!skip_normal)
		for(var/i in turfs)
			var/turf/T = i
			atoms += T
			atoms += photo_draws_on(T) // hippie -- the top of a pile, not all of it
			CHECK_TICK

	atomslist = atoms.Copy() // hippie -- mgs box disguising
	var/icon/res = icon('icons/effects/96x96.dmi', "")
	res.Scale(psize_x, psize_y)

	var/list/sorted = list()
	var/j
	for(var/i in 1 to atoms.len)
		var/atom/c = atoms[i]
		for(j = sorted.len, j > 0, --j)
			var/atom/c2 = sorted[j]
			if(c2.layer <= c.layer)
				break
		sorted.Insert(j+1, c)
		CHECK_TICK

	var/xcomp = FLOOR(psize_x / 2, 1) - 15
	var/ycomp = FLOOR(psize_y / 2, 1) - 15


	for(var/atom/A in sorted)
		var/xo = (A.x - center.x) * world.icon_size + A.pixel_x + xcomp
		var/yo = (A.y - center.y) * world.icon_size + A.pixel_y + ycomp
		if(ismovable(A))
			var/atom/movable/AM = A
			xo += AM.step_x
			yo += AM.step_y
		var/icon/img = photo_flat_icon(A) // hippie -- kept by appearance, see below
		if(img)
			res.Blend(img, blendMode2iconMode(A.blend_mode), xo, yo)
		CHECK_TICK

	if(!silent)
		if(istype(custom_sound))				//This is where the camera actually finishes its exposure.
			playsound(loc, custom_sound, 75, 1, -3)
		else
			playsound(loc, pick('sound/items/polaroid1.ogg', 'sound/items/polaroid2.ogg'), 75, 1, -3)

	if(wipe_atoms)
		QDEL_LIST(atoms)

	return res
