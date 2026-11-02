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
		return owner.mind?.assigned_role in staff
	var/list/keywords = GLOB.bot_department_keywords[owner.mind?.assigned_role]
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
/datum/bot_brain/proc/call_it_in(mob/living/carbon/human/culprit, crime, details, severity)
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
		officer.file_crime(culprit, crime, "[capitalize(details)] in [where] (reported by [owner.real_name]).", severity)

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
	for(var/datum/bot_brain/B as anything in bot_witnesses_of(victim, list(assailant, victim)))
		B.on_saw_violence(assailant, victim)

/datum/bot_brain/proc/on_saw_violence(mob/living/carbon/human/assailant, mob/living/carbon/human/victim)
	if(state == BOT_STATE_COMBAT && attacker == assailant)
		last_hit_by_attacker = world.time //its fight's still going on
		return
	if(is_security_job() || state == BOT_STATE_COMBAT || state == BOT_STATE_ARREST || world.time < next_witness_time || owner.incapacitated())
		return
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
	if(playstyle == BOT_STYLE_HUNTER)
		courage += 0.3 //this is what it came for
	// Somebody needs to get on the radio, whatever else happens. Somebody in the same room as a fight usually does.
	if(!assailant.bot_attack_called_in || world.time > assailant.bot_attack_called_in + 30 SECONDS)
		assailant.bot_attack_called_in = world.time
		call_it_in(assailant, "Assault", "is attacking [victim.name]", BOT_CRIME_MINOR)
	else if(world.time >= next_reaction_time)
		next_reaction_time = world.time + 30
		bot_say(owner, pick(GLOB.bot_saw_attack_lines))
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
	if(length(GLOB.bot_security_wanted))
		look_out_for_trouble()
	look_round_the_room() //bot_playstyles.dm
	watch_the_door()

/// Anybody in sight the crew knows to be dangerous. Anything less than a major crime is security's to deal with.
/datum/bot_brain/proc/look_out_for_trouble()
	if(is_security_job() || greytider)
		return
	for(var/mob/living/carbon/human/H in view(6, owner))
		if(H == owner || H.stat != CONSCIOUS || H.handcuffed)
			continue
		var/datum/bot_wanted/W = bot_get_wanted_entry(H)
		if(!W || W.severity < BOT_CRIME_MAJOR || is_in_active_cell(H))
			continue
		// Heard it on the radio, or it's on the records: everybody knows the face.
		if(world.time >= next_sighting_call)
			next_sighting_call = world.time + 1 MINUTES
			if(prob(50))
				bot_say(owner, ";[H.name] is here, in [get_area_name(owner, TRUE)]! Security!")
		if(nerve >= 0.7 && has_a_weapon() && GLOB.bot_chaos_level >= 1 && bot_fighters_against(H) < BOT_DOGPILE_LIMIT)
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
	if(!staff || !(owner.mind?.assigned_role in staff))
		return
	bot_refresh_open_departments() //bot_departments.dm
	// Open's open, to anybody but the strict ones, and it's nobody's business but the staff's if they want it that way.
	if(GLOB.bot_open_departments[bot_department_of(here)] && strictness < 0.6)
		return
	for(var/mob/living/carbon/human/H in view(6, owner))
		if(H == owner || H.stat != CONSCIOUS || H.handcuffed || bot_means_well(H))
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
		if(bot_near_the_engine(H) && (owner.mind?.assigned_role in GLOB.engineering_positions) && (!warned || world.time > warned + 5 MINUTES))
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
