// Crew population - tops the crew up with bots, so a round with a handful of players still has a
// station full of people.
//
// Set a crew size in hippiestation_config.txt (BOT_CREW_TARGET 20), or mid-round with the "Set Bot
// Crew Target" admin verb. Players count first; bots make up the difference. They start the way
// players who readied up do, at their posts the moment the round starts. After that a few latecomers
// (BOT_CREW_LATE_MIN to BOT_CREW_LATE_MAX) come in on the arrivals shuttle, minutes apart. Jobs are
// picked the way a crew fills up: the posts a station can't run without first, then whatever is
// open, by how popular the job is.
//
// Headless test runs (Bot Gym, Bot Shift) muster their own crews and leave this off; a Bot Shift can
// borrow the job picker with a crew of "fill:25" (gym/bot_shift.dm).

/// The posts a station can't do without, in the order a short-handed crew covers them. Twice in the list is two of them.
GLOBAL_LIST_INIT(bot_crew_core_jobs, list(
	"Station Engineer", "Medical Doctor", "Security Officer", "Assistant", "Botanist", "Cook", "Cargo Technician",
	"Janitor", "Head of Security", "Atmospheric Technician", "Chemist", "Scientist", "Bartender", "Assistant", "Security Officer",
	"Station Engineer", "Captain", "Warden", "Medical Doctor", "Security Officer", "Assistant", "Head of Personnel", "Clown", "Chief Engineer", "Roboticist",
))

/// How popular each job is with players, as relative odds, once the core posts are covered.
GLOBAL_LIST_INIT(bot_crew_job_weights, list(
	"Assistant" = 14,
	"Station Engineer" = 6, "Atmospheric Technician" = 3, "Chief Engineer" = 2,
	"Medical Doctor" = 6, "Chemist" = 3, "Geneticist" = 2, "Virologist" = 1, "Chief Medical Officer" = 2,
	"Security Officer" = 7, "Warden" = 2, "Detective" = 2, "Head of Security" = 2,
	"Scientist" = 6, "Roboticist" = 3, "Research Director" = 2,
	"Cargo Technician" = 4, "Shaft Miner" = 4, "Quartermaster" = 2,
	"Botanist" = 3, "Cook" = 3, "Bartender" = 2, "Janitor" = 3,
	"Clown" = 3, "Mime" = 1, "Chaplain" = 2, "Curator" = 1, "Lawyer" = 1,
	"Captain" = 2, "Head of Personnel" = 2,
))

/// How long after the round starts a target can still be met by standing people at their posts. Any later and they arrive on the shuttle.
#define BOT_CREW_AT_POSTS_UNTIL (1 MINUTES)
/// How far apart latecomers arrive, the first one included.
#define BOT_CREW_LATE_GAP_MIN (2 MINUTES)
#define BOT_CREW_LATE_GAP_MAX (6 MINUTES)
/// How long into the round the traitors are picked.
#define BOT_CREW_TRAITORS_AFTER (10 MINUTES)
/// How long a third of the crew can lie dead with no shuttle called before Central Command sends it.
#define BOT_CREW_CENTCOM_CALL_AFTER (10 MINUTES)

GLOBAL_DATUM_INIT(bot_population, /datum/bot_population, new)

/datum/bot_population
	/// Crew size to keep the round at, players included. 0 is off.
	var/target = 0
	/// Bots brought in so far.
	var/joined = 0
	/// Latecomers still to arrive this round.
	var/latecomers = 0
	var/latecomers_picked = FALSE
	/// TRUE while the crew who start the round are still going to their posts, which go once the round has started
	var/mustering = FALSE
	var/running = FALSE
	var/traitors_made = FALSE
	/// Since when a third of the crew have been dead with the shuttle not called.
	var/decimated_since = 0

/// Called once the round is under way (the ticker hook below).
/datum/bot_population/proc/round_started()
	if((BOT_GYM_PARAMETER in world.params) || (BOT_SHIFT_PARAMETER in world.params))
		return
	mustering = TRUE //before anything can sleep: the ticker's next step is to clear away the posts
	if(!target) //an admin may have set one in the lobby
		set_target(CONFIG_GET(number/bot_crew_target))
	if(!target)
		mustering = FALSE

/datum/bot_population/proc/set_target(new_target)
	target = max(0, round(new_target))
	if(target && !running)
		INVOKE_ASYNC(src, PROC_REF(keep_crewed))

/// Players in the round and alive.
/datum/bot_population/proc/player_count()
	. = 0
	for(var/mob/living/L in GLOB.player_list)
		if(L.stat != DEAD && L.mind?.assigned_role)
			.++

/datum/bot_population/proc/job_open(title)
	var/datum/job/J = SSjob.GetJob(title)
	return J && (J.total_positions == -1 || J.current_positions < J.total_positions)

/// The job the next arrival takes, or null if there's nothing open.
/datum/bot_population/proc/pick_job()
	var/list/wanted = list()
	for(var/title in GLOB.bot_crew_core_jobs)
		wanted[title]++
		var/datum/job/J = SSjob.GetJob(title)
		if(J && J.current_positions < wanted[title] && job_open(title))
			return title
	var/list/open = list()
	for(var/title in GLOB.bot_crew_job_weights)
		if(job_open(title))
			open[title] = GLOB.bot_crew_job_weights[title]
	return length(open) ? pickweight(open) : null

/// One more of the crew, into the next job going. Returns them, or null if there's nothing open.
/datum/bot_population/proc/bring_in(at_post = FALSE)
	var/title = pick_job()
	var/mob/living/carbon/human/H = title ? spawn_bot_crew_member(title, at_post) : null
	if(H)
		joined++
		log_game("BOT CREW: [H.real_name] [at_post ? "started" : "joined"] as [title] ([joined] bot\s, target [target])")
	return H

/// Everyone on shift when the round starts: at their posts, as though they'd readied up with everybody else.
/datum/bot_population/proc/muster()
	var/short = target - player_count() - bot_offstation_stand_ins(SSticker.mode) //bot_round_type.dm: an operative or the wizard is one of the number
	for(var/i in 1 to short)
		if(!bring_in(TRUE))
			break
		CHECK_TICK

/datum/bot_population/proc/keep_crewed()
	running = TRUE
	UNTIL(!target || SSticker.IsRoundInProgress())
	if(world.time < SSticker.round_start_time + BOT_CREW_AT_POSTS_UNTIL)
		muster()
		bot_spawn_silicons(CONFIG_GET(number/bot_crew_silicons)) //goals/silicon.dm
	mustering = FALSE
	if(!latecomers_picked)
		latecomers_picked = TRUE
		var/late_min = CONFIG_GET(number/bot_crew_late_min)
		latecomers = rand(late_min, max(late_min, CONFIG_GET(number/bot_crew_late_max)))
	var/next_latecomer = world.time + rand(BOT_CREW_LATE_GAP_MIN, BOT_CREW_LATE_GAP_MAX)
	while(target > 0 && SSticker.IsRoundInProgress())
		if(!traitors_made && world.time > SSticker.round_start_time + BOT_CREW_TRAITORS_AFTER)
			traitors_made = TRUE
			if(!bot_round_has_antagonists()) //bot_round_type.dm: the round type's are bots too, and these are for a round it gave none
				var/traitors = CONFIG_GET(number/bot_crew_traitors)
				if(traitors)
					bot_make_traitors(traitors) //goals/traitor.dm
				var/changelings = CONFIG_GET(number/bot_crew_changelings)
				if(changelings)
					bot_make_changelings(changelings) //goals/changeling.dm
				var/revolutionaries = CONFIG_GET(number/bot_crew_revolutionaries)
				if(revolutionaries)
					bot_start_revolution(revolutionaries) //goals/revolution.dm
		// A third of the crew dead and nobody's called the shuttle: the heads are among them, and nobody left can or will. Central Command
		// sends it, as it does for a comms console that's down (goals/call_shuttle.dm); the game's own casualty call only counts players.
		// Three traitors loud from the start killed 18 of 20 in a live round, and it would have gone on for ever.
		if(EMERGENCY_IDLE_OR_RECALLED && bot_crew_decimated())
			if(!decimated_since)
				decimated_since = world.time
			else if(world.time > decimated_since + BOT_CREW_CENTCOM_CALL_AFTER)
				decimated_since = 0
				log_game("BOT CREW: Central Command sends the shuttle: a third of the crew dead and nobody called it")
				SSshuttle.emergency.request(null, set_coefficient = 1, reason = "Heavy casualties reported aboard. Evacuation shuttle dispatched by Central Command.")
		else
			decimated_since = 0
		// Nobody new signs on once the evacuation shuttle is on its way.
		if(EMERGENCY_IDLE_OR_RECALLED)
			if(target - player_count() - joined > 0) //an admin raised the target
				bring_in()
				sleep(rand(30, 90))
				continue
			if(latecomers > 0 && world.time >= next_latecomer)
				latecomers--
				next_latecomer = world.time + rand(BOT_CREW_LATE_GAP_MIN, BOT_CREW_LATE_GAP_MAX)
				bring_in()
		sleep(30 SECONDS)
	running = FALSE

/datum/controller/subsystem/ticker/Initialize(timeofday)
	. = ..()
	OnRoundstart(CALLBACK(GLOB.bot_population, TYPE_PROC_REF(/datum/bot_population, round_started)))

/client/proc/admin_set_bot_crew_target()
	set name = "Set Bot Crew Target"
	set category = "Fun"
	set desc = "Tops the crew up to this many with bot crew members, players counted first. 0 stops any more arriving."

	if(!check_rights(R_FUN))
		return
	var/new_target = tgui_input_number(usr, "Crew size to keep the round at, players included. 0 stops any more bots arriving; the ones aboard stay.", "Bot Crew Target", GLOB.bot_population.target)
	if(isnull(new_target))
		return
	GLOB.bot_population.set_target(new_target)
	message_admins("[key_name_admin(usr)] set the bot crew target to [GLOB.bot_population.target] ([GLOB.bot_population.joined] bot\s aboard so far).")
	log_admin("[key_name(usr)] set the bot crew target to [GLOB.bot_population.target].")

#undef BOT_CREW_AT_POSTS_UNTIL
#undef BOT_CREW_LATE_GAP_MIN
#undef BOT_CREW_LATE_GAP_MAX
#undef BOT_CREW_TRAITORS_AFTER
#undef BOT_CREW_CENTCOM_CALL_AFTER
