// Nuclear operatives, from the crew's side (their own is goals/nuke_ops.dm). The user's ruling (2026-11-12): the crew defend the disk
// and the nuke, the Captain guards the disk, Security and crew fight back. In the nuke round of 2026-11-10 (n0_nuclear) the crew fought
// operatives on sight once that was ruled (bot_in_syndicate_suit(), security_tactics.dm) but did nothing else about them: no red alert,
// no armory, the disk stayed in the Captain's pocket wherever the Captain wandered, and once the Captain was down it lay on the body
// until an operative came for it. 27 dead in 13 minutes.
//
//  - Operatives seen, by a bot or on the AI's cameras: the crew goes for them as for a nanosuit (fight_the_suit.dm), and it's called out.
//  - Red alert and the armory, as for a nanosuit (red_alert.dm, security_tactics.dm); a couple of minutes on, a head calls the shuttle.
//  - Whoever has the disk holes up in the Brig, among Security, and says so on Command.
//  - Officers keep close to whoever has the disk, and fight what comes.
//  - The disk on somebody dead, or lying about: the nearest of Security, then the heads, then anybody with the nerve, goes and takes it.

/// How near the disk officers keep
#define BOT_DISK_GUARD_RANGE 4
/// How far somebody goes to take the disk off a body
#define BOT_DISK_RECOVER_RANGE 60

/// When operatives were first seen this round (0: they haven't been)
GLOBAL_VAR_INIT(bot_ops_seen_at, 0)
/// Who's going for the disk off a body, and until when that holds
GLOBAL_DATUM(bot_disk_recoverer, /datum/bot_brain)
GLOBAL_VAR_INIT(bot_disk_recoverer_until, 0)

GLOBAL_LIST_INIT(bot_shuttle_ops_reasons, list(
	"Nuclear operatives aboard the station. Evacuating.",
	"Syndicate operatives on the station and the disk is at risk. Calling the shuttle.",
	"Hostile boarding party, heavily armed. All crew to evacuate.",
))

/// Operatives have been seen.
/proc/bot_note_operative(mob/living/carbon/human/H)
	if(!GLOB.bot_ops_seen_at)
		GLOB.bot_ops_seen_at = world.time
		log_game("BOT CREW: operatives seen ([H] in [get_area_name(H, TRUE)])")

/// Operatives about, seen and up: on the station, or in the Bot Gym the asking bot's own arena.
/proc/bot_operatives_loose(datum/bot_brain/asking)
	if(!GLOB.bot_ops_seen_at)
		return FALSE
	var/static/last_check = -1
	var/static/last_answer = FALSE
	if(!asking?.gym_run && last_check == world.time)
		return last_answer
	. = FALSE
	for(var/mob/living/carbon/human/H in GLOB.carbon_list)
		if(H.stat == DEAD || H.handcuffed || !bot_in_syndicate_suit(H))
			continue
		if(asking?.gym_run ? get_area(H) == get_area(asking.owner) : is_station_level(H.z))
			. = TRUE
			break
	if(!asking?.gym_run)
		last_check = world.time
		last_answer = .

/// Whoever has the disk on them, alive: or null.
/proc/bot_nuke_disk_holder(datum/bot_brain/asking)
	var/obj/item/disk/nuclear/D = bot_find_nuke_disk(asking) //goals/nuke_ops.dm
	for(var/atom/A = D?.loc; A && !isturf(A); A = A.loc)
		if(ishuman(A))
			var/mob/living/carbon/human/H = A
			return H.stat == DEAD ? null : H
	return null

/// Somewhere safe to hole up with the disk: the Brig.
/datum/bot_brain/proc/brig_spot()
	if(gym_run)
		return gym_run.named_spot("brig")
	var/area/A = bot_area_named("brig", get_turf(owner)) //bot_requests.dm
	return A ? nearest_spot_in(A) : null

// ---------------------------------------------------------------------------------------------
// Whoever has the disk
// ---------------------------------------------------------------------------------------------

/datum/bot_duty/hole_up_with_disk
	name = "keeping the disk safe"
	tier = BOT_DUTY_URGENT
	priority = 20
	interval_min = 30
	interval_max = 60

/datum/bot_duty/hole_up_with_disk/try_start(datum/bot_brain/bot)
	if(bot.op_team || bot.bot_traitor || bot.gone_loud() || !bot.find_carried_tool(/obj/item/disk/nuclear) || !bot_operatives_loose(bot))
		return FALSE
	var/turf/safe = bot.brig_spot()
	if(!safe)
		return FALSE
	if(get_dist(bot.owner, safe) <= 3 && get_area(bot.owner) == get_area(safe))
		bot.holding_duty = src //stays put: keep_holding() below
		return TRUE
	var/datum/bot_goal/disk_to_safety/G = new(safe)
	if(!bot.assign_goal(G))
		return FALSE
	bot_tally("disk taken to safety")
	bot_log(bot, "operatives about: taking the disk to the Brig")
	bot.say_after_typing(":c [pick("I've got the disk. Heading for the Brig.", "Disk's with me, I'm going to the Brig. Security, meet me there.", "Taking the disk to the Brig.")]")
	return TRUE

/datum/bot_duty/hole_up_with_disk/keep_holding(datum/bot_brain/bot)
	return bot.find_carried_tool(/obj/item/disk/nuclear) && bot_operatives_loose(bot) && bot.state == BOT_STATE_WANDER

/datum/bot_goal/disk_to_safety
	lawful = TRUE
	holds_for_calls = TRUE
	doing = "keeping the disk safe"
	var/turf/safe

/datum/bot_goal/disk_to_safety/New(turf/safe)
	. = ..()
	src.safe = safe

/datum/bot_goal/disk_to_safety/resolve_target(datum/bot_brain/bot)
	target = safe

/datum/bot_goal/disk_to_safety/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/favour/S = new //bot_favours.dm: always worth a try
	S.steps = list(new /datum/bot_step/move_to())
	return list(S)

// ---------------------------------------------------------------------------------------------
// Security, keeping close to it
// ---------------------------------------------------------------------------------------------

/datum/bot_duty/guard_the_disk
	name = "guarding the disk"
	tier = BOT_DUTY_URGENT
	priority = 18
	interval_min = 30
	interval_max = 60

/datum/bot_duty/guard_the_disk/applies_to(datum/bot_brain/bot)
	return bot.is_security_job()

/datum/bot_duty/guard_the_disk/try_start(datum/bot_brain/bot)
	if(bot.state != BOT_STATE_WANDER || bot.attacker || !bot_operatives_loose(bot))
		return FALSE
	var/mob/living/carbon/human/keeper = bot_nuke_disk_holder(bot)
	if(!keeper || keeper == bot.owner || keeper.z != bot.owner.z || keeper.bot_brain?.op_team || bot_in_syndicate_suit(keeper))
		return FALSE
	if(bot.gym_run && get_area(keeper) != get_area(bot.owner))
		return FALSE
	if(get_dist(bot.owner, keeper) <= BOT_DISK_GUARD_RANGE)
		bot.next_wander_time = world.time + 3 SECONDS //it stays where it is: near enough
		return FALSE
	if(bot.pursuing_kind == "follow")
		return TRUE
	bot.pursue(keeper, "follow", force = TRUE)
	bot_tally("guarding the disk")
	if(prob(30))
		bot.say_after_typing(":s [pick("Coming to you, [keeper.first_name()].", "On the disk.", "Moving to cover the disk.")]")
	return TRUE

// ---------------------------------------------------------------------------------------------
// The disk on somebody dead, or lying about
// ---------------------------------------------------------------------------------------------

/datum/bot_duty/recover_disk
	name = "recovering the disk"
	tier = BOT_DUTY_URGENT
	priority = 19
	interval_min = 50
	interval_max = 100

/datum/bot_duty/recover_disk/try_start(datum/bot_brain/bot)
	if(bot.op_team || bot.bot_traitor || bot.gone_loud() || bot.state != BOT_STATE_WANDER || bot.owner.incapacitated())
		return FALSE
	// Who'd step up: Security and the heads, and with operatives about anybody with the nerve; without them, the Captain's own
	// secure_disk (goals/civilians.dm) sees to a disk lying about.
	if(!bot.is_security_job() && !(bot.work_role() in GLOB.command_positions) && !(bot.nerve >= 0.6 && bot_operatives_loose(bot)))
		return FALSE
	var/obj/item/disk/nuclear/D = bot_find_nuke_disk(bot)
	if(!D || bot_nuke_disk_holder(bot))
		return FALSE //nowhere, or somebody alive has it
	var/atom/movable/holder = bot_outermost_holder(D) //bot_knowledge.dm: the body it's on, or the disk itself
	var/mob/living/carbon/human/body = holder
	// With no operatives about, a disk lying where it's kept (the Captain's office at the start of the shift) is the Captain's to pick up
	// (secure_disk, goals/civilians.dm): a head took it off the desk in the first minute of every shift.
	if(!istype(body) && !bot_operatives_loose(bot) && bot_alive_in_job("Captain"))
		return FALSE
	if(istype(body) && (body.bot_brain?.op_team || bot_in_syndicate_suit(body)))
		return FALSE //an operative's corpse: that's for whoever's fighting there
	if(!holder || holder.z != bot.owner.z || get_dist(bot.owner, holder) > BOT_DISK_RECOVER_RANGE || !(bot.knows_where_disk_is(holder)))
		return FALSE
	if(bot.gym_run && get_area(holder) != get_area(bot.owner))
		return FALSE
	if(GLOB.bot_disk_recoverer && GLOB.bot_disk_recoverer != bot && world.time < GLOB.bot_disk_recoverer_until && !QDELETED(GLOB.bot_disk_recoverer.owner) && GLOB.bot_disk_recoverer.owner.stat == CONSCIOUS)
		return FALSE //somebody's on it
	var/datum/bot_goal/recover_disk/G = new(holder)
	if(!bot.assign_goal(G))
		return FALSE
	GLOB.bot_disk_recoverer = bot
	GLOB.bot_disk_recoverer_until = world.time + 2 MINUTES
	bot_tally("went for the disk")
	bot_log(bot, "going for the disk on [holder]")
	return TRUE

/// Where the disk is, as anybody would know it: it saw the body or the disk, or the Captain's been found dead (the pinpointer in the
/// Captain's locker points at it, and everybody knows who carries it).
/datum/bot_brain/proc/knows_where_disk_is(atom/movable/holder)
	if(holder in view(BOT_SIGHT_RANGE, owner))
		return TRUE
	var/mob/living/carbon/human/body = holder
	if(!istype(body))
		return FALSE //the disk lying about, out of sight: nobody knows where
	if(body.mind?.assigned_role == "Captain")
		return TRUE //the Captain's body: where the disk always is
	return length(facts_about(body.real_name, list(BOT_FACT_DIED, BOT_FACT_KILLED), FALSE, TRUE)) > 0 //bot_memory.dm: it knows they're dead, and where

/datum/bot_goal/recover_disk
	lawful = TRUE
	holds_for_calls = TRUE
	doing = "getting the disk"
	var/atom/movable/holder

/datum/bot_goal/recover_disk/New(atom/movable/holder)
	. = ..()
	src.holder = holder

/datum/bot_goal/recover_disk/resolve_target(datum/bot_brain/bot)
	target = QDELETED(holder) ? null : holder

/datum/bot_goal/recover_disk/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/favour/S = new
	S.steps = list(new /datum/bot_step/move_to(), new /datum/bot_step/take_the_disk())
	return list(S)

/datum/bot_goal/recover_disk/on_give_up(datum/bot_brain/bot)
	if(GLOB.bot_disk_recoverer == bot)
		GLOB.bot_disk_recoverer = null

/// Off the body, through the strip menu as a player does it (a moment's work), or up off the floor.
/datum/bot_step/take_the_disk/execute(datum/bot_brain/bot)
	var/obj/item/disk/nuclear/D = bot_find_nuke_disk(bot)
	if(!D)
		return GOAL_STEP_FAIL
	var/atom/movable/holder = bot_outermost_holder(D)
	if(!bot.owner.Adjacent(holder))
		return GOAL_STEP_FAIL
	var/mob/living/carbon/human/body = holder
	if(istype(body))
		if(body.stat != DEAD && !body.incapacitated())
			return GOAL_STEP_FAIL //they're up: theirs
		bot.human_pause(body)
		if(QDELETED(D) || bot_outermost_holder(D) != body || !bot.owner.Adjacent(body))
			return GOAL_STEP_FAIL
		body.visible_message("<span class='warning'>[bot.owner] takes [D] off [body].</span>")
		if(!body.transferItemToLoc(D, get_turf(bot.owner)))
			D.forceMove(get_turf(bot.owner)) //out of a bag, which transferItemToLoc() doesn't reach
	bot.try_pickup_target(D)
	if(!bot.find_carried_tool(/obj/item/disk/nuclear))
		return GOAL_STEP_FAIL
	bot.put_away(D)
	if(GLOB.bot_disk_recoverer == bot)
		GLOB.bot_disk_recoverer = null
	bot_tally("disk recovered")
	bot_log(bot, "took the disk[istype(body) ? " off [body]" : ""]")
	bot.say_after_typing(":c [pick("I've got the disk.", "Got the disk[istype(body) ? " off [body.first_name()]" : ""]. Keeping it safe.", "Disk's with me now.")]")
	return GOAL_STEP_SUCCESS

#undef BOT_DISK_GUARD_RANGE
#undef BOT_DISK_RECOVER_RANGE
