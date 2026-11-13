// The radio as it is (the user's question after their playtest, 2026-11-13: "how did Security know it was vandalism, telecommunications
// was disabled?"). Calling something in said it on the radio and, whatever became of the line, put it on Security's records too: the user
// had wrecked Telecomms, not one crew bot's radio line got out for the rest of the round, and the Vandalism was on their record anyway.
//
// What a bot radios does what it does (a crime on the record, Security sent, a doctor asked for) only if telecomms carried it: the
// broadcast is noted against whoever spoke, and looked for a moment later. A call that didn't get out is kept, and told to the next
// officer it's close enough to talk to. What's heard over the radio is answered by whoever hears it, as ever (Hear(), bot_brain.dm).

/// REF(speaker) -> when telecomms last carried something they said
GLOBAL_LIST_EMPTY(bot_radio_carried)

/datum/signal/subspace/vocal/broadcast()
	var/atom/movable/virtualspeaker/V = virt
	if(V?.source && data["message"])
		GLOB.bot_radio_carried[REF(V.source)] = world.time
	return ..()

/area/bot_gym
	/// A Bot Gym arena has no telecomms of its own: radio calls made in it count as carried, unless the scenario has the radio out
	var/radio_down = FALSE

/// Once a moment's gone by (telecomms passes a line on within a tick or two), `heard` if something `speaker` said since `since` got out
/// over the radio, `not_heard` if not.
/proc/bot_radio_then(atom/movable/speaker, since, datum/callback/heard, datum/callback/not_heard)
	if(!speaker)
		return
	var/area/bot_gym/arena = get_area(speaker)
	if(istype(arena))
		if(arena.radio_down)
			not_heard?.Invoke()
		else
			heard?.Invoke()
		return
	addtimer(CALLBACK(GLOBAL_PROC, GLOBAL_PROC_REF(bot_radio_check), REF(speaker), since, heard, not_heard), 2 SECONDS)

/proc/bot_radio_check(speaker_ref, since, datum/callback/heard, datum/callback/not_heard)
	if(GLOB.bot_radio_carried[speaker_ref] >= since)
		heard?.Invoke()
	else
		not_heard?.Invoke()

// ---------------------------------------------------------------------------------------------
// What a call does once it's heard
// ---------------------------------------------------------------------------------------------

/// On Security's records, as whoever's on duty would put it from the call (call_it_in(), bot_witness.dm; bot_call_security(),
/// goals/security_patrol.dm), or from being told in person
/datum/bot_brain/proc/report_to_security(datum/weakref/culprit_ref, crime, details, severity, datum/weakref/victim_ref)
	var/mob/living/carbon/human/culprit = culprit_ref?.resolve()
	if(QDELETED(culprit) || !length(GLOB.bot_security_brains))
		return
	var/datum/bot_brain/officer = GLOB.bot_security_brains[1]
	var/datum/bot_wanted/existing = bot_get_wanted_entry(culprit)
	if(!existing || existing.severity < severity)
		officer.file_crime(culprit, crime, details, severity, victim_ref?.resolve())

// ---------------------------------------------------------------------------------------------
// Telling an officer in person
// ---------------------------------------------------------------------------------------------

/// How long something it couldn't radio is still worth telling
#define BOT_UNTOLD_KEEP (10 MINUTES)

/datum/bot_brain
	/// What it radioed that never got out: list(list(callback, what to tell them, when, weakref to who it's about))
	var/list/untold

/// The call didn't get out (bot_radio_then()): kept for the next officer it sees close by, unless that's who it's about
/datum/bot_brain/proc/keep_to_tell(datum/callback/effect, line, datum/weakref/about)
	if(QDELETED(src) || QDELETED(owner))
		return
	LAZYADD(untold, list(list(effect, line, world.time, about)))
	bot_log(src, "nobody heard that on the radio - telling Security when I see them: [line]")
	bot_tally("radio calls that didn't get out")

/// From keep_an_eye_out() (bot_witness.dm): an officer close enough to talk to is told it all. TRUE if it told them something.
/datum/bot_brain/proc/tell_officer_in_person()
	if(!LAZYLEN(untold) || owner.incapacitated())
		return FALSE
	var/mob/living/carbon/human/officer
	for(var/mob/living/carbon/human/H in view(3, owner))
		if(H != owner && H.stat == CONSCIOUS && !H.handcuffed && bot_is_officer(H))
			officer = H
			break
	if(!officer)
		for(var/list/entry as anything in untold.Copy())
			if(world.time > entry[3] + BOT_UNTOLD_KEEP)
				LAZYREMOVE(untold, list(entry))
		return FALSE
	var/list/told = untold
	untold = null
	owner.face_atom(officer)
	var/said = FALSE
	for(var/list/entry as anything in told)
		if(world.time > entry[3] + BOT_UNTOLD_KEEP)
			continue
		var/datum/weakref/about = entry[4]
		if(about?.resolve() == officer)
			LAZYADD(untold, list(entry)) //not to their face: the next officer
			continue
		if(!said)
			said = TRUE
			bot_say(owner, "[officer.first_name()], [entry[2]] The radio's not working.")
		else
			bot_say(owner, "And [entry[2]]")
		var/datum/callback/C = entry[1]
		C?.Invoke()
	if(said)
		bot_log(src, "told [officer] in person what the radio didn't carry")
		bot_tally("told an officer in person")
	return said

#undef BOT_UNTOLD_KEEP

/// Medical asked to come to somebody, from a radio call that got out (the AI's crew monitor, silicon_ai_watch.dm; an officer with a
/// prisoner who needs one, security_medevac.dm)
/proc/bot_ask_medical_for(datum/weakref/W, freq)
	var/mob/living/carbon/human/H = W?.resolve()
	if(QDELETED(H) || H.stat == DEAD)
		return
	var/datum/bot_request_kind/medical/M = locate() in GLOB.bot_request_kinds
	if(M && !bot_open_request_from(H, M))
		bot_offer_request(bot_new_request(M, H, freq, H))
