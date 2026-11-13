// Bot Gym: escape rooms (foundation/escape.dm). Sealed situations with a way out, by skill.

/datum/bot_scenario/escape
	time_limit = 40 SECONDS
	/// Its skill (foundation/skill.dm)
	var/bot_skill = 1

/datum/bot_scenario/escape/post_spawn()
	brain.skill = bot_skill

/datum/bot_scenario/escape/apex_window
	name = "escape: apex, shut in behind a window, breaks out"
	desc = "Shut in a room on its own business, calm, with only a window between it and where it's going and a fire axe in hand. Breaking things was only ever for an emergency, so an apex bot stood there like an assistant waiting to be let out. It smashes its way out."
	kit_hands = list(/obj/item/twohanded/fireaxe)
	layout = list(
		"#########",
		"#B..#...#",
		"#...W..G#",
		"#########")

/datum/bot_scenario/escape/mid_window
	name = "escape: mid skill, shut in behind a window, leaves it alone"
	desc = "The same room for a bot below apex. It isn't in danger, so it doesn't smash the window: nothing changes below apex."
	bot_skill = 0.7
	time_limit = 20 SECONDS
	kit_hands = list(/obj/item/twohanded/fireaxe)
	layout = list(
		"#########",
		"#B..#...#",
		"#...W..G#",
		"#########")

/datum/bot_scenario/escape/mid_window/check()
	if(!bot || QDELETED(bot) || bot.stat == DEAD)
		fail_reason = "bot died"
		return BOT_GYM_FAIL
	for(var/obj/structure/window/W as anything in placed["W"])
		if(QDELETED(W) || W.obj_integrity < W.max_integrity)
			fail_reason = "went at the window, calm and below apex"
			return BOT_GYM_FAIL
	return BOT_GYM_PENDING

/datum/bot_scenario/escape/mid_window/on_timeout()
	return BOT_GYM_PASS

/datum/bot_scenario/escape/apex_everyday
	name = "escape: apex on its everyday work doesn't break out"
	desc = "Apex, shut in behind a window, but on an everyday errand: it keeps to what anybody on the job would do and leaves the window alone."
	time_limit = 20 SECONDS
	kit_hands = list(/obj/item/twohanded/fireaxe)
	layout = list(
		"#########",
		"#B..#...#",
		"#...W..G#",
		"#########")

/datum/bot_scenario/escape/apex_everyday/make_goal()
	var/datum/bot_goal/gym_reach/G = ..()
	G.lawful = TRUE
	return G

/datum/bot_scenario/escape/apex_everyday/check()
	if(!bot || QDELETED(bot) || bot.stat == DEAD)
		fail_reason = "bot died"
		return BOT_GYM_FAIL
	for(var/obj/structure/window/W as anything in placed["W"])
		if(QDELETED(W) || W.obj_integrity < W.max_integrity)
			fail_reason = "broke a window on an everyday errand"
			return BOT_GYM_FAIL
	return BOT_GYM_PENDING

/datum/bot_scenario/escape/apex_everyday/on_timeout()
	return BOT_GYM_PASS

/// An apex officer after somebody behind a window: through it for a major crime, not for a minor one (the user's ruling, 2026-11-04).
/datum/bot_scenario/escape/arrest_window
	job = "Security Officer"
	time_limit = 20 SECONDS
	kit_hands = list(/obj/item/twohanded/fireaxe)
	kit_backpack = list(/obj/item/restraints/handcuffs)
	// room enough on the officer's side (70 tiles) that it isn't shut in (BOT_SHUT_IN_TILES, bot_doors.dm), which is a reason of its own
	layout = list(
		"################",
		"#..........#...#",
		"#..........#...#",
		"#.........BW.K.#",
		"#..........#...#",
		"#..........#...#",
		"#..........#...#",
		"#..........#...#",
		"################")
	var/severity = BOT_CRIME_MINOR
	var/mob/living/carbon/human/suspect

/datum/bot_scenario/escape/arrest_window/post_spawn()
	..()
	suspect = stand_in(first_marker("K"), "Wes Wanted")
	var/datum/bot_wanted/W = new
	W.severity = severity
	W.crime = severity >= BOT_CRIME_MAJOR ? "Murder" : "Trespass"
	W.last_seen = get_turf(suspect)
	W.last_seen_at = world.time
	GLOB.bot_security_wanted[WEAKREF(suspect)] = W
	brain.begin_arrest(suspect)

/datum/bot_scenario/escape/arrest_window/make_goal()
	return null //the arrest is the job

/datum/bot_scenario/escape/arrest_window/proc/window_hit()
	for(var/obj/structure/window/W as anything in placed["W"])
		if(QDELETED(W) || W.obj_integrity < W.max_integrity)
			return TRUE
	return FALSE

/datum/bot_scenario/escape/arrest_window/release_run()
	GLOB.bot_security_wanted -= WEAKREF(suspect)
	return ..()

/datum/bot_scenario/escape/arrest_window/minor
	name = "escape: apex officer after a minor charge behind a window leaves the window alone"
	desc = "An apex officer after somebody wanted for trespass, stood behind a window. Breaking in to chase is for serious crimes only: it doesn't take the axe to the window. One broke into the Head of Security's office through the window with a baton over low-threat trespassing (Bot Shift found_after run3)."

/datum/bot_scenario/escape/arrest_window/minor/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(window_hit())
		fail_reason = "went through the window over a minor charge"
		return BOT_GYM_FAIL
	return BOT_GYM_PENDING

/datum/bot_scenario/escape/arrest_window/minor/on_timeout()
	return BOT_GYM_PASS

/datum/bot_scenario/escape/arrest_window/major
	name = "escape: apex officer after a murderer behind a window goes through it"
	desc = "The same, for a murderer: an apex officer doesn't stand at the glass, it takes the axe to it."
	severity = BOT_CRIME_MAJOR

/datum/bot_scenario/escape/arrest_window/major/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	return window_hit() ? BOT_GYM_PASS : BOT_GYM_PENDING
