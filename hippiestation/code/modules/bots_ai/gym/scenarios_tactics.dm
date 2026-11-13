// Bot Gym: the tactics library and threat reading (foundation/tactics.dm, foundation/threat_read.dm). The user's case, 2026-11-13: "a fuel
// tank, dragging it, pushing it into a player, backing off and shooting it, dealing an easy stunning blow". SCENARIO_BACKLOG.md lists these.
//
// Layout letters used here: U a fuel tank, k somebody (a stand-in), V the mark.

/datum/bot_scenario/tactics
	time_limit = 20 SECONDS
	blast_margin = 10 //a fuel tank's blast reaches five tiles, more in a small sealed room, and its flames and the casing's shards further
	var/bot_skill = 0.7
	var/obj/structure/reagent_dispensers/fueltank/tank
	var/mob/living/carbon/human/foe

/datum/bot_scenario/tactics/setup()
	var/turf/T = first_marker("U")
	if(T)
		tank = new(T)
		place("U", tank)

/datum/bot_scenario/tactics/post_spawn()
	brain.skill = bot_skill

/datum/bot_scenario/tactics/make_goal()
	return null //the fight is the job

/datum/bot_scenario/tactics/proc/tank_went_off()
	return QDELETED(tank)

// ---------------------------------------------------------------------------------------------
// The fuel tank in a fight (tier 2)
// ---------------------------------------------------------------------------------------------

/// In a fight with somebody with a claymore, who's stood beside a fuel tank six tiles off, the bot holding a laser.
/datum/bot_scenario/tactics/fight
	job = "Assistant"
	kit_hands = list(/obj/item/gun/energy/laser)
	layout = list(
		"######################",
		"#....................#",
		"#B......U............#",
		"#.......k............#",
		"######################")

/datum/bot_scenario/tactics/fight/post_spawn()
	..()
	foe = stand_in(first_marker("k"), "Kit Killer")
	var/obj/item/claymore/C = new(foe)
	foe.put_in_hands(C)
	brain.on_attacked(foe, "attacked", C)

/datum/bot_scenario/tactics/fight/shoots
	name = "tactics: a robust crewman in a fight shoots the fuel tank the killer is stood beside"
	desc = "Mid skill, a laser in hand, in a fight with somebody swinging a claymore who's stood beside a fuel tank, itself seven tiles off. It shoots the tank, not them: a blast on the tiles beside it, and it's clear of it (a shard of the casing may still find it: hurt no more than that)."

/datum/bot_scenario/tactics/fight/shoots/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(!tank_went_off())
		return BOT_GYM_PENDING
	if(bot.health < bot.maxHealth * 0.7)
		fail_reason = "set off the tank and got caught in it ([bot.health] health)"
		return BOT_GYM_FAIL
	return BOT_GYM_PASS

/datum/bot_scenario/tactics/fight/low_skill
	name = "tactics: a low-skill crewman in the same fight doesn't think of the tank"
	desc = "The same fight for an ordinary player: it shoots at the killer, as it always did, and never thinks of the tank."
	bot_skill = 0.3
	time_limit = 12 SECONDS

/datum/bot_scenario/tactics/fight/low_skill/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(tank_went_off())
		fail_reason = "a low-skill bot set the tank off"
		return BOT_GYM_FAIL
	return BOT_GYM_PENDING

/datum/bot_scenario/tactics/fight/low_skill/on_timeout()
	return BOT_GYM_PASS

/datum/bot_scenario/tactics/fight/bystander
	name = "tactics: a robust crewman doesn't set off a tank with somebody else beside it"
	desc = "The same fight, with an innocent stood by the tank too: no tank shot."
	time_limit = 12 SECONDS
	layout = list(
		"######################",
		"#.......c............#",
		"#B......U............#",
		"#.......k............#",
		"######################")

/datum/bot_scenario/tactics/fight/bystander/post_spawn()
	..()
	stand_in(first_marker("c"), "Ivy Innocent")

/datum/bot_scenario/tactics/fight/bystander/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(tank_went_off())
		fail_reason = "set off a tank with an innocent beside it"
		return BOT_GYM_FAIL
	return BOT_GYM_PENDING

/datum/bot_scenario/tactics/fight/bystander/on_timeout()
	return BOT_GYM_PASS

// ---------------------------------------------------------------------------------------------
// The fuel tank set up for a killing (tier 3, apex)
// ---------------------------------------------------------------------------------------------

/datum/bot_scenario/tactics/opener
	name = "tactics: an apex killer drags a fuel tank to its mark, backs off and shoots it"
	desc = "The user's case: apex, a laser on it, after somebody with a fuel tank a few tiles from them. It fetches the tank, drags it up to them, steps aside so the tank comes on to the tile beside them, lets go, backs off out of the blast where it can see the tank, and shoots it; then it finishes them."
	bot_skill = 1
	time_limit = 60 SECONDS
	kit_hands = list(/obj/item/gun/energy/laser)
	layout = list(
		"################",
		"#..............#",
		"#.B............#",
		"#..............#",
		"#.......U......#",
		"#..............#",
		"#....V.........#",
		"#..............#",
		"#..............#",
		"################")

/datum/bot_scenario/tactics/opener
	var/went_off_at = 0

/datum/bot_scenario/tactics/opener/post_spawn()
	..()
	foe = stand_in(first_marker("V"), "Mark Target")

/datum/bot_scenario/tactics/opener/make_goal()
	return new /datum/bot_goal/traitor_kill/robust(null, foe)

/datum/bot_scenario/tactics/opener/check()
	if(!bot || QDELETED(bot) || bot.stat == DEAD)
		fail_reason = "bot died"
		return BOT_GYM_FAIL
	if(!tank_went_off())
		return BOT_GYM_PENDING
	if(!went_off_at)
		went_off_at = world.time
	if(world.time < went_off_at + 2 SECONDS)
		return BOT_GYM_PENDING //the blast lands a moment after the tank's gone (SSexplosions)
	if(!bot_transcript_said("is beside Mark Target - backing off"))
		fail_reason = "the tank went off, but not set up beside the mark"
		return BOT_GYM_FAIL
	if(bot.health < bot.maxHealth * 0.7)
		fail_reason = "got caught in its own blast ([bot.health] health)"
		return BOT_GYM_FAIL
	if(QDELETED(foe) || foe.health >= foe.maxHealth)
		fail_reason = "the blast missed the mark"
		return BOT_GYM_FAIL
	return BOT_GYM_PASS

// ---------------------------------------------------------------------------------------------
// Reading the threat
// ---------------------------------------------------------------------------------------------

/datum/bot_scenario/tactics/threat_tank
	name = "threat: stood by a fuel tank, a gunman across the room, it gets away from the tank"
	desc = "Apex, unarmed, beside a fuel tank, in a fight with somebody holding a laser behind a window it can't get through. It doesn't stay by the tank for them to shoot: it gets four tiles off it."
	bot_skill = 1
	time_limit = 10 SECONDS
	layout = list(
		"###############",
		"#.........#...#",
		"#.........#...#",
		"#...UB....W.k.#",
		"#.........#...#",
		"#.........#...#",
		"###############")

/datum/bot_scenario/tactics/threat_tank/post_spawn()
	..()
	brain.nerve = 1 //it stands and fights rather than running from a gun (try_run_for_it(), bot_brain.dm), which would get it off the tank anyway
	foe = stand_in(first_marker("k"), "Gus Gunman")
	var/obj/item/gun/energy/laser/L = new(foe)
	foe.put_in_hands(L)
	brain.on_attacked(foe, "shot", L)

/datum/bot_scenario/tactics/threat_tank/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	return get_dist(bot, tank) >= 3 ? BOT_GYM_PASS : BOT_GYM_PENDING

// ---------------------------------------------------------------------------------------------
// Welding a door shut behind it (tier 2)
// ---------------------------------------------------------------------------------------------

/// Runs from somebody with a claymore, east through a door, a welder in its bag.
/datum/bot_scenario/tactics/weld_behind
	job = "Assistant"
	time_limit = 30 SECONDS
	kit_backpack = list(/obj/item/weldingtool)
	layout = list(
		"###################",
		"#..k....B.D.......#",
		"###################")

/// The door stands open, as one does mid-chase: run_from looks for floor it can walk to without a door (furthest_open_floor_from(),
/// bot_fighting.dm), and on the station for the places it knows of beyond them, which an arena hasn't got
/datum/bot_scenario/tactics/weld_behind/setup()
	..()
	var/obj/machinery/door/airlock/A = first_placed("D")
	A.autoclose = FALSE
	INVOKE_ASYNC(A, TYPE_PROC_REF(/obj/machinery/door/airlock, open))

/datum/bot_scenario/tactics/weld_behind/post_spawn()
	..()
	brain.nerve = 0.2 //it runs from a claymore (try_run_for_it(), bot_brain.dm)
	foe = stand_in(first_marker("k"), "Kit Killer")
	var/obj/item/claymore/C = new(foe)
	foe.put_in_hands(C)
	brain.on_attacked(foe, "attacked", C)

/datum/bot_scenario/tactics/weld_behind/proc/door_welded()
	var/obj/machinery/door/airlock/A = first_placed("D")
	return A && A.welded

/datum/bot_scenario/tactics/weld_behind/robust
	name = "tactics: running from a killer through a door, a robust bot welds it shut behind it"
	desc = "Mid skill, a welder in its bag, running from somebody with a claymore: through the door, and with them well back, it welds the door shut behind it. A player being chased with a welder does."

/datum/bot_scenario/tactics/weld_behind/robust/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	return door_welded() ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/tactics/weld_behind/low_skill
	name = "tactics: a low-skill bot running through a door doesn't weld it"
	desc = "The same chase for an ordinary player: through the door and on, no welding."
	bot_skill = 0.3
	time_limit = 15 SECONDS

/datum/bot_scenario/tactics/weld_behind/low_skill/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(door_welded())
		fail_reason = "a low-skill bot welded the door"
		return BOT_GYM_FAIL
	return BOT_GYM_PENDING

/datum/bot_scenario/tactics/weld_behind/low_skill/on_timeout()
	return BOT_GYM_PASS

// ---------------------------------------------------------------------------------------------
// More threats
// ---------------------------------------------------------------------------------------------

/datum/bot_scenario/tactics/threat_dragged
	name = "threat: the one it's fighting drags a fuel tank up to it, it gets clear"
	desc = "Apex, unarmed, in a fight with somebody who's dragging a fuel tank up to it, three tiles off: the user's trick from the other side. It gets six tiles from the tank rather than going for them past it."
	bot_skill = 1
	time_limit = 10 SECONDS
	layout = list(
		"################",
		"#..............#",
		"#....B..Uk.....#",
		"#..............#",
		"################")

/datum/bot_scenario/tactics/threat_dragged/post_spawn()
	..()
	brain.nerve = 1 //it stands and fights
	foe = stand_in(first_marker("k"), "Dex Dragger")
	foe.start_pulling(tank)
	brain.on_attacked(foe, "attacked", null)

/datum/bot_scenario/tactics/threat_dragged/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	return get_dist(bot, tank) >= BOT_TANK_CLEAR ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/tactics/threat_canister
	name = "threat: a plasma canister let go in the room, it gets out before the air goes"
	desc = "Apex, three tiles from a canister of plasma somebody's opened with nothing on its port. It gets out of the room at once, not once it's breathing plasma."
	bot_skill = 1
	time_limit = 15 SECONDS
	layout = list(
		"####################",
		"#.........#........#",
		"#.B..O....D.......G#",
		"#.........#........#",
		"####################")
	var/obj/machinery/portable_atmospherics/canister/toxins/canister

/datum/bot_scenario/tactics/threat_canister/setup()
	..()
	canister = new(first_marker("O"))
	place("O", canister)

/datum/bot_scenario/tactics/threat_canister/post_spawn()
	..()
	canister.valve_open = TRUE
	canister.update_icon()

/datum/bot_scenario/tactics/threat_canister/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(bot.getToxLoss() > 0)
		fail_reason = "breathed the plasma before getting out ([bot.getToxLoss()] toxin)"
		return BOT_GYM_FAIL
	return get_dist(bot, canister) >= 8 ? BOT_GYM_PASS : BOT_GYM_PENDING

// ---------------------------------------------------------------------------------------------
// Welded doors put right (goals/unweld_doors.dm)
// ---------------------------------------------------------------------------------------------

/datum/bot_scenario/duty/unweld
	duty_type = /datum/bot_duty/unweld_doors
	job = "Station Engineer"
	time_limit = 40 SECONDS
	kit_backpack = list(/obj/item/weldingtool)
	layout = list(
		"##########",
		"#B...D...#",
		"##########")
	var/obj/machinery/door/airlock/door

/datum/bot_scenario/duty/unweld/setup()
	door = first_placed("D")
	door.welded = TRUE
	door.update_icon()
	GLOB.bot_welds_seen[door] = world.time - 5 MINUTES //seen welded a while back: the chase is long over

/datum/bot_scenario/duty/unweld/release_run()
	GLOB.bot_welds_seen -= door
	GLOB.bot_roundstart_welded -= door
	return ..()

/datum/bot_scenario/duty/unweld/put_right
	name = "upkeep: an engineer cuts open a door welded in the round"
	desc = "A door somebody welded shut behind them in a chase, a while ago. The engineer with a welder on it cuts it open again, as station upkeep (the user's ruling, 2026-11-13)."

/datum/bot_scenario/duty/unweld/put_right/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	return door.welded ? BOT_GYM_PENDING : BOT_GYM_PASS

/datum/bot_scenario/duty/unweld/from_roundstart
	name = "upkeep: an engineer leaves a door that was welded when the round began"
	desc = "The same door, but welded since the round began (the map's abandoned rooms): it's left as it is."
	time_limit = 20 SECONDS

/datum/bot_scenario/duty/unweld/from_roundstart/setup()
	..()
	GLOB.bot_roundstart_welded[door] = TRUE

/datum/bot_scenario/duty/unweld/from_roundstart/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(!door.welded)
		fail_reason = "cut open a door that was welded from the start"
		return BOT_GYM_FAIL
	return BOT_GYM_PENDING

/datum/bot_scenario/duty/unweld/from_roundstart/on_timeout()
	return BOT_GYM_PASS

// ---------------------------------------------------------------------------------------------
// Security and the tank; cover from a gun
// ---------------------------------------------------------------------------------------------

/datum/bot_scenario/tactics/officer_tank
	name = "tactics: a robust officer after an armed murderer stood by a fuel tank shoots the tank"
	desc = "Mid skill, an energy gun on disable, after a murderer with a claymore who's stood beside a fuel tank seven tiles off, nobody else about. Somebody it may shoot to kill (bot_may_use_lethal_force()): it switches to the laser and shoots the tank."
	job = "Security Officer"
	kit_hands = list(/obj/item/gun/energy/e_gun)
	kit_backpack = list(/obj/item/restraints/handcuffs)
	layout = list(
		"######################",
		"#....................#",
		"#B......U............#",
		"#.......k............#",
		"######################")

/datum/bot_scenario/tactics/officer_tank/post_spawn()
	..()
	foe = stand_in(first_marker("k"), "Mo Murderer")
	foe.put_in_hands(new /obj/item/claymore(foe))
	var/datum/bot_wanted/W = new
	W.severity = BOT_CRIME_MAJOR
	W.crime = "Murder"
	W.last_seen = get_turf(foe)
	W.last_seen_at = world.time
	GLOB.bot_security_wanted[WEAKREF(foe)] = W
	brain.begin_arrest(foe)

/datum/bot_scenario/tactics/officer_tank/release_run()
	GLOB.bot_security_wanted -= WEAKREF(foe)
	return ..()

/datum/bot_scenario/tactics/officer_tank/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(!tank_went_off())
		return BOT_GYM_PENDING
	if(bot.health < bot.maxHealth * 0.7)
		fail_reason = "set off the tank and got caught in it ([bot.health] health)"
		return BOT_GYM_FAIL
	return BOT_GYM_PASS

/datum/bot_scenario/tactics/cover
	name = "threat: a gunman across the room and nothing to shoot back with, it gets into cover"
	desc = "Apex, unarmed, brave, in a fight with somebody holding a laser six tiles off across open floor, a pillar between them to one side. It doesn't charge across the open floor: it gets behind the pillar, out of the line of fire, and waits there."
	bot_skill = 1
	time_limit = 8 SECONDS
	layout = list(
		"##############",
		"#............#",
		"#.....#......#",
		"#.B.....k....#",
		"#............#",
		"##############")
	var/covered_since = 0

/datum/bot_scenario/tactics/cover/post_spawn()
	..()
	brain.nerve = 1 //it stands and fights rather than running from a gun
	foe = stand_in(first_marker("k"), "Gus Gunman")
	var/obj/item/gun/energy/laser/L = new(foe)
	foe.put_in_hands(L)
	brain.on_attacked(foe, "shot", L)

/datum/bot_scenario/tactics/cover/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(bot_clear_line(get_turf(bot), foe))
		covered_since = 0
		return BOT_GYM_PENDING
	if(!covered_since)
		covered_since = world.time
	return world.time >= covered_since + 2 SECONDS ? BOT_GYM_PASS : BOT_GYM_PENDING

// ---------------------------------------------------------------------------------------------
// Barricading the door behind it; the tank at the only way out
// ---------------------------------------------------------------------------------------------

/datum/bot_scenario/tactics/barricade
	name = "tactics: run into a room from a killer, a robust bot drags a locker across the door"
	desc = "Mid skill, running from somebody with a claymore through a door into a room with a locker in it, them out of sight behind the door. It drags the locker across the inside of the doorway and stands behind it."
	job = "Assistant"
	time_limit = 30 SECONDS
	layout = list(
		"####################",
		"#k......B.D........#",
		"###########L.......#",
		"###########........#",
		"####################")

/datum/bot_scenario/tactics/barricade/setup()
	..()
	var/obj/machinery/door/airlock/A = first_placed("D")
	A.autoclose = FALSE
	INVOKE_ASYNC(A, TYPE_PROC_REF(/obj/machinery/door/airlock, open))

/datum/bot_scenario/tactics/barricade/post_spawn()
	..()
	brain.nerve = 0.2 //it runs from a claymore
	foe = stand_in(first_marker("k"), "Kit Killer")
	var/obj/item/claymore/C = new(foe)
	foe.put_in_hands(C)
	brain.on_attacked(foe, "attacked", C)

/datum/bot_scenario/tactics/barricade/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	var/turf/inner = get_step(first_marker("D"), EAST)
	for(var/obj/structure/closet/C in inner)
		return BOT_GYM_PASS
	return BOT_GYM_PENDING

/datum/bot_scenario/tactics/ambush
	name = "tactics: an apex killer parks a fuel tank at the only way out of its mark's room and waits"
	desc = "Apex, a laser on it, its mark in a room with one door and a fuel tank in the corridor outside. It doesn't go in after them: it parks the tank beside the outside of the door, waits out of the blast where it can see it, and shoots the tank when the mark comes out past it."
	bot_skill = 1
	time_limit = 60 SECONDS
	kit_hands = list(/obj/item/gun/energy/laser)
	layout = list(
		"########################",
		"#......#...............#",
		"#..V...D.......U.......#",
		"#......#...............#",
		"#......#............B..#",
		"########################")

/datum/bot_scenario/tactics/ambush/post_spawn()
	..()
	foe = stand_in(first_marker("V"), "Mark Target")

/datum/bot_scenario/tactics/ambush/make_goal()
	return new /datum/bot_goal/traitor_kill/robust(null, foe)

/datum/bot_scenario/tactics/ambush/check()
	if(!bot || QDELETED(bot) || bot.stat == DEAD)
		fail_reason = "bot died"
		return BOT_GYM_FAIL
	// Once the tank's parked, the mark comes out, a step a second
	var/turf/out = get_step(first_marker("D"), EAST)
	if(!tank_went_off() && bot_transcript_said("parked at the way out") && !QDELETED(foe) && get_turf(foe) != out)
		foe.forceMove(get_step_towards(foe, out))
	if(!tank_went_off())
		return BOT_GYM_PENDING
	if(!bot_transcript_said("parked at the way out"))
		fail_reason = "the tank went off, but it wasn't parked at the way out"
		return BOT_GYM_FAIL
	if(bot.health < bot.maxHealth * 0.7)
		fail_reason = "got caught in its own blast ([bot.health] health)"
		return BOT_GYM_FAIL
	if(QDELETED(foe) || foe.health >= foe.maxHealth)
		fail_reason = "the blast missed the mark"
		return BOT_GYM_FAIL
	return BOT_GYM_PASS
