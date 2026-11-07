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
	// transfer_character() deletes the new_player once the human exists - holding it after that forced a hard delete per bot
	RegisterSignal(owner, COMSIG_PARENT_QDELETING, PROC_REF(owner_deleted))
	// A name nobody on the crew has yet, while there are any left - telemetry and the Bot Shift report tell bots apart by name
	var/list/free_names = GLOB.bot_persona_names.Copy()
	for(var/mob/living/carbon/human/crew_member in GLOB.bot_crew_members)
		free_names -= crew_member.real_name
	fake_prefs = new /datum/preferences(null)
	fake_prefs.random_character()
	if(length(free_names))
		persona_name = pick(free_names)
	else
		// Every persona is on the crew already: the name the character generator rolls, like a player who pressed Random.
		persona_name = fake_prefs.pref_species.random_name(fake_prefs.gender, 1)
	fake_prefs.real_name = persona_name

/datum/bot_identity/proc/owner_deleted()
	SIGNAL_HANDLER
	owner = null

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

	if(H.mind)
		H.mind.bot_handle = pick_handle()
		H.mind.bot_ping = rand(25, 120)

	return H

/// What they go by among the players: the key "bot-whoever-3" is for logs and admins.
/datum/bot_identity/proc/pick_handle()
	var/list/free = GLOB.bot_handles.Copy()
	for(var/mob/living/carbon/human/crew_member as anything in GLOB.bot_crew_members)
		free -= crew_member.mind?.bot_handle
	return length(free) ? pick(free) : "[pick(GLOB.bot_handles)][rand(10, 99)]"

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

/// Whether there's a start point for this job with nobody on it. Without one SSjob.EquipRank() stands them at some other job's.
/proc/bot_post_free(rank)
	if(length(GLOB.jobspawn_overrides[rank]))
		return TRUE
	for(var/obj/effect/landmark/start/post in GLOB.start_landmarks_list)
		if(post.name == rank && !(locate(/mob/living) in post.loc))
			return TRUE
	return FALSE

/// What readying up does in SSticker.setup(), for one bot once the round is under way: at their post, equipped, on the
/// manifest, and no arrival announcement. create_characters() to transfer_characters() in that order.
/mob/dead/new_player/proc/join_at_post(rank)
	if(!SSjob.AssignRole(src, rank, TRUE))
		return FALSE
	var/mob/living/carbon/human/H = create_character(FALSE)
	GLOB.joined_player_list += H.ckey
	SSticker.minds += H.mind
	SSjob.EquipRank(src, rank, FALSE)
	GLOB.data_core.manifest_inject(H)
	AddEmploymentContract(H)
	if(CONFIG_GET(flag/roundstart_traits))
		SSquirks.AssignQuirks(H, null, TRUE)
	log_manifest(H.mind.key, H.mind, H, latejoin = FALSE)
	var/bot_key = H.key
	transfer_character() //stomps the key, see create_bot_character()
	H.key = bot_key
	return TRUE

/// Whether this is one of the bot crew, who have no client and aren't to be treated as if they'd wandered off.
/mob/proc/is_bot_crew()
	return FALSE

/mob/living/carbon/human/is_bot_crew()
	return !isnull(bot_brain)

/datum/mind
	/// A bot's name among the players, in the Who list and the round-end report
	var/bot_handle
	/// What the Who list gives as a bot's ping
	var/bot_ping = 0

GLOBAL_VAR_INIT(bot_id_counter, 0)
GLOBAL_LIST_EMPTY(bot_crew_members)

GLOBAL_LIST_INIT(bot_handles, list(
	"Greytider99", "MaintRat", "RobustRandy", "CargoCultist", "PlasmaFlood", "Sadcrab", "Honkmother7", "Clownshoes", "ToolboxEnjoyer",
	"SoyCaptain", "StationPet", "AtmosFan", "InsulsPlease", "BeepskyFan", "Tiderman", "AirlockShock", "VendorTipper", "PunPunFan",
	"MedbayDweller", "SpessBeans", "DonkPocket", "Breadlord", "MothLamp", "WelderFuel", "PipeDream", "Scrubber", "MopBucket",
	"FloorBuffer", "TileRipper", "GlassShard", "SolarArray", "NukeDiskNerd", "ThermalPaste", "Gorlex", "SpacemanSteve", "Cheesewheel",
	"PocketSand", "Lavalander", "ChefSurprise", "HotDonk", "CritTheory", "Cardboardbox", "Radstorm", "Stationwagon", "Wirecutter",
))

GLOBAL_LIST_INIT(bot_persona_names, list(
	"Alex Reyes", "Jordan Blake", "Casey Nakamura", "Morgan Vance", "Riley Osei",
	"Sam Delacroix", "Taylor Huang", "Jamie Novak", "Avery Solano", "Quinn Larsen",
	"Devon Whitfield", "Parker Osei", "Rowan Kessler", "Elliot Mbeki", "Skyler Voss",
	"Robin Castellanos", "Frankie Dunmore", "Jesse Okafor", "Kai Lindqvist", "Dana Petrov",
	"Emery Haldane", "Reese Tanaka", "Noel Abernathy", "Sasha Brennan", "Harper Nwosu",
	"Blake Ferreira", "Lee Montague", "Charlie Vasquez", "Ash Kowalski", "Remy Thackeray",
	"Shay Okonkwo", "Pat Holloway", "Corey Ishikawa", "Jude Marlowe", "Lane Sorensen",
	"Micah Pemberton", "Toni Achebe", "Val Castillo", "Sage Whitlock", "Drew Halvorsen",
	"Bailey Rourke", "Cam Oyelaran", "Jo Sandoval", "Kit Brannigan", "Max Adeyemi",
	"Nico Faulkner", "Ollie Strand", "Perry Nakata", "Ray Dubois", "Terry Mwangi",
	"Vic Sorrento", "Wren Gallagher", "Alexis Byrne", "Jean Kovac", "Marlow Singh",
))
