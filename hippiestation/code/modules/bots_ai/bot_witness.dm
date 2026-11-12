// Witnesses: what the crew does about what it sees, past what's done to the bot itself. Security always reacted to violence
// in front of it (goals/security_patrol.dm). Everybody else carried on with their work while a griefer smashed their
// department up and beat their friends to death around them. Now:
//
//  - Somebody being attacked in front of it: a bot with the nerve steps in, one without gets out of the way, and whoever's
//    left shouts about it. The first one to see it calls it in, over the radio, once.
//  - Somebody smashing the place up: told to stop, called in, written up. Security comes for them, and staff of the
//    department it's happening in don't leave it to them if they've the nerve.
//  - Somebody in a staff-only room who has no business there: asked to leave, and reported if they won't.
//  - Somebody known to be dangerous, seen coming: the crew knows, from the radio or the records. They keep clear of them,
//    or the ones with the nerve and something to hit them with take them on, and it goes out on the radio where they are.
//  - A bomb going live in sight: it's called out, and everybody runs.
//
// Things crew do to the station in an emergency, or a bot's own ordinary work, don't count: only somebody with no good
// reason (bot_means_well(), bot_reflexes.dm).

/// Bots already fighting somebody before another one thinks better of joining in.
#define BOT_DOGPILE_LIMIT 3
/// How often a bot takes in what's going on in the room.
#define BOT_WATCH_INTERVAL (5 SECONDS)
/// Between one word and the next to somebody who shouldn't be in here, and from the second word to calling them in.
#define BOT_TRESPASS_PATIENCE (20 SECONDS)
/// Swings at the station before the vandal goes on the record as more than a nuisance.
#define BOT_VANDAL_MAJOR_HITS 10

/// What counts as the station's property to smash. Not items, and nothing that's somebody's mess.
GLOBAL_LIST_INIT(bot_vandal_targets, typecacheof(list(
	/obj/machinery,
	/obj/structure/window,
	/obj/structure/grille,
	/obj/structure/table,
	/obj/structure/rack,
	/obj/structure/closet,
	/obj/structure/displaycase,
	/obj/structure/fireaxecabinet,
	/obj/structure/extinguisher_cabinet,
	/obj/structure/sign,
	/obj/structure/mirror,
	/obj/structure/reagent_dispensers,
)))
/// Rooms with staff, by area type (checked with istype, so the first match). Jobs from GLOB.*_positions, read when asked.
GLOBAL_LIST_INIT(bot_staff_areas, list(
	/area/engine = "engineering",
	/area/storage/tech = "engineering",
	/area/medical/chemistry = "medical",
	/area/medical/surgery = "medical",
	/area/medical/virology = "medical",
	/area/medical/genetics = "medical",
	/area/medical/storage = "medical",
	/area/science/lab = "science",
	/area/science/robotics = "science",
	/area/science/server = "science",
	/area/science/mixing = "science",
	/area/science/xenobiology = "science",
	/area/bridge = "command",
	/area/crew_quarters/heads = "command",
	/area/security/warden = "security",
	/area/ai_monitored/security/armory = "security",
	/area/security/main = "security",
	/area/security/prison = "security",
	/area/security/execution = "security",
	/area/quartermaster/qm = "supply",
	/area/quartermaster/storage = "supply",
))

GLOBAL_LIST_INIT(bot_saw_attack_lines, list(
	"Hey! Stop that!",
	"What are you doing?!",
	"Leave them alone!",
	"Somebody stop them!",
	"Whoa, whoa, whoa!",
	"Get off them!",
))

GLOBAL_LIST_INIT(bot_saw_vandal_lines, list(
	"Hey! Stop smashing that!",
	"What the hell are you doing?!",
	"Hey! Knock that off!",
	"That's station property!",
	"Cut it out!",
	"Are you insane?!",
))

GLOBAL_LIST_INIT(bot_own_turf_lines, list(
	"Get out of my department!",
	"Not in here you don't!",
	"I work here! Get out!",
))

GLOBAL_LIST_INIT(bot_trespass_lines, list(
	"Hey, you're not supposed to be in here.",
	"Staff only, sorry. Who let you in?",
	"Can I help you? This is a restricted area.",
	"You need to leave.",
))

/mob/living/carbon/human
	/// Swings at the station in the current spree, when the last one was, and when it was last called in.
	var/bot_vandal_hits = 0
	var/bot_vandal_last = 0
	var/bot_vandal_called_in = 0
	/// When an attack by this person was last called in, so one fight isn't reported by everybody who saw it.
	var/bot_attack_called_in = 0

/datum/bot_brain
	/// When it can next react to something it saw happen.
	var/next_witness_time = 0
	/// When it next takes a look round for trouble.
	var/next_watch_time = 0
	/// Somebody it's told to leave -> when it told them.
	var/list/trespass_warned
	/// When it last called a sighting in on the radio.
	var/next_sighting_call = 0

/// The bots who can see `seen` from where they stand, in no special order, other than the ones listed in `except`.
/proc/bot_witnesses_of(atom/seen, list/except)
	. = list()
	var/turf/T = get_turf(seen)
	if(!T)
		return
	for(var/datum/bot_brain/B as anything in GLOB.bot_brains)
		var/mob/living/carbon/human/H = B.owner
		if(QDELETED(H) || (H in except) || H.stat != CONSCIOUS || H.z != T.z || get_dist(H, T) > BOT_SIGHT_RANGE || is_blind(H))
			continue
		if(T in view(BOT_SIGHT_RANGE, H))
			. += B

/// Whether this bot would call the place its own: it works here. Uses the staff areas above, or failing that its wander keywords.
/datum/bot_brain/proc/is_my_department(area/A)
	if(gym_run)
		return gym_run.arena_is_home
	var/list/staff = bot_staff_of(A)
	if(staff)
		return work_role() in staff
	var/list/keywords = GLOB.bot_department_keywords[work_role()]
	for(var/keyword in keywords)
		if(findtext(A.name, keyword))
			return TRUE
	return FALSE

/// The jobs that work in this area, or null if it isn't staff-only.
/proc/bot_staff_of(area/A)
	var/area/bot_gym/arena = A
	if(istype(arena))
		return arena.staff_jobs
	for(var/area_type in GLOB.bot_staff_areas)
		if(istype(A, area_type))
			switch(GLOB.bot_staff_areas[area_type])
				if("engineering")
					return GLOB.engineering_positions
				if("medical")
					return GLOB.medical_positions
				if("science")
					return GLOB.science_positions
				if("command")
					return GLOB.command_positions
				if("security")
					return GLOB.security_positions
				if("supply")
					return GLOB.supply_positions
	return null

/// Radios that somebody's up to something where they are, unless somebody's beaten it to it. Names them if it can see their
/// face, and has whoever's on duty put it on their record, the same as bot_call_security() (goals/security_patrol.dm).
/datum/bot_brain/proc/call_it_in(mob/living/carbon/human/culprit, crime, details, severity, mob/living/victim)
	if(gone_loud()) //goals/robust.dm: nobody Security's after calls Security
		return
	var/who = culprit.name
	var/where = get_area_name(culprit, TRUE)
	var/line = "[who] [details] in [where]!"
	if(!who || who == "Unknown")
		line = "Somebody [details] in [where]!"
	bot_say(owner, ";Security! [line]")
	bot_log(src, "called in [culprit]: [crime]")
	bot_tally("called in")
	if(!length(GLOB.bot_security_brains) || !who || who == "Unknown")
		return
	var/datum/bot_brain/officer = GLOB.bot_security_brains[1]
	var/datum/bot_wanted/existing = bot_get_wanted_entry(culprit)
	if(!existing || existing.severity < severity)
		officer.file_crime(culprit, crime, "[capitalize(details)] in [where] (reported by [owner.real_name]).", severity, victim)

// ---------------------------------------------------------------------------------------------
// Somebody being attacked
// ---------------------------------------------------------------------------------------------

/// A tick after a blow lands, so the victim's condition reads after it. From bot_security_witness_combat().
/proc/bot_crew_witness_combat(mob/living/carbon/human/assailant, mob/living/carbon/human/victim, what_done, atom/object)
	if(GLOB.bot_reflexes_off || QDELETED(assailant) || QDELETED(victim))
		return
	if(bot_means_well(assailant) && !istype(assailant.bot_brain?.current_goal, /datum/bot_goal/traitor_kill))
		return //a bot hitting somebody means it's defending itself, or it's an officer about their job
	// Hitting back at somebody who started it isn't anything to get involved in.
	var/their_first = GLOB.bot_recent_aggression["[REF(victim)]>[REF(assailant)]"]
	var/our_first = GLOB.bot_recent_aggression["[REF(assailant)]>[REF(victim)]"]
	if(their_first && their_first < our_first)
		return
	if(bot_is_officer(assailant))
		return
	if(bot_is_fair_game(victim) || (bot_is_wanted(victim) && victim.stat != DEAD)) //fair game, as Security sees it (bot_security_judge_combat())
		return
	if(bot_lawful_execution(assailant, victim) || bot_hit_a_corpse(victim)) //bot_law.dm
		return
	var/place = get_area_name(victim, TRUE)
	for(var/datum/bot_brain/B as anything in bot_witnesses_of(victim, list(assailant, victim)))
		B.learn_fact(BOT_FACT_ATTACKED, assailant, victim, place) //bot_memory.dm
		B.on_saw_violence(assailant, victim)

/datum/bot_brain/proc/on_saw_violence(mob/living/carbon/human/assailant, mob/living/carbon/human/victim)
	if(state == BOT_STATE_COMBAT && attacker == assailant)
		last_hit_by_attacker = world.time //its fight's still going on
		return
	if(is_security_job() || state == BOT_STATE_COMBAT || state == BOT_STATE_ARREST || world.time < next_witness_time || owner.incapacitated())
		return
	if(on_my_side(assailant) || (gone_loud() && !on_my_side(victim)))
		return //bot_brain.dm: nobody stops their own from doing what they came to do, and somebody who's turned on the crew doesn't stand up for them
	next_witness_time = world.time + 4 SECONDS
	if(istype(current_goal, /datum/bot_goal/brig_prisoner) || greytider) //a greytider's got its own troubles, and likes a fight
		return
	owner.face_atom(assailant)
	var/courage = nerve
	var/obj/item/theirs = assailant.get_active_held_item()
	if(theirs?.force >= 10)
		courage -= 0.3
	if(owner.get_active_held_item()?.force >= BOT_COMBAT_WEAPON_FORCE)
		courage += 0.2
	if(is_my_department(get_area(victim)))
		courage += 0.15
	// Friends (bot_social.dm): it backs a friend, and doesn't wade in against one
	if(is_friend(victim))
		courage += 0.35
	if(is_friend(assailant) && !is_friend(victim))
		courage -= 0.6
	if(playstyle == BOT_STYLE_HUNTER)
		courage += 0.3 //this is what it came for
	// Somebody needs to get on the radio, whatever else happens. Somebody in the same room as a fight usually does.
	if(!assailant.bot_attack_called_in || world.time > assailant.bot_attack_called_in + 30 SECONDS)
		assailant.bot_attack_called_in = world.time
		call_it_in(assailant, "Assault", "is attacking [victim.name]", BOT_CRIME_MINOR, victim)
	else if(world.time >= next_reaction_time)
		next_reaction_time = world.time + 30
		bot_say(owner, pick(GLOB.bot_saw_attack_lines))
	// A nanosuit: anybody, any time, whatever their nerve and however many are on it already (goals/fight_the_suit.dm)
	if(bot_suit_to_fight(assailant) && takes_on_suits(assailant))
		take_on_the_suit(assailant)
		return
	if(courage >= 0.65 && bot_fighters_against(assailant) < BOT_DOGPILE_LIMIT)
		step_in_against(assailant)
	else if(courage < 0.3 && get_dist(owner, assailant) <= 5)
		run_from(assailant, "somebody's getting hurt in here")

/// How many bots are fighting this person right now.
/proc/bot_fighters_against(mob/living/who)
	. = 0
	for(var/datum/bot_brain/B as anything in GLOB.bot_brains)
		if(B.attacker == who)
			.++

/// Takes them on, as if they'd hit it. They're the one who started it, as far as anybody coming along later can tell.
/datum/bot_brain/proc/step_in_against(mob/living/carbon/human/assailant)
	bot_log(src, "stepping in against [assailant]")
	bot_tally("stepped in")
	bot_record_aggression(assailant, owner)
	// Not hit itself, so nothing of its own to radio in: a doctor stepping in against the user radioed "Security! Mikayla Collins is
	// attacking me", and that went on the user's record as an assault on the doctor, who hadn't been touched
	next_assault_report_time = max(next_assault_report_time, world.time + 1 MINUTES)
	on_attacked(assailant, "stepped in", null)

// ---------------------------------------------------------------------------------------------
// Somebody smashing the place up
// ---------------------------------------------------------------------------------------------

/// From bot_security_witness_combat(), for every melee hit on an object in the game: keep it cheap.
/proc/bot_note_vandalism(mob/living/carbon/human/user, obj/target)
	if(GLOB.bot_reflexes_off || !ishuman(user) || !length(GLOB.bot_brains) || !is_type_in_typecache(target, GLOB.bot_vandal_targets) || bot_means_well(user))
		return
	if(world.time > user.bot_vandal_last + 1 MINUTES)
		user.bot_vandal_hits = 0
	user.bot_vandal_hits++
	user.bot_vandal_last = world.time
	for(var/datum/bot_brain/B as anything in bot_witnesses_of(user, list(user)))
		B.on_saw_vandalism(user, target)

/datum/bot_brain/proc/on_saw_vandalism(mob/living/carbon/human/vandal, obj/target)
	if(world.time < next_witness_time || owner.incapacitated() || state == BOT_STATE_ARREST || state == BOT_STATE_COMBAT || istype(current_goal, /datum/bot_goal/brig_prisoner))
		return
	next_witness_time = world.time + 4 SECONDS
	if(greytider)
		join_in_the_smashing(vandal)
		return
	owner.face_atom(vandal)
	var/major = vandal.bot_vandal_hits >= BOT_VANDAL_MAJOR_HITS
	var/crime = major ? "Major Vandalism" : "Vandalism"
	var/severity = major ? BOT_CRIME_MAJOR : BOT_CRIME_MINOR
	var/where = get_area_name(vandal, TRUE)
	if(is_security_job())
		var/datum/bot_wanted/existing = bot_get_wanted_entry(vandal)
		if(!existing || existing.severity < severity)
			file_crime(vandal, crime, "Smashing up [target] in [where].", severity)
			bot_say(owner, ":s [crime] in progress, [where] - suspect [vandal.name]. Responding.")
		begin_arrest(vandal)
		return
	var/mine = is_my_department(get_area(vandal))
	if(!vandal.bot_vandal_called_in || world.time > vandal.bot_vandal_called_in + 45 SECONDS)
		vandal.bot_vandal_called_in = world.time
		call_it_in(vandal, crime, "is smashing the place up", severity)
	else if(world.time >= next_reaction_time)
		next_reaction_time = world.time + 40
		bot_say(owner, pick(mine ? GLOB.bot_own_turf_lines : GLOB.bot_saw_vandal_lines))
	// Their own department, and they've the nerve for it: not leaving it to security.
	if(mine && nerve >= 0.6 && vandal.bot_vandal_hits >= 2 && bot_fighters_against(vandal) < BOT_DOGPILE_LIMIT)
		step_in_against(vandal)

/// Bombs, grenades and the like going live: from log_bomber().
/proc/bot_note_bomb(mob/living/user, atom/bomb)
	if(GLOB.bot_reflexes_off || !bomb || !length(GLOB.bot_brains))
		return
	var/called_out = FALSE
	for(var/datum/bot_brain/B as anything in bot_witnesses_of(bomb, list(user)))
		if(!called_out)
			called_out = TRUE
			bot_say(B.owner, ";[pick("BOMB!", "Bomb! Get out!", "Everybody out, bomb!")] [get_area_name(bomb, TRUE)]!")
		B.run_from(bomb, "there's a bomb")

// ---------------------------------------------------------------------------------------------
// Keeping an eye out
// ---------------------------------------------------------------------------------------------

/// A look round the room, every few seconds, from process().
/datum/bot_brain/proc/keep_an_eye_out()
	next_watch_time = world.time + BOT_WATCH_INTERVAL + rand(0, 2 SECONDS)
	if(GLOB.bot_reflexes_off || state == BOT_STATE_COMBAT || state == BOT_STATE_ARREST || gym_scripted)
		return
	if(look_out_for_bombers()) //bot_fighting.dm
		return
	if(length(GLOB.bot_security_wanted) || bot_any_suit_worn()) //goals/fight_the_suit.dm
		look_out_for_trouble()
	look_round_the_room() //bot_playstyles.dm
	watch_the_door()
	if(bot_any_loose_slime())
		notice_loose_slimes() //goals/sabotage_slimes.dm

/// Anybody in sight the crew knows to be dangerous. Anything less than a major crime is security's to deal with.
/datum/bot_brain/proc/look_out_for_trouble()
	if(is_security_job() || greytider)
		return
	for(var/mob/living/carbon/human/H in view(6, owner))
		if(H == owner || H.stat != CONSCIOUS || H.handcuffed)
			continue
		// A nanosuit in sight, wanted or not: it's Syndicate, and the crew goes for it (goals/fight_the_suit.dm)
		if(bot_suit_to_fight(H) && takes_on_suits(H))
			if(world.time >= next_sighting_call)
				next_sighting_call = world.time + 1 MINUTES
				var/who = H.name == "Unknown" ? "Somebody" : H.name //the helmet hides the face
				bot_say(owner, ";[who]'s here in a Syndicate suit, [get_area_name(owner, TRUE)]!")
			take_on_the_suit(H)
			return
		var/datum/bot_wanted/W = bot_get_wanted_entry(H)
		if(!W || W.severity < BOT_CRIME_MAJOR || is_in_active_cell(H))
			continue
		// Heard it on the radio, or it's on the records: everybody knows the face.
		if(world.time >= next_sighting_call)
			next_sighting_call = world.time + 1 MINUTES
			if(prob(50))
				bot_say(owner, ";[H.name] is here, in [get_area_name(owner, TRUE)]! Security!")
		// Somebody who's hurt people, that is: a doctor went for the user for having been seen with a sword, before they'd hurt anybody
		if(nerve >= 0.7 && has_a_weapon() && GLOB.bot_chaos_level >= 1 && bot_crime_is_violent(W.crime) && bot_fighters_against(H) < BOT_DOGPILE_LIMIT)
			bot_say(owner, pick("It's you!", "That's the one!", "Get them!"))
			step_in_against(H)
		else if(nerve < 0.5 && get_dist(owner, H) <= 4 && state != BOT_STATE_GOAL)
			run_from(H, "that's [H.name]")
		return

/// Somebody in the room where this bot works, who doesn't work here. Bots keep to what their ID opens unless they're up to
/// something, so that only ever means a player or a greytider.
/datum/bot_brain/proc/watch_the_door()
	var/area/here = get_area(owner)
	var/list/staff = bot_staff_of(here)
	if(!staff || !(work_role() in staff))
		return
	bot_refresh_open_departments() //bot_departments.dm
	// Open's open, to anybody but the strict ones, and it's nobody's business but the staff's if they want it that way.
	if(GLOB.bot_open_departments[bot_department_of(here)] && strictness < 0.6)
		return
	for(var/mob/living/carbon/human/H in view(6, owner))
		if(H == owner || H.stat != CONSCIOUS || H.handcuffed || bot_means_well(H) || H.bot_brain?.shut_in_result) //not much point arresting somebody for not leaving when they can't
			continue
		var/job = H.get_assignment("", "")
		if((job in staff) || (job in GLOB.command_positions) || (job in GLOB.security_positions))
			continue
		var/charge = bot_trespass_charge(get_area(H), world.time < H.bot_broke_in_at + 5 MINUTES)
		var/datum/weakref/ref = WEAKREF(H)
		var/warned = LAZYACCESS(trespass_warned, ref)
		// Fort Knox: no second telling in the brig, and the arrest is Security's own to make.
		if(is_security_job())
			if(!warned || world.time > warned + 5 MINUTES)
				LAZYSET(trespass_warned, ref, world.time)
				owner.face_atom(H)
				bot_say(owner, "[H.name], you can't be in here. Out, now.")
			else if(world.time > warned + 10 SECONDS)
				file_crime(H, charge, "In [get_area_name(H, TRUE)] with no business being there.", BOT_CRIME_MINOR)
				begin_arrest(H)
			return
		// Nobody but an engineer goes near the engine. There's no asking nicely about that.
		if(bot_near_the_engine(H) && (work_role() in GLOB.engineering_positions) && (!warned || world.time > warned + 5 MINUTES))
			LAZYSET(trespass_warned, ref, world.time)
			owner.face_atom(H)
			bot_say(owner, pick("Get away from the engine!", "What do you think you're doing down here?! OUT!", "You touch anything and we all die! Get out!"))
			call_it_in(H, charge, "is at the engine", BOT_CRIME_MAJOR)
			bot_tally("engine scares")
			bot_sound_engine_alarm()
			return
		if(!warned || world.time > warned + 5 MINUTES)
			LAZYSET(trespass_warned, ref, world.time)
			owner.face_atom(H)
			bot_say(owner, pick(GLOB.bot_trespass_lines))
			bot_log(src, "told [H] they shouldn't be in [here]")
		else if(world.time > warned + BOT_TRESPASS_PATIENCE)
			LAZYSET(trespass_warned, ref, world.time - 5 MINUTES + 1 MINUTES) //won't come round again for a minute
			call_it_in(H, charge, "won't leave", BOT_CRIME_MINOR)
			shut_them_in(H)
		return

#undef BOT_DOGPILE_LIMIT
#undef BOT_WATCH_INTERVAL
#undef BOT_TRESPASS_PATIENCE
#undef BOT_VANDAL_MAJOR_HITS

/// Whether a crime is one of hurting people: what crew take somebody on for, rather than leave to Security
/proc/bot_crime_is_violent(crime)
	var/lower = lowertext("[crime]")
	for(var/word in list("assault", "murder", "manslaughter", "battery", "kidnap", "mutiny", "terror"))
		if(findtext(lower, word))
			return TRUE
	return FALSE

// ---------------------------------------------------------------------------------------------
// Accidents
// ---------------------------------------------------------------------------------------------

// Something thrown at something else that hit somebody on the way looks like an accident. Nobody fights or reports it at once ("Ow!
// Watch it!"); said sorry for in time, it's forgiven by whoever was hit and whoever saw. A second, or a swing at them, isn't one; with
// no sorry by the end of the time, it's taken as it looked. The user ruled it, 2026-11-05 ("Forgive if it fits"): their sword, thrown
// at a table in Medbay, hit the cuffed janitor beside it, and the janitor and a doctor fought them for three minutes through "sorry"
// and "I'm helping him". The user's first sorry came 16 seconds after.

/// What the throw being logged was for (living_defense.dm hitby()), while it's logged
GLOBAL_VAR(bot_throw_aimed_at)

#define BOT_ACCIDENT_MEMORY (3 MINUTES)

/mob/living/carbon/human
	/// Accidents they've had on somebody: REF of who -> list(when, forgiven)
	var/list/bot_accidents
	var/bot_apologised_at = -INFINITY

/// A thrown hit that looks like an accident, held back while they've time to say sorry. TRUE if it's held.
/proc/bot_hold_accident(mob/living/carbon/human/culprit, mob/living/carbon/human/victim, what_done, atom/object)
	var/atom/aim = GLOB.bot_throw_aimed_at
	if(!aim || aim == victim || get_turf(aim) == get_turf(victim) || !istype(culprit) || !istype(victim) || culprit == victim)
		return FALSE //at them, or there's no telling
	var/key = REF(victim)
	var/list/had = LAZYACCESS(culprit.bot_accidents, key)
	if(had && world.time < had[1] + BOT_ACCIDENT_MEMORY)
		return FALSE //twice isn't an accident
	LAZYSET(culprit.bot_accidents, key, list(world.time, FALSE))
	var/sociability = victim.bot_brain ? victim.bot_brain.sociability : 0.5
	var/grace = 20 SECONDS + round(10 SECONDS * clamp(sociability, 0, 1))
	bot_tally("accidents held")
	victim.bot_brain?.on_accident(culprit)
	for(var/datum/bot_brain/B as anything in bot_witnesses_of(victim, list(culprit, victim)))
		B.on_saw_accident(culprit, victim)
	addtimer(CALLBACK(GLOBAL_PROC, GLOBAL_PROC_REF(bot_accident_unanswered), WEAKREF(culprit), WEAKREF(victim), world.time, what_done, object), grace)
	return TRUE

/// The time's up: said sorry for, it's done with; otherwise it's taken as the attack it looked like
/proc/bot_accident_unanswered(datum/weakref/culprit_ref, datum/weakref/victim_ref, when, what_done, atom/object)
	var/mob/living/carbon/human/culprit = culprit_ref?.resolve()
	var/mob/living/carbon/human/victim = victim_ref?.resolve()
	if(QDELETED(culprit) || QDELETED(victim))
		return
	var/list/had = LAZYACCESS(culprit.bot_accidents, REF(victim))
	if(!had || had[1] != when || had[2])
		return
	if(victim.bot_brain)
		bot_log(victim.bot_brain, "[culprit] never said sorry for the accident: taken as an attack")
	bot_security_witness_combat(culprit, victim, what_done, QDELETED(object) ? null : object) //nothing to read the aim off now: as it looked

/// Somebody saying sorry, heard by a bot: anything they've done by accident in the last while is forgiven
/proc/bot_heard_apology(mob/living/carbon/human/H, lower_msg)
	if(!istype(H) || (!LAZYLEN(H.bot_accidents) && !H.bot_uncuffed) || world.time < H.bot_apologised_at + 2 SECONDS)
		return
	if(!bot_text_has_any(lower_msg, list("sorry", "my bad", "apologies", "accident", "didn't mean", "didnt mean", "oops", "whoops", "i'm helping", "im helping", "trying to help", "i'm trying to help", "not trying to hurt")))
		return
	H.bot_apologised_at = world.time
	bot_uncuff_settled(H)
	for(var/key in H.bot_accidents)
		var/list/had = H.bot_accidents[key]
		if(had[2] || world.time > had[1] + 40 SECONDS)
			continue
		had[2] = TRUE
		var/mob/living/carbon/human/victim = locate(key)
		bot_tally("accidents forgiven")
		if(istype(victim) && victim.bot_brain)
			victim.bot_brain.forgive_accident(H)
		else
			for(var/datum/bot_brain/B as anything in bot_witnesses_of(H, list(H)))
				B.forgive_accident(H)
				break

/// Hit by something meant for something else
/datum/bot_brain/proc/on_accident(mob/living/carbon/human/culprit)
	if(QDELETED(owner) || owner.stat != CONSCIOUS)
		return
	bot_log(src, "hit by [culprit]'s throw at something else: an accident, unless they don't say sorry")
	owner.face_atom(culprit)
	if(world.time >= next_reaction_time)
		next_reaction_time = world.time + 50
		bot_say(owner, pick("Ow! Watch it!", "Hey! Watch where you're throwing that!", "OW! What the hell?!", "Ow! Careful!"))

/// Saw somebody hit by something meant for something else
/datum/bot_brain/proc/on_saw_accident(mob/living/carbon/human/culprit, mob/living/carbon/human/victim)
	if(owner.stat != CONSCIOUS || state == BOT_STATE_COMBAT)
		return
	next_witness_time = max(next_witness_time, world.time + 4 SECONDS)
	if(world.time >= next_reaction_time && prob(50))
		next_reaction_time = world.time + 50
		bot_say(owner, pick("Whoa, careful!", "Watch it!", "Hey, mind where that's going!"))

/// They said sorry for an accident on this bot, or one it saw: forgiven, and a fight over it ended
/datum/bot_brain/proc/forgive_accident(mob/living/carbon/human/culprit)
	if(QDELETED(owner) || owner.stat != CONSCIOUS)
		return
	bot_log(src, "forgave [culprit] for the accident")
	if(state == BOT_STATE_COMBAT && attacker == culprit)
		end_combat_with(culprit)
	if(owner.stat == CONSCIOUS)
		say_after_typing(mood_pick(list("It's fine, no harm done.", "Don't worry about it!"), list("It's fine. Just watch where you're throwing things.", "Alright. Be careful."), list("Fine. Watch it next time.", "Yeah, yeah. Careful.")))

/// Stops fighting somebody, the way it does when they're down or gone
/datum/bot_brain/proc/end_combat_with(mob/living/who)
	if(attacker != who)
		return
	attacker = null
	state = state_before_combat || BOT_STATE_WANDER
	stop_pursuit()

#undef BOT_ACCIDENT_MEMORY

// ---------------------------------------------------------------------------------------------
// Uncuffing Security's prisoner
// ---------------------------------------------------------------------------------------------

// Somebody who isn't Security taking the cuffs off somebody Security has: whoever sees it says so to them and radios it in, a minor
// charge; said sorry for with the cuffs back on, it's dropped. The prisoner doesn't take being let go as being set on, and only
// one with reason to runs. The user ruled it, 2026-11-05: "they should report it, allowing me to apologize and then recuff the
// prisoner". The user had uncuffed the janitor, a traitor Security had brought to Medbay, without knowing he was a prisoner.

#define BOT_UNCUFF_SETTLE (5 MINUTES)

/mob/living/carbon/human
	/// The prisoner they let out of their cuffs: list(REF, when, cuffed again)
	var/list/bot_uncuffed
	var/bot_freed_called_in = -INFINITY

/// Whether what was done names restraints: "stripped the handcuffs off"
/proc/bot_restraints_named(what_done)
	var/lower = lowertext("[what_done]")
	for(var/word in list("handcuffs", "cuffs", "zipties", "restraints"))
		if(findtext(lower, word))
			return TRUE
	return FALSE

/// In Security's hands: wanted, on the way to a cell, or serving a sentence
/proc/bot_in_custody(mob/living/carbon/human/H)
	if(bot_is_wanted(H))
		return TRUE
	var/datum/bot_brain/other = GLOB.bot_work_claims[REF(H)]
	if(other?.is_security_job() && istype(other.current_goal, /datum/bot_goal/brig_prisoner))
		return TRUE
	for(var/obj/machinery/door_timer/T as anything in GLOB.bot_brig_sentences)
		var/datum/weakref/ref = GLOB.bot_brig_sentences[T]
		if(!QDELETED(T) && T.timing && ref?.resolve() == H)
			return TRUE
	return FALSE

/proc/bot_note_uncuffed(mob/living/carbon/human/freer, mob/living/carbon/human/prisoner)
	if(GLOB.bot_reflexes_off || !istype(freer) || !istype(prisoner) || bot_is_officer(freer) || !bot_in_custody(prisoner))
		return //not Security's, or Security letting them go
	freer.bot_uncuffed = list(REF(prisoner), world.time, FALSE)
	bot_tally("prisoners uncuffed")
	prisoner.bot_brain?.on_uncuffed(freer)
	for(var/datum/bot_brain/B as anything in bot_witnesses_of(freer, list(freer, prisoner)))
		if(B.owner.stat == CONSCIOUS && !B.gone_loud() && !B.on_my_side(prisoner) && !B.is_security_job())
			B.object_to_uncuffing(freer, prisoner)
			return

/// Its cuffs off by somebody who isn't Security
/datum/bot_brain/proc/on_uncuffed(mob/living/carbon/human/freer)
	if(QDELETED(owner) || owner.stat != CONSCIOUS)
		return
	if(resists_arrest())
		bot_log(src, "uncuffed by [freer]: making a run for it")
		say_after_typing(pick("Thanks!", "Cheers, sucker.", "See ya!"))
		run_from(freer, "got its cuffs off")
		return
	bot_log(src, "uncuffed by [freer]: waiting for Security")
	say_after_typing(pick("Uh, thanks? I'd better wait for Security.", "Thanks... I'll wait here for Security, though.", "Are you allowed to do that? I'll wait for Security."))

/// Saw it: says so to them, and on the radio
/datum/bot_brain/proc/object_to_uncuffing(mob/living/carbon/human/freer, mob/living/carbon/human/prisoner)
	owner.face_atom(freer)
	bot_log(src, "saw [freer] uncuff [prisoner], Security's prisoner")
	bot_say(owner, pick("Hey! That's Security's prisoner!", "What are you doing? [prisoner.first_name()]'s under arrest!", "Hey, those cuffs are Security's! Put them back on!"))
	if(world.time > prisoner.bot_freed_called_in + 1 MINUTES)
		prisoner.bot_freed_called_in = world.time
		call_it_in(freer, "Freeing a Prisoner", "has uncuffed [prisoner.name], Security's prisoner,", BOT_CRIME_MINOR)

/// The cuffs back on the prisoner they let out: TRUE if it's that (not violence, then)
/proc/bot_note_recuffed(mob/living/carbon/human/freer, mob/living/carbon/human/prisoner)
	var/list/had = freer.bot_uncuffed
	if(!had || had[1] != REF(prisoner) || world.time > had[2] + BOT_UNCUFF_SETTLE)
		return FALSE
	had[3] = TRUE
	bot_uncuff_settled(freer)
	return TRUE

/// Said sorry, and the cuffs back on: the charge for it is dropped, and said so
/proc/bot_uncuff_settled(mob/living/carbon/human/freer)
	var/list/had = freer.bot_uncuffed
	if(!had || !had[3] || freer.bot_apologised_at < had[2] || world.time > had[2] + BOT_UNCUFF_SETTLE)
		return
	freer.bot_uncuffed = null
	var/mob/living/carbon/human/prisoner = locate(had[1])
	var/datum/bot_wanted/W = bot_get_wanted_entry(freer)
	if(W?.crime == "Freeing a Prisoner")
		bot_clear_wanted(freer)
	bot_tally("uncuffing put right")
	for(var/datum/bot_brain/B as anything in bot_witnesses_of(freer, list(freer, prisoner)))
		if(B.owner.stat == CONSCIOUS && !B.is_security_job())
			bot_log(B, "[freer] put [prisoner]'s cuffs back on and said sorry")
			bot_say(B.owner, ";Never mind, Security. [freer.name]'s cuffed [istype(prisoner) ? prisoner.name : "them"] again.")
			return

#undef BOT_UNCUFF_SETTLE

/// Anything dangerous on them at all, searched: in their hands, their bag, their pockets
/proc/bot_carrying_contraband(mob/living/carbon/human/H)
	for(var/obj/item/I in H.GetAllContents())
		if(is_type_in_typecache(I, GLOB.bot_contraband))
			return TRUE
	return FALSE

// ---- Players griefing, seen (the user's ruling, 2026-11-10): griefing is the admins' business, but bots subdue anybody who's blatantly
// at it, the Captain too: murdering crew who aren't valid (bot_classify_crime() already makes that murder), flooding plasma, wrecking
// the engine. A bot saboteur reports itself (goals/sabotage.dm); these are a player doing the same, seen by whoever's there, and called
// in the same way: Security arrests for Sabotage, an engineer at the engine goes for them there and then.

/// A player (not a bot) caught at one of these. Bots report their own.
/proc/bot_saw_player_sabotage(mob/living/carbon/human/H, details, engine = FALSE, crime = "Sabotage", severity = BOT_CRIME_MAJOR)
	if(!istype(H) || H.bot_brain)
		return
	log_game("BOT WITNESS: [key_name(H)] [details] at [AREACOORD(H)] ([crime])")
	bot_witness_sabotage(H, details, engine, crime, severity)

/// The station's running supermatter, if it's this part's: a loop pump or filter in its engine room (not Atmospherics next door)
/proc/bot_running_crystal_part(obj/machinery/M)
	var/obj/machinery/power/supermatter_crystal/S = GLOB.main_supermatter_engine
	var/area/room = get_area(M)
	if(QDELETED(S) || S.power < 100 || S.z != M.z || get_dist(S, M) > 22)
		return FALSE
	return istype(room, /area/engine) && !istype(room, /area/engine/atmos)

/// Engineering staff at their own engine are working on it, whatever they switch: it's the rest who've no business there
/proc/bot_engine_staff(mob/living/carbon/human/H)
	return H?.mind?.assigned_role in GLOB.engineering_positions

// Gas let out where people are, judged by what it does there (the user, 2026-11-10):
//  - Sabotage, as plasma or N2O is: anything that isn't air (freon, water vapour for its slips, CO2 and the rest); gas hot or cold enough
//    to hurt, let into a room it doesn't help back to a safe temperature; oxygen let in where there's plasma, which can't burn on its own.
//  - Vandalism, arrestable but no flood: a canister's worth of plain oxygen, nitrogen or air dumped past the room's pressure (too much
//    nitrogen and there's nothing to breathe). The scrubbers put a room's pressure right, so it's the lesser charge.
//  - Fine: air let out at a normal pressure, a little of it, or into a room that's lost its own (that's putting it back).
// From a canister's valve, a portable pump pumping out, or a canister or pipe broken open by whoever hit it last. Never in Atmospherics or
// Toxins, where gas is the work.

/// Below this many moles of what isn't air, it's a whiff, not a flood
#define BOT_GAS_FLOOD_MOLES 50
/// A canister's worth of plain air or what it's made of, dumped
#define BOT_AIR_DUMP_MOLES 500
/// Plasma already in a room that oxygen let in would feed
#define BOT_PLASMA_IN_ROOM 5
/// How long after somebody's hit it a machine breaking is put down to them
#define BOT_DAMAGE_BLAME_TIME (10 SECONDS)

/// What's in air and does no harm let out: air's own, and pluoxium and hyper-noblium
GLOBAL_LIST_INIT(bot_harmless_gases, typecacheof(list(/datum/gas/oxygen, /datum/gas/nitrogen, /datum/gas/pluoxium, /datum/gas/hypernoblium)))

/// The gas there's most of in this air that isn't harmless, by name, if there's a flood's worth of what isn't. Null for plain air.
/proc/bot_harmful_gas_in(datum/gas_mixture/G)
	if(!G)
		return null
	var/total = 0
	var/worst
	var/worst_amount = 0
	for(var/id in G.moles)
		if(GLOB.bot_harmless_gases[id])
			continue
		var/amount = G.moles[id]
		total += amount
		if(amount > worst_amount)
			worst = id
			worst_amount = amount
	if(total < BOT_GAS_FLOOD_MOLES)
		return null
	return lowertext(GAS_META[META_GAS_NAME][worst])

/// What letting this gas out at `where` comes to: list(crime, what they're doing, severity), or null if it's fine. `dumping`: out past
/// the room's own pressure (a high release pressure, or broken open), not just topping it up.
/proc/bot_gas_release_verdict(datum/gas_mixture/G, atom/where, dumping, how)
	var/turf/T = get_turf(where)
	if(!G || !T || G.total_moles() < BOT_GAS_FLOOD_MOLES || bot_air_meant_to_be_bad(T))
		return null
	var/datum/gas_mixture/room = T.return_air()
	var/gas = bot_harmful_gas_in(G)
	if(gas)
		return list("Sabotage", "is letting [gas] out of [how]", BOT_CRIME_MAJOR)
	var/temperature = G.return_temperature()
	var/room_temperature = room ? room.return_temperature() : T20C
	// Hot into a room that isn't freezing, cold into one that isn't sweltering: it hurts people, it isn't putting the room right
	if(temperature > BODYTEMP_HEAT_DAMAGE_LIMIT && room_temperature >= BODYTEMP_COLD_DAMAGE_LIMIT)
		return list("Sabotage", "is letting scalding gas out of [how]", BOT_CRIME_MAJOR)
	if(temperature < BODYTEMP_COLD_DAMAGE_LIMIT && room_temperature <= BODYTEMP_HEAT_DAMAGE_LIMIT)
		return list("Sabotage", "is letting freezing gas out of [how]", BOT_CRIME_MAJOR)
	if(G.moles[/datum/gas/oxygen] >= BOT_GAS_FLOOD_MOLES && room?.moles[/datum/gas/plasma] >= BOT_PLASMA_IN_ROOM)
		return list("Sabotage", "is letting oxygen into the plasma from [how]", BOT_CRIME_MAJOR)
	if(dumping && G.total_moles() >= BOT_AIR_DUMP_MOLES && room && room.return_pressure() >= WARNING_LOW_PRESSURE)
		var/main = G.moles[/datum/gas/nitrogen] > G.moles[/datum/gas/oxygen] ? "nitrogen" : "oxygen"
		if(G.moles[/datum/gas/nitrogen] && G.moles[/datum/gas/oxygen] && abs(G.moles[/datum/gas/nitrogen] - 4 * G.moles[/datum/gas/oxygen]) < G.total_moles() * 0.2)
			main = "air"
		return list("Vandalism", "is dumping [main] out of [how]", BOT_CRIME_MINOR)
	return null

/// A player at it, if the verdict says so
/proc/bot_judge_gas_release(mob/living/carbon/human/H, datum/gas_mixture/G, atom/where, dumping, how)
	var/list/verdict = bot_gas_release_verdict(G, where, dumping, how)
	if(verdict)
		bot_saw_player_sabotage(H, verdict[2], FALSE, verdict[1], verdict[3])

/obj/machinery
	/// Who last hit it with something, and when: who it breaking open is put down to
	var/datum/weakref/last_damager
	var/last_damaged_at = 0

/obj/machinery/attacked_by(obj/item/I, mob/living/user)
	. = ..()
	if(I?.force && ishuman(user))
		last_damager = WEAKREF(user)
		last_damaged_at = world.time

/obj/machinery/bullet_act(obj/item/projectile/P, def_zone)
	. = ..()
	if(ishuman(P?.firer) && !P.nodamage)
		last_damager = WEAKREF(P.firer)
		last_damaged_at = world.time

/// Who broke this, if anybody did, just now
/obj/machinery/proc/broken_by()
	if(world.time > last_damaged_at + BOT_DAMAGE_BLAME_TIME)
		return null
	return last_damager?.resolve()

/obj/machinery/portable_atmospherics/canister/ui_act(action, params)
	var/was_open = valve_open
	var/was_pressure = release_pressure
	. = ..()
	if(!valve_open || holding)
		return
	// Opened, or its release pressure turned up while open (a dump starts as an ordinary top-up as often as not)
	var/dumping = release_pressure > ONE_ATMOSPHERE * 1.5
	if(was_open && !(dumping && was_pressure <= ONE_ATMOSPHERE * 1.5))
		return
	bot_judge_gas_release(usr, air_contents, src, dumping, "a canister")

/obj/machinery/portable_atmospherics/pump/ui_act(action, params)
	var/was_releasing = on && direction == "out" && !holding
	var/was_pressure = pump?.target_pressure
	. = ..()
	if(!on || direction != "out" || holding)
		return
	var/dumping = pump?.target_pressure > ONE_ATMOSPHERE * 1.5
	if(was_releasing && !(dumping && was_pressure <= ONE_ATMOSPHERE * 1.5))
		return
	bot_judge_gas_release(usr, air_contents, src, dumping, "a portable pump")

/obj/machinery/portable_atmospherics/canister/canister_break()
	var/datum/gas_mixture/inside = air_contents?.copy()
	var/mob/living/carbon/human/breaker = broken_by()
	. = ..()
	if(breaker)
		bot_judge_gas_release(breaker, inside, src, TRUE, "a canister broken open")

/obj/machinery/atmospherics/pipe/releaseAirToTurf()
	var/datum/gas_mixture/inside = air_temporary?.copy()
	var/mob/living/carbon/human/breaker = broken_by()
	. = ..()
	if(breaker)
		bot_judge_gas_release(breaker, inside, src, TRUE, "a broken pipe")

#undef BOT_GAS_FLOOD_MOLES
#undef BOT_AIR_DUMP_MOLES
#undef BOT_PLASMA_IN_ROOM
#undef BOT_DAMAGE_BLAME_TIME

/obj/machinery/atmospherics/components/binary/pump/ui_act(action, params)
	var/was_on = on
	. = ..()
	if(action == "power" && was_on && !on && bot_running_crystal_part(src) && !bot_engine_staff(usr))
		bot_saw_player_sabotage(usr, "is messing with the engine", TRUE)

/obj/machinery/atmospherics/components/trinary/filter/ui_act(action, params)
	var/was_on = on
	. = ..()
	if(action == "power" && was_on && !on && bot_running_crystal_part(src) && !bot_engine_staff(usr))
		bot_saw_player_sabotage(usr, "is messing with the engine", TRUE)

/obj/machinery/power/emitter/interact(mob/user)
	var/was_active = active
	. = ..()
	if(!was_active || active || bot_engine_staff(user))
		return
	var/turf/site = bot_caged_tesla_site() //setup_tesla_engine.dm
	if(site && site.z == z && get_dist(src, site) <= 40)
		bot_saw_player_sabotage(user, "is messing with the engine", TRUE)
