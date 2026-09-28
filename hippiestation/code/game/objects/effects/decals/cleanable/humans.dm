/obj/effect/decal/cleanable/blood
	plane = -1
	random_jitter = TRUE

/obj/effect/decal/cleanable/blood/tracks
	random_jitter = FALSE

/obj/effect/decal/cleanable/blood/footprints
	random_jitter = FALSE

/// Sprays a splatter of this mob's blood up to `range` tiles in `direction`, bloodying what it passes over and splashing onto walls.
/// Returns the splatter, or null if the mob has no ordinary blood to spray.
/mob/living/proc/spray_hit_blood(direction, range)
	var/list/blood_dna = get_blood_dna_list()
	if(!length(blood_dna) || !isturf(loc))
		return
	if(!direction)
		direction = pick(GLOB.alldirs)
	var/obj/effect/decal/cleanable/blood/hitsplatter/B = new(loc, get_static_viruses(), blood_dna)
	B.GoTo(get_ranged_target_turf(src, direction, range), range)
	return B

/obj/effect/decal/cleanable/blood/hitsplatter
	name = "blood splatter"
	pass_flags = PASSTABLE | PASSGRILLE
	icon = 'hippiestation/icons/effects/blood.dmi'
	icon_state = "hitsplatter1"
	random_icon_states = list("hitsplatter1", "hitsplatter2", "hitsplatter3")
	layer = ABOVE_MOB_LAYER //it's in the air, so draw it over people
	mergeable_decal = FALSE //shotgun pellets can put several on one tile at once
	random_jitter = FALSE
	var/skip = FALSE //Skip creation of blood when destroyed?
	var/amount = 3 //how many things we can bloody before we run dry

/obj/effect/decal/cleanable/blood/hitsplatter/Initialize(mapload, list/datum/disease/diseases, list/blood_dna)
	add_blood_DNA(blood_dna)
	return ..(mapload, diseases)

/obj/effect/decal/cleanable/blood/hitsplatter/proc/GoTo(turf/T, range, speed = 1)
	set waitfor = FALSE
	set_glide_size(DELAY_TO_GLIDE_SIZE(speed))
	for(var/i in 1 to range)
		step_towards(src, T)
		sleep(speed) //higher = slower
		if(QDELETED(src)) //splashed against something solid
			return
		for(var/atom/A in loc)
			if(isitem(A) || ishuman(A))
				splash(A)
		if(amount <= 0) // we used all the puff so we delete it.
			break
	qdel(src)

/obj/effect/decal/cleanable/blood/hitsplatter/proc/splash(atom/A)
	var/list/blood_dna = return_blood_DNA()
	if(ishuman(A))
		var/mob/living/carbon/human/H = A
		if(H.wear_suit)
			H.wear_suit.add_blood_DNA(blood_dna)
			H.update_inv_wear_suit()    //updates mob overlays to show the new blood (no refresh)
		if(H.w_uniform)
			H.w_uniform.add_blood_DNA(blood_dna)
			H.update_inv_w_uniform()    //updates mob overlays to show the new blood (no refresh)
	else
		A.add_blood_DNA(blood_dna)
	amount--

/obj/effect/decal/cleanable/blood/hitsplatter/Bump(atom/A)
	if(ishuman(A))
		splash(A)
	else if(isclosedturf(A))
		new /obj/effect/decal/cleanable/blood/wall_splatter(loc, null, get_dir(loc, A), return_blood_DNA())
		skip = TRUE
	else
		A.add_blood_DNA(return_blood_DNA())
	qdel(src)

/obj/effect/decal/cleanable/blood/hitsplatter/Destroy()
	if(isturf(loc) && !skip)
		var/list/blood_dna = return_blood_DNA()
		if(length(blood_dna))
			loc.add_blood_DNA(blood_dna)
	return ..()

/// Blood that hit a wall. It lives on the tile in front of the wall, shifted onto the wall's face.
/obj/effect/decal/cleanable/blood/wall_splatter
	name = "blood splatter"
	desc = "Something hit this wall hard. And wet."
	icon_state = "gibbl1"
	random_icon_states = list("gibbl1", "gibbl2", "gibbl3", "gibbl4", "gibbl5")
	bloodiness = 0 //it's on the wall, so you can't step in it
	random_jitter = FALSE

/obj/effect/decal/cleanable/blood/wall_splatter/Initialize(mapload, list/datum/disease/diseases, wall_dir, list/blood_dna)
	if(wall_dir & NORTH)
		pixel_y = world.icon_size
	else if(wall_dir & SOUTH)
		pixel_y = -world.icon_size
	if(wall_dir & EAST)
		pixel_x = world.icon_size
	else if(wall_dir & WEST)
		pixel_x = -world.icon_size
	add_blood_DNA(blood_dna) //before ..() so it carries over if we merge into a splatter already on this wall
	return ..(mapload, diseases)

/obj/effect/decal/cleanable/blood/wall_splatter/replace_decal(obj/effect/decal/cleanable/C)
	if(C.pixel_x != pixel_x || C.pixel_y != pixel_y) //that one's on a different wall
		return FALSE
	return ..()
