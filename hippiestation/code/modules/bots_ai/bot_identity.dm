// Milestone 1 "AI crew" scaffolding.
//
// A bot never gets a real /client connection - BYOND's key/ckey system can only be
// set by an actual connection logging in, so there's no way to fake one. Instead,
// bot_identity stands in for the handful of things core code reads from
// client/client.prefs, so a bot's /mob/dead/new_player can flow through the normal
// ready-up -> job assignment -> arrivals shuttle pipeline completely unmodified
// everywhere else (SSjob.AssignRole/EquipRank, antag latejoin rolling, quirks, etc.
// already null-guard their client reads and need no changes).
/mob/dead/new_player
	var/datum/bot_identity/bot_identity

/datum/bot_identity
	var/mob/dead/new_player/owner
	var/persona_name
	var/datum/preferences/fake_prefs
	var/mob/living/carbon/human/spawned_human //set once create_bot_character() runs, since owner (the new_player) gets qdel'd by transfer_character()

/datum/bot_identity/New(mob/dead/new_player/new_owner)
	. = ..()
	owner = new_owner
	persona_name = pick(GLOB.bot_persona_names)
	fake_prefs = new /datum/preferences(null)
	fake_prefs.random_character()
	fake_prefs.real_name = persona_name

/datum/bot_identity/Destroy()
	owner = null
	QDEL_NULL(fake_prefs)
	return ..()

// Mirrors /mob/dead/new_player/proc/create_character(), but sources appearance from
// fake_prefs instead of client.prefs (which would be a null-deref for a bot).
/datum/bot_identity/proc/create_bot_character(transfer_after)
	var/mob/dead/new_player/NP = owner
	NP.spawning = 1
	NP.close_spawn_windows()

	var/mob/living/carbon/human/H = new(NP.loc)
	fake_prefs.copy_to(H)
	H.dna.update_dna_identity()

	if(NP.mind)
		if(transfer_after)
			NP.mind.late_joiner = TRUE
		NP.mind.active = FALSE //we wish to "transfer the key" manually (i.e. not at all - there isn't one)
		NP.mind.transfer_to(H)

	H.name = H.real_name
	NP.real_name = H.real_name

	spawned_human = H
	NP.new_character = H
	if(transfer_after)
		NP.transfer_character() //NOTE: this stomps H.key back to NP.key (null) - key must be (re)assigned after this call, not before

	// Without a key, human/examine.dm treats a mob as a permanently catatonic corpse
	// ("the stresses of life in deep-space...") rather than a merely-unresponsive one.
	// A synthetic, never-connectable key flips that branch (and every other `if(!key)`
	// check scattered around the codebase) without needing a real client - no client
	// will ever actually hold this string, so it just sits as inert bookkeeping.
	H.key = generate_fake_key()

	// GLOB.player_list is documented as "all mobs with clients attached" and is read
	// that way in hot per-tick code (SSinput.fire() calls user.focus?.keyLoop(user.client)
	// for every entry, every tick, with no null-guard on client) - putting a clientless
	// bot in it caused a runtime flood, not just a shuttle fix. bot_crew_members is our
	// own list for the one place that actually needed bot-awareness (see arrivals.dm override).
	GLOB.bot_crew_members |= H

	return H

/datum/bot_identity/proc/generate_fake_key()
	GLOB.bot_id_counter++
	var/slug = lowertext(replacetext(persona_name, " ", ""))
	return "bot-[slug]-[GLOB.bot_id_counter]"

/mob/dead/new_player/IsJobUnavailable(rank, latejoin = FALSE)
	if(!bot_identity)
		return ..()
	// Ban/age/playtime checks all key off ckey/client, neither of which a bot has -
	// they trivially don't apply, so only slot availability is checked here.
	var/datum/job/job = SSjob.GetJob(rank)
	if(!job)
		return JOB_UNAVAILABLE_GENERIC
	if((job.current_positions >= job.total_positions) && job.total_positions != -1)
		return JOB_UNAVAILABLE_SLOTFULL
	return JOB_AVAILABLE

/mob/dead/new_player/create_character(transfer_after)
	if(bot_identity)
		return bot_identity.create_bot_character(transfer_after)
	return ..()

GLOBAL_VAR_INIT(bot_id_counter, 0)
GLOBAL_LIST_EMPTY(bot_crew_members)

GLOBAL_LIST_INIT(bot_persona_names, list(
	"Alex Reyes", "Jordan Blake", "Casey Nakamura", "Morgan Vance", "Riley Osei",
	"Sam Delacroix", "Taylor Huang", "Jamie Novak", "Avery Solano", "Quinn Larsen",
	"Devon Whitfield", "Parker Osei", "Rowan Kessler", "Elliot Mbeki", "Skyler Voss",
))
