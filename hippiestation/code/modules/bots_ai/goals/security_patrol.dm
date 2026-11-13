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

// Sentences go by Space Law (bot_law.dm), fed straight into door_timer/set_timer(), and
// brigdoors.dm caps those at 15 minutes. A capital charge is held for that long while
// whoever's in charge decides what's to be done.

#define BOT_SEC_VIEW_RANGE 7
// How long a suspect can stay out of sight before the chase is called off.
#define BOT_ARREST_LOST_TIMEOUT 300
// Hard cap on one arrest attempt, however it's going.
#define BOT_ARREST_MAX_DURATION 3000
// After giving one up for taking too long, before it starts on the same suspect again (unless they come at it).
#define BOT_ARREST_RETRY_REST (3 MINUTES)
// Retaliating against someone who hit you within this window is self-defense, not a crime.
#define BOT_SELF_DEFENSE_WINDOW 300

GLOBAL_LIST_EMPTY(bot_security_brains) //every living security-job bot_brain, see is_security_job()
GLOBAL_LIST_EMPTY(bot_security_wanted) //weakref(mob) -> /datum/bot_wanted
GLOBAL_LIST_EMPTY(bot_recent_aggression) //"[REF(attacker)]>[REF(victim)]" -> world.time
GLOBAL_LIST_EMPTY(bot_brig_sentences) //door_timer -> weakref(prisoner), see check_finished_sentences()

/// Both brig lists here are keyed by the cell's timer: one blown up stayed in them, a hard delete (3-4 a disaster round)
/obj/machinery/door_timer/Destroy()
	GLOB.bot_brig_cell_interiors -= src
	GLOB.bot_brig_sentences -= src
	return ..()
GLOBAL_LIST_EMPTY(bot_brig_cell_interiors) //door_timer -> list of turfs inside that cell

// Substrings of log_combat()'s what_done that count as violence. Deliberately excludes
// grabs, shoves and disarms (horseplay as often as not), injections (doctors), and
// "fired at" (logged at the moment of firing, before anything's actually been hit).
GLOBAL_LIST_INIT(bot_violent_combat_verbs, list(
	"attacked", "punched", "kick", "shot", "threw and hit", "tackled", "smothered",
	"strangled", "stunned", "stung", "flashed", "handcuffed", "slashed", "stabbed",
	"bit", "chop", "elbow", "knee", "sweep", "gibbed", "attempted to punch", "attempted to neck grab", "attempted to strangle",
	"tabled", "pinned", "thrown",
))

/datum/bot_wanted
	var/crime
	var/severity = BOT_CRIME_MINOR
	var/time_reported = 0
	/// Where they were last reported, and when: what a hunter goes on (bot_playstyles.dm).
	var/turf/last_seen
	var/last_seen_at = 0
	/// What they did, as it went on the record, and who to: what an officer tells them, and weighs what they say against (bot_asks.dm).
	var/details
	var/datum/weakref/victim
	/// Everybody they're on the record for hurting (weakrefs): one of them dying of it later is murder (bot_victim_died())
	var/list/victims
	/// Called out on the radio as one to kill on sight (bot_law.dm bot_call_kill_on_sight()), and how senior whoever last said
	/// otherwise, or said it again, was (bot_authority_rank()): 0 is Security's own call.
	var/kill_on_sight = FALSE
	var/kos_rank = 0

/datum/bot_brain
	/// When it'll next say on the radio that the cells are full
	var/next_cells_full_shout = 0
	var/mob/living/carbon/human/arrest_suspect
	var/arrest_crime
	var/arrest_severity = BOT_CRIME_MINOR
	var/arrest_hailed = FALSE
	var/arrest_resisted = FALSE
	var/arrest_started = 0
	/// weakref(suspect) -> when it'll start on them again, after an arrest given up for taking too long
	var/list/arrest_rests
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
	var/role = work_role()
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

/// When any officer may next say the cells are full
GLOBAL_VAR_INIT(bot_cells_full_shouted, 0)

/// What makes somebody a confirmed antagonist on the record: killing, wrecking the station, owning up to the Syndicate.
GLOBAL_LIST_INIT(bot_antag_crimes, list("Murder", "Attempted Murder", "Sabotage", "Subversion of the Chain of Command"))

/// A confirmed antagonist: in a nanosuit, or wanted for one of bot_antag_crimes. Fighting them is no crime, and killing them isn't either.
/// The user's ruling (2026-11-10): "Known valids and antags killers are always innocent". In their round an officer cuffed a nanosuit,
/// searched it, found "nothing on them" (the suit's worn, not carried) and let it go, and the next officer along booked the cook and the
/// atmos tech who were fighting it for Assault with a Deadly Weapon. One was hunted as a criminal for the rest of the round.
/proc/bot_is_fair_game(mob/living/carbon/human/H)
	if(bot_in_nanosuit(H) || bot_in_syndicate_suit(H)) //goals/security_tactics.dm
		return TRUE
	var/datum/bot_wanted/W = bot_get_wanted_entry(H)
	return W && (W.severity >= BOT_CRIME_MURDER || (W.crime in GLOB.bot_antag_crimes))

// Mirrors what the sec HUD's "status" and "add_crime" hrefs (human.dm Topic()) do.
/datum/bot_brain/proc/file_crime(mob/living/carbon/human/H, crime, details, severity, mob/living/victim)
	if(severity < BOT_CRIME_MAJOR && bot_is_the_captain(H)) //bot_law.dm
		bot_log(src, "not putting the Captain on record for [lowertext(crime)]")
		return
	var/datum/bot_wanted/W = bot_get_wanted_entry(H)
	if(!W)
		W = new
		W.time_reported = world.time
		GLOB.bot_security_wanted[WEAKREF(H)] = W
	// A confirmed antagonist's charge isn't written over by a lesser one of the same weight. In the user's Captain round (round-20.37.50)
	// Wren called the Captain kill on sight for Attempted Murder, the HoS saw him shoot her a minute later and filed Assaulting an Officer
	// over it, and from then on he wasn't fair game (bot_is_fair_game()) and every officer cuffed him "for assaulting an officer".
	var/keeps_charge = W.crime && severity == W.severity && (W.crime in GLOB.bot_antag_crimes) && !(crime in GLOB.bot_antag_crimes)
	if(victim)
		LAZYOR(W.victims, WEAKREF(victim))
	if((severity >= W.severity || !W.crime) && !keeps_charge)
		W.crime = crime
		W.severity = severity
		W.details = details
		W.victim = victim ? WEAKREF(victim) : null
	W.last_seen = get_turf(H)
	W.last_seen_at = world.time
	bot_news("Security's after [H.real_name] for [lowertext(crime)]", H)
	for(var/datum/bot_brain/officer as anything in GLOB.bot_security_brains) //bot_memory.dm: it's on the records
		officer.learn_fact(BOT_FACT_WANTED, H, null, null, crime, 1, "the records")
	// A confirmed antagonist: to be killed on sight, and the radio told so, unless somebody senior has already said otherwise (bot_law.dm)
	if(!W.kill_on_sight && !W.kos_rank && (W.crime in GLOB.bot_antag_crimes))
		W.kill_on_sight = TRUE
		bot_call_kill_on_sight(H, W, src)

	var/datum/data/record/R = bot_find_security_record(H)
	if(!R)
		return
	var/author = "[owner.real_name] ([work_role()])"
	var/datum/data/crime/C = GLOB.data_core.createCrimeEntry(crime, details, author, station_time_timestamp())
	if(severity >= BOT_CRIME_MAJOR)
		GLOB.data_core.addMajorCrime(R.fields["id"], C)
	else
		GLOB.data_core.addMinorCrime(R.fields["id"], C)
	if(R.fields["criminal"] != "*Arrest*")
		H.investigate_log("[key_name(H)] has been set from [R.fields["criminal"]] to *Arrest* by [key_name(owner)] (bot AI).", INVESTIGATE_RECORDS)
		R.fields["criminal"] = "*Arrest*"
	H.sec_hud_set_security_status()

/// A murder on the records (the severity defines stop at the end of this file).
/datum/bot_brain/proc/file_murder(mob/living/carbon/human/H, details)
	file_crime(H, "Murder", details, BOT_CRIME_MURDER)

/// How long after the last blow a death is still put down to it
#define BOT_DIED_OF_IT_WINDOW (3 MINUTES)

GLOBAL_DATUM(bot_death_listener, /datum/bot_death_listener)

/datum/bot_death_listener/proc/on_death(datum/source, mob/living/M, gibbed)
	SIGNAL_HANDLER
	if(ishuman(M))
		addtimer(CALLBACK(GLOBAL_PROC, GLOBAL_PROC_REF(bot_victim_died), M), 1)
		addtimer(CALLBACK(GLOBAL_PROC, GLOBAL_PROC_REF(bot_crew_saw_death), M), 1) //bot_memory.dm: who saw it
		addtimer(CALLBACK(GLOBAL_PROC, GLOBAL_PROC_REF(bot_ghosts_saw_death), M), 1) //bot_comings.dm: the ghosts notice

/// Listens for deaths, from the first bot on (SSdcs isn't up when globals are made)
/datum/bot_brain/New()
	. = ..()
	if(!GLOB.bot_death_listener)
		GLOB.bot_death_listener = new
		GLOB.bot_death_listener.RegisterSignal(SSdcs, COMSIG_GLOB_MOB_DEATH, TYPE_PROC_REF(/datum/bot_death_listener, on_death))

/// Somebody who died of what was done to them after the fact, bleeding out or choking in crit, while whoever did it is already wanted:
/// that's murder now. In the user's Captain round (round-20.37.50) the Warden bled out two minutes after the Captain shotgunned him,
/// the crew monitor read it out on the radio, and the Captain stayed wanted for Assaulting an Officer. A death in front of an officer
/// is called at the time (bot_classify_crime()).
/proc/bot_victim_died(mob/living/carbon/human/victim)
	if(QDELETED(victim) || victim.stat != DEAD || !victim.mind?.assigned_role || !victim.last_assailant || victim.last_assailant == victim.real_name)
		return
	if(world.time - victim.last_assailant_at > BOT_DIED_OF_IT_WINDOW || bot_is_fair_game(victim))
		return
	// Whoever's on the record for hurting this one, and was the last to: Security knows who did it, not just that somebody died. A bartender
	// wanted for a punch at somebody else, who killed the Captain where nobody saw, was booked for it all the same (shift batch capt2_1110).
	var/mob/living/carbon/human/killer
	var/datum/bot_wanted/W
	var/datum/weakref/victim_ref = WEAKREF(victim)
	for(var/datum/weakref/ref as anything in GLOB.bot_security_wanted)
		var/mob/living/carbon/human/H = ref.resolve()
		var/datum/bot_wanted/entry = GLOB.bot_security_wanted[ref]
		if(H && H != victim && H.real_name == victim.last_assailant && (victim_ref in entry.victims))
			killer = H
			W = entry
			break
	if(!killer)
		return
	// Security's own force, as when it's seen (bot_security_judge_combat())
	if(bot_is_officer(killer) && (killer.bot_brain || bot_is_wanted(victim)))
		return
	// They went for the killer first: that's self-defense, however it ended (bot_security_judge_combat())
	var/their_first = GLOB.bot_recent_aggression["[REF(victim)]>[REF(killer)]"]
	var/our_first = GLOB.bot_recent_aggression["[REF(killer)]>[REF(victim)]"]
	if(their_first && (!our_first || their_first < our_first))
		return
	var/list/verdict = bot_classify_crime(killer, victim, "killed", null)
	if(W.crime == verdict[1])
		return
	// Whoever keeps the records: the nearest officer who's up, else the nearest of anybody (Bot Gym: the one in that arena)
	var/datum/bot_brain/clerk
	var/clerk_dist
	var/turf/where = get_turf(victim)
	for(var/datum/bot_brain/B as anything in GLOB.bot_brains)
		if(QDELETED(B.owner) || B.owner.stat != CONSCIOUS || B.owner == killer)
			continue
		var/dist = (B.owner.z == where?.z ? get_dist(B.owner, where) : 500) + (B.is_security_job() ? 0 : 1000)
		if(!clerk || dist < clerk_dist)
			clerk = B
			clerk_dist = dist
	if(!clerk)
		return
	var/old_crime = W.crime
	clerk.file_crime(killer, verdict[1], "[victim.real_name] died of it. [verdict[3]]", verdict[2], victim)
	if(W.crime == old_crime)
		return
	bot_log(clerk, "[victim] died of what [killer] did to them: [lowertext(old_crime)] is [lowertext(W.crime)] now")
	for(var/datum/bot_brain/B as anything in GLOB.bot_security_brains)
		if(B.arrest_suspect == killer && W.severity >= B.arrest_severity)
			B.arrest_crime = W.crime
			B.arrest_severity = W.severity
	if(clerk.is_security_job())
		bot_say(clerk.owner, ":s [victim.real_name] didn't make it. [killer.real_name]'s wanted for [lowertext(W.crime)] now.")

#undef BOT_DIED_OF_IT_WINDOW

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
	if(isobj(target))
		if(what_done == "attacked")
			bot_note_vandalism(user, target) //bot_witness.dm
		return
	if(issilicon(target))
		var/mob/living/silicon/S = target
		if(S.bot_silicon && isliving(user) && bot_is_violent_verb(what_done))
			addtimer(CALLBACK(S.bot_silicon, TYPE_PROC_REF(/datum/bot_silicon, hit_by), user), 1) //goals/silicon.dm
		return
	if(!isliving(user) || !ishuman(target) || user == target)
		return
	// Security's prisoner's cuffs off them, and back on again (bot_witness.dm)
	if(ishuman(user) && findtext(what_done, "stripped") && bot_restraints_named(what_done))
		bot_note_uncuffed(user, target)
		return
	if(ishuman(user) && findtext(what_done, "handcuffed") && bot_note_recuffed(user, target))
		return
	if(ishuman(user) && findtext(what_done, "handcuffed"))
		addtimer(CALLBACK(GLOBAL_PROC, GLOBAL_PROC_REF(bot_crew_saw_cuffing), user, target), 1) //bot_memory.dm
	if(!bot_is_violent_verb(what_done))
		bot_note_kindness(user, target, what_done) //bot_social.dm: patched up, brought round
		bot_note_handling(user, target, what_done, object) //bot_reflexes.dm: a shove, a grab, a needle
		return
	// Something light that came flying isn't violence: a bruise pack out of the hand of somebody who slipped, a
	// thrown paper cup. Not a crime and not a fight - a doctor it happened to once kicked its own patient into a coma.
	var/obj/item/thrown = object
	if(istype(thrown) && thrown.throwforce < 5 && findtext(what_done, "threw"))
		var/mob/living/carbon/human/struck = target
		struck.bot_brain?.mind_thrown_junk()
		return
	// Thrown at something else and it hit them on the way: an accident, held back while there's time to say sorry (bot_witness.dm)
	if(findtext(what_done, "threw") && ishuman(user) && bot_hold_accident(user, target, what_done, object))
		return
	// Records when each attacker FIRST started on each victim (within the window), not
	// the latest hit - so a fight's instigator stays the instigator even after the
	// other side starts hitting back. See bot_security_judge_combat()'s self-defense check.
	if(ishuman(user))
		bot_record_aggression(user, target)
		var/mob/living/carbon/human/assailant = user
		var/mob/living/carbon/human/marked = target
		marked.last_assailant = assailant.real_name //what a forensic scan can turn up (goals/detective.dm)
		if(bot_is_fair_game(marked))
			assailant.bot_fought_valid_at = world.time //bot_witness.dm: what they break getting at one isn't vandalism
		marked.last_assailant_gloved = !!assailant.gloves
		marked.last_assailant_at = world.time
	// A bot notices being hurt however it happened - fists, feet, teeth, bullets, thrown junk - not just item hits
	// (this used to hang off attacked_by(), which only item attacks reach).
	var/mob/living/carbon/human/victim = target
	victim.bot_brain?.on_attacked(user, what_done, object)
	if(!ishuman(user))
		return
	addtimer(CALLBACK(GLOBAL_PROC, /proc/bot_crew_witness_combat, user, target, what_done, object), 1) //bot_witness.dm
	bot_note_backup(user, target) //bot_social.dm: a hand in somebody's fight
	if(GLOB.bot_security_brains.len)
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
	// Security using force is assumed lawful, unless it's a player who's just killed somebody nobody wanted arrested.
	if(bot_is_officer(attacker) && (attacker.bot_brain || victim.stat != DEAD || bot_is_wanted(victim)))
		return
	// Hitting back at someone who started it is self-defense.
	var/their_first = GLOB.bot_recent_aggression["[REF(victim)]>[REF(attacker)]"]
	var/our_first = GLOB.bot_recent_aggression["[REF(attacker)]>[REF(victim)]"]
	if(their_first && world.time - their_first <= BOT_SELF_DEFENSE_WINDOW && their_first < our_first)
		return
	// A confirmed antagonist is fair game, killing them included (bot_is_fair_game()).
	if(bot_is_fair_game(victim))
		return
	// The Captain executing somebody wanted, or a blow to a body already dead (bot_law.dm)
	if(bot_lawful_execution(attacker, victim) || bot_hit_a_corpse(victim))
		return
	// Somebody Security's already after for less is fair game too: hitting them is no crime, down or cuffed or not. Killing them still is.
	if(bot_is_wanted(victim) && victim.stat != DEAD)
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
	// tg's item attacks log the weapon by name (item_attack.dm: log_combat(user, M, "attacked", src.name)), so a toolbox to the head read
	// as a bare-handed "Assault", a minor charge, for every player: it's the thing in their hands of that name
	if(istext(object))
		for(var/obj/item/held in attacker.held_items)
			if(held.name == object)
				object = held
				break
	if(isitem(object))
		var/obj/item/I = object
		weapon_force = I.force
	if(istype(object, /obj/item/projectile))
		var/obj/item/projectile/P = object
		if(!P.nodamage && P.damage_type != STAMINA)
			weapon_force = max(weapon_force, P.damage)
	var/where = get_area_name(victim, TRUE)
	if(victim.stat == DEAD)
		if(bot_is_wanted(victim)) //somebody Security was after: still murder, but no capital case over it
			return list("Murder", BOT_CRIME_MAJOR, "Killed [victim.real_name], who Security was after, in [where].")
		if(victim.mind?.assigned_role in GLOB.command_positions)
			return list("Subversion of the Chain of Command", BOT_CRIME_MURDER, "Killed [victim.real_name] in [where].")
		return list("Murder", BOT_CRIME_MURDER, "Killed [victim.real_name] in [where].")
	if(findtext(lower, "handcuffed"))
		return list("Kidnapping", BOT_CRIME_MAJOR, "Restrained [victim.real_name] without authority in [where].")
	// Beaten into crit, somebody who wasn't fair game: that's a confirmed antagonist as the user has it (2026-11-10)
	if(victim.health <= victim.crit_threshold)
		return list("Attempted Murder", BOT_CRIME_MAJOR, "Left [victim.real_name] dying in [where].")
	if(victim.mind?.assigned_role in GLOB.security_positions)
		return list("Assaulting an Officer", BOT_CRIME_MAJOR, "Attacked [victim.real_name] ([what_done]) in [where].")
	if(weapon_force >= 10)
		return list("Assault with a Deadly Weapon", BOT_CRIME_MAJOR, "[capitalize(what_done)] [victim.real_name] with [object] in [where].")
	if(victim.stat != CONSCIOUS)
		return list("Aggravated Assault", BOT_CRIME_MAJOR, "Left [victim.real_name] incapacitated in [where].")
	if(attacker.bot_brain?.playstyle == BOT_STYLE_HUNTER)
		return list("Vigilantism", BOT_CRIME_MINOR, "[capitalize(what_done)] [victim.real_name] in [where], with nobody having asked them to.")
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
	file_crime(attacker, crime, details, severity, victim)
	if(new_report)
		bot_log(src, "witnessed [attacker] commit [crime] against [victim] @ [bot_coord(get_turf(victim))]")
		bot_say(owner, ":s [crime] in progress, [get_area_name(attacker, TRUE)] - suspect [attacker.name]. Responding.")
	begin_arrest(attacker)

// ============================================================
// Arrest (BOT_STATE_ARREST - see process(), bot_brain.dm)
// ============================================================

// Returns TRUE if the bot is now (or already was) arresting H.
/// Another officer's prisoner already: on the way to a cell with them (their escort claims the prisoner), or in a running cell. Two
/// officers after one prisoner went wrong: one came into the cell the other had just put him in, tasered and cuffed him and started
/// dragging him out, the first took that for a jailbreak and shot, and four officers fought it out at the labor shuttle dock.
/datum/bot_brain/proc/brigged_by_another(mob/living/carbon/human/H)
	if(taken_by_another(H))
		var/datum/bot_brain/other = GLOB.bot_work_claims[REF(H)]
		if(other?.is_security_job() && istype(other.current_goal, /datum/bot_goal/brig_prisoner))
			return TRUE
	// Serving a sentence: the prisoner of a running cell (GLOB.bot_brig_sentences), inside it. Not just anybody standing in a cell
	// with a timer going: a Bot Gym arena built where a running cell had been read as one, and nobody there was ever arrested.
	for(var/obj/machinery/door_timer/T as anything in GLOB.bot_brig_sentences)
		var/datum/weakref/ref = GLOB.bot_brig_sentences[T]
		if(!QDELETED(T) && T.timing && ref?.resolve() == H && (get_turf(H) in bot_get_cell_interior(T)))
			return TRUE
	return FALSE

/datum/bot_brain/proc/begin_arrest(mob/living/carbon/human/H)
	if(!istype(H) || QDELETED(H) || H == owner || H.stat == DEAD)
		return FALSE
	if(brigged_by_another(H))
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
	if(severity < BOT_CRIME_MAJOR && bot_is_the_captain(H)) // even on the records (a player officer's): bot_law.dm
		return FALSE
	// A nanosuit loose: that's Security's business till it's dealt with, not a broken window. Two officers came for the user lying in crit
	// for Vandalism, a nanosuit in the room (the user's playtest, 2026-11-13).
	if(severity < BOT_CRIME_MAJOR && !bot_is_fair_game(H) && suit_at_large()) //goals/security_tactics.dm
		if(world.time >= next_keep_clear_note)
			next_keep_clear_note = world.time + 1 MINUTES
			bot_log(src, "a nanosuit's loose - [lowertext(crime)] by [H] can wait")
		return FALSE

	if(state == BOT_STATE_ARREST)
		if(arrest_suspect == H)
			if(severity > arrest_severity)
				arrest_severity = severity
				arrest_crime = crime
			return TRUE
		// Somebody worse in sight: they come first, and whoever it was after stays wanted for later. An officer used to carry on after
		// a player for a scuffle with a traitor in a nanosuit stood beside them.
		var/mob/living/carbon/human/current = arrest_suspect
		if(QDELETED(current) || current.handcuffed || arrest_busy || (world.time < fallen_back_until && bot_too_dangerous(H)) || !(severity > arrest_severity || (bot_too_dangerous(H) && !bot_too_dangerous(current))) || !(H in view(7, owner)))
			return FALSE //already busy with someone else - they stay wanted, picked up later
		bot_log(src, "leaving [current] ([arrest_crime]) for [H] ([crime])")
		end_arrest("somebody worse turned up")

	// Never drop a prisoner mid-escort to go chase someone new.
	if(state == BOT_STATE_GOAL && istype(current_goal, /datum/bot_goal/brig_prisoner))
		return FALSE
	// Nor red alert, the armory or arming up, for somebody walking past: the Warden off for the ion rifle took a cuffed prisoner to the
	// brig instead, and never went back for it.
	if(state == BOT_STATE_GOAL && current_goal?.holds_for_calls)
		return FALSE
	if(world.time < fallen_back_until && bot_too_dangerous(H)) //goals/security_tactics.dm
		return FALSE
	// Given up on for taking too long: not straight back on to them. An officer waiting on two more for a traitor in a nanosuit
	// started the same arrest over the moment it timed out, seven times running (27 minutes in the Brig, "Couldn't bring in" on
	// the radio every time, 79 pacing flags, shift batch ask1 run8). Somebody coming at it is a fight, not this.
	if(LAZYACCESS(arrest_rests, WEAKREF(H)) > world.time)
		return FALSE
	// Nothing to arrest them with. An officer who'd used up its cuffs started and ended the same arrest thousands of times,
	// stood next to the suspect for five minutes. It can fight (on_attacked()) or go and get some (try_security_round()).
	if(!H.handcuffed && !find_restraints())
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
	if(brigged_by_another(S))
		end_arrest("another officer has them, or they're in a cell")
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
		LAZYSET(arrest_rests, WEAKREF(S), world.time + BOT_ARREST_RETRY_REST)
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
		// It looks for them, where they'd have gone and what they could be hiding in (foundation/hunt.dm), rather than going back to its
		// rounds: a player does
		var/turf/lost_at = arrest_last_seen_turf
		var/lost_since = arrest_last_seen
		var/minor = arrest_severity < BOT_CRIME_MAJOR
		end_arrest("lost sight of suspect")
		start_search(S, lost_at, lost_since, minor ? "arrest_minor" : "arrest")
		return

	var/dist = get_dist(owner, S)
	var/subdued = is_subdued(S)
	// Somebody you don't walk up to (a nanosuit, a gun, blood on them) is only down when they're down: out, out of breath for good, or
	// held for longer than it takes to get the cuffs on. A Warden walked in on a baton's moment of stun on a traitor in a nanosuit, who
	// was up before the cuffs were, and five officers died one after another in the Brig the same way.
	if(subdued && S.stat == CONSCIOUS && bot_too_dangerous(S) && S.AmountParalyzed() < 4 SECONDS && S.AmountUnconscious() <= 0 && S.getStaminaLoss() < 100)
		subdued = FALSE

	// Badly hurt on somebody dangerous: it falls back, seen or not. It used to only notice in sight of them, and one waiting just out
	// of sight stayed put however hurt it was.
	if(!subdued && bot_too_dangerous(S) && too_hurt_to_stay()) //goals/security_tactics.dm
		fall_back_from(S)
		return
	// Somebody it may shoot to kill stood beside a fuel tank: the tank (foundation/tactics.dm)
	if(visible && !subdued && bot_may_use_lethal_force(S) && try_tank_shot(S))
		arrest_last_dist = dist
		return
	if(visible && !subdued && bot_too_dangerous(S) && keep_it_at_range(S, dist)) //goals/security_tactics.dm
		arrest_last_dist = dist
		return

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

	// A colleague's beside them already, making the same arrest: stand by a few tiles off rather than walk into them. Two officers
	// after one man who stood still for it took turns swapping each other off the one tile beside him, and every pair of cuffs that
	// went on was cut short and counted as him resisting. Not while he's fighting, or has the colleague beaten - but flashed or
	// stunned on the floor he isn't fighting, whatever his intent: two officers swapped places over a swordsman the flash had put
	// down, and the cuffs never got on.
	if(visible && dist <= 3 && (S.a_intent != INTENT_HARM || S.incapacitated()) && bot_colleague_arresting(S))
		stop_pursuit()
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
	// Running across in front of it: to where they'll be, not where they are (foundation/hunt.dm)
	if(visible && !subdued && chase == S && !bot_too_dangerous(S))
		var/turf/cut = cut_off_point(S)
		if(cut)
			pursuit_goal = cut
	var/turf/goal_turf = get_turf(pursuit_goal)
	if(!goal_turf)
		return
	// Reached the last sighting and they're not here: keep looking around until the lost-sight timeout. Beside it is as good, with
	// somebody already stood on it: two officers after the same man took turns walking on to the spot and swapping the other off it,
	// for the half minute it took them to give him up.
	if(!visible && (get_turf(owner) == goal_turf || (get_dist(owner, goal_turf) <= 1 && (locate(/mob/living) in goal_turf))))
		stop_pursuit()
		return
	if(!subdued && bot_too_dangerous(S)) //goals/security_tactics.dm
		var/hold = hold_off_distance(S)
		// Waiting on the others out of sight, it stays put a couple of tiles past the hold distance too: the spot short of the last
		// sighting moves with every step it takes, and with people about it was never free (security_tactics.dm wait_for_the_others())
		var/slack = (!visible && short_of_the_others(S)) ? 2 : 0
		if(get_dist(owner, goal_turf) > hold + slack)
			var/turf/short = spot_short_of(goal_turf, hold)
			// Waiting on the others, a spot a step off isn't worth the step: the same officer shuffled between two Brig tiles
			// for half an hour of waiting (ask1 run8)
			if(slack && short && get_dist(owner, short) <= 1)
				stop_pursuit()
				return
			if(short)
				pursuit_goal = short
				goal_turf = short
		else if(!visible && short_of_the_others(S))
			stop_pursuit()
			return //no nearer where a suit was last seen, without the others
	// In the pool, or somewhere in it it was walking to, with this bot on the side (poolside_instead(), bot_items.dm): round to the side
	// nearest them, and a wait there for the breath to go in after them. Not a walk that fails: five of those in a row gave the arrest up
	// as "can't reach", and anybody in the pool used to be out of Security's reach (the user, 2026-11-04).
	var/turf/side = poolside_instead(pursuit_goal)
	if(side == get_turf(owner))
		stop_pursuit()
		return
	if(side)
		pursuit_goal = side
		goal_turf = side
	if(!pursuing_kind || pursue_target != pursuit_goal || !arrest_path_turf || get_dist(arrest_path_turf, goal_turf) > 1)
		arrest_path_turf = goal_turf
		pursue(pursuit_goal, "arrest", force = TRUE)

/// Another officer stood beside `S`, on its feet and not badly hurt, arresting them too.
/datum/bot_brain/proc/bot_colleague_arresting(mob/living/carbon/human/S)
	for(var/mob/living/carbon/human/H in range(1, S))
		if(H == owner || H == S || H.stat != CONSCIOUS || H.health < H.maxHealth * 0.5)
			continue
		var/datum/bot_brain/other = H.bot_brain
		if(other && other.state == BOT_STATE_ARREST && other.arrest_suspect == S)
			return TRUE
	return FALSE

/// A door in the way of an arrest for something minor, that won't open for this officer: not worth hacking or breaking into a
/// department for. It asks over the radio (the AI opens doors for whoever asks with a reason, goals/silicon.dm), and otherwise
/// waits for them to come out, until the lost-sight timeout gives them up. An officer after somebody for a scuffle once hacked the
/// Kitchen's door and bolted it open. Major crimes and murder still get through whatever's in the way.
/datum/bot_brain/proc/minor_arrest_at_door(obj/machinery/door/D)
	if(state != BOT_STATE_ARREST || arrest_severity >= BOT_CRIME_MAJOR)
		return FALSE
	if(world.time >= next_minor_door_ask)
		next_minor_door_ask = world.time + 20 SECONDS
		bot_log(src, "[D] won't open for me, and [lowertext(arrest_crime)] isn't worth breaking in for - asking the AI")
		bot_say(owner, ";AI, open [D.name] for Security, please. I'm after [arrest_suspect?.name] for [lowertext(arrest_crime)].")
	return TRUE

/datum/bot_brain
	var/next_minor_door_ask = 0

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
	var/list/line = getline(owner, target)
	for(var/turf/T in line)
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
	return !crew_in_the_way(target, line)

/// Somebody innocent right beside the line of fire, or next to the target: a shot that goes a little wide, or a target that steps
/// aside, hits them instead. Officers shot a cargo tech beating on a nanosuit, twice with a disabler and twice with a laser, from
/// across the room: the line itself was clear. Not somebody wanted or fighting this bot, and not somebody beside the shooter itself
/// (a shot goes away from there).
/datum/bot_brain/proc/crew_in_the_way(mob/living/target, list/line)
	var/turf/mine = get_turf(owner)
	for(var/turf/T in line)
		if(T == mine)
			continue
		for(var/mob/living/carbon/human/H in range(1, T))
			if(H == owner || H == target || H == attacker || H.stat == DEAD || get_dist(H, mine) <= 1)
				continue
			var/datum/bot_wanted/W = bot_get_wanted_entry(H)
			if(W && W.severity >= BOT_CRIME_MAJOR)
				continue //on the other side of this
			return TRUE
	return FALSE

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
	// Somebody dangerous on their feet: the flash first, which an energy sword doesn't block and puts them down for long enough to cuff
	if(bot_too_dangerous(S) && !is_subdued(S) && S.get_eye_protection() <= 0 && try_flash(S)) //bot_playstyles.dm
		return
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
		LAZYOR(my_prisoners, WEAKREF(S)) //goals/security_custody.dm: its to see to, whatever comes up next
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
		// A pair it can walk to by its own doors: the SecTech, a locker, one lying about in the Brig. The nearest as the crow flies was as
		// often the pair on the Bridge's desk, the zipties in the Head of Personnel's office or the pair walled up with a skeleton in
		// maintenance: officers set off for those 127 times in twelve shifts and gave up at the end of the route search, every two
		// minutes, and now and then started on the Captain's Quarters door with a screwdriver to get at them.
		sub.lawful = TRUE
		sub.lawful_tries = 16 //MetaStation has seven pairs behind somebody else's door, and the SecTech can be the furthest of the lot
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
		if(LAZYACCESS(arrest_rests, WEAKREF(H)) > world.time) //given up on for taking too long (begin_arrest())
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
	return !current_goal?.holds_for_calls && !istype(current_goal, /datum/bot_goal/brig_prisoner) && !istype(current_goal, /datum/bot_goal/respond_to_call)

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
	if(istype(real_speaker, /obj/item/electronic_assembly))
		on_heard_circuit_alarm(real_speaker, raw_message, radio_freq) //goals/circuits.dm: a motion alarm calling it in
		return
	if(!isliving(real_speaker) || real_speaker == owner)
		return
	var/mob/living/L = real_speaker
	if(L.mind?.assigned_role in GLOB.security_positions)
		return //another officer's radio chatter isn't a call for help
	var/turf/T = get_turf(L)
	if(!T || T.z != owner.z)
		return
	if(!bot_line_calls_security(lowertext(raw_message), T))
		return
	next_security_call_time = world.time + 600
	if(state == BOT_STATE_GOAL)
		abandon_goals_for_arrest()
	var/datum/bot_goal/respond_to_call/G = new()
	G.caller_turf = T
	G.caller_name = L.name
	if(assign_goal(G))
		bot_say(owner, radio_freq ? ":s Responding to a call from [L.name] in [get_area_name(T, TRUE)]." : "On my way.")

/// "help" as a cry, wherever it is in the line (a line opening with "help" is one too: "Help! Security!", "help maint").
GLOBAL_LIST_INIT(bot_help_cries, list("help me", "help us", "need help", "needs help", "someone help", "somebody help", "anyone help", "anybody help", "send help", "get help"))
/// "help" as an everyday word: "better parts would help", "help yourselves", "I'll come help", "can I help you?".
GLOBAL_LIST_INIT(bot_help_not_cries, list("would help", "will help", "should help", "might help", "can help", "could help", "help yourself", "help yourselves",
	"help you", "help out", "help with", "to help", "i'll help", "ill help", "come help"))
/// Trouble in a call for help that's Security's whoever it was put to ("medic, someone's attacking me").
GLOBAL_LIST_INIT(bot_danger_words, list("attack", "attacked", "attacking", "kill", "killing", "murder", "murderer", "after me", "stabbed", "stabbing",
	"shot", "shooting", "beating", "traitor", "changeling", "griefer", "greytide"))

/// Whether a line said near an officer, or on its radio, is somebody calling Security. Security named is always a call ("sec to
/// medbay": bot_typing.dm types it so too). Otherwise it's a cry for help, and not one put to another trade: round-10.32.13, a doctor
/// radioed "Science, could you upgrade the machines in Medbay Treatment Center? Better parts would help." and all five officers
/// answered it, on the word "help".
/proc/bot_line_calls_security(lower, turf/near)
	// Put to the AI or a cyborg, or about bolts, with nobody in danger and no "help" in it: "AI unbolt all security" is the Brig's
	// doors, not a call. Three officers said they were responding to the Captain asking the AI for them (round-20.48.49).
	if(!bot_text_has_any(lower, list("help")) && !bot_text_has_any(lower, GLOB.bot_danger_words) && (bot_silicon_addressed(lower, list("ai", "ais", "borg", "borgs", "cyborg")) || bot_text_has_any(lower, list("unbolt", "unbolted", "bolt", "bolted", "bolts"))))
		return FALSE
	if(findtext(lower, "security") || findtext(lower, "shitcurity") || bot_text_has_any(lower, list("sec")))
		return TRUE
	if(!bot_text_has_any(lower, list("help")))
		return FALSE
	if(bot_text_has_any(lower, GLOB.bot_danger_words))
		return TRUE
	var/cry = bot_text_word_at(lower, "help") == 1 || bot_text_has_any(lower, GLOB.bot_help_cries)
	if(!cry && bot_text_has_any(lower, GLOB.bot_help_not_cries))
		return FALSE
	// Put to another trade ("doctor, I need help"): theirs to answer (bot_requests.dm)
	var/datum/bot_request_kind/K = bot_request_kind_of(lower, FALSE, near)
	if(K && length(K.jobs) && !length(K.jobs & GLOB.security_positions))
		return FALSE
	return TRUE

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
	addtimer(CALLBACK(bot, TYPE_PROC_REF(/datum/bot_brain, report_on_call)), 8 SECONDS)

/// A look round, and word to whoever called: they'd want to know.
/datum/bot_brain/proc/report_on_call()
	if(QDELETED(owner) || owner.stat != CONSCIOUS || state != BOT_STATE_WANDER)
		return
	bot_tally("checked in on a department")
	bot_say(owner, pick(":s Nothing here now, [get_area_name(owner, TRUE)]'s clear.", ";[get_area_name(owner, TRUE)] looks clear from here. Call again if they come back."))

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
	return active_cell_of(M) ? TRUE : FALSE

/// The timer of the cell M is in, if a sentence is running in it; null otherwise.
/datum/bot_brain/proc/active_cell_of(atom/M)
	var/turf/here = get_turf(M)
	if(!here)
		return null
	for(var/obj/machinery/door_timer/T as anything in bot_instances_of(/obj/machinery/door_timer))
		if(!T.timing || T.z != here.z)
			continue
		var/list/interior = bot_get_cell_interior(T)
		if(interior && (here in interior))
			return T
	return null

/// prisoner: who it's for, who doesn't count as somebody already in there (stood in their own cell after a fight in it, they're
/// arrested again and the cell they're in is the one to use: it used to read as taken).
/datum/bot_brain/proc/find_free_brig_cell(mob/living/prisoner)
	var/obj/machinery/door_timer/best
	var/best_dist
	for(var/obj/machinery/door_timer/T as anything in bot_instances_of(/obj/machinery/door_timer))
		if(T.z != owner.z || T.timing || (T.stat & (NOPOWER|BROKEN)))
			continue
		var/list/interior = bot_get_cell_interior(T)
		if(!length(interior))
			continue
		var/occupied = FALSE
		for(var/turf/I in interior)
			// The trapdoor's still open from the last release (two minutes on the Hippie map): nobody can stand on it to swap a prisoner
			// to the back. The Warden picked Cell 4 a second after its last prisoner went down it and failed eleven times.
			if(GLOB.bot_open_trapdoors[I])
				occupied = TRUE
				break
			for(var/mob/living/carbon/C in I)
				if(C.stat != DEAD && C != prisoner && C != owner)
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
		if(bot_turf_is_deadly(I)) //an open trapdoor: the route there never gets planned (bot_pathing_permissive.dm)
			continue
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
	if(prisoner_in_lawful_hands(H)) //the Captain, a head or another officer walking them off (bot_law.dm)
		bot_log(src, "leaving [H] to [H.pulledby], who has them")
		LAZYSET(failed_brig_targets, H, world.time + 30 SECONDS)
		return FALSE
	// With the shuttle on its way there's no sentence left to serve. Locking somebody up now only leaves them behind: an officer brigged a
	// man as another stopped that cell's timer, the door was caught half shut, and he was still in there when the shuttle left.
	var/datum/bot_wanted/W = bot_get_wanted_entry(H)
	var/obj/docking_port/mobile/emergency/E = SSshuttle.emergency
	if(E && (E.mode == SHUTTLE_CALL || E.mode == SHUTTLE_DOCKED) && (!W || W.severity < BOT_CRIME_MURDER))
		H.uncuff()
		bot_clear_wanted(H)
		bot_set_criminal_status(H, "Discharged")
		bot_say(owner, "[H.name], get to the shuttle. You can explain yourself at CentCom.")
		bot_log(src, "let [H] go for the evacuation")
		return FALSE
	// Wanted only for something they were seen carrying, and searched with nothing on them: let go. The user was arrested for an
	// energy sword they'd got rid of three minutes before, which the HoP was carrying by then. Never somebody in a nanosuit: it's worn, so
	// the search turns up nothing, and an officer let one go that way (2026-11-10).
	if(W?.crime == "Possession of Dangerous Equipment" && H.handcuffed && owner.Adjacent(H) && !bot_carrying_contraband(H) && !bot_in_nanosuit(H))
		human_pause(H)
		if(!QDELETED(H) && owner.Adjacent(H) && !bot_carrying_contraband(H))
			H.uncuff()
			bot_clear_wanted(H)
			bot_set_criminal_status(H, "Discharged")
			bot_say(owner, pick("Alright, you're clean. Next time you find something like that, hand it in to Security.", "Nothing on you. You're free to go - bring anything like that straight to Security next time."))
			bot_log(src, "searched [H], wanted for carrying contraband: nothing on them, let go")
			bot_tally("searched and let go")
			return FALSE
	// Where they lie, the air was too bad to go in for them a moment ago (assign_goal()): left for now, whichever way they'd have been taken.
	// Three officers asked again every time they looked for a cuffed traitor lying in crit in Atmospherics as its air went, 117 times between
	// them, each time first finding nowhere in Security to keep him for a doctor (bugs1112b run3).
	if(refused_for_air(H) && !is_eva_ready())
		return FALSE
	// Nobody's locked up dying. A cook cuffed at -4 health was dragged to a cell and left: he died there 3 minutes later. Down or pale
	// from losing blood, they're taken to Medbay instead (security_medevac.dm), or failing a way there, Medical is called to them.
	if(bot_prisoner_needs_medbay(H))
		// Somebody dangerous doesn't leave Security: kept in the Brig, and Medical's called there (security_medevac.dm). With no doctor
		// after a while, into the cell regardless, patched up there.
		if(bot_prisoner_dangerous(H))
			var/tried = LAZYACCESS(brig_care_tried, H)
			if((!tried || world.time > tried + 5 MINUTES) && start_brig_care(H))
				return TRUE
			var/datum/bot_goal/brig_prisoner/cell_anyway = new()
			cell_anyway.prisoner = H
			return assign_goal(cell_anyway)
		// On their feet: processed in the cell first, into orange and patched, then to Medbay in cuffs (security_medevac.dm). The user's
		// ruling (2026-11-05): "ensure they are always wearing prison outfits, never their regular clothes".
		if(H.stat == CONSCIOUS && H.health > 0 && !istype(H.w_uniform, /obj/item/clothing/under/rank/prisoner))
			var/datum/bot_goal/brig_prisoner/first = new()
			first.prisoner = H
			first.then_medbay = TRUE
			if(assign_goal(first))
				return TRUE
		if(start_medevac(H))
			return TRUE
		if(!bot_in_medbay(H))
			bot_say(owner, ";Medical, [H.name] is in cuffs and needs a doctor, [get_area_name(H, TRUE)].")
			LAZYSET(failed_brig_targets, H, world.time + 1 MINUTES)
		return FALSE
	var/datum/bot_goal/brig_prisoner/G = new()
	G.prisoner = H
	return assign_goal(G)

/datum/bot_goal/brig_prisoner
	exclusive = TRUE //two officers once took the same prisoner to two different cells
	var/mob/living/carbon/human/prisoner
	var/obj/machinery/door_timer/cell_timer
	var/turf/deep_turf
	/// On their way to the Prison Wing rather than a cell (bot_law.dm), and the locker for what they own.
	var/for_life = FALSE
	var/obj/structure/closet/secure_closet/brig/prison_locker
	/// Processed into orange in the cell, then on to Medbay in their cuffs rather than left there (security_medevac.dm)
	var/then_medbay = FALSE

/datum/bot_goal/brig_prisoner/resolve_target(datum/bot_brain/bot)
	if(QDELETED(prisoner) || prisoner.stat == DEAD || !prisoner.handcuffed)
		return
	if(bot.prisoner_in_lawful_hands(prisoner)) //taken over by the Captain, a head or another officer: theirs now (bot_law.dm)
		return
	var/datum/bot_case/case = bot_case_of(prisoner)
	if(case?.verdict == BOT_VERDICT_PERMABRIG)
		deep_turf = bot_prison_spot()
		if(deep_turf)
			for_life = TRUE
			prison_locker = bot_prison_locker(deep_turf)
			target = prisoner
			return
	var/obj/machinery/door_timer/T = bot.find_free_brig_cell(prisoner)
	if(!T)
		bot_log(bot, "no free brig cell for [prisoner]")
		// it tries again every minute: the channel had this 37 times in three shifts. Once for all of Security: three officers said it
		// in the same second (2026-11-10).
		if(world.time >= bot.next_cells_full_shout && world.time >= GLOB.bot_cells_full_shouted)
			bot.next_cells_full_shout = world.time + 5 MINUTES
			GLOB.bot_cells_full_shouted = world.time + 1 MINUTES
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
	return list(for_life ? new /datum/bot_strategy/take_to_prison(src) : new /datum/bot_strategy/brig_prisoner(src))

/datum/bot_goal/brig_prisoner/on_give_up(datum/bot_brain/bot)
	bot.owner.stop_pulling()
	LAZYSET(bot.failed_brig_targets, prisoner, world.time + 150)

/datum/bot_goal/brig_prisoner/on_success(datum/bot_brain/bot)
	bot.owner.stop_pulling()
	if(then_medbay && !QDELETED(prisoner) && prisoner.stat != DEAD)
		if((bot_prisoner_needs_medbay(prisoner) || bot_bleeding_out(prisoner)) && bot_prisoner_dangerous(prisoner))
			bot.continue_goal_chain(CALLBACK(bot, TYPE_PROC_REF(/datum/bot_brain, start_brig_care), prisoner, cell_timer))
		else if(bot_prisoner_needs_medbay(prisoner) || bot_bleeding_out(prisoner))
			bot.continue_goal_chain(CALLBACK(bot, TYPE_PROC_REF(/datum/bot_brain, start_medevac), prisoner, cell_timer))
		else
			bot.continue_goal_chain(CALLBACK(bot, TYPE_PROC_REF(/datum/bot_brain, start_brig_escort), prisoner))

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
		new /datum/bot_step/move_to/brig_first_aid(G), //security_brig_first_aid.dm: the Brig's kit, for somebody bleeding
		new /datum/bot_step/take_brig_first_aid(G),
		to_cell,
		new /datum/bot_step/process_prisoner(G),
		to_timer,
		new /datum/bot_step/start_sentence(G),
	)
	if(G.then_medbay) //no sentence yet: Medbay next, in their cuffs
		steps -= list(to_timer, steps[length(steps)])

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
			// All of it but their clothes goes in the cell's locker, and comes back when the timer opens it (the user's ruling): what's
			// in their hands, the bag, the belt, the pockets, the ID, the headset, gloves, mask, glasses, hat and suit, and what a search
			// turns up hidden on them. Weapons only, it used to be: a prisoner kept their tools, their radio and whatever was in their bag.
			to_confiscate = bot.everything_but_clothes(P) //bot_law.dm
			bot.search_prisoner(P, src) //bot_law.dm
			phase = 2
			return schedule(bot)
		if(2)
			var/obj/structure/closet/locker = bot_find_cell_locker(goal.cell_timer)
			if(to_confiscate.len)
				var/obj/item/I = to_confiscate[1]
				to_confiscate.Cut(1, 2)
				if(!QDELETED(I) && (I in P.GetAllContents()))
					var/turf/drop = (locker && bot.owner.Adjacent(locker)) ? get_turf(locker) : get_turf(bot.owner)
					if(bot_take_from_hiding(P, I, drop)) //bot_law.dm: out of the butt, and the like
						P.visible_message("<span class='warning'>[bot.owner] pulls [I] out of [P]'s hiding place.</span>")
						bot_log(bot, "found [I] hidden on [P]")
						bot_tally("hidden things found")
					else if(istype(I, /obj/item/disk/nuclear) && P.transferItemToLoc(I, get_turf(bot.owner)))
						bot.owner.put_in_hands(I)
						bot.put_away(I)
						bot_log(bot, "took [I] off [P]")
					else
						var/slot = bot_slot_holding(P, I) //goals/released_prisoner.dm: theirs to take back when they're let out
						if(P.transferItemToLoc(I, drop))
							P.visible_message("<span class='warning'>[bot.owner] confiscates [I] from [P].</span>")
							bot_log(bot, "confiscated [I] from [P]")
							bot_note_confiscated(P, I, slot, locker)
				return schedule(bot)
			// Into orange, out of the locker: the brig lockers keep a prisoner's jumpsuit and shoes. Brig lockers start the round
			// locked (secure closets), hence the unlock.
			if(locker && !locker.opened && bot.owner.Adjacent(locker))
				if(locker.locked)
					locker.togglelock(bot.owner, TRUE)
				locker.open(bot.owner)
				return schedule(bot)
			if(locker?.opened && bot.owner.Adjacent(locker) && bot.dress_in_orange(P, get_turf(locker))) //bot_law.dm, a piece a go
				return schedule(bot)
			// Close the locker over whatever got dropped on its tile - door_timer's timer_start() locks it (brigdoors.dm) until the
			// sentence is up.
			if(locker && locker.opened && bot.owner.Adjacent(locker))
				locker.close(bot.owner)
			phase = 3
			return schedule(bot)
		if(3)
			// Bleeding: patched up before they're left (security_brig_first_aid.dm)
			if(bot.patch_up_prisoner(P, src))
				return schedule(bot)
			var/obj/item/restraints/handcuffs/cuffs = P.handcuffed
			// Still bleeding with nothing to patch them with: not left in a cell no doctor's ID opens. Off to a doctor in their cuffs
			// instead, or kept by Security's front door for one if they're dangerous (brig_prisoner on_success(), security_medevac.dm).
			if(cuffs && told_medical && !goal.then_medbay && bot_bleeding_out(P))
				bot_log(bot, "[P] is still bleeding and I've nothing to patch them with - to a doctor in the cuffs, no sentence yet")
				goal.then_medbay = TRUE
			if(cuffs && goal.then_medbay)
				phase = 0
				return GOAL_STEP_SUCCESS //to Medbay in them
			// Went for the officer the last time the cuffs came off: they stay on (goals/released_prisoner.dm)
			// A confirmed antagonist stays cuffed too: a wizard cuffed for attempted murder was uncuffed in its cell two seconds later
			// (live round n0_wizard, 2026-11-10). Capital prisoners are held for the Captain's word (bot_law.dm).
			if(cuffs && (bot_keep_cuffed(P) || bot_is_fair_game(P)))
				if(bot_keep_cuffed(P))
					bot_log(bot, "leaving [P] cuffed - they went for the officer the last time they were uncuffed")
					bot_say(bot.owner, pick("You're keeping those on.", "Cuffs stay on. You had your chance.", "Not after last time. They stay on."))
				else
					var/datum/bot_wanted/W = bot_get_wanted_entry(P)
					bot_log(bot, "leaving [P] cuffed - wanted for [W ? W.crime : "something serious"]")
					bot_say(bot.owner, pick("Those stay on.", "You're not going anywhere.", "Cuffs stay on."))
				phase = 0
				return GOAL_STEP_SUCCESS
			// "Uncuff the prisoner, leaving them to buckle cuffed is considered poor
			// form" - and the bot needs its cuffs back for the next arrest anyway.
			if(cuffs)
				bot_note_uncuffed_in_cell(P)
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
	if(goal.then_medbay)
		return GOAL_STEP_SUCCESS //decided in the cell: a doctor first, the sentence after
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
	var/sentence = bot_sentence_for(crime, severity)
	bot.owner.changeNext_move(CLICK_CD_MELEE)
	T.set_timer(sentence)
	T.timer_start()
	T.update_icon()
	GLOB.bot_brig_sentences[T] = WEAKREF(P)
	bot_set_criminal_status(P, "Incarcerated")
	bot_clear_wanted(P)
	if(P.bot_brain)
		P.bot_brain.last_charge = crime //what it says it's in for (bot_asks.dm)
	bot_log(bot, "sentenced [P] to [sentence / 600] minute\s in [T.name] for [crime]")
	bot_say(bot.owner, ":s [P.name] brigged in [T.name] for [sentence / 600] minute\s, charge: [bot_charge_line(crime)].")
	if(severity >= BOT_CRIME_MURDER)
		bot_open_case(P, crime, T, bot) //bot_law.dm
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
	// Somebody Security's after has nothing to report: whoever's hitting them is doing Security's job. A traitor in a nanosuit
	// reported a player for assault this way, the crime went on the player's record though the traitor's radio call came out
	// as a threat, and every officer who saw the player went for them while the traitor stood beside them.
	if(gone_loud() || bot_is_wanted(owner))
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
		officer.file_crime(H, verdict[1], "[verdict[3]] (reported by the victim)", verdict[2], owner)
		bot_log(src, "reported [verdict[1]] by [H] to security")

#undef BOT_SEC_VIEW_RANGE
#undef BOT_ARREST_LOST_TIMEOUT
#undef BOT_ARREST_MAX_DURATION
#undef BOT_ARREST_RETRY_REST
#undef BOT_SELF_DEFENSE_WINDOW
