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
