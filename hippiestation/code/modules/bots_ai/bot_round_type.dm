// The round type's antagonists, bots among them. SSticker.setup() rolls the mode and picks its antagonists before anybody is aboard, from
// the humans who readied up. So a bot crew never had a cult or a nuke round (they want 24 and 30 players), the antagonists the bots did
// get were a fixed few from the config whatever the round type, and a lone human who'd ticked the box was the traitor every round. Now,
// while a round with a bot crew is being set up:
//  - The roll counts the crew the round will have (the bot crew target), not only the humans in the lobby (num_players(), can_start()).
//  - Every antagonist pick has a stand-in for each bot still to come (get_players_for_role()), so a human's odds are any crewmember's, and
//    nobody who left the box unticked is drafted while there are bots to take it. Blood brothers stay human: bots can't play them.
//  - Once the crew is aboard, and before the mode hands out its roles, every stand-in it picked becomes a bot (bot_take_stand_in_roles(),
//    from the ticker's PostSetup()): one of the crew for a role aboard (traitor, changeling, cultist, head revolutionary), a body of its
//    own for one that starts off the station (operative, wizard). The mode then sets them up the way it does players, teams, objectives
//    and gear included, and each bot's brain takes the role on from there (the on_gain() hooks in goals/).

/// A mind for a bot that isn't aboard yet, in the mode's antagonist picks.
/datum/mind/bot_stand_in

/datum/game_mode
	/// One for each bot still to come, while the round's being set up.
	var/list/bot_stand_ins
	/// How many of the round's antagonists are bots, for the log.
	var/bots_picked = 0

/// Humans in the lobby, readied up.
/proc/bot_ready_humans()
	. = 0
	for(var/mob/dead/new_player/P in GLOB.player_list)
		if(P.client && P.ready == PLAYER_READY_TO_PLAY)
			.++

/// How many bots the round is going to have on top of `humans`, while it's being set up. 0 at any other time, or with no bot crew.
/proc/bot_crew_to_come(humans)
	if(SSticker.current_state > GAME_STATE_SETTING_UP || (BOT_GYM_PARAMETER in world.params) || (BOT_SHIFT_PARAMETER in world.params))
		return 0
	var/target = GLOB.bot_population.target || CONFIG_GET(number/bot_crew_target) //an admin may have set one in the lobby
	return max(0, target - humans)

/datum/game_mode/num_players()
	. = ..()
	. += bot_crew_to_come(.)

/datum/game_mode/can_start()
	var/bots = bot_crew_to_come(bot_ready_humans())
	if(!bots)
		return ..()
	var/fewest = required_players
	var/most = maximum_players
	required_players = max(0, required_players - bots)
	if(maximum_players >= 0)
		maximum_players += bots
	. = ..()
	required_players = fewest
	maximum_players = most

/datum/game_mode/get_players_for_role(role)
	var/bots = role == ROLE_BROTHER ? 0 : bot_crew_to_come(bot_ready_humans())
	if(!bots)
		return ..()
	if(length(bot_stand_ins) != bots)
		bot_stand_ins = list()
		for(var/i in 1 to bots)
			var/datum/mind/bot_stand_in/S = new
			S.name = "bot stand-in [i]"
			bot_stand_ins += S
	var/wanted = recommended_enemies
	recommended_enemies = max(0, recommended_enemies - bots) //the bots are all willing: nobody's drafted while they'll do
	. = ..()
	recommended_enemies = wanted
	. += bot_stand_ins

/// The wizard is moved to the den in pre_setup(), which a stand-in has no body for: that comes with the rest of the crew.
/datum/game_mode/wizard/pre_setup()
	var/datum/mind/wizard = length(bot_stand_ins) ? antag_pick(antag_candidates) : null
	if(!istype(wizard, /datum/mind/bot_stand_in))
		if(wizard)
			antag_candidates = list(wizard) //the parent picks again: the same one
		return ..()
	wizards += wizard
	wizard.assigned_role = ROLE_WIZARD
	wizard.special_role = ROLE_WIZARD
	log_game("[key_name(wizard)] has been selected as a Wizard")
	if(!length(GLOB.wizardstart))
		setup_error = "No wizard starting location found"
		return FALSE
	return TRUE

/// A mode that wants a head of staff aboard (the revolution) would otherwise go back to the lobby without a human in the job: the heads'
/// posts are among the first the bot crew fill (bot_population.dm).
/datum/controller/subsystem/job/DivideOccupations(list/required_jobs)
	if(length(required_jobs) && length(SSticker.mode?.bot_stand_ins))
		required_jobs = list()
	return ..(required_jobs)

// Until the crew is aboard, the mode's roles aren't handed out, and these ask after what that makes.
/datum/game_mode/nuclear/check_finished()
	if(!nuke_team)
		return FALSE
	return ..()

/datum/game_mode/nuclear/check_win()
	if(!nuke_team)
		return FALSE
	return ..()

/datum/game_mode/revolution/check_win()
	if(!revolution)
		return
	return ..()

/// A mode that isn't continuous (nuke, revolution) ends the round once its antagonists are all dead, and it looks for them among the
/// mobs with a client. A bot has none, so a nuke round with bot operatives ended half a second after it started. The one it keeps an eye
/// on (living_antag_player) is checked without asking for a client, so a bot that's still at it goes there.
/datum/game_mode/check_finished(force_ending)
	if(!living_antag_player || QDELETED(living_antag_player) || living_antag_player.stat == DEAD)
		living_antag_player = bot_living_antagonist() // not the old one back: dead or deleted, it can't keep the round going, and a deleted one was a hard delete
	return ..()

/// A bot still alive with an antagonist role that keeps the round going (prevent_roundtype_conversion, as check_finished() asks).
/proc/bot_living_antagonist()
	for(var/datum/bot_brain/B as anything in GLOB.bot_brains)
		var/mob/living/carbon/human/H = B.owner
		if(QDELETED(H) || H.stat == DEAD || !H.mind)
			continue
		for(var/datum/antagonist/A as anything in H.mind.antag_datums)
			if(A.prevent_roundtype_conversion)
				return H
	return null

/// Stand-ins the round type picked for a role off the station (an operative, the wizard): bots that won't be among the crew at their posts.
/proc/bot_offstation_stand_ins(datum/game_mode/mode)
	. = 0
	for(var/datum/mind/bot_stand_in/S as anything in mode?.bot_stand_ins)
		if(S.assigned_role) //only the off-station roles set one in pre_setup(): the crew's come with their jobs
			.++

/// Every stand-in the mode picked becomes a bot, in each of the mode's lists it's in, before the mode hands out the roles. The crew are
/// aboard by now (ticker.dm PostSetup()).
/proc/bot_take_stand_in_roles(datum/game_mode/mode)
	if(!length(mode?.bot_stand_ins))
		return
	var/list/stand_ins = mode.bot_stand_ins
	mode.bot_stand_ins = null
	mode.antag_candidates -= stand_ins //the ones nobody picked: the revolution looks here for a head to stand by
	var/list/lists = list()
	var/list/picked = list()
	for(var/V in mode.vars)
		var/list/L = mode.vars[V]
		if(V == "vars" || !islist(L))
			continue
		var/found = FALSE
		for(var/datum/mind/bot_stand_in/S in L)
			found = TRUE
			// Given a role, not merely in a pool: traitorchan keeps every changeling candidate in possible_changelings, and 31 were
			// "picked" for 6 roles. The revolution marks its head revolutionaries only with the mode's restricted jobs.
			if(S.special_role || S.assigned_role || (S.restricted_roles && S.restricted_roles == mode.restricted_jobs))
				picked |= S
		if(found)
			lists += list(L)
	var/list/taken = list()
	for(var/datum/mind/bot_stand_in/S as anything in picked)
		var/datum/mind/bot = S.assigned_role ? bot_offstation_mind(S.assigned_role) : bot_crew_mind_for(S, taken)
		for(var/list/L as anything in lists)
			var/i = L.Find(S)
			while(i)
				if(bot)
					L[i] = bot
				else
					L.Cut(i, i + 1)
				i = L.Find(S)
		if(!bot)
			log_game("BOT ROLES: nobody to be the [S.special_role || "pick"] [S.name] stood in for")
			continue
		taken += bot
		bot.special_role = S.special_role
		bot.restricted_roles = S.restricted_roles
		mode.bots_picked++
		log_game("BOT ROLES: [key_name(bot)] ([bot.assigned_role]) is the [S.special_role || "pick"] [S.name] stood in for")
	for(var/list/L as anything in lists) //the ones nobody picked, out of the pools they were in
		for(var/datum/mind/bot_stand_in/S as anything in stand_ins)
			while(S in L)
				L -= S
	log_game("BOT ROLES: [mode.name], [mode.bots_picked] of its antagonists bots, [length(stand_ins)] bots stood in")

/// One of the crew aboard for a role the mode handed out, by the mode's own rules for who can't (its restricted jobs), and nobody
/// Security or Command would look at closely (bot_traitor_job_allowed()).
/proc/bot_crew_mind_for(datum/mind/bot_stand_in/S, list/taken)
	var/list/choices = list()
	for(var/datum/bot_brain/B as anything in GLOB.bot_brains)
		var/mob/living/carbon/human/H = B.owner
		if(QDELETED(H) || H.stat == DEAD || !H.mind || (H.mind in taken) || length(H.mind.antag_datums) || !is_station_level(H.z))
			continue
		if((H.mind.assigned_role in S.restricted_roles) || !bot_traitor_job_allowed(H.mind.assigned_role) || HAS_TRAIT(H, TRAIT_MINDSHIELD))
			continue
		choices += H.mind
	return length(choices) ? pick(choices) : null

/// A bot of its own for a role that starts off the station. It comes in the way the crew do (bot_identity.dm), so it passes for a player
/// to its team, and the antagonist datum puts it where it starts.
/proc/bot_offstation_mind(role)
	var/mob/dead/new_player/NP = new()
	var/datum/bot_identity/identity = new(NP)
	NP.bot_identity = identity
	NP.real_name = identity.persona_name
	NP.mind_initialize()
	NP.mind.assigned_role = role
	var/mob/living/carbon/human/H = identity.create_bot_character(FALSE)
	qdel(NP)
	if(!H?.mind)
		return null
	var/turf/T
	if(role == ROLE_WIZARD && length(GLOB.wizardstart))
		T = get_turf(pick(GLOB.wizardstart))
	else if(length(GLOB.nukeop_start))
		T = get_turf(GLOB.nukeop_start[1])
	if(T)
		H.forceMove(T)
	new /datum/bot_brain(H)
	GLOB.bot_population.joined++
	GLOB.joined_player_list += H.ckey
	SSticker.minds |= H.mind
	return H.mind

/// Whether anybody aboard is an antagonist. The bot crew's fixed few (BOT_CREW_TRAITORS and the rest) only come in when the round
/// type gave out nobody.
/proc/bot_round_has_antagonists()
	for(var/datum/mind/M as anything in SSticker.minds)
		if(length(M.antag_datums))
			return TRUE
	return FALSE

// ---------------------------------------------------------------------------------------------
// Latecomers
// ---------------------------------------------------------------------------------------------

// A player who joins late gets the round type's chance at a role (make_antag_chance(), from AttemptLateSpawn() in new_player.dm).
// Every mode's version asks the client on the way for its preferences, its bans and the age of its account, and a bot has no client,
// so new_player.dm leaves bots out. A round's traitors were only ever the ones it started with: with a bot crew nobody off the
// arrivals shuttle was worth a second look. A bot joining late now gets the same chance by the same sums, the crew counted as the
// round has it, bots and players.

/// How many have joined the round, bots among them: what a mode's cap on its latecomers goes by. The game's own count
/// (GLOB.joined_player_list) is of ckeys, and a bot has none.
/proc/bot_crew_joined()
	return GLOB.bot_population.player_count() + GLOB.bot_population.joined

/// A bot off the arrivals shuttle gets the round type's chance at a role (bot_population.dm, for each latecomer). TRUE if it took one.
/proc/bot_latecomer_role_chance(mob/living/carbon/human/H)
	if(!CONFIG_GET(flag/allow_latejoin_antagonists) || !SSticker.mode || !H?.mind || !H.bot_brain || length(H.mind.antag_datums))
		return FALSE
	if(!EMERGENCY_IDLE_OR_RECALLED) //as for a player: nobody's sent to a station that's being left
		return FALSE
	var/role = SSticker.mode.bot_latecomer_role(H, bot_crew_joined())
	if(!role)
		return FALSE
	SSticker.mode.bots_picked++
	log_game("BOT ROLES: [H.real_name], the [H.mind.assigned_role], joined late and is a [role]")
	return TRUE

/// The role a bot joining late is given, if any: the mode's make_antag_chance() over again, less what that asks of a client.
/// `crew` is how many have joined the round.
/datum/game_mode/proc/bot_latecomer_role(mob/living/carbon/human/H, crew)
	if(replacementmode && round_converted == 2)
		return replacementmode.bot_latecomer_role(H, crew)
	return null

/datum/game_mode/traitor/bot_latecomer_role(mob/living/carbon/human/H, crew)
	var/tsc = CONFIG_GET(number/traitor_scaling_coeff)
	var/cap = min(round(crew / (tsc * 2)) + 2 + num_modifier, round(crew / tsc) + num_modifier)
	var/have = length(traitors) + length(pre_traitors)
	if(have >= cap)
		return null
	if(have > cap - 2 && !prob(100 / (tsc * 2)))
		return null
	if((H.mind.assigned_role in restricted_jobs) || !bot_traitor_job_allowed(H.mind.assigned_role)) //goals/traitor.dm
		return null
	add_latejoin_traitor(H.mind)
	return "traitor"

/datum/game_mode/changeling/bot_latecomer_role(mob/living/carbon/human/H, crew)
	var/csc = CONFIG_GET(number/changeling_scaling_coeff)
	var/cap = min(round(crew / (csc * 2)) + 2, round(crew / csc))
	if(length(changelings) >= cap)
		return null
	if(length(changelings) > cap - 2 && !prob(100 - (csc * 2)))
		return null
	if((H.mind.assigned_role in restricted_jobs) || !bot_traitor_job_allowed(H.mind.assigned_role))
		return null
	H.bot_brain.become_changeling() //goals/changeling.dm
	changelings |= H.mind
	return "changeling"

/// Traitors and changelings: the changeling's chance first, then the traitor's. A player can come out of the game's version as both;
/// a bot plays one role.
/datum/game_mode/traitor/changeling/bot_latecomer_role(mob/living/carbon/human/H, crew)
	var/csc = CONFIG_GET(number/changeling_scaling_coeff)
	var/cap = min(round(crew / (csc * 4)) + 2, round(crew / (csc * 2)))
	if(length(changelings) < cap && (length(changelings) <= cap - 2 || prob(100 / (csc * 4))))
		if(!(H.mind.assigned_role in restricted_jobs) && bot_traitor_job_allowed(H.mind.assigned_role))
			H.bot_brain.become_changeling()
			changelings |= H.mind
			return "changeling"
	return ..()

/// A live test round (tools/bot_gym/run_live_round.sh) gives its round type on the command line: "secret" rolls as a server does.
/datum/controller/subsystem/ticker/load_mode()
	..()
	var/forced = world.params["bot-mode"]
	if(forced)
		GLOB.master_mode = forced
		log_game("BOT ROLES: mode '[forced]' from the command line")

/// And how long it goes on, in minutes, if it doesn't end before then.
/datum/bot_population/round_started()
	. = ..()
	var/limit = text2num(world.params["bot-round-limit"])
	if(limit)
		addtimer(CALLBACK(GLOBAL_PROC, GLOBAL_PROC_REF(bot_end_test_round)), limit MINUTES)
	if(world.params["bot-mode"])
		INVOKE_ASYNC(GLOBAL_PROC, GLOBAL_PROC_REF(bot_log_test_round_load))
	if(world.params["rogue-captain-drill"]) //gym/bot_shift.dm
		addtimer(CALLBACK(GLOBAL_PROC, GLOBAL_PROC_REF(bot_rogue_captain_drill)), 5 MINUTES)

/// What the round costs the server, a line a minute, for live_round_report.py: world.cpu is the share of a tick used, averaged over
/// the last few, and the worst second of the minute is kept too.
/proc/bot_log_test_round_load()
	UNTIL(SSticker.IsRoundInProgress()) //it's called as the round starts, a moment before the ticker says so
	while(SSticker.IsRoundInProgress())
		var/worst = 0
		var/total = 0
		for(var/i in 1 to 60)
			sleep(1 SECONDS)
			worst = max(worst, world.cpu)
			total += world.cpu
		var/alive = 0
		for(var/datum/bot_brain/B as anything in GLOB.bot_brains)
			if(!QDELETED(B.owner) && B.owner.stat != DEAD)
				alive++
		log_game("LIVE LOAD: average [round(total / 60, 0.1)]%, worst [round(worst, 0.1)]%, [alive] bots alive, [length(GLOB.mob_living_list)] living mobs")

/proc/bot_end_test_round()
	if(!SSticker.IsRoundInProgress())
		return
	log_game("BOT ROLES: the test round's time is up")
	SSticker.force_ending = TRUE

/// With nobody connected, nobody's shown the round-end report: a test round keeps it with its logs, for who the antagonists were and how
/// they did.
/datum/controller/subsystem/ticker/display_report(popcount)
	..()
	if(world.params["bot-mode"])
		text2file("[GLOB.common_report][GLOB.survivor_report]", "[GLOB.log_directory]/round_end_report.html")

/// What the game puts on a bot along with a role (an uplink, a flash, the robes) is no more its doing than its uniform: the telemetry
/// leaves it alone.
/datum/mind/add_antag_datum(datum_type_or_instance, team)
	var/mob/living/carbon/human/H = current
	if(!istype(H) || !H.bot_brain || H.bot_brain.being_issued_kit)
		return ..()
	H.bot_brain.being_issued_kit = TRUE
	. = ..()
	if(H.bot_brain)
		H.bot_brain.being_issued_kit = FALSE
