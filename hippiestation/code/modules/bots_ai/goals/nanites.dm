// Nanites: a two-person job, like it is for players. The chamber's console is on the outside and whoever is getting nanites is
// inside, so a scientist asks round the department for somebody to step in, works the console, and lets them out again.
//
//  - nanites in a host are what makes nanite research points at all (component/nanites add_research()), a little under two a
//    second for each host with nobody at the keyboard, so nothing in the nanite tree opens up until somebody has been injected.
//  - the host is put on cloud 1 on the way out (console "set_cloud"). Programs go on the cloud, and every host on it picks them
//    up by itself.
//  - a program gets to the cloud the way it does for a player: a blank disk out of the box, into the program hub for the
//    download, out and into the cloud controller for the upload (nanite_program_hub, nanite_cloud_controller).

/// Crew with nanites in them before the department stops asking for more volunteers.
#define BOT_NANITE_HOSTS 8
/// How long the operator waits for the volunteer to turn up and get in.
#define BOT_NANITE_VOLUNTEER_WAIT (45 SECONDS)
/// The one cloud backup the department runs.
#define BOT_NANITE_CLOUD 1

/// What goes on the cloud, in this order, when it's been researched: the two that pay for themselves in research points, then
/// what's good for the host. Nothing that does anything to anybody else, and nothing that needs setting up per person.
GLOBAL_LIST_INIT(bot_nanite_programs, list("research_nanites", "researchplus_nanites", "monitoring_nanites", "regenerative_nanites", "bloodheal_nanites", "purging_nanites", "brainheal_nanites"))

/datum/bot_brain
	var/nanites_injected = 0
	var/nanite_programs_uploaded = 0
	var/nanite_blocked_until = 0

/proc/bot_has_nanites(mob/living/L)
	return SEND_SIGNAL(L, COMSIG_HAS_NANITES)

/// How many of the crew have nanites in them.
/proc/bot_nanite_host_count()
	. = 0
	for(var/mob/living/carbon/human/H in GLOB.bot_crew_members)
		if(H.stat != DEAD && bot_has_nanites(H))
			.++

/// A chamber console with its chamber, free, powered and in this bot's reach.
/datum/bot_brain/proc/find_nanite_console()
	var/obj/machinery/computer/nanite_chamber_control/best
	var/best_dist
	for(var/obj/machinery/computer/nanite_chamber_control/C as anything in bot_instances_of(/obj/machinery/computer/nanite_chamber_control))
		if(QDELETED(C) || C.z != owner.z || (C.stat & (BROKEN|NOPOWER)) || !in_science(C) || taken_by_another(C))
			continue
		if(!C.chamber)
			C.find_chamber()
		var/obj/machinery/nanite_chamber/N = C.chamber
		if(!N || (N.stat & (BROKEN|NOPOWER)) || N.panel_open || N.occupant || N.busy || N.locked)
			continue
		var/dist = get_dist(owner, C)
		if(!best || dist < best_dist)
			best = C
			best_dist = dist
	return best

/// Somebody who could step in: at a loose end, up to it, with no nanites yet, and not the operator. The department before anybody
/// else, and those near at hand before those further off.
/datum/bot_brain/proc/find_nanite_volunteer(obj/machinery/nanite_chamber/N)
	var/mob/living/carbon/human/best
	var/best_score
	for(var/mob/living/carbon/human/H in GLOB.bot_crew_members)
		var/datum/bot_brain/other = H.bot_brain
		if(H == owner || !other || H.z != N.z || H.stat != CONSCIOUS || H.incapacitated() || bot_has_nanites(H))
			continue
		if(other.state != BOT_STATE_WANDER || other.current_goal || other.gym_scripted != gym_scripted || other.holding_duty)
			continue
		var/dist = get_dist(H, N)
		if(dist > 40)
			continue
		var/role = H.mind?.assigned_role
		var/score = dist - ((role in list("Scientist", "Research Director", "Roboticist")) ? 30 : 0)
		if(role == "Research Director")
			score -= 10 //the department's own head first
		if(!best || score < best_score)
			best = H
			best_score = score
	if(best && !best.bot_brain.can_walk_lawfully_to(N))
		return null
	return best

// ---------------------------------------------------------------------------------------------
// The round
// ---------------------------------------------------------------------------------------------

/datum/bot_duty/nanites
	name = "nanites"
	jobs = list("Scientist", "Research Director")
	interval_min = 300
	interval_max = 700

/datum/bot_duty/nanites/try_start(datum/bot_brain/bot)
	if(world.time < bot.nanite_blocked_until)
		return FALSE
	// With somebody to put them in, what the nanites run comes next.
	var/obj/machinery/computer/nanite_cloud_controller/cloud = bot.find_nanite_cloud()
	var/design_id = cloud && bot_nanite_hosts_exist() ? bot.next_nanite_program(cloud) : null
	if(design_id)
		return bot.assign_goal(new /datum/bot_goal/upload_nanite_program(cloud, design_id))
	if(bot_nanite_host_count() >= BOT_NANITE_HOSTS)
		return FALSE
	var/obj/machinery/computer/nanite_chamber_control/C = bot.find_nanite_console()
	if(!C)
		return FALSE
	var/mob/living/carbon/human/volunteer = bot.find_nanite_volunteer(C.chamber)
	if(!volunteer)
		return FALSE
	return bot.assign_goal(new /datum/bot_goal/run_nanite_chamber(C, volunteer))

/proc/bot_nanite_hosts_exist()
	return bot_nanite_host_count() > 0

/datum/bot_brain
	/// The first nanites have been tried for, and not again before this.
	var/first_nanites_next = 0

/// Nobody with nanites yet, and Basic Nanite Programming researched: a scientist sees to the first ones before the rest of the day's
/// work, as players do to get the nanite points coming. The nanite nodes past the first cost Nanite Research, which only hosts make,
/// so without them that half of the tree never opens. In the user's round (2026-11-10) the one scientist went through experiments,
/// slimes, printing and upgrades and the duty above never once got a look in: no nanites, and the user's R&D console said "not
/// enough research points". Somebody free to step in goes first, the RD before anybody; with nobody free, the scientist gets in
/// itself and asks Science on the radio (goals/powergame.dm get_nanites), as somebody on their own would.
/datum/bot_duty/nanites/first
	name = "the first nanites"
	priority = 30
	interval_min = 200
	interval_max = 400

/datum/bot_duty/nanites/first/try_start(datum/bot_brain/bot)
	if(world.time < bot.first_nanites_next || world.time < bot.nanite_blocked_until || bot_nanite_hosts_exist())
		return FALSE
	if(!SSresearch.science_tech.researched_nodes["nanite_base"])
		return FALSE
	var/obj/machinery/computer/nanite_chamber_control/C = bot.find_nanite_console()
	if(!C)
		return FALSE
	bot.first_nanites_next = world.time + 4 MINUTES //whichever way it goes, not straight back at it
	var/mob/living/carbon/human/volunteer = bot.find_nanite_volunteer(C.chamber)
	if(volunteer)
		return bot.assign_goal(new /datum/bot_goal/run_nanite_chamber(C, volunteer))
	if(bot_has_nanites(bot.owner) || !bot.can_walk_lawfully_to(C.chamber))
		return FALSE
	bot_log(bot, "nobody about to put nanites in: getting in the chamber myself")
	return bot.assign_goal(new /datum/bot_goal/get_nanites(C.chamber))

// ---------------------------------------------------------------------------------------------
// The chamber
// ---------------------------------------------------------------------------------------------

/datum/bot_goal/run_nanite_chamber
	lawful = TRUE
	exclusive = TRUE
	doing = "running the nanite chamber"
	var/mob/living/carbon/human/volunteer

/datum/bot_goal/run_nanite_chamber/New(obj/machinery/computer/nanite_chamber_control/C, mob/living/carbon/human/H)
	. = ..()
	target = C
	volunteer = H

/datum/bot_goal/run_nanite_chamber/resolve_target(datum/bot_brain/bot)
	if(QDELETED(target) || QDELETED(volunteer))
		target = null

/datum/bot_goal/run_nanite_chamber/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/nanites/S = new
	S.steps = list(new /datum/bot_step/move_to(), new /datum/bot_step/paced/operate_nanite_chamber())
	return list(S)

/datum/bot_goal/run_nanite_chamber/on_give_up(datum/bot_brain/bot)
	bot.nanite_blocked_until = world.time + 3 MINUTES

/datum/bot_strategy/nanites/is_feasible(datum/bot_brain/bot)
	return bot.current_goal?.target && !QDELETED(bot.current_goal.target)

/// The ask, the wait for them to get in, the injection, and letting them out.
/datum/bot_step/paced/operate_nanite_chamber
	max_clicks = 120
	var/asked = FALSE
	var/injecting = FALSE
	var/give_up_at = 0
	var/done = FALSE

/datum/bot_step/paced/operate_nanite_chamber/start(datum/bot_brain/bot)
	asked = FALSE
	injecting = FALSE
	done = FALSE
	give_up_at = world.time + BOT_NANITE_VOLUNTEER_WAIT
	return TRUE

/datum/bot_step/paced/operate_nanite_chamber/do_click(datum/bot_brain/bot)
	var/datum/bot_goal/run_nanite_chamber/G = bot.current_goal
	var/obj/machinery/computer/nanite_chamber_control/C = G?.target
	var/obj/machinery/nanite_chamber/N = C?.chamber
	var/mob/living/carbon/human/H = G?.volunteer
	if(!istype(G) || QDELETED(C) || QDELETED(N) || (C.stat & (BROKEN|NOPOWER)) || !bot.owner.Adjacent(C))
		return FALSE
	wait_for = 10
	if(!asked)
		asked = TRUE
		if(N.occupant == H) //in already, and asked for it (goals/powergame.dm get_nanites)
			return TRUE
		if(QDELETED(H) || !H.bot_brain || !H.bot_brain.assign_goal(new /datum/bot_goal/step_into_chamber(N, bot.owner)))
			return FALSE
		if(!bot.gym_scripted)
			bot.say_after_typing("[H.first_name()], [pick("got a minute? I need somebody in the nanite chamber.", "you're up for the nanite chamber.", "hop in the chamber, would you? It won't hurt.")]")
		return TRUE
	if(QDELETED(H) || H.stat == DEAD)
		return FALSE
	if(done)
		if(N.busy)
			return TRUE
		return finish_up(bot, C, N, H)
	if(N.occupant != H)
		return world.time < give_up_at
	if(!N.busy && !injecting)
		bot.human_pause(C)
		if(QDELETED(C) || N.occupant != H)
			return FALSE
		bot.owner.face_atom(C)
		bot.telemetry_ui_action(C, "nanite injection")
		N.inject_nanites()
		injecting = TRUE
		done = TRUE
		bot_log(bot, "injecting [H] with nanites")
		wait_for = 20
	return TRUE

/// They've got them: on the cloud, and out they come.
/datum/bot_step/paced/operate_nanite_chamber/proc/finish_up(datum/bot_brain/bot, obj/machinery/computer/nanite_chamber_control/C, obj/machinery/nanite_chamber/N, mob/living/carbon/human/H)
	if(N.occupant == H && bot_has_nanites(H))
		bot.human_pause(C)
		if(!QDELETED(N))
			N.set_cloud(BOT_NANITE_CLOUD)
			N.open_machine()
		bot.nanites_injected++
		bot_log(bot, "[H] has nanites now")
	return FALSE

/datum/bot_step/paced/operate_nanite_chamber/finish(datum/bot_brain/bot)
	var/datum/bot_goal/run_nanite_chamber/G = bot.current_goal
	var/obj/machinery/computer/nanite_chamber_control/C = G?.target
	var/obj/machinery/nanite_chamber/N = C?.chamber
	// However it went, nobody gets left shut in.
	if(!QDELETED(N) && N.occupant && !N.busy)
		N.open_machine()
	return bot_has_nanites(G?.volunteer) ? GOAL_STEP_SUCCESS : GOAL_STEP_FAIL

/// Asked to get in: over to the chamber, door open if it's shut, and in. The one running the console does the rest.
/datum/bot_goal/step_into_chamber
	lawful = TRUE
	doing = "getting nanites put in"
	var/mob/living/operator

/datum/bot_goal/step_into_chamber/New(obj/machinery/nanite_chamber/N, mob/living/operator)
	. = ..()
	target = N
	src.operator = operator

/datum/bot_goal/step_into_chamber/resolve_target(datum/bot_brain/bot)
	if(QDELETED(target))
		target = null

/datum/bot_goal/step_into_chamber/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/nanites/S = new
	S.steps = list(new /datum/bot_step/move_to(), new /datum/bot_step/paced/sit_in_chamber())
	return list(S)

/datum/bot_step/paced/sit_in_chamber
	max_clicks = 80
	var/got_in = FALSE

/datum/bot_step/paced/sit_in_chamber/start(datum/bot_brain/bot)
	got_in = FALSE
	return TRUE

/datum/bot_step/paced/sit_in_chamber/do_click(datum/bot_brain/bot)
	var/obj/machinery/nanite_chamber/N = bot.current_goal?.target
	if(!istype(N) || QDELETED(N))
		return FALSE
	wait_for = 10
	if(got_in)
		return bot.owner.loc == N
	if(!bot.owner.Adjacent(N))
		return FALSE
	bot.human_pause(N)
	if(QDELETED(N) || N.occupant)
		return FALSE
	if(!N.state_open)
		N.toggle_open(bot.owner)
		return TRUE
	N.MouseDrop_T(bot.owner, bot.owner)
	got_in = bot.owner.loc == N
	return got_in

/datum/bot_step/paced/sit_in_chamber/finish(datum/bot_brain/bot)
	var/obj/machinery/nanite_chamber/N = bot.current_goal?.target
	if(istype(N) && bot.owner.loc == N && !N.busy && !N.locked)
		N.open_machine() //nobody came: lets itself out
	return got_in ? GOAL_STEP_SUCCESS : GOAL_STEP_FAIL

// ---------------------------------------------------------------------------------------------
// Programs
// ---------------------------------------------------------------------------------------------

/datum/bot_brain/proc/find_nanite_cloud()
	for(var/obj/machinery/computer/nanite_cloud_controller/C as anything in bot_instances_of(/obj/machinery/computer/nanite_cloud_controller))
		if(!QDELETED(C) && C.z == owner.z && !(C.stat & (BROKEN|NOPOWER)) && in_science(C) && !taken_by_another(C))
			return C
	return null

/datum/bot_brain/proc/find_nanite_hub()
	for(var/obj/machinery/nanite_program_hub/H as anything in bot_instances_of(/obj/machinery/nanite_program_hub))
		if(!QDELETED(H) && H.z == owner.z && !(H.stat & (BROKEN|NOPOWER)) && in_science(H))
			return H
	return null

/// The next program on the list that's been researched and isn't on the cloud.
/datum/bot_brain/proc/next_nanite_program(obj/machinery/computer/nanite_cloud_controller/C)
	var/datum/nanite_cloud_backup/backup = SSnanites.get_cloud_backup(BOT_NANITE_CLOUD, TRUE)
	for(var/id in GLOB.bot_nanite_programs)
		var/datum/design/nanites/D = bot_researched_design(id)
		if(!istype(D))
			continue
		if(!backup)
			return id
		var/datum/component/nanites/cloud = backup.nanites
		var/found = FALSE
		for(var/datum/nanite_program/P in cloud.programs)
			if(P.type == D.program_type)
				found = TRUE
				break
		if(!found)
			return id
	return null

/// A disk for the hub: one the bot has, one out of the box in the lab, or one lying about.
/datum/bot_brain/proc/find_nanite_disk()
	var/obj/item/disk/nanite_program/disk = find_carried_tool(/obj/item/disk/nanite_program)
	if(disk)
		return disk
	for(var/obj/item/storage/box/disks_nanite/box as anything in bot_instances_of(/obj/item/storage/box/disks_nanite))
		if(!QDELETED(box) && box.z == owner.z && in_science(box) && (locate(/obj/item/disk/nanite_program) in box))
			return box
	return find_loose_item(/obj/item/disk/nanite_program, 30)

/datum/bot_goal/upload_nanite_program
	lawful = TRUE
	exclusive = TRUE
	doing = "programming nanites"
	var/design_id

/datum/bot_goal/upload_nanite_program/New(obj/machinery/computer/nanite_cloud_controller/C, design_id)
	. = ..()
	target = C
	src.design_id = design_id

/datum/bot_goal/upload_nanite_program/resolve_target(datum/bot_brain/bot)
	if(QDELETED(target) || !bot.find_nanite_hub())
		target = null

/datum/bot_goal/upload_nanite_program/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/nanites/S = new
	S.steps = list(new /datum/bot_step/nanite_program_run())
	return list(S)

/datum/bot_goal/upload_nanite_program/on_give_up(datum/bot_brain/bot)
	bot.nanite_blocked_until = world.time + 3 MINUTES

/datum/bot_goal/upload_nanite_program/on_success(datum/bot_brain/bot)
	var/datum/bot_duty/nanites/duty = bot_duty_of(/datum/bot_duty/nanites)
	bot.continue_goal_chain(CALLBACK(duty, TYPE_PROC_REF(/datum/bot_duty, try_start), bot))

/// One errand, a leg at a time, run again after each walk: the disk, the hub, the cloud controller.
/datum/bot_step/nanite_program_run
	var/legs = 0

/datum/bot_step/nanite_program_run/proc/walk_up(datum/bot_brain/bot, atom/A)
	return bot.suspend_goal_for(new /datum/bot_goal/walk_up_to(A)) ? GOAL_STEP_PENDING : GOAL_STEP_FAIL

/datum/bot_step/nanite_program_run/execute(datum/bot_brain/bot)
	var/datum/bot_goal/upload_nanite_program/G = bot.current_goal
	var/obj/machinery/computer/nanite_cloud_controller/cloud = G?.target
	if(!istype(G) || !istype(cloud) || QDELETED(cloud) || ++legs > 12)
		return GOAL_STEP_FAIL
	var/datum/design/nanites/D = SSresearch.techweb_design_by_id(G.design_id)
	var/obj/item/disk/nanite_program/disk = bot.find_carried_tool(/obj/item/disk/nanite_program)
	if(!disk)
		var/atom/source = bot.find_nanite_disk()
		if(!source)
			return GOAL_STEP_FAIL
		if(!bot.owner.Adjacent(source))
			return walk_up(bot, source)
		var/obj/item/disk/nanite_program/blank = istype(source, /obj/item/disk/nanite_program) ? source : locate(/obj/item/disk/nanite_program) in source
		if(!blank)
			return GOAL_STEP_FAIL
		bot.human_pause(source)
		if(!bot.owner.put_in_hands(blank))
			return GOAL_STEP_FAIL
		bot_log(bot, "took a blank program disk")
		disk = blank
	if(disk.program?.type != D.program_type)
		var/obj/machinery/nanite_program_hub/hub = bot.find_nanite_hub()
		if(!hub)
			return GOAL_STEP_FAIL
		if(!bot.owner.Adjacent(hub))
			return walk_up(bot, hub)
		bot.human_pause(hub)
		if(!bot.use_tool_on(disk, hub) || hub.disk != disk)
			return GOAL_STEP_FAIL
		bot.telemetry_ui_action(hub, "download [D.name]")
		QDEL_NULL(disk.program)
		disk.program = new D.program_type
		disk.name = "[initial(disk.name)] \[[disk.program.name]\]"
		hub.disk = null
		bot.owner.put_in_hands(disk)
		return walk_up(bot, cloud)
	if(!bot.owner.Adjacent(cloud))
		return walk_up(bot, cloud)
	bot.human_pause(cloud)
	if(!bot.use_tool_on(disk, cloud) || cloud.disk != disk)
		return GOAL_STEP_FAIL
	var/datum/nanite_cloud_backup/backup = SSnanites.get_cloud_backup(BOT_NANITE_CLOUD, TRUE)
	if(!backup)
		bot.telemetry_ui_action(cloud, "create cloud backup")
		cloud.generate_backup(BOT_NANITE_CLOUD, bot.owner)
		backup = SSnanites.get_cloud_backup(BOT_NANITE_CLOUD, TRUE)
	if(!backup)
		return GOAL_STEP_FAIL
	bot.telemetry_ui_action(cloud, "upload [D.name]")
	var/datum/component/nanites/nanites = backup.nanites
	nanites.add_program(null, disk.program.copy())
	cloud.disk = null
	bot.owner.put_in_hands(disk)
	bot.nanite_programs_uploaded++
	bot_log(bot, "uploaded [D.name] to the nanite cloud")
	if(!bot.gym_scripted && prob(50))
		bot.say_after_typing(":n [D.name] is on the nanite cloud.")
	return GOAL_STEP_SUCCESS

#undef BOT_NANITE_HOSTS
#undef BOT_NANITE_VOLUNTEER_WAIT
#undef BOT_NANITE_CLOUD
