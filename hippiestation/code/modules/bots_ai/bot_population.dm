// Crew population - tops the crew up with bots, so a round with a handful of players still has a
// station full of people.
//
// Set a crew size in hippiestation_config.txt (BOT_CREW_TARGET 20), or mid-round with the "Set Bot
// Crew Target" admin verb. Players count first; bots make up the difference. They join the way
// players do - most of them in the first few minutes, a few seconds apart on the arrivals shuttle,
// then the odd latecomer - into jobs picked the way a crew fills up: the posts a station can't run
// without first, then whatever is open, by how popular the job is.
//
// Headless test runs (Bot Gym, Bot Shift) muster their own crews and leave this off; a Bot Shift can
// borrow the job picker with a crew of "fill:25" (gym/bot_shift.dm).

/// The posts a station can't do without, in the order a short-handed crew covers them. Twice in the list is two of them.
GLOBAL_LIST_INIT(bot_crew_core_jobs, list(
	"Station Engineer", "Medical Doctor", "Security Officer", "Botanist", "Cook", "Cargo Technician",
	"Janitor", "Atmospheric Technician", "Chemist", "Scientist", "Bartender", "Station Engineer",
	"Security Officer", "Captain", "Medical Doctor", "Head of Personnel", "Chief Engineer", "Roboticist",
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

/// The opening rush ends once this share of the target is aboard; the rest drift in as latecomers.
#define BOT_CREW_RUSH_SHARE 0.7

GLOBAL_DATUM_INIT(bot_population, /datum/bot_population, new)

/datum/bot_population
	/// Crew size to keep the round at, players included. 0 is off.
	var/target = 0
	/// Bots brought in so far.
	var/joined = 0
	var/running = FALSE

/// Called once the round is under way (the ticker hook below).
/datum/bot_population/proc/round_started()
	if((BOT_GYM_PARAMETER in world.params) || (BOT_SHIFT_PARAMETER in world.params))
		return
	set_target(CONFIG_GET(number/bot_crew_target))

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

/datum/bot_population/proc/keep_crewed()
	running = TRUE
	sleep(rand(100, 300)) //the shuttle doesn't unload the instant the round starts
	while(target > 0 && SSticker.IsRoundInProgress())
		var/short = target - player_count() - joined
		// Nobody new signs on once the evacuation shuttle is on its way.
		if(short <= 0 || !EMERGENCY_IDLE_OR_RECALLED)
			sleep(30 SECONDS)
			continue
		var/title = pick_job()
		var/mob/living/carbon/human/H = title ? spawn_bot_crew_member(title) : null
		if(H)
			joined++
			log_game("BOT CREW: [H.real_name] joined as [title] ([joined] bot\s, target [target])")
		// A few seconds apart while the crew is still filling up, minutes apart for the last latecomers.
		sleep(short > target * (1 - BOT_CREW_RUSH_SHARE) ? rand(30, 90) : rand(600, 2400))
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
	var/new_target = input(usr, "Crew size to keep the round at, players included. 0 stops any more bots arriving; the ones aboard stay.", "Bot Crew Target", GLOB.bot_population.target) as null|num
	if(isnull(new_target))
		return
	GLOB.bot_population.set_target(new_target)
	message_admins("[key_name_admin(usr)] set the bot crew target to [GLOB.bot_population.target] ([GLOB.bot_population.joined] bot\s aboard so far).")
	log_admin("[key_name(usr)] set the bot crew target to [GLOB.bot_population.target].")

#undef BOT_CREW_RUSH_SHARE
