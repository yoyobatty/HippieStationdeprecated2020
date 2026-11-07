
//generic (by snowflake + others) tile smoothing code; smooth your icons with this!
/*
	hippie -- bitmask smoothing, ported from tg (tgstation b3daa4c4, 2026-11-07) in place of the old corner overlays.

	A smoothed atom shows one baked icon_state, "[base_icon_state]-[smoothing_junction]", picked by which neighbours it joins.
	The states are baked from the old corner states (1-i .. 4-f), which stay in each .dmi as the source:
	edit those and run `python tools/smooth_bake/bake.py` (the sheet list is tools/smooth_bake/sheets.txt).

	To use it, set smoothing_flags to SMOOTH_BITMASK, base_icon_state to the baked prefix, and icon_state to
	"[base_icon_state]-0" (what map editors show). smoothing_groups are the groups an atom belongs to; canSmoothWith the
	groups it joins. A joins B when one of A's canSmoothWith is one of B's smoothing_groups. Both are strings of the
	SMOOTH_GROUP_* defines below, added together; they're parsed into lists once and cached.

	Turf groups (S_TURF) are only looked for on turfs. Anything with an object group (S_OBJ) in canSmoothWith also
	looks through the neighbouring turf's anchored movables (SMOOTH_OBJ is set for it).

	DIAGONAL: SMOOTH_DIAGONAL_CORNERS on a closed turf uses "[base_icon_state]-[junction]-diagonal" for the 8 diagonal
	shapes, with an underlay of the floor that was there (or fixed_underlay, list("space" = TRUE) for space).

	Kept from the old code where tg differs, so nothing looks different: an unanchored atom with can_be_unanchored
	joins nothing, an area's area_limited_icon_smoothing is checked from both sides, and the diagonal underlay looks
	at the neighbours in the old order.
*/

/* smoothing_flags */
/// Smoothing system in where adjacencies are calculated and used to select a pre-baked icon_state, encoded by bitmasking.
#define SMOOTH_BITMASK (1<<0)
/// Limits SMOOTH_BITMASK to only cardinal directions, for use with cardinal smoothing
#define SMOOTH_BITMASK_CARDINALS (1<<1)
/// Atom has diagonal corners, with underlays under them.
#define SMOOTH_DIAGONAL_CORNERS (1<<2)
/// Atom will smooth with the borders of the map.
#define SMOOTH_BORDER (1<<3)
/// Atom is currently queued to smooth.
#define SMOOTH_QUEUED (1<<4)
/// Smooths with objects, and will thus need to scan turfs for contents.
#define SMOOTH_OBJ (1<<5)

#define USES_SMOOTHING (SMOOTH_BITMASK|SMOOTH_BITMASK_CARDINALS)

/// Components of a smoothing junction
/// Redefinitions of the diagonal directions so they can be stored in one var without conflicts
#define NORTH_JUNCTION NORTH //(1<<0)
#define SOUTH_JUNCTION SOUTH //(1<<1)
#define EAST_JUNCTION EAST  //(1<<2)
#define WEST_JUNCTION WEST  //(1<<3)
#define NORTHEAST_JUNCTION (1<<4)
#define SOUTHEAST_JUNCTION (1<<5)
#define SOUTHWEST_JUNCTION (1<<6)
#define NORTHWEST_JUNCTION (1<<7)

#define CARDINAL_SMOOTHING_JUNCTIONS (NORTH_JUNCTION|SOUTH_JUNCTION|EAST_JUNCTION|WEST_JUNCTION)
#define ALL_SMOOTHING_JUNCTIONS (NORTH_JUNCTION|SOUTH_JUNCTION|EAST_JUNCTION|WEST_JUNCTION|NORTHEAST_JUNCTION|SOUTHEAST_JUNCTION|SOUTHWEST_JUNCTION|NORTHWEST_JUNCTION)

/*smoothing macros*/

#define QUEUE_SMOOTH(thing_to_queue) if(thing_to_queue.smoothing_flags & USES_SMOOTHING) {SSicon_smooth.add_to_queue(thing_to_queue)}

#define QUEUE_SMOOTH_NEIGHBORS(thing_to_queue) for(var/atom/atom_neighbor as anything in orange(1, thing_to_queue)) {QUEUE_SMOOTH(atom_neighbor)}

/**SMOOTHING GROUPS
 * Groups of things to smooth with: an atom joins another when one of its canSmoothWith is one of the other's smoothing_groups.
 * hippie -- worked out from the old typepath canSmoothWith lists so every pair of types joins exactly as before, except the
 * full-tile windows (built ones join mapped ones and each other) and alien tables (the wabbajack altar's halves).
 */

#define S_TURF(num) (#num + ",")

/* /turf only */

#define SMOOTH_GROUP_CLOSED_TURFS S_TURF(0) ///turf/closed/*
#define SMOOTH_GROUP_MINERAL_WALLS S_TURF(1) ///turf/closed/indestructible/* /turf/closed/mineral/*
#define SMOOTH_GROUP_FAKEGLASS S_TURF(2) ///turf/closed/indestructible/fakeglass
#define SMOOTH_GROUP_OPSGLASS S_TURF(3) ///turf/closed/indestructible/opsglass
#define SMOOTH_GROUP_RIVETED_WALLS S_TURF(4) ///turf/closed/indestructible/riveted
#define SMOOTH_GROUP_BOSS_WALLS S_TURF(5) ///turf/closed/indestructible/riveted/boss /turf/closed/indestructible/riveted/boss/see_through
#define SMOOTH_GROUP_HIEROPHANT S_TURF(6) ///turf/closed/indestructible/riveted/hierophant
#define SMOOTH_GROUP_RIVETED_URANIUM_WALLS S_TURF(7) ///turf/closed/indestructible/riveted/uranium
#define SMOOTH_GROUP_INDESTRUCTIBLE_SANDSTONE S_TURF(8) ///turf/closed/indestructible/sandstone
#define SMOOTH_GROUP_INDESTRUCTIBLE_SYNDICATE S_TURF(9) ///turf/closed/indestructible/syndicate
#define SMOOTH_GROUP_INDESTRUCTIBLE_WOOD S_TURF(10) ///turf/closed/indestructible/wood
#define SMOOTH_GROUP_ANY_WALL S_TURF(11) ///turf/closed/wall/*
#define SMOOTH_GROUP_CLOCKWORK_WALL S_TURF(12) ///turf/closed/wall/clockwork
#define SMOOTH_GROUP_ICED_WALLS S_TURF(13) ///turf/closed/wall/ice
#define SMOOTH_GROUP_PLAIN_MINERAL_WALL S_TURF(14) ///turf/closed/wall/mineral
#define SMOOTH_GROUP_BRONZE_WALLS S_TURF(15) ///turf/closed/wall/mineral/bronze
#define SMOOTH_GROUP_CULT_WALLS S_TURF(16) ///turf/closed/wall/mineral/cult
#define SMOOTH_GROUP_CULT_ARTIFICER_WALLS S_TURF(17) ///turf/closed/wall/mineral/cult/artificer
#define SMOOTH_GROUP_PLASTITANIUM_WALLS S_TURF(18) ///turf/closed/wall/mineral/plastitanium/*
#define SMOOTH_GROUP_REAGENT_WALLS S_TURF(19) ///turf/closed/wall/mineral/reagent
#define SMOOTH_GROUP_SNOW_WALLS S_TURF(20) ///turf/closed/wall/mineral/snow
#define SMOOTH_GROUP_TITANIUM_WALLS S_TURF(21) ///turf/closed/wall/mineral/titanium/*
#define SMOOTH_GROUP_SURVIVAL_TITANIUM_WALLS S_TURF(22) ///turf/closed/wall/mineral/titanium/survival/*
#define SMOOTH_GROUP_NONMETAL_WOOD_WALLS S_TURF(23) ///turf/closed/wall/mineral/wood/nonmetal
#define SMOOTH_GROUP_SYNDICATE_WALLS S_TURF(24) ///turf/closed/wall/r_wall/syndicate/*
#define SMOOTH_GROUP_TEST_WALL S_TURF(25) ///turf/closed/wall/smooth
#define SMOOTH_GROUP_TURF_CHASM S_TURF(26) ///turf/open/chasm/*
#define SMOOTH_GROUP_CARPET S_TURF(27) ///turf/open/floor/carpet
#define SMOOTH_GROUP_CARPET_BLACK S_TURF(28) ///turf/open/floor/carpet/black
#define SMOOTH_GROUP_FAKEPIT S_TURF(29) ///turf/open/floor/fakepit/*
#define SMOOTH_GROUP_HOLOCARPET S_TURF(30) ///turf/open/floor/holofloor/carpet
#define SMOOTH_GROUP_CHRISTMAS_FLOOR S_TURF(31) ///turf/open/floor/plasteel/christmas/*
#define SMOOTH_GROUP_FLOOR_ASHPLANET S_TURF(32) ///turf/open/floor/plating/ashplanet
#define SMOOTH_GROUP_FLOOR_ASH S_TURF(33) ///turf/open/floor/plating/ashplanet/ash/*
#define SMOOTH_GROUP_FLOOR_ASH_ROCKY S_TURF(34) ///turf/open/floor/plating/ashplanet/rocky/*
#define SMOOTH_GROUP_FLOOR_ICE S_TURF(35) ///turf/open/floor/plating/ice/* /turf/open/floor/plating/ice/smooth/*
#define SMOOTH_GROUP_FLOOR_SNOWED S_TURF(36) ///turf/open/floor/plating/snowed/* /turf/open/floor/plating/snowed/smoothed/*
#define SMOOTH_GROUP_CLOCK_SPAWN_ROOM S_TURF(37) ///turf/open/indestructible/clock_spawn_room/*
#define SMOOTH_GROUP_HIEROPHANT_FLOOR S_TURF(38) ///turf/open/indestructible/hierophant
#define SMOOTH_GROUP_HIEROPHANT_FLOOR_TWO S_TURF(39) ///turf/open/indestructible/hierophant/two
#define SMOOTH_GROUP_FLOOR_LAVA S_TURF(40) ///turf/open/lava/smooth/*

#define MAX_S_TURF 40 //Always match this value with the one above it.

#define S_OBJ(num) ("-" + #num + ",")
/* /obj included */

#define SMOOTH_GROUP_CLOCKWORK_OVERLAY_WALL S_OBJ(1) ///obj/effect/clockwork/overlay/wall
#define SMOOTH_GROUP_CLEANABLE_DIRT S_OBJ(2) ///obj/effect/decal/cleanable/dirt/*
#define SMOOTH_GROUP_HIERO_WALL S_OBJ(3) ///obj/effect/temp_visual/hierophant/wall
#define SMOOTH_GROUP_HIERO_WALL_CRUSHER S_OBJ(4) ///obj/effect/temp_visual/hierophant/wall/crusher
#define SMOOTH_GROUP_AIRLOCK S_OBJ(5) ///obj/machinery/door/airlock/*
#define SMOOTH_GROUP_SHUTTLE_AIRLOCK S_OBJ(6) ///obj/machinery/door/airlock/shuttle/*
#define SMOOTH_GROUP_SURVIVAL_TITANIUM_POD S_OBJ(7) ///obj/machinery/door/airlock/survival_pod/* /obj/structure/window/shuttle/survival_pod/*
#define SMOOTH_GROUP_ALIEN_RESIN S_OBJ(8) ///obj/structure/alien/resin
#define SMOOTH_GROUP_ALIEN_WALLS S_OBJ(9) ///obj/structure/alien/resin/membrane /obj/structure/alien/resin/wall
#define SMOOTH_GROUP_ALIEN_WEEDS S_OBJ(10) ///obj/structure/alien/weeds/*
#define SMOOTH_GROUP_SANDBAGS S_OBJ(11) ///obj/structure/barricade/sandbags /obj/structure/barricade/security
#define SMOOTH_GROUP_ALIEN_NEST S_OBJ(12) ///obj/structure/bed/nest
#define SMOOTH_GROUP_WALLS S_OBJ(13) ///obj/structure/falsewall /obj/structure/falsewall/reinforced /turf/closed/wall /turf/closed/wall/r_wall /turf/closed/wall/r_wall/rust /turf/closed/wall/rust
#define SMOOTH_GROUP_FALSEWALLS S_OBJ(14) ///obj/structure/falsewall/*
#define SMOOTH_GROUP_ABDUCTOR_WALLS S_OBJ(15) ///obj/structure/falsewall/abductor /turf/closed/wall/mineral/abductor
#define SMOOTH_GROUP_BANANIUM_WALLS S_OBJ(16) ///obj/structure/falsewall/bananium /turf/closed/wall/mineral/bananium
#define SMOOTH_GROUP_BRASS_FALSEWALL S_OBJ(17) ///obj/structure/falsewall/brass
#define SMOOTH_GROUP_DIAMOND_WALLS S_OBJ(18) ///obj/structure/falsewall/diamond /turf/closed/wall/mineral/diamond
#define SMOOTH_GROUP_GOLD_WALLS S_OBJ(19) ///obj/structure/falsewall/gold /turf/closed/wall/mineral/gold
#define SMOOTH_GROUP_IRON_WALLS S_OBJ(20) ///obj/structure/falsewall/iron /turf/closed/wall/mineral/iron
#define SMOOTH_GROUP_PLASMA_WALLS S_OBJ(21) ///obj/structure/falsewall/plasma /turf/closed/wall/mineral/plasma
#define SMOOTH_GROUP_PLASTITANIUM_SHUTTLE_PARTS S_OBJ(22) ///obj/structure/falsewall/plastitanium/* /obj/structure/window/plastitanium/*
#define SMOOTH_GROUP_SANDSTONE_WALLS S_OBJ(23) ///obj/structure/falsewall/sandstone /turf/closed/wall/mineral/sandstone
#define SMOOTH_GROUP_SILVER_WALLS S_OBJ(24) ///obj/structure/falsewall/silver /turf/closed/wall/mineral/silver
#define SMOOTH_GROUP_TITANIUM_FALSEWALL S_OBJ(25) ///obj/structure/falsewall/titanium/*
#define SMOOTH_GROUP_URANIUM_WALLS S_OBJ(26) ///obj/structure/falsewall/uranium /turf/closed/wall/mineral/uranium
#define SMOOTH_GROUP_WOOD_WALLS S_OBJ(27) ///obj/structure/falsewall/wood /turf/closed/wall/mineral/wood
#define SMOOTH_GROUP_LATTICE S_OBJ(28) ///obj/structure/lattice/* /turf/open/floor/*
#define SMOOTH_GROUP_CATWALK S_OBJ(29) ///obj/structure/lattice/catwalk
#define SMOOTH_GROUP_SWARMER_CATWALK S_OBJ(30) ///obj/structure/lattice/catwalk/swarmer_catwalk
#define SMOOTH_GROUP_PAPERFRAME S_OBJ(31) ///obj/structure/mineral_door/paperframe /obj/structure/window/paperframe
#define SMOOTH_GROUP_SHUTTLE_ENGINE S_OBJ(32) ///obj/structure/shuttle/engine/*
#define SMOOTH_GROUP_SHUTTLE_HEATER S_OBJ(33) ///obj/structure/shuttle/engine/heater/*
#define SMOOTH_GROUP_TABLES S_OBJ(34) ///obj/structure/table /obj/structure/table/reinforced
#define SMOOTH_GROUP_ABDUCTOR_TABLES S_OBJ(35) ///obj/structure/table/abductor/*
#define SMOOTH_GROUP_BRONZE_TABLES S_OBJ(36) ///obj/structure/table/bronze /obj/structure/table/reinforced/brass
#define SMOOTH_GROUP_GLASS_TABLES S_OBJ(37) ///obj/structure/table/glass
#define SMOOTH_GROUP_WOOD_TABLES S_OBJ(38) ///obj/structure/table/wood /obj/structure/table/wood/bar /obj/structure/table/wood/poker
#define SMOOTH_GROUP_FANCY_WOOD_TABLES S_OBJ(39) ///obj/structure/table/wood/fancy /obj/structure/table/wood/fancy/black
#define SMOOTH_GROUP_WINDOW_FULLTILE S_OBJ(40) ///obj/structure/window/fulltile/* /obj/structure/window/reinforced/fulltile/* /obj/structure/window/reinforced/tinted/fulltile/*
#define SMOOTH_GROUP_WINDOW_FULLTILE_PLASMA S_OBJ(41) ///obj/structure/window/plasma/fulltile/* /obj/structure/window/plasma/reinforced/fulltile/*
#define SMOOTH_GROUP_WINDOW_FULLTILE_PLASTITANIUM S_OBJ(42) ///obj/structure/window/plastitanium /obj/structure/window/plastitanium/unanchored
#define SMOOTH_GROUP_WINDOW_FULLTILE_BRONZE S_OBJ(43) ///obj/structure/window/reinforced/clockwork/fulltile /obj/structure/window/reinforced/clockwork/fulltile/unanchored
#define SMOOTH_GROUP_WINDOW_FULLTILE_SHUTTLE S_OBJ(44) ///obj/structure/window/shuttle /obj/structure/window/shuttle/tinted /obj/structure/window/shuttle/unanchored
#define SMOOTH_GROUP_SHUTTLE_WINDOWS S_OBJ(45) ///obj/structure/window/shuttle/*

/// Given a smoothing groups variable, will set out to the actual numbers inside it
#define UNWRAP_SMOOTHING_GROUPS(smoothing_groups, out) \
	json_decode("\[[##smoothing_groups]0\]"); \
	##out.len--;

GLOBAL_LIST_EMPTY(bitflag_lists)

/**
 * Turns a string of smoothing group numbers into an associative list of bitflags, for quick comparison:
 * "0,4,26,32," => list("0" = (1<<0)|(1<<4), "1" = (1<<2)|(1<<8)). Cached, so identical strings share one list.
 */
#define SET_SMOOTHING_GROUPS(read_from, set_into) \
	do { \
		var/txt_signature = read_from; \
		if(isnull((set_into = GLOB.bitflag_lists[txt_signature]))) { \
			var/list/new_bitflag_list = list(); \
			var/list/decoded = UNWRAP_SMOOTHING_GROUPS(txt_signature, decoded); \
			for(var/value in decoded) { \
				if (value < 0) { \
					value = MAX_S_TURF + 1 + abs(value); \
				} \
				new_bitflag_list["[round(value / 24)]"] |= (1 << (value % 24)); \
			}; \
			set_into = GLOB.bitflag_lists[txt_signature] = new_bitflag_list; \
		}; \
	} while (FALSE)

/// Parses smoothing_groups and canSmoothWith from their strings, and sets SMOOTH_OBJ when an object group is wanted.
/// In /atom/Initialize() and /turf/Initialize(); a neighbour that isn't initialized yet is parsed when it's first looked at.
#define SETUP_SMOOTHING(...) \
	if(istext(smoothing_groups)) { \
		SET_SMOOTHING_GROUPS(smoothing_groups, smoothing_groups); \
	} \
	if(istext(canSmoothWith)) { \
		if(findtext(canSmoothWith, "-")) { \
			smoothing_flags |= SMOOTH_OBJ; \
		} \
		SET_SMOOTHING_GROUPS(canSmoothWith, canSmoothWith); \
	}

/atom/var/smoothing_flags = NONE
/// What directions this is currently smoothing with, in the junction bits above (not BYOND's directions)
/atom/var/smoothing_junction = null
/// The smoothing groups this atom belongs to, to match canSmoothWith. If null, nobody can smooth with it.
/atom/var/list/smoothing_groups = null
/// The smoothing groups this atom joins. A string of SMOOTH_GROUP_* until Initialize(), then a parsed list.
/atom/var/list/canSmoothWith = null
/// Used for changing icon states for different base sprites: smoothed atoms show "[base_icon_state]-[junction]"
/atom/var/base_icon_state
/// An unanchored one of these joins nothing (windows being moved about)
/atom/movable/var/can_be_unanchored = FALSE
/turf/var/list/fixed_underlay = null

///do not use, use QUEUE_SMOOTH(atom)
/atom/proc/smooth_icon()
	smoothing_flags &= ~SMOOTH_QUEUED
	if(!z || QDELETED(src))
		return
	if(smoothing_flags & USES_SMOOTHING)
		bitmask_smooth()

/**
 * Basic smoothing proc. The atom checks for adjacent directions to smooth with and changes the icon_state based on that.
 */
/atom/proc/bitmask_smooth()
	var/new_junction = NONE
	// cache for sanic speed
	var/list/canSmoothWith = src.canSmoothWith
	if(istext(canSmoothWith))
		SETUP_SMOOTHING()
		canSmoothWith = src.canSmoothWith

	if(ismovable(src))
		var/atom/movable/self = src
		if(self.can_be_unanchored && !self.anchored)
			set_smoothed_icon_state(NONE)
			return

	var/area/home_base = get_area(src)
	var/area_limited_icon_smoothing = home_base?.area_limited_icon_smoothing
	var/smooth_border = (smoothing_flags & SMOOTH_BORDER)
	var/smooth_obj = (smoothing_flags & SMOOTH_OBJ)

	#define SMOOTH_AGAINST(thing, their_groups, direction_flag) \
		if(istext(their_groups)) { \
			SET_SMOOTHING_GROUPS(their_groups, their_groups); \
			thing.smoothing_groups = their_groups; \
		}; \
		for(var/target in canSmoothWith) { \
			if(canSmoothWith[target] & their_groups[target]) { \
				new_junction |= direction_flag; \
				break set_adj_in_dir; \
			} \
		}

	#define SEARCH_ADJ_IN_DIR(direction, direction_flag) \
		do { \
			set_adj_in_dir: { \
				var/turf/neighbor = get_step(src, direction); \
				if(!neighbor) { \
					if(smooth_border) { \
						new_junction |= direction_flag; \
					}; \
					break set_adj_in_dir; \
				}; \
				var/area/neighbor_area = neighbor.loc; \
				if(area_limited_icon_smoothing && !istype(neighbor_area, area_limited_icon_smoothing)) { \
					break set_adj_in_dir; \
				}; \
				if(neighbor_area.area_limited_icon_smoothing && !istype(home_base, neighbor_area.area_limited_icon_smoothing)) { \
					break set_adj_in_dir; \
				}; \
				var/list/neighbor_smoothing_groups = neighbor.smoothing_groups; \
				if(neighbor_smoothing_groups) { \
					SMOOTH_AGAINST(neighbor, neighbor_smoothing_groups, direction_flag); \
				}; \
				if(smooth_obj) { \
					for(var/atom/movable/thing as anything in neighbor) { \
						var/list/thing_smoothing_groups = thing.smoothing_groups; \
						if(!thing.anchored || isnull(thing_smoothing_groups)) { \
							continue; \
						}; \
						SMOOTH_AGAINST(thing, thing_smoothing_groups, direction_flag); \
					} \
				} \
			} \
		} while(FALSE)

	SEARCH_ADJ_IN_DIR(NORTH, NORTH_JUNCTION)
	SEARCH_ADJ_IN_DIR(SOUTH, SOUTH_JUNCTION)
	SEARCH_ADJ_IN_DIR(EAST, EAST_JUNCTION)
	SEARCH_ADJ_IN_DIR(WEST, WEST_JUNCTION)

	// If there's nothing going on already
	if(smoothing_flags & SMOOTH_BITMASK_CARDINALS || !(new_junction & (NORTH|SOUTH)) || !(new_junction & (EAST|WEST)))
		set_smoothed_icon_state(new_junction)
		return

	if(new_junction & NORTH_JUNCTION)
		if(new_junction & WEST_JUNCTION)
			SEARCH_ADJ_IN_DIR(NORTHWEST, NORTHWEST_JUNCTION)

		if(new_junction & EAST_JUNCTION)
			SEARCH_ADJ_IN_DIR(NORTHEAST, NORTHEAST_JUNCTION)

	if(new_junction & SOUTH_JUNCTION)
		if(new_junction & WEST_JUNCTION)
			SEARCH_ADJ_IN_DIR(SOUTHWEST, SOUTHWEST_JUNCTION)

		if(new_junction & EAST_JUNCTION)
			SEARCH_ADJ_IN_DIR(SOUTHEAST, SOUTHEAST_JUNCTION)

	set_smoothed_icon_state(new_junction)

	#undef SEARCH_ADJ_IN_DIR
	#undef SMOOTH_AGAINST

#define DEFAULT_UNDERLAY_ICON 'icons/turf/floors.dmi'
#define DEFAULT_UNDERLAY_ICON_STATE "plating"

///Changes the icon state based on the new junction bitmask
/atom/proc/set_smoothed_icon_state(new_junction)
	. = smoothing_junction
	smoothing_junction = new_junction
	icon_state = "[base_icon_state]-[smoothing_junction]"

/turf/closed/set_smoothed_icon_state(new_junction)
	// Avoid calling ..() here to avoid setting icon_state twice, which is expensive given how hot this proc is
	. = smoothing_junction
	smoothing_junction = new_junction

	if (!(smoothing_flags & SMOOTH_DIAGONAL_CORNERS))
		icon_state = "[base_icon_state]-[smoothing_junction]"
		return

	switch(new_junction)
		if(
			NORTH_JUNCTION|WEST_JUNCTION,
			NORTH_JUNCTION|EAST_JUNCTION,
			SOUTH_JUNCTION|WEST_JUNCTION,
			SOUTH_JUNCTION|EAST_JUNCTION,
			NORTH_JUNCTION|WEST_JUNCTION|NORTHWEST_JUNCTION,
			NORTH_JUNCTION|EAST_JUNCTION|NORTHEAST_JUNCTION,
			SOUTH_JUNCTION|WEST_JUNCTION|SOUTHWEST_JUNCTION,
			SOUTH_JUNCTION|EAST_JUNCTION|SOUTHEAST_JUNCTION,
		)
			icon_state = "[base_icon_state]-[smoothing_junction]-diagonal"
			// redone every time, as the old code did: the floor next to us may have changed
			add_turf_underlay(reverse_ndir(smoothing_junction))
			diagonal_corner_made()
		else
			icon_state = "[base_icon_state]-[smoothing_junction]"

/// A diagonal wall corner has just been shown (walls drop the posters on them)
/turf/closed/proc/diagonal_corner_made()
	return

/turf/closed/wall/diagonal_corner_made()
	// Drop posters which were previously placed on this wall.
	for(var/obj/structure/sign/poster/P in src)
		P.roll_and_drop(src)

/// The floor under a diagonal corner: the turf on the open side, then the two beside it, then our own turf's idea
/turf/proc/add_turf_underlay(junction_dir)
	var/mutable_appearance/underlay_appearance = mutable_appearance(layer = TURF_LAYER, plane = FLOOR_PLANE)
	var/list/U = list(underlay_appearance)
	if(fixed_underlay)
		if(fixed_underlay["space"])
			underlay_appearance.icon = 'icons/turf/space.dmi'
			underlay_appearance.icon_state = SPACE_ICON_STATE
			underlay_appearance.plane = PLANE_SPACE
		else
			underlay_appearance.icon = fixed_underlay["icon"]
			underlay_appearance.icon_state = fixed_underlay["icon_state"]
	else
		var/turned_adjacency = turn(junction_dir, 180)
		var/turf/T = get_step(src, turned_adjacency)
		if(!T.get_smooth_underlay_icon(underlay_appearance, src, turned_adjacency))
			T = get_step(src, turn(junction_dir, 135))
			if(!T.get_smooth_underlay_icon(underlay_appearance, src, turned_adjacency))
				T = get_step(src, turn(junction_dir, 225))
		//if all else fails, ask our own turf
		if(!T.get_smooth_underlay_icon(underlay_appearance, src, turned_adjacency) && !get_smooth_underlay_icon(underlay_appearance, src, turned_adjacency))
			underlay_appearance.icon = DEFAULT_UNDERLAY_ICON
			underlay_appearance.icon_state = DEFAULT_UNDERLAY_ICON_STATE
	underlays = U

#undef DEFAULT_UNDERLAY_ICON
#undef DEFAULT_UNDERLAY_ICON_STATE

//Icon smoothing helpers
/proc/smooth_zlevel(zlevel, now = FALSE)
	var/list/away_turfs = block(locate(1, 1, zlevel), locate(world.maxx, world.maxy, zlevel))
	for(var/turf/turf_to_smooth as anything in away_turfs)
		if(turf_to_smooth.smoothing_flags & USES_SMOOTHING)
			if(now)
				turf_to_smooth.smooth_icon()
			else
				QUEUE_SMOOTH(turf_to_smooth)
		for(var/atom/movable/movable_to_smooth as anything in turf_to_smooth)
			if(movable_to_smooth.smoothing_flags & USES_SMOOTHING)
				if(now)
					movable_to_smooth.smooth_icon()
				else
					QUEUE_SMOOTH(movable_to_smooth)

/atom/proc/set_can_smooth_with(canSmoothWith)
	if(!canSmoothWith)
		src.canSmoothWith = null
		smoothing_flags &= ~SMOOTH_OBJ
		return
	if(findtext(canSmoothWith, "-"))
		smoothing_flags |= SMOOTH_OBJ
	else
		smoothing_flags &= ~SMOOTH_OBJ
	SET_SMOOTHING_GROUPS(canSmoothWith, src.canSmoothWith)

/atom/proc/set_smoothing_groups(smoothing_groups)
	if(!smoothing_groups)
		src.smoothing_groups = null
		return
	SET_SMOOTHING_GROUPS(smoothing_groups, src.smoothing_groups)

/proc/reverse_ndir(ndir)
	switch(ndir)
		if(NORTH_JUNCTION)
			return NORTH
		if(SOUTH_JUNCTION)
			return SOUTH
		if(WEST_JUNCTION)
			return WEST
		if(EAST_JUNCTION)
			return EAST
		if(NORTHWEST_JUNCTION)
			return NORTHWEST
		if(NORTHEAST_JUNCTION)
			return NORTHEAST
		if(SOUTHEAST_JUNCTION)
			return SOUTHEAST
		if(SOUTHWEST_JUNCTION)
			return SOUTHWEST
		if(NORTH_JUNCTION | WEST_JUNCTION)
			return NORTHWEST
		if(NORTH_JUNCTION | EAST_JUNCTION)
			return NORTHEAST
		if(SOUTH_JUNCTION | WEST_JUNCTION)
			return SOUTHWEST
		if(SOUTH_JUNCTION | EAST_JUNCTION)
			return SOUTHEAST
		if(NORTH_JUNCTION | WEST_JUNCTION | NORTHWEST_JUNCTION)
			return NORTHWEST
		if(NORTH_JUNCTION | EAST_JUNCTION | NORTHEAST_JUNCTION)
			return NORTHEAST
		if(SOUTH_JUNCTION | WEST_JUNCTION | SOUTHWEST_JUNCTION)
			return SOUTHWEST
		if(SOUTH_JUNCTION | EAST_JUNCTION | SOUTHEAST_JUNCTION)
			return SOUTHEAST
		else
			return NONE

//SSicon_smooth
/proc/queue_smooth_neighbors(atom/A)
	QUEUE_SMOOTH_NEIGHBORS(A)

//SSicon_smooth, as a proc for callbacks
/proc/queue_smooth(atom/A)
	QUEUE_SMOOTH(A)

//Example smooth wall
/turf/closed/wall/smooth
	smoothing_flags = SMOOTH_BITMASK|SMOOTH_DIAGONAL_CORNERS|SMOOTH_BORDER
	base_icon_state = "smooth_wall"
	smoothing_groups = SMOOTH_GROUP_CLOSED_TURFS + SMOOTH_GROUP_ANY_WALL + SMOOTH_GROUP_TEST_WALL
	canSmoothWith = SMOOTH_GROUP_TEST_WALL
	name = "smooth wall"
	icon = 'icons/turf/smooth_wall.dmi'
	icon_state = "smooth_wall-0"
