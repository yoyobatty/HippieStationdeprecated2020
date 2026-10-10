// Security-role behavior: a bot doing the Security Officer (or Warden/HoS) job patrols,
// notices crime happening in front of it, and runs the standard arrest procedure from
// the tgstation Guide to Security - rather than only ever fist-fighting whoever
// personally attacks it, the way every other job's bot does (handle_combat(),
// bot_brain.dm).
//
// The procedure, as the guide lays it out and as this file follows it:
//  - Low-threat criminals (petty/non-violent): get their attention, tell them they're
//    under arrest and state their crimes, cuff them - and only stun them if they turn
//    non-compliant (run, or break away mid-cuff).
//  - High-threat criminals (violent): stun first, cuff, THEN state their crimes.
//  - Bring them to the brig: confiscate anything they could use to break out into the
//    cell locker, uncuff them ("leaving them to buckle cuffed is considered poor form"),
//    and set a timer that fits the crime (a minute or two for something minor).
//  - Keep weapons holstered when not actively using them ("Don't run around with your
//    disabler or baton out!").
//  - Call it in on the security channel; request backup; a murder gets flagged for the
//    Warden/HoS, since only they can authorize a permanent sentence.
//
// Where crime comes from:
//  - Witnessed violence - every punch/hit/shot in the game already funnels through
//    log_combat() (atoms.dm), which calls bot_security_witness_combat() below. A bot
//    only reacts to what's inside its own view(), same as a real officer standing there.
//  - The security records themselves - anyone set to *Arrest* (by a human officer's
//    HUD, a records console, or another bot) gets picked up on sight, the same check
//    Beepsky's assess_threat() (human.dm) uses.
//  - Calls for help - hearing "help"/"security" in person or over the radio sends the
//    bot to go look (see on_heard_security_call()).
//
// Crimes a bot witnesses are written into the real security records (status *Arrest*
// plus a minor/major crime entry), so they show on every sec HUD exactly as if a player
// officer had filed them - and a wanted entry is also kept in GLOB.bot_security_wanted
// for people with no record at all (no manifest entry, face hidden and no ID, ...).

#define BOT_CRIME_MINOR 1
#define BOT_CRIME_MAJOR 2
#define BOT_CRIME_MURDER 3

// Sentences in deciseconds, fed straight into door_timer/set_timer() (brigdoors.dm
// caps it at 9000). Minor matches the guide's "a fair timer, one to two minutes"; a
// murder is the longest a cell timer allows, plus a radio request for the Warden/HoS
// to decide on permabrig, which bots never do on their own.
#define BOT_SENTENCE_MINOR 1200
#define BOT_SENTENCE_MAJOR 3000
#define BOT_SENTENCE_MURDER 9000

#define BOT_SEC_VIEW_RANGE 7
// How long a suspect can stay out of sight before the chase is called off.
#define BOT_ARREST_LOST_TIMEOUT 300
// Hard cap on one arrest attempt, however it's going.
#define BOT_ARREST_MAX_DURATION 3000
// Retaliating against someone who hit you within this window is self-defense, not a crime.
#define BOT_SELF_DEFENSE_WINDOW 300

GLOBAL_LIST_EMPTY(bot_security_brains) //every living security-job bot_brain, see is_security_job()
GLOBAL_LIST_EMPTY(bot_security_wanted) //weakref(mob) -> /datum/bot_wanted
GLOBAL_LIST_EMPTY(bot_recent_aggression) //"[REF(attacker)]>[REF(victim)]" -> world.time
GLOBAL_LIST_EMPTY(bot_brig_sentences) //door_timer -> weakref(prisoner), see check_finished_sentences()
GLOBAL_LIST_EMPTY(bot_brig_cell_interiors) //door_timer -> list of turfs inside that cell

// Substrings of log_combat()'s what_done that count as violence. Deliberately excludes
// grabs, shoves and disarms (horseplay as often as not), injections (doctors), and
// "fired at" (logged at the moment of firing, before anything's actually been hit).
GLOBAL_LIST_INIT(bot_violent_combat_verbs, list(
	"attacked", "punched", "kick", "shot", "threw and hit", "tackled", "smothered",
	"strangled", "stunned", "stung", "flashed", "handcuffed", "slashed", "stabbed",
	"bit", "chop", "elbow", "knee", "sweep", "gibbed",
))

/datum/bot_wanted
	var/crime
	var/severity = BOT_CRIME_MINOR
	var/time_reported = 0

/datum/bot_brain
	var/mob/living/carbon/human/arrest_suspect
	var/arrest_crime
	var/arrest_severity = BOT_CRIME_MINOR
	var/arrest_hailed = FALSE
	var/arrest_resisted = FALSE
	var/arrest_started = 0
	var/arrest_last_seen = 0
	var/turf/arrest_last_seen_turf
	var/arrest_last_dist = 0
	var/turf/arrest_path_turf //where the current arrest pursuit was pathed to - repath only once the suspect has actually moved off it
	var/arrest_busy = FALSE //an INVOKE_ASYNC'd cuffing attempt (do_mob(), 3s) is in flight
	var/arrest_path_failures = 0 //see on_arrest_pursuit_failed()
	var/next_taser_time = 0
	var/next_security_check_time = 0
	var/next_security_call_time = 0
	var/next_security_restock_time = 0
	var/next_sec_hud_check_time = 0
	// Suspects this bot recently failed to brig (they broke free, no cell was free, ...)
	// mapped to a cooldown - same LAZYSET/world.time pattern as failed_areas.
	var/list/failed_brig_targets

/datum/bot_brain/proc/is_security_job()
	var/role = owner.mind?.assigned_role
	return role == "Security Officer" || role == "Warden" || role == "Head of Security"

// Registered from bot_brain/New() - a bot's job never changes after spawn.
/datum/bot_brain/proc/register_security()
	if(is_security_job())
		GLOB.bot_security_brains |= src

// ============================================================
// Records
// ============================================================

// Same identity lookup assess_threat() (human.dm) and the sec HUD use: the name on
// the face if it's visible, otherwise the name on the ID.
/proc/bot_find_security_record(mob/living/carbon/human/H)
	if(!istype(H) || !GLOB.data_core)
		return null
	var/perpname = H.get_face_name(H.get_id_name())
	if(!perpname || perpname == "Unknown")
		return null
	return find_record("name", perpname, GLOB.data_core.security)

/proc/bot_get_wanted_entry(mob/living/carbon/human/H)
	return GLOB.bot_security_wanted[WEAKREF(H)]

/proc/bot_clear_wanted(mob/living/carbon/human/H)
	GLOB.bot_security_wanted -= WEAKREF(H)

/proc/bot_is_wanted(mob/living/carbon/human/H)
	if(bot_get_wanted_entry(H))
		return TRUE
	var/datum/data/record/R = bot_find_security_record(H)
	return R && R.fields["criminal"] == "*Arrest*"

// Mirrors what the sec HUD's "status" and "add_crime" hrefs (human.dm Topic()) do.
/datum/bot_brain/proc/file_crime(mob/living/carbon/human/H, crime, details, severity)
	var/datum/bot_wanted/W = bot_get_wanted_entry(H)
	if(!W)
		W = new
		W.time_reported = world.time
		GLOB.bot_security_wanted[WEAKREF(H)] = W
	if(severity >= W.severity || !W.crime)
		W.crime = crime
		W.severity = severity

	var/datum/data/record/R = bot_find_security_record(H)
	if(!R)
		return
	var/author = "[owner.real_name] ([owner.mind?.assigned_role])"
	var/datum/data/crime/C = GLOB.data_core.createCrimeEntry(crime, details, author, station_time_timestamp())
	if(severity >= BOT_CRIME_MAJOR)
		GLOB.data_core.addMajorCrime(R.fields["id"], C)
	else
		GLOB.data_core.addMinorCrime(R.fields["id"], C)
	if(R.fields["criminal"] != "*Arrest*")
		H.investigate_log("[key_name(H)] has been set from [R.fields["criminal"]] to *Arrest* by [key_name(owner)] (bot AI).", INVESTIGATE_RECORDS)
		R.fields["criminal"] = "*Arrest*"
	H.sec_hud_set_security_status()

/proc/bot_set_criminal_status(mob/living/carbon/human/H, status)
	var/datum/data/record/R = bot_find_security_record(H)
	if(!R || R.fields["criminal"] == status)
		return
	H.investigate_log("[key_name(H)] has been set from [R.fields["criminal"]] to [status] by the bot AI.", INVESTIGATE_RECORDS)
	R.fields["criminal"] = status
	H.sec_hud_set_security_status()

// Picks the crime to read out for someone who's wanted only via the records (set by a
// human officer, say) - the most recent major crime, else the most recent minor one.
/proc/bot_describe_record_crimes(mob/living/carbon/human/H)
	var/datum/data/record/R = bot_find_security_record(H)
	if(!R)
		return list("an outstanding warrant", BOT_CRIME_MINOR)
	var/list/majors = R.fields["ma_crim"]
	if(length(majors))
		var/datum/data/crime/C = majors[majors.len]
		return list(C.crimeName, BOT_CRIME_MAJOR)
	var/list/minors = R.fields["mi_crim"]
	if(length(minors))
		var/datum/data/crime/C = minors[minors.len]
		return list(C.crimeName, BOT_CRIME_MINOR)
	return list("an outstanding warrant", BOT_CRIME_MINOR)

// ============================================================
// Witnessing
// ============================================================

// Called at the end of every log_combat() (atoms.dm). Must stay cheap and must never
// sleep - log_combat() runs inside every attack path in the game. Anything more than
// bookkeeping is deferred a tick, which also lets the hit's damage land first so the
// victim's stat reads post-hit (critted/killed) rather than pre-hit.
/proc/bot_security_witness_combat(atom/user, atom/target, what_done, atom/object)
	if(!isliving(user) || !ishuman(target) || user == target)
		return
	if(!bot_is_violent_verb(what_done))
		return
	// Something light that came flying isn't violence: a bruise pack out of the hand of somebody who slipped, a
	// thrown paper cup. Not a crime and not a fight - a doctor it happened to once kicked its own patient into a coma.
	var/obj/item/thrown = object
	if(istype(thrown) && thrown.throwforce < 5 && findtext(what_done, "threw"))
		var/mob/living/carbon/human/struck = target
		struck.bot_brain?.mind_thrown_junk()
		return
	// Records when each attacker FIRST started on each victim (within the window), not
	// the latest hit - so a fight's instigator stays the instigator even after the
	// other side starts hitting back. See bot_security_judge_combat()'s self-defense check.
	if(ishuman(user))
		bot_record_aggression(user, target)
	// A bot notices being hurt however it happened - fists, feet, teeth, bullets, thrown junk - not just item hits
	// (this used to hang off attacked_by(), which only item attacks reach).
	var/mob/living/carbon/human/victim = target
	victim.bot_brain?.on_attacked(user, what_done, object)
	if(!GLOB.bot_security_brains.len || !ishuman(user))
		return
	addtimer(CALLBACK(GLOBAL_PROC, /proc/bot_security_judge_combat, user, target, what_done, object), 1)

/// Hit by something harmless that somebody threw or dropped: a word about it, now and then.
/datum/bot_brain/proc/mind_thrown_junk()
	if(QDELETED(owner) || owner.stat != CONSCIOUS || world.time < next_reaction_time || !prob(60))
		return
	next_reaction_time = world.time + 100
	bot_say(owner, pick("Hey, watch it!", "Careful!", "Mind where that's going!", "Ow. Really?"))

/proc/bot_record_aggression(mob/living/carbon/human/user, mob/living/carbon/human/target)
	var/key = "[REF(user)]>[REF(target)]"
	var/first_hit = GLOB.bot_recent_aggression[key]
	if(!first_hit || world.time - first_hit > BOT_SELF_DEFENSE_WINDOW)
		GLOB.bot_recent_aggression[key] = world.time
	if(GLOB.bot_recent_aggression.len > 300)
		for(var/old_key in GLOB.bot_recent_aggression)
			if(world.time - GLOB.bot_recent_aggression[old_key] > BOT_SELF_DEFENSE_WINDOW)
				GLOB.bot_recent_aggression -= old_key

/proc/bot_is_violent_verb(what_done)
	if(!istext(what_done))
		return FALSE
	var/lower = lowertext(what_done)
	for(var/v in GLOB.bot_violent_combat_verbs)
		if(findtext(lower, v))
			return TRUE
	return FALSE

/proc/bot_security_judge_combat(mob/living/carbon/human/attacker, mob/living/carbon/human/victim, what_done, atom/object)
	if(QDELETED(attacker) || QDELETED(victim))
		return
	// Security using force is assumed lawful - internal affairs is out of scope here.
	if(attacker.mind?.assigned_role in GLOB.security_positions)
		return
	// Hitting back at someone who started it is self-defense.
	var/their_first = GLOB.bot_recent_aggression["[REF(victim)]>[REF(attacker)]"]
	var/our_first = GLOB.bot_recent_aggression["[REF(attacker)]>[REF(victim)]"]
	if(their_first && world.time - their_first <= BOT_SELF_DEFENSE_WINDOW && their_first < our_first)
		return
	// Crew subduing someone who's already wanted - not a new crime.
	if(bot_is_wanted(victim))
		return

	var/list/verdict = bot_classify_crime(attacker, victim, what_done, object)
	var/crime = verdict[1]
	var/severity = verdict[2]
	var/details = verdict[3]

	// Everyone who saw it responds (the guide's "call backup" / buddy system), but only
	// one of them - the victim itself if it's a security bot, else whoever's first -
	// files the paperwork and calls it in, so the radio isn't spammed once per officer.
	var/list/datum/bot_brain/witnesses = list()
	for(var/datum/bot_brain/B in GLOB.bot_security_brains)
		if(B.can_witness(attacker, victim))
			witnesses += B
	if(!witnesses.len)
		return
	var/datum/bot_brain/reporter = witnesses[1]
	if(victim.bot_brain && (victim.bot_brain in witnesses))
		reporter = victim.bot_brain
	reporter.on_witnessed_crime(attacker, victim, crime, severity, details)
	for(var/datum/bot_brain/B in witnesses)
		if(B != reporter)
			B.begin_arrest(attacker)

/proc/bot_classify_crime(mob/living/carbon/human/attacker, mob/living/carbon/human/victim, what_done, atom/object)
	var/lower = lowertext(what_done)
	var/weapon_force = 0
	if(isitem(object))
		var/obj/item/I = object
		weapon_force = I.force
	if(istype(object, /obj/item/projectile))
		var/obj/item/projectile/P = object
		if(!P.nodamage && P.damage_type != STAMINA)
			weapon_force = max(weapon_force, P.damage)
	var/where = get_area_name(victim, TRUE)
	if(victim.stat == DEAD)
		return list("Murder", BOT_CRIME_MURDER, "Killed [victim.real_name] in [where].")
	if(findtext(lower, "handcuffed"))
		return list("Kidnapping", BOT_CRIME_MAJOR, "Restrained [victim.real_name] without authority in [where].")
	if(victim.mind?.assigned_role in GLOB.security_positions)
		return list("Assaulting an Officer", BOT_CRIME_MAJOR, "Attacked [victim.real_name] ([what_done]) in [where].")
	if(weapon_force >= 10)
		return list("Assault with a Deadly Weapon", BOT_CRIME_MAJOR, "[capitalize(what_done)] [victim.real_name] with [object] in [where].")
	if(victim.stat != CONSCIOUS)
		return list("Aggravated Assault", BOT_CRIME_MAJOR, "Left [victim.real_name] incapacitated in [where].")
	return list("Assault", BOT_CRIME_MINOR, "[capitalize(what_done)] [victim.real_name] in [where].")

/datum/bot_brain/proc/can_witness(mob/living/carbon/human/attacker, mob/living/carbon/human/victim)
	if(QDELETED(owner) || owner.stat != CONSCIOUS || is_blind(owner))
		return FALSE
	if(owner.z != attacker.z)
		return FALSE
	if(victim == owner || attacker == owner)
		return TRUE
	if(get_dist(owner, attacker) > BOT_SEC_VIEW_RANGE && get_dist(owner, victim) > BOT_SEC_VIEW_RANGE)
		return FALSE
	var/list/seen = view(BOT_SEC_VIEW_RANGE, owner)
	return (attacker in seen) || (victim in seen)

/datum/bot_brain/proc/on_witnessed_crime(mob/living/carbon/human/attacker, mob/living/carbon/human/victim, crime, severity, details)
	var/datum/bot_wanted/existing = bot_get_wanted_entry(attacker)
	var/new_report = !existing || existing.severity < severity
	file_crime(attacker, crime, details, severity)
	if(new_report)
		bot_log(src, "witnessed [attacker] commit [crime] against [victim] @ [bot_coord(get_turf(victim))]")
		bot_say(owner, ":s [crime] in progress, [get_area_name(attacker, TRUE)] - suspect [attacker.name]. Responding.")
	begin_arrest(attacker)

// ============================================================
// Arrest (BOT_STATE_ARREST - see process(), bot_brain.dm)
// ============================================================

// Returns TRUE if the bot is now (or already was) arresting H.
/datum/bot_brain/proc/begin_arrest(mob/living/carbon/human/H)
	if(!istype(H) || QDELETED(H) || H == owner || H.stat == DEAD)
		return FALSE
	var/datum/bot_wanted/W = bot_get_wanted_entry(H)
	var/crime
	var/severity
	if(W)
		crime = W.crime
		severity = W.severity
	else
		var/list/rec = bot_describe_record_crimes(H)
		crime = rec[1]
		severity = rec[2]

	if(state == BOT_STATE_ARREST)
		if(arrest_suspect == H)
			if(severity > arrest_severity)
				arrest_severity = severity
				arrest_crime = crime
			return TRUE
		return FALSE //already busy with someone else - they stay wanted, picked up later

	// Never drop a prisoner mid-escort to go chase someone new.
	if(state == BOT_STATE_GOAL && istype(current_goal, /datum/bot_goal/brig_prisoner))
		return FALSE

	abandon_goals_for_arrest()
	if(H.handcuffed)
		return start_brig_escort(H)

	arrest_suspect = H
	arrest_crime = crime
	arrest_severity = severity
	arrest_hailed = FALSE
	arrest_resisted = FALSE
	arrest_started = world.time
	arrest_last_seen = world.time
	arrest_last_seen_turf = get_turf(H)
	arrest_last_dist = get_dist(owner, H)
	arrest_path_turf = null
	arrest_path_failures = 0
	attacker = null
	state = BOT_STATE_ARREST
	if(owner.buckled)
		owner.buckled.unbuckle_mob(owner, force = TRUE)
	hangout_until = 0
	bot_log(src, "moving to arrest [H] for [crime] ([severity >= BOT_CRIME_MAJOR ? "high" : "low"] threat)")
	return TRUE

// An arrest takes over from whatever the bot was doing - personal errands, restocking,
// patrolling. Unlike combat's state_before_combat (which resumes a paused goal), there's
// nothing a security bot does that's worth coming back to half-done over an arrest.
/datum/bot_brain/proc/abandon_goals_for_arrest()
	stop_pursuit()
	state_before_combat = null
	if(state == BOT_STATE_COMBAT)
		state = BOT_STATE_WANDER
	if(state != BOT_STATE_GOAL && !current_goal && !suspended_goal)
		return
	if(current_goal)
		bot_log(src, "dropping [current_goal.type] to make an arrest")
	current_goal = null
	current_strategy = null
	current_step_index = 0
	suspended_goal = null
	suspended_strategy = null
	suspended_step_index = 0
	state = BOT_STATE_WANDER

/datum/bot_brain/proc/end_arrest(reason)
	bot_log(src, "ending arrest of [arrest_suspect]: [reason]")
	stop_pursuit()
	holster_weapons()
	owner.a_intent = INTENT_HELP
	arrest_suspect = null
	arrest_path_turf = null
	arrest_busy = FALSE
	state = BOT_STATE_WANDER
	next_wander_time = world.time

// Called from on_pursuit_finished() (bot_brain.dm). handle_arrest() re-pursues every
// tick the bot isn't already moving, so a suspect behind a door the bot can't get
// through would otherwise mean a fresh (yielding) pathfind every single second until
// the lost-sight timeout - give up after a handful of consecutive failures instead.
/datum/bot_brain/proc/on_arrest_pursuit_failed()
	if(state != BOT_STATE_ARREST)
		return
	arrest_path_failures++
	arrest_path_turf = null
	if(arrest_path_failures >= 5)
		bot_say(owner, ":s Can't reach [arrest_suspect?.name], they're in [get_area_name(arrest_suspect, TRUE)]. Need someone with access there.")
		end_arrest("no path to suspect")

// Paralyzed/knocked down/stamcritted/unconscious - anything that means cuffs can go on
// without them just walking off mid-cuff. Hippie's electrode/disabler are stamina
// weapons (projectile/energy.dm), so a taser hit alone isn't enough - this reads the
// resulting state instead of trusting any one weapon's effect.
/datum/bot_brain/proc/is_subdued(mob/living/carbon/C)
	if(C.stat != CONSCIOUS)
		return TRUE
	if(C.IsParalyzed() || C.IsStun() || C.IsKnockdown() || C.IsUnconscious())
		return TRUE
	return !(C.mobility_flags & MOBILITY_STAND)

/datum/bot_brain/proc/handle_arrest()
	var/mob/living/carbon/human/S = arrest_suspect
	if(QDELETED(S))
		end_arrest("suspect is gone")
		return
	if(arrest_busy)
		return
	if(S.stat == DEAD)
		bot_say(owner, ":s Suspect [S.name] is down, deceased, in [get_area_name(S, TRUE)].")
		bot_clear_wanted(S)
		end_arrest("suspect died")
		return
	if(S.handcuffed)
		var/mob/living/carbon/human/cuffed = S
		end_arrest("suspect restrained")
		start_brig_escort(cuffed)
		return
	if(world.time - arrest_started > BOT_ARREST_MAX_DURATION)
		bot_say(owner, ":s Couldn't bring in [S.name], they're still at large. Last seen in [get_area_name(arrest_last_seen_turf, TRUE)].")
		end_arrest("took too long")
		return
	var/turf/suspect_turf = get_turf(S) // S.z is 0 while they're hiding in a locker - that used to end the arrest on the spot
	if(!suspect_turf || suspect_turf.z != owner.z)
		end_arrest("suspect left the z-level")
		return

	// A suspect hiding in a locker/crate: go to the container and open it.
	var/atom/chase = bot_outermost_holder(S)
	// By sight (can_see_target(), bot_brain.dm): a locker in view only counts if they were seen getting into it.
	var/visible = can_see_target(S, arrest_last_seen_turf, arrest_last_seen)
	if(visible)
		arrest_last_seen = world.time
		arrest_last_seen_turf = get_turf(S)
	else if(world.time - arrest_last_seen > BOT_ARREST_LOST_TIMEOUT)
		bot_say(owner, ":s Lost sight of [S.name]. Last seen in [get_area_name(arrest_last_seen_turf, TRUE)].")
		end_arrest("lost sight of suspect")
		return

	var/dist = get_dist(owner, S)
	var/subdued = is_subdued(S)

	if(chase != S && owner.Adjacent(chase))
		stop_pursuit()
		if(istype(chase, /obj/structure/closet))
			var/obj/structure/closet/C = chase
			if(!C.opened)
				bot_log(src, "opening [C] to get at [S]")
				use_atom(C)
		return

	if(owner.Adjacent(S) && isturf(S.loc))
		stop_pursuit()
		arrest_path_failures = 0
		owner.face_atom(S)
		var/stun_first = !subdued && (arrest_severity >= BOT_CRIME_MAJOR || arrest_resisted)
		if(stun_first)
			if(!arrest_hailed && arrest_severity < BOT_CRIME_MAJOR)
				hail_suspect(S)
			melee_subdue(S)
		else
			if(!arrest_hailed)
				hail_suspect(S)
			arrest_busy = TRUE
			INVOKE_ASYNC(src, PROC_REF(attempt_cuff), S, subdued)
		arrest_last_dist = dist
		return

	// Not in reach yet.
	if(visible && !subdued)
		if(!arrest_hailed && arrest_severity < BOT_CRIME_MAJOR && dist <= 5)
			hail_suspect(S)
		else if(arrest_hailed && !arrest_resisted && arrest_severity < BOT_CRIME_MAJOR && dist > arrest_last_dist && dist > 2)
			// Told they were under arrest and walked off anyway - the guide's
			// "non-compliant", which is where stunning them becomes appropriate.
			arrest_resisted = TRUE
			bot_say(owner, pick("Stop resisting!", "Halt! Don't make this harder than it has to be!", "[S.name], stop right there!"))
			bot_log(src, "[S] is fleeing - escalating")
		if((arrest_severity >= BOT_CRIME_MAJOR || arrest_resisted) && dist >= 2 && dist <= 6 && world.time >= next_taser_time)
			try_taser(S)
	arrest_last_dist = dist

	// Out of sight, head for where they were last seen rather than wherever they
	// actually are now - a real officer doesn't get a live feed of the suspect's position.
	var/atom/pursuit_goal = visible ? chase : arrest_last_seen_turf
	var/turf/goal_turf = get_turf(pursuit_goal)
	if(!goal_turf)
		return
	if(!visible && get_turf(owner) == goal_turf)
		return //reached the last sighting and they're not here - keep looking around until the lost-sight timeout
	if(!pursuing_kind || pursue_target != pursuit_goal || !arrest_path_turf || get_dist(arrest_path_turf, goal_turf) > 1)
		arrest_path_turf = goal_turf
		pursue(pursuit_goal, "arrest", force = TRUE)

/datum/bot_brain/proc/hail_suspect(mob/living/carbon/human/S)
	arrest_hailed = TRUE
	if(arrest_severity >= BOT_CRIME_MAJOR)
		bot_say(owner, "[S.name], you're under arrest for [lowertext(arrest_crime)].")
	else
		bot_say(owner, pick("[S.name], stop right there! You're under arrest for [lowertext(arrest_crime)].", "Security! [S.name], you're under arrest for [lowertext(arrest_crime)]. Hands where I can see them."))
	bot_log(src, "told [S] they're under arrest for [arrest_crime]")

// ------------------------------------------------------------
// Weapons
// ------------------------------------------------------------

/datum/bot_brain/proc/find_usable_baton()
	for(var/obj/item/melee/baton/B in owner.GetAllContents())
		if(B.cell && B.cell.charge >= B.hitcost)
			return B
	return null

/datum/bot_brain/proc/is_nonlethal_shot(obj/item/ammo_casing/energy/shot)
	return istype(shot, /obj/item/ammo_casing/energy/electrode) || istype(shot, /obj/item/ammo_casing/energy/disabler)

// Any carried energy gun with a stun/disable mode that currently has the charge for it -
// the hybrid taser officers spawn with, a warden's/HoS's energy gun on its disable
// setting, a disabler. Switches the gun to that mode (select_fire(), energy.dm, same as
// a player clicking it in hand) - electrode preferred, it's the harder-hitting of the two.
/datum/bot_brain/proc/ready_nonlethal_gun()
	for(var/obj/item/gun/energy/G in owner.GetAllContents())
		if(!G.ammo_type || !G.ammo_type.len)
			continue
		var/list/order = list()
		for(var/i in 1 to G.ammo_type.len)
			if(istype(G.ammo_type[i], /obj/item/ammo_casing/energy/electrode))
				order.Insert(1, i)
			else if(is_nonlethal_shot(G.ammo_type[i]))
				order += i
		for(var/idx in order)
			var/obj/item/ammo_casing/energy/shot = G.ammo_type[idx]
			if(G.cell.charge < shot.e_cost)
				continue
			var/guard = G.ammo_type.len
			while(G.select != idx && guard-- > 0)
				G.select_fire(owner)
			if(G.select == idx)
				return G
	return null

// Nothing but walls, windows and bystanders are checked - the projectile itself handles
// everything else. Bystanders matter most: an officer tasering into a crowd hits
// whoever's in front, and the guide is emphatic about friendly fire.
/datum/bot_brain/proc/has_clear_shot(mob/living/target)
	for(var/turf/T in getline(owner, target))
		if(T == get_turf(owner) || T == get_turf(target))
			continue
		if(T.density)
			return FALSE
		for(var/atom/movable/AM in T)
			if(isliving(AM))
				return FALSE
			// Tables let shots over them (PASSTABLE); anything else dense - windows,
			// machines, closed doors - is treated as blocking.
			if(AM.density && !istype(AM, /obj/structure/table))
				return FALSE
	return TRUE

/datum/bot_brain/proc/try_taser(mob/living/carbon/human/S)
	if(!has_clear_shot(S))
		return FALSE
	var/obj/item/gun/energy/G = ready_nonlethal_gun()
	if(!G)
		return FALSE
	if(owner.get_active_held_item() != G)
		free_hand_for(G)
		if(!owner.put_in_hands(G))
			return FALSE
	owner.a_intent = INTENT_HELP
	owner.face_atom(S)
	owner.changeNext_move(CLICK_CD_RANGE)
	next_taser_time = world.time + max(CLICK_CD_RANGE, G.fire_delay) + 5
	bot_log(src, "firing [G] at [S] (dist [get_dist(owner, S)])")
	INVOKE_ASYNC(G, TYPE_PROC_REF(/obj/item/gun, afterattack), S, owner, FALSE, null)
	return TRUE

// Baton on help intent stuns without doing brute damage (baton/attack(), stunbaton.dm) -
// exactly the "use your stun weapons, minimal force" the guide asks for. Falls back to a
// disarm shove with bare hands if there's no charged baton.
/datum/bot_brain/proc/melee_subdue(mob/living/carbon/human/S)
	var/obj/item/melee/baton/B = find_usable_baton()
	owner.changeNext_move(CLICK_CD_MELEE)
	if(B)
		if(!B.status)
			toggle_in_hand(B)
		owner.a_intent = INTENT_HELP
		bot_log(src, "stunning [S] with [B]")
		use_item_on(B, S)
		return
	free_hand_for(null)
	owner.a_intent = INTENT_DISARM
	bot_log(src, "no charged baton - shoving [S]")
	owner.UnarmedAttack(S, TRUE)
	owner.a_intent = INTENT_HELP

/datum/bot_brain/proc/find_restraints()
	for(var/obj/item/restraints/handcuffs/H in owner.GetAllContents())
		if(istype(H, /obj/item/restraints/handcuffs/cable/zipties/used))
			continue
		return H
	return null

// Runs async (INVOKE_ASYNC from handle_arrest()) - handcuffs/attack() (handcuffs.dm)
// blocks for a 3 second do_mob() channel, which process() mustn't sleep through.
/datum/bot_brain/proc/attempt_cuff(mob/living/carbon/human/S, was_subdued)
	var/obj/item/restraints/handcuffs/cuffs = find_restraints()
	if(!cuffs)
		bot_log(src, "no restraints left to cuff [S] with")
		bot_say(owner, ":s I'm out of cuffs, need backup at [get_area_name(owner, TRUE)]!")
		arrest_busy = FALSE
		next_security_restock_time = 0
		end_arrest("no restraints")
		return
	owner.a_intent = INTENT_HELP
	bot_log(src, "cuffing [S]")
	use_item_on(cuffs, S) //yields ~3s
	arrest_busy = FALSE
	if(QDELETED(S) || state != BOT_STATE_ARREST || arrest_suspect != S)
		return
	if(S.handcuffed)
		if(arrest_severity >= BOT_CRIME_MAJOR && !arrest_resisted)
			// High-threat order: stun, cuff, THEN state the crime.
			hail_suspect(S)
		bot_say(owner, ":s [S.name] is in custody for [lowertext(arrest_crime)]. Bringing them to the brig.")
		return
	if(!was_subdued && !arrest_resisted)
		arrest_resisted = TRUE
		bot_say(owner, pick("Don't resist!", "Hold still!", "Stop resisting!"))
		bot_log(src, "[S] pulled away from the cuffs - escalating")

// "Don't run around with your disabler or baton out!" - batons go back into the bag
// switched off, guns back onto the suit storage slot they spawn on.
/datum/bot_brain/proc/holster_weapons()
	for(var/obj/item/I in owner.held_items)
		if(istype(I, /obj/item/melee/baton))
			var/obj/item/melee/baton/B = I
			if(B.status)
				toggle_in_hand(B)
			stow_item(B)
		else if(istype(I, /obj/item/gun))
			if(!owner.equip_to_slot_if_possible(I, ITEM_SLOT_SUITSTORE, disable_warning = TRUE))
				stow_item(I)

// ============================================================
// Patrol loop - called from handle_wander() (bot_brain.dm)
// ============================================================

/datum/bot_brain/proc/try_security_round()
	if(!is_security_job())
		return FALSE
	check_finished_sentences()

	// Anyone wanted and in plain sight comes first.
	if(try_spot_wanted())
		return TRUE

	// Start-of-shift gear-up, per the guide: "Go to the Security Office and open a
	// security locker. Get HUD glasses and put them on."
	if(try_gear_up_sec_hud())
		return TRUE

	// Out of cuffs (left them on someone, or never had any) - get another pair before
	// there's a suspect in front of us and nothing to restrain them with.
	if(!find_restraints() && world.time >= next_security_restock_time)
		next_security_restock_time = world.time + 1200
		var/datum/bot_goal/acquire_item_type/sub = new()
		sub.item_type = /obj/item/restraints/handcuffs
		if(assign_goal(sub))
			bot_log(src, "out of handcuffs - going to find a pair")
			return TRUE
	return FALSE

/// Anyone this officer knows is wanted, in plain sight: go get them. Also run mid-errand (process(), bot_brain.dm).
/datum/bot_brain/proc/try_spot_wanted()
	var/mob/living/carbon/human/best
	var/best_dist
	for(var/mob/living/carbon/human/H in view(BOT_SEC_VIEW_RANGE, owner))
		if(H == owner || H.stat == DEAD)
			continue
		if(!can_tell_wanted(H))
			continue
		if(is_in_active_cell(H))
			continue
		var/cooldown = LAZYACCESS(failed_brig_targets, H)
		if(cooldown && world.time < cooldown)
			continue
		var/d = get_dist(owner, H)
		if(!best || d < best_dist)
			best = H
			best_dist = d
	if(best && begin_arrest(best))
		if(state == BOT_STATE_ARREST)
			bot_say(owner, pick("Freeze, [best.name]!", "[best.name]! Security, don't move!", "Hey! [best.name], stop right there!"))
		return TRUE
	return FALSE

// Whether this bot can tell, on sight, that H is wanted. Crimes it witnessed itself (or
// that another officer called in - GLOB.bot_security_wanted stands in for the radio)
// need no equipment, but reading someone's *Arrest* status off the records at a glance
// is exactly what the sec HUD is for - the same TRAIT_SECURITY_HUD gate examine.dm and
// the HUD's own record hrefs (human.dm) use for players.
/datum/bot_brain/proc/can_tell_wanted(mob/living/carbon/human/H)
	if(bot_get_wanted_entry(H))
		return TRUE
	if(!HAS_TRAIT(owner, TRAIT_SECURITY_HUD))
		return FALSE
	var/datum/data/record/R = bot_find_security_record(H)
	return R && R.fields["criminal"] == "*Arrest*"

/datum/bot_brain/proc/is_wearing_sec_hud()
	return istype(owner.glasses, /obj/item/clothing/glasses/hud/security)

// Puts on a sec HUD the bot is already carrying (just picked one up, or grabbed one in
// passing), stowing whatever was on its face first rather than dropping it on the floor.
/datum/bot_brain/proc/wear_sec_hud()
	if(is_wearing_sec_hud())
		return TRUE
	var/obj/item/clothing/glasses/hud/security/hud = locate() in owner.GetAllContents()
	if(!hud)
		return FALSE
	var/obj/item/old = owner.glasses
	if(old)
		owner.dropItemToGround(old)
		stow_item(old)
	// equip_to_slot_if_possible() won't pull an item out of a backpack itself -
	// put_in_hands() will (same trick use_item_on() relies on for stowed tools).
	if(!(hud in owner.held_items))
		free_hand_for(hud)
		owner.put_in_hands(hud)
	if(!equip_displacing(hud, ITEM_SLOT_EYES))
		return FALSE
	bot_log(src, "put on [hud]")
	return TRUE

/datum/bot_brain/proc/try_gear_up_sec_hud()
	if(is_wearing_sec_hud() || world.time < next_sec_hud_check_time)
		return FALSE
	next_sec_hud_check_time = world.time + 1200 //one try every 2 minutes if the fetch fails
	if(wear_sec_hud())
		return FALSE //already had one on us - worn now, nothing to go fetch
	var/datum/bot_goal/acquire_item_type/sec_hud/G = new()
	if(assign_goal(G))
		bot_log(src, "no sec HUD - going to get one from a security locker")
		return TRUE
	return FALSE

// The generic item fetch (goals/acquire_item_type.dm) - nearest loose pair, else the
// nearest locker this bot can actually open that has one (security lockers do, see
// secure_closet/security/PopulateContents()) - plus putting them on once in hand.
/datum/bot_goal/acquire_item_type/sec_hud
	item_type = /obj/item/clothing/glasses/hud/security/sunglasses

/datum/bot_goal/acquire_item_type/sec_hud/on_success(datum/bot_brain/bot)
	if(bot.wear_sec_hud())
		bot_say(bot.owner, pick("Much better.", "HUD's on.", "Right, let's see who's been naughty."))

// Sentences started by a bot that have since run out: the timer's already opened the
// door and unlocked the locker itself (door_timer/timer_end(), brigdoors.dm) - all that's
// left is the paperwork, same as a real officer marking the record once someone's served.
/datum/bot_brain/proc/check_finished_sentences()
	for(var/obj/machinery/door_timer/T in GLOB.bot_brig_sentences)
		if(QDELETED(T))
			GLOB.bot_brig_sentences -= T
			continue
		if(T.timing)
			continue
		var/datum/weakref/ref = GLOB.bot_brig_sentences[T]
		GLOB.bot_brig_sentences -= T
		var/mob/living/carbon/human/P = ref?.resolve()
		if(!P)
			continue
		bot_set_criminal_status(P, "Discharged")
		bot_say(owner, ":s [P.name]'s sentence in [T.name] is up, released.")
		bot_log(src, "[P]'s sentence in [T] finished - record set to Discharged")

// ============================================================
// Calls for help
// ============================================================

/// Whether a security bot would drop what it's doing to answer a call or grab someone wanted: yes for idling and
/// errands (fetching a HUD, restocking cuffs), no mid-fight, mid-arrest, or with a prisoner on the way to the brig.
/datum/bot_brain/proc/can_drop_for_call()
	if(state == BOT_STATE_WANDER)
		return TRUE
	if(state != BOT_STATE_GOAL)
		return FALSE
	return !istype(current_goal, /datum/bot_goal/brig_prisoner) && !istype(current_goal, /datum/bot_goal/respond_to_call)

/datum/bot_brain/proc/on_heard_security_call(atom/movable/speaker, raw_message, radio_freq)
	// (Used to need the bot idle, so an officer off fetching a sec HUD ignored someone screaming for help.)
	if(!is_security_job() || goal_chain_pending || !can_drop_for_call())
		return
	if(world.time < next_security_call_time)
		return
	var/atom/movable/real_speaker = speaker
	if(istype(speaker, /atom/movable/virtualspeaker))
		var/atom/movable/virtualspeaker/V = speaker
		real_speaker = V.source
	if(!isliving(real_speaker) || real_speaker == owner)
		return
	var/mob/living/L = real_speaker
	if(L.mind?.assigned_role in GLOB.security_positions)
		return //another officer's radio chatter isn't a call for help
	var/lower = lowertext(raw_message)
	if(!findtext(lower, "help") && !findtext(lower, "security") && !findtext(lower, "shitcurity"))
		return
	var/turf/T = get_turf(L)
	if(!T || T.z != owner.z)
		return
	next_security_call_time = world.time + 600
	if(state == BOT_STATE_GOAL)
		abandon_goals_for_arrest()
	var/datum/bot_goal/respond_to_call/G = new()
	G.caller_turf = T
	G.caller_name = L.name
	if(assign_goal(G))
		bot_say(owner, radio_freq ? ":s Responding to a call from [L.name] in [get_area_name(T, TRUE)]." : "On my way.")

/datum/bot_goal/respond_to_call
	var/turf/caller_turf
	var/caller_name

/datum/bot_goal/respond_to_call/resolve_target(datum/bot_brain/bot)
	target = caller_turf

/datum/bot_goal/respond_to_call/get_strategies(datum/bot_brain/bot)
	return list(new /datum/bot_strategy/respond_to_call())

/datum/bot_strategy/respond_to_call/New()
	. = ..()
	steps = list(new /datum/bot_step/move_to())

/datum/bot_strategy/respond_to_call/is_feasible(datum/bot_brain/bot)
	return TRUE

// Nothing more to do on arrival - once there, try_security_round()/the witness hook
// pick up anyone wanted or anything still going on, same as any other patrol stop.
/datum/bot_goal/respond_to_call/on_success(datum/bot_brain/bot)
	bot_log(bot, "arrived at [caller_name]'s call - looking around")
	bot.next_wander_time = world.time + 100 //linger a bit instead of immediately wandering off

// ============================================================
// Brig
// ============================================================

// The cell behind a brig door: a flood fill from the tile on the door's far side (a cell
// windoor blocks its own dir edge, so its own tile is OUTSIDE the cell - confirmed
// against the Box brig on hippiestation.dmm, where the doors face south into 3x3 cells),
// stopping at walls, windows, grilles and other doors. Cached per timer.
/proc/bot_get_cell_interior(obj/machinery/door_timer/T)
	if(GLOB.bot_brig_cell_interiors[T])
		return GLOB.bot_brig_cell_interiors[T]
	var/obj/machinery/door/window/brigdoor/door = locate() in T.targets
	if(!door)
		return null
	var/turf/door_turf = get_turf(door)
	var/turf/seed = get_step(door_turf, door.dir)
	var/list/interior = list()
	var/list/queue = list(seed)
	while(queue.len && interior.len < 30)
		var/turf/cur = queue[1]
		queue.Cut(1, 2)
		if(!cur || (cur in interior) || cur == door_turf || cur.density || isspaceturf(cur))
			continue
		if(get_dist(cur, seed) > 4)
			continue
		if(locate(/obj/machinery/door) in cur)
			continue
		if(locate(/obj/structure/window) in cur)
			continue
		if(locate(/obj/structure/grille) in cur)
			continue
		interior += cur
		for(var/d in GLOB.cardinals)
			queue += get_step(cur, d)
	GLOB.bot_brig_cell_interiors[T] = interior
	return interior

/proc/bot_find_cell_locker(obj/machinery/door_timer/T)
	return locate(/obj/structure/closet/secure_closet/brig) in T.targets

/datum/bot_brain/proc/is_in_active_cell(atom/M) // a prisoner, or anything else sitting in the cell
	var/turf/here = get_turf(M)
	if(!here)
		return FALSE
	for(var/obj/machinery/door_timer/T in GLOB.machines)
		if(!T.timing || T.z != here.z)
			continue
		var/list/interior = bot_get_cell_interior(T)
		if(interior && (here in interior))
			return TRUE
	return FALSE

/datum/bot_brain/proc/find_free_brig_cell()
	var/obj/machinery/door_timer/best
	var/best_dist
	for(var/obj/machinery/door_timer/T in GLOB.machines)
		if(T.z != owner.z || T.timing || (T.stat & (NOPOWER|BROKEN)))
			continue
		var/list/interior = bot_get_cell_interior(T)
		if(!length(interior))
			continue
		var/occupied = FALSE
		for(var/turf/I in interior)
			for(var/mob/living/carbon/C in I)
				if(C.stat != DEAD)
					occupied = TRUE
					break
			if(occupied)
				break
		if(occupied)
			continue
		var/d = get_dist(owner, T) // nearest cell, however far - an 80-tile cap here left anyone arrested on the far side of the station cuffed on the floor
		if(!best || d < best_dist)
			best = T
			best_dist = d
	return best

// The interior tile deepest from the door (preferring one next to the cell locker, where
// confiscated items go) - the bot drags the prisoner there, then swaps places with them
// so the prisoner ends up at the back of the cell and the bot between them and the door.
/proc/bot_pick_deep_cell_turf(obj/machinery/door_timer/T)
	var/list/interior = bot_get_cell_interior(T)
	var/obj/machinery/door/window/brigdoor/door = locate() in T.targets
	var/obj/structure/closet/locker = bot_find_cell_locker(T)
	if(!length(interior) || !door)
		return null
	var/turf/best
	var/best_score
	for(var/turf/I in interior)
		var/blocked = FALSE
		for(var/atom/movable/AM in I)
			if(AM.density && !ismob(AM))
				blocked = TRUE
				break
		if(blocked)
			continue
		var/score = get_dist(I, door) * 10
		if(locker && get_dist(I, locker) <= 1)
			score += 5
		if(!best || score > best_score)
			best = I
			best_score = score
	return best

/datum/bot_brain/proc/start_brig_escort(mob/living/carbon/human/H)
	var/cooldown = LAZYACCESS(failed_brig_targets, H)
	if(cooldown && world.time < cooldown)
		return FALSE
	var/datum/bot_goal/brig_prisoner/G = new()
	G.prisoner = H
	return assign_goal(G)

/datum/bot_goal/brig_prisoner
	var/mob/living/carbon/human/prisoner
	var/obj/machinery/door_timer/cell_timer
	var/turf/deep_turf

/datum/bot_goal/brig_prisoner/resolve_target(datum/bot_brain/bot)
	if(QDELETED(prisoner) || prisoner.stat == DEAD || !prisoner.handcuffed)
		return
	var/obj/machinery/door_timer/T = bot.find_free_brig_cell()
	if(!T)
		bot_log(bot, "no free brig cell for [prisoner]")
		bot_say(bot.owner, ":s All the cells are full, I need somewhere to put [prisoner.name]!")
		LAZYSET(bot.failed_brig_targets, prisoner, world.time + 600)
		return
	var/turf/D = bot_pick_deep_cell_turf(T)
	if(!D)
		return
	cell_timer = T
	deep_turf = D
	target = prisoner

/datum/bot_goal/brig_prisoner/get_strategies(datum/bot_brain/bot)
	return list(new /datum/bot_strategy/brig_prisoner(src))

/datum/bot_goal/brig_prisoner/on_give_up(datum/bot_brain/bot)
	bot.owner.stop_pulling()
	LAZYSET(bot.failed_brig_targets, prisoner, world.time + 150)

/datum/bot_goal/brig_prisoner/on_success(datum/bot_brain/bot)
	bot.owner.stop_pulling()

/datum/bot_strategy/brig_prisoner
	var/datum/bot_goal/brig_prisoner/goal

/datum/bot_strategy/brig_prisoner/New(datum/bot_goal/brig_prisoner/G)
	. = ..()
	goal = G
	var/datum/bot_step/move_to/to_cell = new()
	to_cell.step_target = G.deep_turf
	var/datum/bot_step/move_to/to_timer = new()
	to_timer.step_target = G.cell_timer
	steps = list(
		new /datum/bot_step/move_to(), //to the prisoner
		new /datum/bot_step/grab_patient(), //shared with escort_to_sleeper (treat_patient.dm) - it's just "pull the goal's target"
		to_cell,
		new /datum/bot_step/process_prisoner(G),
		to_timer,
		new /datum/bot_step/start_sentence(G),
	)

/datum/bot_strategy/brig_prisoner/is_feasible(datum/bot_brain/bot)
	return goal.cell_timer && !QDELETED(goal.cell_timer) && !QDELETED(goal.prisoner)

// Inside the cell: swap to the back, confiscate, uncuff. Paced one action per timer
// tick (like pickup_tool_from_target's grab_next()) rather than all in one instant.
/datum/bot_step/process_prisoner
	var/datum/bot_goal/brig_prisoner/goal
	var/phase = 0
	var/list/obj/item/to_confiscate

/datum/bot_step/process_prisoner/New(datum/bot_goal/brig_prisoner/G)
	. = ..()
	goal = G

/datum/bot_step/process_prisoner/execute(datum/bot_brain/bot)
	var/mob/living/carbon/human/P = goal.prisoner
	if(QDELETED(P) || P.stat == DEAD)
		return GOAL_STEP_FAIL
	if(!bot.owner.Adjacent(P))
		bot_log(bot, "lost hold of [P] on the way to the cell")
		return GOAL_STEP_FAIL
	var/list/interior = bot_get_cell_interior(goal.cell_timer)
	switch(phase)
		if(0)
			// Swap so the prisoner is deepest in the cell. Restrained mobs swap
			// with a help-intent mob (living/MobBump()) - the same thing that
			// happens when a player walks into someone they're escorting.
			bot.owner.stop_pulling()
			bot.owner.a_intent = INTENT_HELP
			var/turf/theirs = get_turf(P)
			if(P.handcuffed && (theirs in interior) && get_turf(bot.owner) == goal.deep_turf)
				bot.owner.Move(theirs, get_dir(bot.owner, theirs))
			phase = 1
			return schedule(bot)
		if(1)
			if(!(get_turf(P) in interior))
				bot_log(bot, "[P] isn't inside [goal.cell_timer.name] - can't process them there")
				return GOAL_STEP_FAIL
			// Weapons and anything else useful for breaking out - held items plus
			// anything obviously a weapon on the belt/back/suit storage. Tools and
			// ordinary job gear are left alone ("Don't confiscate items that were
			// unrelated to the crime").
			to_confiscate = list()
			for(var/obj/item/I in P.held_items)
				to_confiscate += I
			for(var/obj/item/I in list(P.belt, P.back, P.s_store, P.l_store, P.r_store))
				if(I && ((I.item_flags & NEEDS_PERMIT) || I.force >= 10 || istype(I, /obj/item/card/emag)))
					to_confiscate |= I
			phase = 2
			return schedule(bot)
		if(2)
			var/obj/structure/closet/locker = bot_find_cell_locker(goal.cell_timer)
			if(to_confiscate.len)
				var/obj/item/I = to_confiscate[1]
				to_confiscate.Cut(1, 2)
				if(!QDELETED(I) && (I in P.GetAllContents()))
					var/turf/drop = (locker && bot.owner.Adjacent(locker)) ? get_turf(locker) : get_turf(bot.owner)
					if(P.transferItemToLoc(I, drop))
						P.visible_message("<span class='warning'>[bot.owner] confiscates [I] from [P].</span>")
						bot_log(bot, "confiscated [I] from [P]")
				return schedule(bot)
			// Close the locker over whatever got dropped on its tile - door_timer's
			// timer_start() locks it (brigdoors.dm) until the sentence is up. Brig
			// lockers start the round locked (secure closets), hence the unlock.
			if(locker && !locker.opened && bot.owner.Adjacent(locker))
				if(locker.locked)
					locker.togglelock(bot.owner, TRUE)
				locker.open(bot.owner)
			if(locker && locker.opened && bot.owner.Adjacent(locker))
				locker.close(bot.owner)
			phase = 3
			return schedule(bot)
		if(3)
			// "Uncuff the prisoner, leaving them to buckle cuffed is considered poor
			// form" - and the bot needs its cuffs back for the next arrest anyway.
			var/obj/item/restraints/handcuffs/cuffs = P.handcuffed
			if(cuffs)
				P.uncuff()
				P.visible_message("<span class='notice'>[bot.owner] removes [P]'s restraints.</span>")
				if(!QDELETED(cuffs) && isturf(cuffs.loc) && !istype(cuffs, /obj/item/restraints/handcuffs/cable/zipties/used))
					bot.try_pickup_target(cuffs)
				bot_log(bot, "uncuffed [P]")
			phase = 0
			return GOAL_STEP_SUCCESS
	return GOAL_STEP_FAIL

/datum/bot_step/process_prisoner/proc/schedule(datum/bot_brain/bot)
	bot.owner.changeNext_move(CLICK_CD_MELEE)
	addtimer(CALLBACK(src, PROC_REF(continue_processing), bot), 10)
	return GOAL_STEP_PENDING

/datum/bot_step/process_prisoner/proc/continue_processing(datum/bot_brain/bot)
	if(QDELETED(bot) || bot.state != BOT_STATE_GOAL || bot.current_strategy?.steps?[bot.current_step_index] != src)
		return //goal moved on while we were waiting - don't act on stale state
	var/result = execute(bot)
	if(result != GOAL_STEP_PENDING)
		bot.advance_goal_step(result == GOAL_STEP_SUCCESS)

// At the timer outside the cell. Mirrors door_timer/ui_act()'s "preset"+"start" actions
// (brigdoors.dm), including its allowed() access check.
/datum/bot_step/start_sentence
	var/datum/bot_goal/brig_prisoner/goal

/datum/bot_step/start_sentence/New(datum/bot_goal/brig_prisoner/G)
	. = ..()
	goal = G

/datum/bot_step/start_sentence/execute(datum/bot_brain/bot)
	var/obj/machinery/door_timer/T = goal.cell_timer
	var/mob/living/carbon/human/P = goal.prisoner
	if(QDELETED(T) || QDELETED(P))
		return GOAL_STEP_FAIL
	if(!bot.owner.Adjacent(T))
		return GOAL_STEP_FAIL
	if(!T.allowed(bot.owner))
		bot_log(bot, "no access to [T]")
		return GOAL_STEP_FAIL
	if(!(get_turf(P) in bot_get_cell_interior(T)))
		// Walked out behind us before the door shut - still wanted, so the next
		// try_security_round() goes straight back after them.
		bot_log(bot, "[P] slipped out of [T.name] before the door closed")
		bot_say(bot.owner, "Get back in the cell, [P.name]!")
		return GOAL_STEP_FAIL
	var/datum/bot_wanted/W = bot_get_wanted_entry(P)
	var/crime
	var/severity
	if(W)
		crime = W.crime
		severity = W.severity
	else
		var/list/rec = bot_describe_record_crimes(P)
		crime = rec[1]
		severity = rec[2]
	var/sentence = BOT_SENTENCE_MINOR
	if(severity >= BOT_CRIME_MURDER)
		sentence = BOT_SENTENCE_MURDER
	else if(severity >= BOT_CRIME_MAJOR)
		sentence = BOT_SENTENCE_MAJOR
	bot.owner.changeNext_move(CLICK_CD_MELEE)
	T.set_timer(sentence)
	T.timer_start()
	T.update_icon()
	GLOB.bot_brig_sentences[T] = WEAKREF(P)
	bot_set_criminal_status(P, "Incarcerated")
	bot_clear_wanted(P)
	bot_log(bot, "sentenced [P] to [sentence / 600] minute\s in [T.name] for [crime]")
	bot_say(bot.owner, ":s [P.name] brigged in [T.name] for [sentence / 600] minute\s, charge: [lowertext(crime)].")
	if(severity >= BOT_CRIME_MURDER)
		bot_say(bot.owner, ":s Warden, HoS - [P.name] is in for murder, requesting a decision on permabrig.")
	return GOAL_STEP_SUCCESS



// ============================================================
// Victims calling it in
// ============================================================

/// Attacked by H: radio it in, the way a crewmember being beaten yells for security. Names them if their face can
/// be seen (so the officers who hear it know who to grab on sight - GLOB.bot_security_wanted), otherwise just
/// where. Nothing if this bot started the fight. Officers respond through on_heard_security_call() - no radio,
/// no response.
/datum/bot_brain/proc/bot_call_security(mob/living/carbon/human/H, what_done, atom/object)
	if(is_security_job() || world.time < next_assault_report_time || QDELETED(H))
		return
	var/we_started = GLOB.bot_recent_aggression["[REF(owner)]>[REF(H)]"]
	var/they_started = GLOB.bot_recent_aggression["[REF(H)]>[REF(owner)]"]
	if(we_started && world.time - we_started <= BOT_SELF_DEFENSE_WINDOW && (!they_started || we_started < they_started))
		return
	next_assault_report_time = world.time + 600
	var/where = get_area_name(owner, TRUE)
	var/who = H.name // their visible name - "Unknown" behind a mask with no ID showing
	var/identified = who && who != "Unknown"
	bot_say(owner, identified ? ";Security! [who] is attacking me in [where]!" : ";Help! Someone's attacking me in [where]!")
	if(!identified || !GLOB.bot_security_brains.len)
		return
	// Whoever's on duty takes the report down - a named assault goes on the record like any other.
	var/datum/bot_brain/officer = GLOB.bot_security_brains[1]
	var/list/verdict = bot_classify_crime(H, owner, what_done || "attacked", object)
	var/datum/bot_wanted/existing = bot_get_wanted_entry(H)
	if(!existing || existing.severity < verdict[2])
		officer.file_crime(H, verdict[1], "[verdict[3]] (reported by the victim)", verdict[2])
		bot_log(src, "reported [verdict[1]] by [H] to security")

#undef BOT_CRIME_MINOR
#undef BOT_CRIME_MAJOR
#undef BOT_CRIME_MURDER
#undef BOT_SENTENCE_MINOR
#undef BOT_SENTENCE_MAJOR
#undef BOT_SENTENCE_MURDER
#undef BOT_SEC_VIEW_RANGE
#undef BOT_ARREST_LOST_TIMEOUT
#undef BOT_ARREST_MAX_DURATION
#undef BOT_SELF_DEFENSE_WINDOW
