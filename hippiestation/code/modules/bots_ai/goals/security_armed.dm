// Security against somebody armed, after the user's round of 2026-11-04: as Chief Engineer with an energy sword they killed the chemist and
// the Head of Security in the Kitchen while four officers stood off, called for backup and never hit them once. The guns were the
// trouble: officers carry a hybrid taser whose taser shots cost 200 of its 1000 charge, it was spent from earlier arrests, nothing
// ever recharged it, and with "nothing to shoot with" an officer keeps its distance from anybody dangerous for good.
//
// The user's ruling: ammo checks, and when a gun is out, melee, stuns and slips, creatively. So:
//  - A gun counts while any of its settings has a shot left (find_usable_gun(), goals/security_tactics.dm).
//  - Out of shots, an officer goes in on them with the flash and then the baton, the ordinary arrest, when it isn't alone or when
//    somebody's being cut down in front of it. A flash puts somebody without eye protection down for eight to twelve seconds, and an
//    energy sword can't block it. Alone with nobody in danger, it still waits for the others.
//  - Free and with a gun under 60% charge, it takes it to a recharger and waits by it, as anybody stood at one does.
//  - Lethal force once they've killed (the user's ruling: "after a witnessed kill") or are armed and dangerous, as Space Law has it
//    (bot_may_use_lethal_force(), bot_law.dm); now said on the radio the first time.
//  - Nobody goes off to the armory for something heavier with them in sight.

/datum/bot_brain
	var/next_going_in_note = 0

/// A flash it's carrying that still works.
/datum/bot_brain/proc/carried_flash()
	for(var/obj/item/assembly/flash/handheld/F in owner.GetAllContents())
		if(!F.burnt_out)
			return F
	return null

/// Officers on their feet within reach of `S` and after them (this bot among them), for going in together.
/datum/bot_brain/proc/officers_close_to(mob/living/carbon/human/S)
	. = 0
	for(var/datum/bot_brain/B as anything in GLOB.bot_security_brains)
		if(QDELETED(B.owner) || B.owner.stat != CONSCIOUS || B.owner.z != S.z || get_dist(B.owner, S) > BOT_SIGHT_RANGE)
			continue
		if(B.owner.health < B.owner.maxHealth * 0.4 || world.time < B.fallen_back_until) //BOT_SEC_FALL_BACK_AT
			continue
		if(B == src || (B.state == BOT_STATE_ARREST && B.arrest_suspect == S) || istype(B.current_goal, /datum/bot_goal/respond_to_call))
			.++

/// Armed, and somebody beside them is hurt by them: they're at it now. The officer itself counts.
/proc/bot_cutting_someone_down(mob/living/carbon/human/S)
	if(!bot_armed_and_dangerous(S))
		return FALSE
	for(var/mob/living/carbon/human/victim in range(1, S))
		if(victim != S && victim.stat != DEAD && victim.lastattacker == S.real_name && victim.health < victim.maxHealth)
			return TRUE
	return FALSE

/// Nothing to shoot with: whether it goes in on them anyway, with the flash and the baton.
/datum/bot_brain/proc/should_go_in_unarmed(mob/living/carbon/human/S)
	if(istype(S.wear_suit, /obj/item/clothing/suit/space/hardsuit/nano))
		return FALSE //a suit is gathered against first (the user's ruling), and a flash doesn't get through its helmet
	if(!carried_flash() && !find_usable_baton())
		return FALSE
	if(officers_close_to(S) >= 2)
		return TRUE
	return nerve >= 0.3 && bot_cutting_someone_down(S)

/// Somebody wanted and dangerous it can see, on their feet.
/datum/bot_brain/proc/dangerous_suspect_in_sight()
	for(var/mob/living/carbon/human/H in view(BOT_SIGHT_RANGE, owner))
		if(H != owner && H.stat != DEAD && !H.handcuffed && bot_get_wanted_entry(H) && bot_too_dangerous(H))
			return TRUE
	return FALSE

/// REF(suspect) -> until when somebody on Security has said they're going lethal on them.
GLOBAL_LIST_EMPTY(bot_lethal_said)

/// The switch to lethal, said on the radio: once between them, not by every officer every shot.
/datum/bot_brain/proc/say_going_lethal(mob/living/carbon/human/S)
	if(GLOB.bot_lethal_said[REF(S)] > world.time)
		return
	GLOB.bot_lethal_said[REF(S)] = world.time + 2 MINUTES
	var/datum/bot_wanted/W = bot_get_wanted_entry(S)
	var/why = W?.severity >= BOT_CRIME_MURDER ? "they've killed" : "armed and dangerous"
	bot_log(src, "going lethal on [S] ([why])")
	bot_say(owner, ":s Going lethal on [S.name], [get_area_name(S, TRUE)]. [capitalize(why)].")

// ---------------------------------------------------------------------------------------------
// Keeping a gun charged
// ---------------------------------------------------------------------------------------------

/// A gun it carries that wants charging: under 60%.
/datum/bot_brain/proc/gun_wanting_charge()
	for(var/obj/item/gun/energy/G in owner.GetAllContents())
		if(G.can_charge && G.cell && G.cell.charge < G.cell.maxcharge * 0.6)
			return G
	return null

/// The nearest recharger with nothing in it, working, that it may walk to.
/datum/bot_brain/proc/nearest_free_recharger()
	var/obj/machinery/recharger/best
	var/best_dist
	for(var/obj/machinery/recharger/R as anything in bot_instances_of(/obj/machinery/recharger))
		if(QDELETED(R) || R.z != owner.z || !R.anchored || R.charging || R.panel_open || (R.stat & (NOPOWER|BROKEN)))
			continue
		var/dist = get_dist(owner, R)
		if(dist > 60 || (best && dist >= best_dist) || !can_walk_lawfully_to(R))
			continue
		best = R
		best_dist = dist
	return best

/datum/bot_duty/recharge_gun
	name = "charging a gun"
	jobs = list("Security Officer", "Warden", "Head of Security")
	tier = BOT_DUTY_WORK
	priority = 25
	interval_min = 150
	interval_max = 300

/datum/bot_duty/recharge_gun/try_start(datum/bot_brain/bot)
	if(bot.state != BOT_STATE_WANDER || bot.dangerous_suspect_in_sight())
		return FALSE
	var/obj/item/gun/energy/G = bot.gun_wanting_charge()
	if(!G)
		return FALSE
	var/obj/machinery/recharger/R = bot.nearest_free_recharger()
	if(!R)
		return FALSE
	return bot.assign_goal(new /datum/bot_goal/recharge_gun(R, G))

/datum/bot_goal/recharge_gun
	lawful = TRUE
	doing = "charging my gun"
	holds_for_calls = TRUE //a few seconds, and the gun isn't left behind in it
	var/obj/item/gun/energy/gun

/datum/bot_goal/recharge_gun/New(obj/machinery/recharger/R, obj/item/gun/energy/G)
	. = ..()
	target = R
	gun = G

/datum/bot_goal/recharge_gun/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/recharge_gun/S = new
	S.steps = list(new /datum/bot_step/move_to(), new /datum/bot_step/paced/recharge_gun())
	return list(S)

/datum/bot_strategy/recharge_gun/is_feasible(datum/bot_brain/bot)
	var/datum/bot_goal/recharge_gun/G = bot.current_goal
	return istype(G) && !QDELETED(G.target) && !QDELETED(G.gun)

/// In it, stood by until it's full, and out again
/datum/bot_step/paced/recharge_gun
	max_clicks = 40
	var/inserted = FALSE
	var/until = 0

/datum/bot_step/paced/recharge_gun/start(datum/bot_brain/bot)
	var/datum/bot_goal/recharge_gun/G = bot.current_goal
	inserted = FALSE
	until = world.time + 90 SECONDS
	return istype(G) && !QDELETED(G.target) && !QDELETED(G.gun) && bot.owner.Adjacent(G.target)

/datum/bot_step/paced/recharge_gun/do_click(datum/bot_brain/bot)
	var/datum/bot_goal/recharge_gun/G = bot.current_goal
	var/obj/machinery/recharger/R = G?.target
	if(!istype(R) || QDELETED(R) || QDELETED(G.gun) || !bot.owner.Adjacent(R))
		return FALSE
	if(!inserted)
		if(R.charging)
			return FALSE //somebody's gun got there first
		bot.use_item_on(G.gun, R)
		if(R.charging != G.gun)
			return FALSE
		inserted = TRUE
		bot_log(bot, "charging [G.gun] at [R]")
		wait_for = 30
		return TRUE
	if(G.gun.cell.charge < G.gun.cell.maxcharge && world.time < until)
		wait_for = 30
		return TRUE
	return FALSE

/datum/bot_step/paced/recharge_gun/finish(datum/bot_brain/bot)
	var/datum/bot_goal/recharge_gun/G = bot.current_goal
	if(!istype(G) || QDELETED(G.gun))
		return GOAL_STEP_FAIL
	if(G.gun.loc == G.target && bot.owner.Adjacent(G.target))
		bot.use_atom(G.target) //out into a hand: it's never left in there
	if(G.gun.loc == bot.owner)
		bot.stow_item(G.gun)
	return G.gun.cell.charge >= G.gun.cell.maxcharge * 0.9 ? GOAL_STEP_SUCCESS : GOAL_STEP_FAIL
