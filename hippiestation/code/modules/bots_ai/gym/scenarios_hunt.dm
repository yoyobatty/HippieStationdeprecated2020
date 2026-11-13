// Bot Gym: hide and seek (foundation/hunt.dm, apex/director.dm). An officer after a murderer who's ducked into a locker somewhere it didn't
// see: it searches, by skill; an apex one is steered by the director's clues.
//
// Layout letters used here: L a locker (bot_gym.dm), h the locker the suspect is hiding in, s where the suspect was last seen.

/datum/bot_scenario/hunt
	job = "Security Officer"
	time_limit = 60 SECONDS
	kit_backpack = list(/obj/item/restraints/handcuffs)
	var/bot_skill = 0.7
	var/mob/living/carbon/human/suspect
	var/obj/structure/closet/hideout

/datum/bot_scenario/hunt/setup()
	for(var/turf/T as anything in markers["h"])
		hideout = new(T)
		place("h", hideout)

/datum/bot_scenario/hunt/post_spawn()
	brain.skill = bot_skill
	suspect = stand_in(get_turf(hideout), "Mo Murderer")
	suspect.forceMove(hideout)
	var/datum/bot_wanted/W = new
	W.severity = BOT_CRIME_MAJOR
	W.crime = "Murder"
	W.last_seen = first_marker("s")
	W.last_seen_at = world.time
	GLOB.bot_security_wanted[WEAKREF(suspect)] = W
	brain.begin_arrest(suspect)
	// Last seen out on the floor a while ago, not getting into the locker: the arrest has thirty seconds of looking where they were
	// before it counts them lost (BOT_ARREST_LOST_TIMEOUT); two of those are left
	brain.arrest_last_seen_turf = first_marker("s")
	brain.arrest_last_seen = world.time - 28 SECONDS

/datum/bot_scenario/hunt/make_goal()
	return null //the arrest is the job

/datum/bot_scenario/hunt/release_run()
	GLOB.bot_security_wanted -= WEAKREF(suspect)
	return ..()

/datum/bot_scenario/hunt/proc/found()
	return !QDELETED(suspect) && (isturf(suspect.loc) || suspect.handcuffed)

/datum/bot_scenario/hunt/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	return found() ? BOT_GYM_PASS : BOT_GYM_PENDING //found by the search, or seen once it opened the locker (look_out_for_trouble())

/datum/bot_scenario/hunt/lockers
	name = "hunt: an officer loses a murderer and searches the lockers till it finds him"
	desc = "Mid skill. A murderer last seen by a row of lockers, gone into the far one. The officer counts him lost and, rather than going back to its rounds, opens the lockers nearest where he was seen till it finds him, then arrests him."
	layout = list(
		"################",
		"#B.............#",
		"#.......s......#",
		"#.....L.L.L.h..#",
		"#..............#",
		"################")

/datum/bot_scenario/hunt/low_skill
	name = "hunt: a low-skill officer opens a couple of lockers and gives up"
	desc = "The same, for an ordinary player: it looks in the nearest few and gives up, the murderer in the far one."
	bot_skill = 0.3
	time_limit = 50 SECONDS
	layout = list(
		"################",
		"#B.............#",
		"#.......s......#",
		"#...L.L.L.L.h..#",
		"#..............#",
		"################")

/datum/bot_scenario/hunt/low_skill/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(bot_transcript_said("HUNT: gave up") || bot_transcript_said("HUNT: nowhere left"))
		return found() ? BOT_GYM_FAIL : BOT_GYM_PASS
	return BOT_GYM_PENDING

/datum/bot_scenario/hunt/far_hideout
	time_limit = 80 SECONDS
	layout = list(
		"##########################",
		"#B.......................#",
		"#..L.s.L...........L.h.L.#",
		"#........................#",
		"##########################")

/datum/bot_scenario/hunt/far_hideout/apex
	name = "hunt: an apex officer, steered by the director, finds a murderer hidden across the room"
	desc = "Apex. The murderer was last seen by the lockers at one end and is in one at the far end, out of reach of a search round where he was seen. The director's clue of roughly where he is (never the tile) takes it to the far end, and it finds him."
	bot_skill = 1

/datum/bot_scenario/hunt/far_hideout/apex/check()
	. = ..()
	if(. == BOT_GYM_PASS && !bot_transcript_said("DIRECTOR:"))
		fail_reason = "found him without a clue: the test isn't testing the director"
		return BOT_GYM_FAIL

/datum/bot_scenario/hunt/far_hideout/mid
	name = "hunt: a robust officer with no director searches where he was seen, not across the room"
	desc = "The same for a robust officer: no director, so it searches round where he was last seen, finds nothing and gives up. Nobody beelines to somebody they never saw go there."
	bot_skill = 0.7
	time_limit = 60 SECONDS

/datum/bot_scenario/hunt/far_hideout/mid/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(found())
		fail_reason = "found him with nothing to go on"
		return BOT_GYM_FAIL
	return (bot_transcript_said("HUNT: gave up") || bot_transcript_said("HUNT: nowhere left")) ? BOT_GYM_PASS : BOT_GYM_PENDING

/// An antag hunter (a vigilante, bot_playstyles.dm) goes to where a wanted murderer was last seen: he's gone into a locker by then.
/datum/bot_scenario/duty/hunter_search
	name = "hunt: a vigilante at a murderer's last sighting finds nobody, and searches the lockers"
	desc = "Mid skill, an antag hunter with a toolbox, after a murderer the radio last put by some lockers. He's ducked into one by the time it gets there: it searches rather than standing at the sighting (it used to go to the spot and stop)."
	duty_type = /datum/bot_duty/hunt_valids
	job = "Assistant"
	time_limit = 50 SECONDS
	kit_hands = list(/obj/item/storage/toolbox/mechanical)
	layout = list(
		"################",
		"#B.............#",
		"#.......s......#",
		"#.....L.L.L.h..#",
		"#..............#",
		"################")
	var/mob/living/carbon/human/suspect
	var/obj/structure/closet/hideout
	var/hidden = FALSE

/datum/bot_scenario/duty/hunter_search/setup()
	hideout = new(first_marker("h"))
	place("h", hideout)

/datum/bot_scenario/duty/hunter_search/post_spawn()
	brain.skill = 0.7
	brain.set_playstyle(BOT_STYLE_HUNTER)
	brain.nerve = 1
	suspect = stand_in(first_marker("s"), "Mo Murderer")
	var/datum/bot_wanted/W = new
	W.severity = BOT_CRIME_MAJOR
	W.crime = "Murder"
	W.last_seen = first_marker("s")
	W.last_seen_at = world.time
	GLOB.bot_security_wanted[WEAKREF(suspect)] = W

/datum/bot_scenario/duty/hunter_search/release_run()
	GLOB.bot_security_wanted -= WEAKREF(suspect)
	return ..()

/// Into the locker the moment the hunt's on
/datum/bot_scenario/duty/hunter_search/issue_goal()
	..()
	if(!hidden && istype(brain.current_goal, /datum/bot_goal/hunt))
		hidden = TRUE
		suspect.forceMove(hideout)

/datum/bot_scenario/duty/hunter_search/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(hidden && isturf(suspect.loc))
		return BOT_GYM_PASS
	return BOT_GYM_PENDING

// ---------------------------------------------------------------------------------------------
// Killers who haven't seen their mark (foundation/hunt.dm mark_whereabouts())
// ---------------------------------------------------------------------------------------------

/// A killer after somebody in the next room, behind a wall: never seen them, and no post to start from (a stand-in has no job).
/datum/bot_scenario/unseen_mark
	time_limit = 40 SECONDS
	kit_hands = list(/obj/item/kitchen/knife)
	layout = list(
		"####################",
		"#B.......#.........#",
		"#........#.........#",
		"#........D......V..#",
		"#........#.........#",
		"####################")
	var/bot_skill = 1
	var/mob/living/carbon/human/mark

/datum/bot_scenario/unseen_mark/post_spawn()
	brain.skill = bot_skill
	mark = stand_in(first_marker("V"), "Mark Target")

/datum/bot_scenario/unseen_mark/make_goal()
	return new /datum/bot_goal/traitor_kill/robust(null, mark)

/datum/bot_scenario/unseen_mark/apex
	name = "hunt: an apex killer that's never seen its mark goes by the director's word"
	desc = "Apex, after somebody in the next room it's never laid eyes on. It used to walk straight to them, wherever they were. It goes to where the director says they roughly are, sees them, and goes for them."

/datum/bot_scenario/unseen_mark/apex/check()
	if(!bot || QDELETED(bot) || bot.stat == DEAD)
		fail_reason = "bot died"
		return BOT_GYM_FAIL
	if(!QDELETED(mark) && mark.health < mark.maxHealth)
		if(!bot_transcript_said("DIRECTOR:"))
			fail_reason = "got to them without a clue: it still knows where they are"
			return BOT_GYM_FAIL
		return BOT_GYM_PASS
	return BOT_GYM_PENDING

/datum/bot_scenario/unseen_mark/mid
	name = "hunt: a killer with nothing to go on doesn't walk straight to its mark"
	desc = "The same for a killer below apex: never seen them, no post to look from, no director. It can't know where they are, and doesn't go straight to them."
	bot_skill = 0.7
	time_limit = 20 SECONDS

/datum/bot_scenario/unseen_mark/mid/check()
	if(!bot || QDELETED(bot) || bot.stat == DEAD)
		fail_reason = "bot died"
		return BOT_GYM_FAIL
	if(get_dist(bot, mark) <= 3)
		fail_reason = "went straight to somebody it had no way of knowing where they were"
		return BOT_GYM_FAIL
	return BOT_GYM_PENDING

/datum/bot_scenario/unseen_mark/mid/on_timeout()
	return BOT_GYM_PASS
