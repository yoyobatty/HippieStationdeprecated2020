// Histories: something that happened to the station before this shift, there to see from the first minute. About one round in
// three gets one (none_history in station_looks.dm). Off for now (weight 0, the planned weight beside it) until they're reviewed:
// the admin window still forces them, and STATION_LOOK_WEIGHT turns one on. They change the station for good, so once on they can't be taken off, and
// the admin window locks the slot (slot_locked()). They go on as the round starts, ahead of the shift time and the extras.
// What they leave is the crew's work to put right, the way a mess is: the janitors mop up vines, the engineers lay the floor tiles.

/datum/station_look/history
	slot = LOOK_SLOT_HISTORY
	removable = FALSE
	/// A few floors where it shows best, once it's on: for an admin to look, and tools/keybind_check/station_looks_shots.dm
	var/list/turf/showcase = list()

/// Every floor of the station's rooms, area by area: area -> its floors
/proc/station_look_floors()
	. = list()
	for(var/area_type in GLOB.the_station_areas)
		var/area/A = GLOB.areas_by_type[area_type]
		if(!A || istype(A, /area/solar) || istype(A, /area/space))
			continue
		var/list/floors = list()
		for(var/turf/open/floor/T in A)
			floors += T
		if(length(floors))
			.[A] = floors

/// A floor near the middle of an area, or null
/proc/station_look_middle(area/A)
	var/list/floors = list()
	for(var/turf/open/floor/T in A)
		if(!is_blocked_turf(T, TRUE))
			floors += T
	if(!length(floors))
		return null
	var/sx = 0
	var/sy = 0
	for(var/turf/T as anything in floors)
		sx += T.x
		sy += T.y
	var/turf/best
	var/best_dist
	for(var/turf/T as anything in floors)
		var/dist = abs(T.x - sx / length(floors)) + abs(T.y - sy / length(floors))
		if(!best || dist < best_dist)
			best = T
			best_dist = dist
	return best

// ---- Abandoned: Abandon Station's dirt, dried blood, litter, cobwebs and old remains, at its lightest, nothing wrecked
// (admin/verbs/abandon_station.dm). The last crew left in a hurry, and nobody's cleaned since.

/datum/station_look/history/abandoned
	id = "abandoned"
	name = "Abandoned"
	weight = 0 //1 once reviewed
	news = "The last crew left in a hurry, and nobody's cleaned since."

/datum/station_look/history/abandoned/apply(at_start)
	..()
	INVOKE_ASYNC(GLOBAL_PROC, GLOBAL_PROC_REF(abandon_station), 1, FALSE, null)

// ---- Overgrown: Botany's last crop got loose. Vines creep along the walls and across the floors, thickest near where they started
// (Hydroponics, and a maintenance room or two where something took root), with grass and flowers coming up between, and glowing
// mushrooms in the dark of maintenance. None of it spreads: it's a mess to mop, not a blob.

/obj/effect/decal/cleanable/overgrowth
	name = "creeping vines"
	desc = "Vines have crept across the floor here. A mop gets them up."
	icon = 'icons/effects/spacevines.dmi'
	icon_state = "Light1"
	mergeable_decal = TRUE

/obj/effect/decal/cleanable/overgrowth/Initialize(mapload, thick = FALSE)
	. = ..(mapload) //its second argument is diseases
	icon_state = thick ? pick("Med1", "Med2", "Med3") : pick("Light1", "Light2", "Light3")
	setDir(pick(GLOB.cardinals))

/obj/effect/decal/cleanable/overgrowth/tuft
	name = "weeds"
	desc = "Grass and flowers, coming up through the cracks between the tiles."
	icon = 'icons/obj/flora/ausflora.dmi'
	icon_state = "sparsegrass_1"

/obj/effect/decal/cleanable/overgrowth/tuft/Initialize(mapload, thick = FALSE)
	. = ..(mapload)
	icon_state = pick("sparsegrass_[rand(1, 3)]", "fullgrass_[rand(1, 3)]", "ywflowers_[rand(1, 4)]", "brflowers_[rand(1, 3)]", "ppflowers_[rand(1, 3)]")
	setDir(SOUTH)

/datum/station_look/history/overgrown
	id = "overgrown"
	name = "Overgrown"
	weight = 0 //3 once reviewed
	news = "Botany's last crop got loose: mind the vines."
	/// How far from where it started it reaches, in tiles
	var/reach = 30

/datum/station_look/history/overgrown/apply(at_start)
	..()
	INVOKE_ASYNC(src, PROC_REF(grow))

/datum/station_look/history/overgrown/proc/grow()
	var/list/floors_by_area = station_look_floors()
	var/list/turf/origins = list()
	var/list/maintenance = list()
	for(var/area/A as anything in floors_by_area)
		if(istype(A, /area/hydroponics))
			var/turf/middle = station_look_middle(A)
			if(middle)
				origins += middle
		else if(istype(A, /area/maintenance))
			maintenance += A
	for(var/i in 1 to min(2, length(maintenance)))
		var/turf/middle = station_look_middle(pick_n_take(maintenance))
		if(middle)
			origins += middle
	showcase = origins.Copy()
	var/vines = 0
	var/tufts = 0
	var/shrooms = 0
	for(var/area/A as anything in floors_by_area)
		var/dark = istype(A, /area/maintenance)
		for(var/turf/open/floor/T as anything in floors_by_area[A])
			var/nearest = reach
			for(var/turf/O as anything in origins)
				if(O.z == T.z)
					nearest = min(nearest, get_dist(O, T))
			if(nearest >= reach || is_blocked_turf(T, TRUE))
				continue
			var/closeness = 1 - nearest / reach
			var/walls = 0
			for(var/direction in GLOB.cardinals)
				if(isclosedturf(get_step(T, direction)))
					walls++
			// Along the walls first, then out across the floor
			if(prob(100 * closeness * closeness * (walls ? 0.7 : 0.18)))
				new /obj/effect/decal/cleanable/overgrowth(T, closeness > 0.55)
				vines++
			else if(prob(20 * closeness))
				new /obj/effect/decal/cleanable/overgrowth/tuft(T)
				tufts++
			if(dark && walls && prob(5 * closeness))
				new /obj/structure/glowshroom/single(T)
				shrooms++
		CHECK_TICK
	log_game("Overgrown: [vines] vines, [tufts] weeds, [shrooms] glowshrooms from [length(origins)] places")

// ---- Half-finished refit: the contractors left one department mid-job. In two or three of its rooms a patch of floor is up to the
// plating, with the tiles stacked beside it, and their kit about: sheets, paint, a wet floor sign, cones. Half its walls have had
// the new coat of paint. Laying the tiles back is the engineers' to finish.

/datum/station_look/history/refit
	id = "refit"
	name = "Half-finished refit"
	weight = 0 //3 once reviewed
	/// The department being refitted this time
	var/department
	/// The departments a refit can be in: name -> its areas
	var/static/list/departments = list(
		"Science" = list(/area/science),
		"Cargo" = list(/area/quartermaster),
		"Medbay" = list(/area/medical),
		"Security" = list(/area/security),
		"Service" = list(/area/crew_quarters/bar, /area/crew_quarters/kitchen, /area/hydroponics),
		"the Dormitories" = list(/area/crew_quarters/dorms, /area/crew_quarters/locker, /area/crew_quarters/toilet))
	// Not Engineering: its own floors are as dark as plating, and a patch up in there didn't show at all
	/// The new paint, multiplied into the walls it's on: a cooler, cleaner grey
	var/paint = "#DCE6EE"

/datum/station_look/history/refit/news_line()
	return "The refit of [department || "one department"] was left half done: floors up, paint drying."

/datum/station_look/history/refit/apply(at_start)
	..()
	department = pick(departments)
	INVOKE_ASYNC(src, PROC_REF(refit))

/datum/station_look/history/refit/proc/refit()
	var/list/areas = typecacheof(departments[department])
	var/list/rooms = list() //area -> its clear floors
	var/list/turf/walls = list()
	for(var/area/A as anything in station_look_floors())
		if(!is_type_in_typecache(A, areas))
			continue
		var/list/clear = list()
		for(var/turf/open/floor/T in A)
			if(!is_blocked_turf(T, TRUE) && !isplatingturf(T))
				clear += T
		if(length(clear) >= 12)
			rooms[A] = clear
		for(var/turf/closed/wall/W in A)
			walls += W
	var/patches = 0
	var/pulled = 0
	for(var/i in 1 to min(rand(2, 3), length(rooms)))
		var/area/A = pick(rooms)
		var/list/clear = rooms[A]
		rooms -= A
		var/list/turf/patch = refit_patch(pick(clear), clear, rand(6, 14))
		if(!length(patch))
			continue
		patches++
		showcase += patch[1]
		for(var/turf/open/floor/T as anything in patch)
			T.make_plating()
			pulled++
		// Warning stripes round its edge: a work zone
		for(var/turf/T as anything in patch)
			for(var/direction in GLOB.cardinals)
				if(!(get_step(T, direction) in patch))
					T.AddComponent(/datum/component/decal, 'icons/turf/decals.dmi', "warningline", direction, CLEAN_NEVER, null, null, null, 255)
		var/list/beside = list()
		for(var/turf/open/floor/T as anything in clear)
			if(!(T in patch) && !is_blocked_turf(T, TRUE) && get_dist(T, patch[1]) <= 3)
				beside += T
		if(!length(beside))
			continue
		var/obj/item/stack/tile/plasteel/tiles = new(pick(beside))
		tiles.amount = length(patch)
		tiles.update_icon()
		new /obj/item/stack/sheet/metal/ten(pick(beside))
		var/paint_type = pick(/obj/item/paint/white, /obj/item/paint/blue, /obj/item/paint/green, /obj/item/paint/yellow)
		new paint_type(pick(beside))
		new /obj/item/caution(pick(beside))
		for(var/c in 1 to rand(1, 2))
			new /obj/item/clothing/head/cone(pick(beside))
		CHECK_TICK
	// The new paint: the walls on one side of the department so far
	var/painted = 0
	if(length(walls))
		var/middle = 0
		for(var/turf/W as anything in walls)
			middle += W.x
		middle /= length(walls)
		var/west = prob(50)
		for(var/turf/closed/wall/W as anything in walls)
			if((W.x < middle) == west)
				W.add_atom_colour(paint, FIXED_COLOUR_PRIORITY)
				painted++
	log_game("Half-finished refit of [department]: [pulled] tiles up in [patches] patches, [painted] walls painted")

/// A patch of floor grown out from `start` through `clear`, up to `size` tiles
/datum/station_look/history/refit/proc/refit_patch(turf/start, list/clear, size)
	var/list/turf/patch = list(start)
	var/list/turf/edge = list(start)
	while(length(edge) && length(patch) < size)
		var/turf/T = pick_n_take(edge)
		for(var/direction in GLOB.cardinals)
			var/turf/next = get_step(T, direction)
			if(length(patch) >= size)
				break
			if((next in clear) && !(next in patch) && prob(75))
				patch += next
				edge += next
	return patch

// ---- Second-hand station: Nanotrasen bought the station from somebody else, and their things are still about. Posters of theirs torn
// down, their plaques on the walls, their colours showing through on the floors, and the old crew's lockers left in corners with what
// they didn't take, notes and all. The old owner is made up afresh each round.

/datum/station_look/history/second_hand
	id = "second_hand"
	name = "Second-hand station"
	weight = 0 //3 once reviewed
	/// Who had it before
	var/owner
	var/static/list/owners = list("Kestrel Deepspace Freight", "Halcyon Salvage Co-op", "Tarrow Ore Concern", "Brightwater Orbital Leasing", "Meridian Tug & Tow", "Calloway Survey Corps")

/datum/station_look/history/second_hand/news_line()
	return "Bought second-hand from [owner || "its last owners"]: some of their things are still aboard."

/datum/station_look/history/second_hand/apply(at_start)
	..()
	owner = pick(owners)
	INVOKE_ASYNC(src, PROC_REF(furnish))

/datum/station_look/history/second_hand/proc/furnish()
	var/list/floors_by_area = station_look_floors()
	var/list/turf/hall_walls = list() //a wall beside a hall floor: wall -> TRUE
	var/list/turf/hall_floors = list()
	var/list/turf/corners = list() //floors with walls on two sides, in maintenance and the dorms
	for(var/area/A as anything in floors_by_area)
		var/hall = istype(A, /area/hallway)
		var/out_of_the_way = istype(A, /area/maintenance) || istype(A, /area/crew_quarters/dorms) || istype(A, /area/crew_quarters/locker)
		if(!hall && !out_of_the_way)
			continue
		for(var/turf/open/floor/T as anything in floors_by_area[A])
			var/walls = 0
			for(var/direction in GLOB.cardinals)
				var/turf/W = get_step(T, direction)
				if(iswallturf(W))
					walls++
					if(hall)
						hall_walls[W] = TRUE
			if(hall)
				hall_floors += T
			else if(walls >= 2 && !is_blocked_turf(T, TRUE))
				corners += T
		CHECK_TICK
	var/list/turf/walls = hall_walls.Copy()
	// Their posters, torn down, and a plaque or two of theirs
	var/posters = 0
	for(var/i in 1 to min(rand(8, 12), length(walls)))
		var/turf/W = pick_n_take(walls)
		if(locate(/obj/structure/sign) in W)
			continue
		new /obj/structure/sign/poster/ripped(W)
		posters++
	for(var/i in 1 to min(rand(3, 5), length(walls)))
		var/turf/W = pick_n_take(walls)
		if(locate(/obj/structure/sign) in W)
			continue
		var/obj/structure/sign/plaques/P = new(W)
		P.name = "[owner] plaque"
		P.desc = "\"This station is the property of [owner].\" Somebody's had a go at it with a screwdriver."
	// Their colours: a patch of the old floor trim, here and there along the halls
	var/patches = 0
	var/static/list/trims = list(/obj/effect/turf_decal/tile/brown, /obj/effect/turf_decal/tile/green, /obj/effect/turf_decal/tile/red)
	var/obj/effect/turf_decal/tile/trim = pick(trims)
	for(var/i in 1 to min(rand(5, 8), length(hall_floors)))
		var/turf/centre = pick(hall_floors)
		if(!patches)
			showcase += centre
		for(var/turf/open/floor/T in range(rand(1, 2), centre))
			if((T in hall_floors) && prob(70)) //the decal's own Initialize() can't be given a direction: its component, as it would add
				T.AddComponent(/datum/component/decal, initial(trim.icon), initial(trim.icon_state), pick(GLOB.cardinals), CLEAN_NEVER, initial(trim.color), null, null, initial(trim.alpha))
		patches++
	// The old crew's lockers, with what they left
	var/lockers = 0
	for(var/i in 1 to min(rand(3, 5), length(corners)))
		var/turf/T = pick_n_take(corners)
		if(lockers < 2)
			showcase += T
		var/obj/structure/closet/C = new(T)
		C.name = "old [owner] locker"
		new /obj/item/clothing/under/color/brown(C)
		if(prob(60))
			new /obj/item/clothing/shoes/sneakers/brown(C)
		if(prob(50))
			new /obj/item/stack/spacecash/c10(C)
		var/obj/item/paper/note = new(C)
		note.name = "note from [owner]"
		note.info = pick(
			"To all [owner] hands: the station is sold. Leave the fittings, take your things. The last shuttle goes at 1800.",
			"[owner] crew roster, final week. Half the names are crossed out.",
			"Whoever takes this locker next: the left door sticks. Good luck with the new lot. - one of the old [owner] crew",
			"I.O.U. 40 credits. Pay you back when [owner] pays us. (They never did.)")
		note.update_icon()
		lockers++
	log_game("Second-hand station from [owner]: [posters] torn posters, [patches] patches of old trim, [lockers] lockers left")
