// Random maintenance rooms: small maint nooks marked on the station map get a random room loaded into them each round.
//
// Mapping one: clear the nook down to its floor (keep landmarks, cables and pipes), put the right size of
// /obj/effect/landmark/maint_room on its bottom-left tile, and make sure every room in that size's pool fits.
// Rooms live in _maps/RandomRooms/: area /area/template_noop so the nook keeps the station's area, and
// /turf/template_noop wherever the map's own floor should stay (plain plating). Include the nook's original
// contents as one of the options, so rounds where it looks like it always did still come up.

#define MAINT_ROOMS_PATH "_maps/RandomRooms/"

/// Room size ("[width]x[height]") -> list(room file = weight)
GLOBAL_LIST_INIT(maint_rooms, list(
	"3x3" = list(
		"maint_3x3_basic.dmm" = 3, // the original nook
		"maint_3x3_jani.dmm" = 1, // janitor's forgotten closet
		"maint_3x3_medi.dmm" = 1, // back-alley surgery
		"maint_3x3_squatter.dmm" = 1, // someone lives here
		"maint_3x3_casino.dmm" = 1, // back-room poker
		"maint_3x3_growop.dmm" = 1, // hidden grow-op
		"maint_3x3_spiders.dmm" = 1, // cocoons and webs, dark
		"maint_3x3_workshop.dmm" = 1, // abandoned workshop
		"maint_3x3_honkshrine.dmm" = 1, // shrine to the Honkmother
		"maint_3x3_crimescene.dmm" = 1, // unsolved case, dark
		"maint_3x3_arcade.dmm" = 1 // arcade hideaway
	),
	"3x2" = list(
		"maint_3x2_basic.dmm" = 3, // the original nook
		"maint_3x2_bar.dmm" = 1, // hole-in-the-wall bar
		"maint_3x2_crashpad.dmm" = 1, // crash pad
		"maint_3x2_junk.dmm" = 1, // junk pile, dark
		"maint_3x2_garden.dmm" = 1 // tiny garden
	)
))

/// Every maint room marker waiting for SSmapping to load its room
GLOBAL_LIST_EMPTY(maint_room_spawners)

/obj/effect/landmark/maint_room
	name = "random maint room"
	icon_state = "x"
	/// Width of the nook, bottom-left corner on this marker
	var/room_width = 0
	/// Height of the nook
	var/room_height = 0

/obj/effect/landmark/maint_room/Initialize()
	. = ..()
	// Landmarks initialize immediately (INITIALIZE_IMMEDIATE), so this runs as the station map loads - before SSmapping
	// gets to load_maint_rooms()
	if(!SSmapping.initialized)
		GLOB.maint_room_spawners += src
		return
	// Placed after SSmapping's pass (by a template, say) - nothing loads it safely any more
	log_mapping("Maint room marker at [AREACOORD(src)] came too late to get a room")
	return INITIALIZE_HINT_QDEL

/obj/effect/landmark/maint_room/Destroy()
	GLOB.maint_room_spawners -= src
	return ..()

/obj/effect/landmark/maint_room/three_by_three
	name = "random maint room (3x3)"
	room_width = 3
	room_height = 3

/obj/effect/landmark/maint_room/three_by_two
	name = "random maint room (3x2)"
	room_width = 3
	room_height = 2

/// Loads a random room into every marked maint nook. Called during SSmapping's Initialize, before atoms initialize.
/datum/controller/subsystem/mapping/proc/load_maint_rooms()
	var/list/used = list()
	for(var/obj/effect/landmark/maint_room/marker as anything in GLOB.maint_room_spawners.Copy())
		var/size = "[marker.room_width]x[marker.room_height]"
		var/list/options = GLOB.maint_rooms[size]
		if(!length(options))
			log_mapping("No [size] maint rooms for the marker at [AREACOORD(marker)]")
			qdel(marker)
			continue
		// Spread the variety around: rooms not used yet this round first
		var/list/fresh = list()
		for(var/room in options)
			if(!used[room])
				fresh[room] = options[room]
		var/room_file = pickweight(length(fresh) ? fresh : options)
		used[room_file] = TRUE

		var/turf/corner = get_turf(marker)
		var/width = marker.room_width
		var/height = marker.room_height
		qdel(marker)
		var/datum/map_template/room = new(MAINT_ROOMS_PATH + room_file, "maint room [room_file]")
		if(room.width != width || room.height != height)
			log_mapping("Maint room [room_file] is [room.width]x[room.height], expected [size] - skipped at [AREACOORD(corner)]")
			continue
		check_maint_room_nook(corner, room)
		room.load(corner)

/// The room loads on top of whatever is already there, so a nook still holding its old furniture gets it doubled
/datum/controller/subsystem/mapping/proc/check_maint_room_nook(turf/corner, datum/map_template/room)
	var/static/list/allowed = typecacheof(list(
		/obj/effect/landmark,
		/obj/structure/cable,
		/obj/machinery/atmospherics/pipe,
		/obj/structure/disposalpipe
	))
	for(var/turf/T as anything in room.get_affected_turfs(corner))
		for(var/obj/O in T)
			if(!is_type_in_typecache(O, allowed))
				log_mapping("Maint room nook at [AREACOORD(T)] still has [O] ([O.type]) - clear it from the map")

#undef MAINT_ROOMS_PATH
