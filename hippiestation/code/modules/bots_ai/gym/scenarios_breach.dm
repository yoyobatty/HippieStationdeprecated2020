// Bot Gym scenarios for getting through obstacles (bot_breach.dm, bot_items.dm).
// Legend is in /datum/bot_scenario/proc/build_tile() (bot_gym.dm).

// --- Welded doors ---

/datum/bot_scenario/welded_airlock_with_welder
	name = "welded airlock, welder carried"
	desc = "Unwelds the only door and walks through."
	layout = list(
		"#########",
		"#B..X..G#",
		"#########")
	kit_hands = list(/obj/item/weldingtool)

/datum/bot_scenario/welded_airlock_fetch_welder
	name = "welded airlock, welder in a locker"
	desc = "No welder carried; one is in a locker on the bot's side. Should fetch it, then unweld."
	layout = list(
		"##########",
		"#B...X..G#",
		"#.L.######",
		"##########")

/datum/bot_scenario/welded_airlock_fetch_welder/setup()
	new /obj/item/weldingtool(first_placed("L"))

/datum/bot_scenario/welded_firelock_with_tools
	name = "welded firelock, welder + crowbar"
	desc = "Unwelds the firelock, then pries it open."
	layout = list(
		"#########",
		"#B..f..G#",
		"#########")
	kit_hands = list(/obj/item/weldingtool, /obj/item/crowbar)

/datum/bot_scenario/firelock_with_crowbar
	name = "closed firelock, crowbar"
	layout = list(
		"#########",
		"#B..F..G#",
		"#########")
	kit_hands = list(/obj/item/crowbar)

// --- Calm bots don't break things ---

/datum/bot_scenario/calm_goes_around_window
	name = "calm bot walks around a window"
	desc = "A window blocks the direct line but there's a way around. A calm bot must not smash it."
	layout = list(
		"###########",
		"#B...W...G#",
		"#....#....#",
		"#.........#",
		"###########")
	kit_hands = list(/obj/item/storage/toolbox/mechanical)
	urgency_override = BOT_URGENCY_CALM

/datum/bot_scenario/calm_goes_around_window/check_success_conditions()
	if(placed_destroyed("W"))
		return "reached the goal, but smashed the window to do it"

/datum/bot_scenario/calm_refuses_only_window
	name = "calm bot won't break the only window"
	desc = "The only way through is a window. A calm bot should leave it alone - pass = window intact at timeout."
	layout = list(
		"#########",
		"#B..W..G#",
		"#########")
	kit_hands = list(/obj/item/storage/toolbox/mechanical)
	urgency_override = BOT_URGENCY_CALM
	time_limit = 20 SECONDS

/datum/bot_scenario/calm_refuses_only_window/check()
	if(placed_destroyed("W"))
		fail_reason = "a calm bot broke the window"
		return BOT_GYM_FAIL
	return ..()

/datum/bot_scenario/calm_refuses_only_window/on_timeout()
	return BOT_GYM_PASS

// --- Emergencies: break through, choosing a weapon ---

/datum/bot_scenario/emergency_window_carried_toolbox
	name = "emergency, window, toolbox carried"
	layout = list(
		"#########",
		"#B..W..G#",
		"#########")
	kit_hands = list(/obj/item/storage/toolbox/mechanical)
	urgency_override = BOT_URGENCY_EMERGENCY

/datum/bot_scenario/emergency_window_nearby_toolbox
	name = "emergency, window, toolbox on the floor"
	desc = "Nothing carried; a toolbox lies two tiles behind the bot."
	layout = list(
		"##########",
		"#T.B..W.G#",
		"##########")
	urgency_override = BOT_URGENCY_EMERGENCY

/// Knocked off its way mid-walk (a shove, a slip, the arrivals shuttle moving under it) to the far side of a wall: it finds the
/// way round. It used to keep stepping at the next tile of its old route, through the wall, until it counted itself stuck
/// and gave up - 141 of 267 give-ups for being stuck in a three-shift batch.
/datum/bot_scenario/knocked_off_route
	name = "walking: knocked off its way to the far side of a wall, it finds the way round"
	desc = "Walking along the top corridor to G, it's moved to the bottom one, the wall between, open only at the far end. It goes round to G without giving up."
	layout = list(
		"####################",
		"#B................G#",
		"#############.######",
		"#..................#",
		"####################")
	time_limit = 30 SECONDS
	var/knocked = FALSE

/datum/bot_scenario/knocked_off_route/post_spawn()
	addtimer(CALLBACK(src, PROC_REF(knock)), 6)

/datum/bot_scenario/knocked_off_route/proc/knock()
	if(QDELETED(bot))
		return
	var/turf/T = locate(bot.x, bot.y - 2, bot.z)
	if(T && !T.density)
		bot.forceMove(T)
		knocked = TRUE
		log_line("knocked to [bot_coord(T)], on the other side of the wall")

/datum/bot_scenario/knocked_off_route/check()
	if(bot_transcript_said("giving up on"))
		fail_reason = "gave up after being knocked off its way"
		return BOT_GYM_FAIL
	. = ..()
	if(. == BOT_GYM_PASS && !knocked)
		fail_reason = "never knocked (it got there first)"
		return BOT_GYM_FAIL

/datum/bot_scenario/emergency_window_extinguisher_cabinet
	name = "emergency, window, extinguisher cabinet"
	desc = "Nothing carried or loose; an extinguisher sits in a wall cabinet behind the bot."
	layout = list(
		"##########",
		"#E.B..W.G#",
		"##########")
	urgency_override = BOT_URGENCY_EMERGENCY

/datum/bot_scenario/emergency_grille_wirecutters
	name = "emergency, grille, wirecutters"
	desc = "Should snip the grille rather than beat it down."
	layout = list(
		"#########",
		"#B..g..G#",
		"#########")
	kit_hands = list(/obj/item/wirecutters)
	urgency_override = BOT_URGENCY_EMERGENCY

// --- Not built yet (Phase 2): look before you breach ---

/datum/bot_scenario/emergency_window_into_vacuum
	name = "emergency, window with vacuum behind"
	desc = "Phase 2. The room past the window is airless and the bot has no suit - breaking in would be suicide. Pass = window intact at timeout."
	layout = list(
		"##########",
		"#B..WvvvG#",
		"##########")
	kit_hands = list(/obj/item/storage/toolbox/mechanical)
	urgency_override = BOT_URGENCY_EMERGENCY
	time_limit = 20 SECONDS
	expect_success = FALSE

/datum/bot_scenario/emergency_window_into_vacuum/setup()
	var/turf/open/goal = first_marker("G")
	goal.air.parse_gas_string("TEMP=2.7")
	SSair.add_to_active(goal) // so atmos hears it's empty now

/datum/bot_scenario/emergency_window_into_vacuum/check()
	if(placed_destroyed("W"))
		fail_reason = "breached a window into vacuum with no suit"
		return BOT_GYM_FAIL
	return ..()

/datum/bot_scenario/emergency_window_into_vacuum/on_timeout()
	return BOT_GYM_PASS

// --- Unpowered doors ---

/datum/bot_scenario/unpowered_safety_airlock_by_hand
	name = "unpowered safety airlock, bare hands"
	desc = "The only door has no power but has the emergency hand release (safety_mode, like the arrivals dock airlocks). With no tools the bot should work the release (15s) and walk through - not treat the dead door as a wall."
	layout = list(
		"#########",
		"#B..D..G#",
		"#########")

/datum/bot_scenario/unpowered_safety_airlock_by_hand/setup()
	var/obj/machinery/door/airlock/A = first_placed("D")
	A.safety_mode = TRUE
	A.stat |= NOPOWER //the arena area never loses power, so nothing turns this back off
	A.update_icon()

/datum/bot_scenario/unpowered_safety_airlock_by_hand/check_success_conditions()
	if(QDELETED(first_placed("D"))) //not placed_destroyed() - that also counts an opened door
		return "reached the goal, but broke the door down instead of using its hand release"

/datum/bot_scenario/unpowered_safety_airlock_crowbar
	name = "unpowered safety airlock, crowbar"
	desc = "Same dead safety door, but the bot has a crowbar: prying is near-instant, so it should pry rather than spend 15s on the hand release."
	layout = list(
		"#########",
		"#B..D..G#",
		"#########")
	kit_hands = list(/obj/item/crowbar)
	time_limit = 14 SECONDS //finishing inside the hand release's 15s is the proof it pried

/datum/bot_scenario/unpowered_safety_airlock_crowbar/setup()
	var/obj/machinery/door/airlock/A = first_placed("D")
	A.safety_mode = TRUE
	A.stat |= NOPOWER
	A.update_icon()

/// A hole blown in the floor (goals/repair_hull.dm): suited up, rods and tiles in the bag, it patches it from beside it.
/datum/bot_scenario/patch_hull
	name = "engineering: a hole blown in the floor, it lays a lattice and a tile over it"
	desc = "A Station Engineer in a space suit on internals, rods and floor tiles in its bag, and a hole to space in the middle of the room (S). It stands beside it, puts a rod down for a lattice and a tile on that. Holes used to stay open all round."
	job = "Station Engineer"
	time_limit = 60 SECONDS
	kit_backpack = list(/obj/item/stack/rods/ten, /obj/item/stack/tile/plasteel)
	layout = list(
		"#########",
		"#B......#",
		"#.......#",
		"#....S..#",
		"#.......#",
		"#########")
	var/turf/hole

/datum/bot_scenario/patch_hull/setup()
	hole = first_marker("S")
	bot_note_breach(hole)

/datum/bot_scenario/patch_hull/post_spawn()
	bot.equip_to_slot_or_del(new /obj/item/clothing/mask/breath(bot), ITEM_SLOT_MASK)
	bot.equip_to_slot_or_del(new /obj/item/clothing/suit/space/eva(bot), ITEM_SLOT_OCLOTHING)
	bot.equip_to_slot_or_del(new /obj/item/clothing/head/helmet/space/eva(bot), ITEM_SLOT_HEAD)
	var/obj/item/tank/internals/emergency_oxygen/T = new(bot)
	bot.equip_to_slot_or_del(T, ITEM_SLOT_SUITSTORE)
	bot.internal = T

/datum/bot_scenario/patch_hull/make_goal()
	return new /datum/bot_goal/patch_hull(hole)

/datum/bot_scenario/patch_hull/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	return istype(hole, /turf/open/space) ? BOT_GYM_PENDING : BOT_GYM_PASS

/datum/bot_scenario/patch_hull/fetches
	name = "engineering: a hole blown in the floor, it fetches rods and a tile from across the room first"
	desc = "The same with nothing in its bag: rods (q) and floor tiles (u) lie across the room. It gets them, then patches the hole."
	kit_backpack = list()
	layout = list(
		"#########",
		"#B......#",
		"#.......#",
		"#....S..#",
		"#......q#",
		"#......u#",
		"#########")

/datum/bot_scenario/patch_hull/fetches/setup()
	..()
	new /obj/item/stack/rods/ten(first_marker("q"))
	new /obj/item/stack/tile/plasteel(first_marker("u"))

/datum/bot_scenario/patch_hull/from_metal
	name = "engineering: a hole blown in the floor, it makes rods and a tile from metal sheets and patches it"
	desc = "Only metal sheets in its bag: it makes a couple of rods and floor tiles with the sheets' own menu, then patches the hole."
	kit_backpack = list(/obj/item/stack/sheet/metal/ten)

