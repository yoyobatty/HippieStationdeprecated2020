// The Wizard Federation's man (bot-wizards=N on a Bot Shift, or bot_spawn_wizards()), with the game's own wizard antagonist datum. The
// way a player plays one who's out to cause trouble:
//
//  - In the den: the spellbook, a spell at a time off its "buy" links: a fireball and magic missiles to fight with, blink and the
//    ethereal jaunt to get away, mutate if there's anything left.
//  - The teleportation scroll to wherever the crew are thickest.
//  - Then whoever's about, at range with the spells (try_attack_from_range(), bot_fighting.dm) and up close with the staff, blinking
//    away when it's hurt.
//
// Loud from the start (gone_loud()), like the operatives.

/// Spells it buys, in this order, while the book has the points.
GLOBAL_LIST_INIT(bot_wizard_spells, list(/datum/spellbook_entry/fireball, /datum/spellbook_entry/magicm, /datum/spellbook_entry/blink, /datum/spellbook_entry/jaunt, /datum/spellbook_entry/mutate))

/datum/bot_brain
	var/bot_wizard = FALSE
	var/wizard_shopped = FALSE
	var/next_wizard_escape = 0
	var/next_wizard_fail_note = 0

/proc/bot_spawn_wizards(count)
	var/made = 0
	for(var/i in 1 to count)
		var/turf/T = length(GLOB.wizardstart) ? get_turf(pick(GLOB.wizardstart)) : get_turf(pick(SSjob.latejoin_trackers))
		var/mob/living/carbon/human/H = new(T)
		H.mind_initialize()
		H.mind.assigned_role = "Wizard"
		H.mind.add_antag_datum(/datum/antagonist/wizard)
		var/datum/bot_brain/B = new(H)
		B.bot_wizard = TRUE
		B.bot_traitor = TRUE //an antagonist's words and manner (goals/robust.dm)
		B.set_playstyle(BOT_STYLE_ROBUST)
		log_game("BOT WIZARD: [H.real_name] at [AREACOORD(H)]")
		made++
	return made

/datum/bot_duty/wizard
	name = "wizardry"
	tier = BOT_DUTY_URGENT
	priority = 9
	interval_min = 20
	interval_max = 40

/datum/bot_duty/wizard/applies_to(datum/bot_brain/bot)
	return bot.bot_wizard

/datum/bot_duty/wizard/next_look(datum/bot_brain/bot)
	return rand(interval_min, interval_max)

/datum/bot_duty/wizard/try_start(datum/bot_brain/bot)
	return bot.wizard_business()

/datum/bot_brain/proc/wizard_business()
	if(owner.incapacitated())
		return FALSE
	var/obj/item/spellbook/book = locate() in owner.GetAllContents()
	if(!wizard_shopped && book)
		wizard_shopped = TRUE
		wizard_buy_spells(book)
	var/turf/here = get_turf(owner)
	if(!isturf(owner.loc)) //mid-jaunt
		return FALSE
	if(!here || !is_station_level(here.z))
		return wizard_teleport_in()
	var/mob/living/carbon/human/V
	var/best_dist
	for(var/mob/living/carbon/human/H in view(BOT_SIGHT_RANGE, owner))
		if(H == owner || H.stat == DEAD || H.bot_brain?.bot_wizard || iswizard(H))
			continue
		var/dist = get_dist(owner, H)
		if(!V || dist < best_dist)
			V = H
			best_dist = dist
	if(!V) //nobody in sight: off to wherever there's somebody
		for(var/mob/living/carbon/human/H in GLOB.carbon_list)
			if(H == owner || H.stat == DEAD || H.z != owner.z || H.bot_brain?.bot_wizard || iswizard(H) || !H.mind?.assigned_role)
				continue
			var/dist = get_dist(owner, H)
			if(!V || dist < best_dist)
				V = H
				best_dist = dist
	return V ? assign_goal(new /datum/bot_goal/traitor_kill/robust/wizard(null, V)) : FALSE

/// A spell at a time off the book's links, while there are points for them.
/datum/bot_brain/proc/wizard_buy_spells(obj/item/spellbook/book)
	if(!length(book.entries))
		book.prepare_spells() //opening it
	usr = owner
	for(var/path in GLOB.bot_wizard_spells)
		for(var/i in 1 to length(book.entries))
			var/datum/spellbook_entry/E = book.entries[i]
			if(E.type != path)
				continue
			if(E.CanBuy(owner, book))
				human_pause(book)
				telemetry_ui_action(book, "buy [E.name]")
				book.Topic(null, list("buy" = "[i]"))
				bot_log(src, "learned [E.name] ([book.uses] points left)")
			break

/// The scroll's menu, to wherever the crew are thickest: a room with somebody to fight in it.
/datum/bot_brain/proc/wizard_teleport_in()
	var/obj/item/teleportation_scroll/scroll = locate() in owner.GetAllContents()
	if(!scroll || scroll.uses <= 0)
		return FALSE
	var/list/crowd = list() //area name -> how many
	for(var/mob/living/carbon/human/H in GLOB.carbon_list)
		if(H.stat == DEAD || !is_station_level(H.z) || !H.mind?.assigned_role)
			continue
		var/area/A = get_area(H)
		for(var/name in GLOB.teleportlocs)
			if(GLOB.teleportlocs[name] == A)
				crowd[name]++
				break
	if(!length(crowd))
		return FALSE
	var/best
	for(var/name in crowd)
		if(!best || crowd[name] > crowd[best])
			best = name
	if(!ready_in_hand(scroll))
		return FALSE
	human_pause(scroll)
	telemetry_ui_action(scroll, "teleport to [best]")
	var/area/thearea = GLOB.teleportlocs[best]
	var/list/spots = list()
	for(var/turf/T in get_area_turfs(thearea.type))
		if(!is_blocked_turf(T))
			spots += T
	if(!length(spots))
		return FALSE
	var/datum/effect_system/smoke_spread/smoke = new
	smoke.set_up(2, owner.loc)
	smoke.attach(owner)
	smoke.start()
	if(do_teleport(owner, pick(spots), forceMove = TRUE, channel = TELEPORT_CHANNEL_MAGIC, forced = TRUE))
		smoke.start()
		scroll.uses--
		log_game("BOT WIZARD: [owner] teleported to [best] ([crowd[best]] there)")
		bot_say(owner, pick("SCYAR NILA!", "Behold!", "The Federation sends its regards!", "EI NATH!"))
	put_away(scroll)
	return FALSE //on to whoever's there, next look

/// A spell at them if one's ready: the fireball (armed, then a click on them), or the missiles, which find everybody in range.
/datum/bot_brain/proc/wizard_cast_at(mob/living/target)
	var/list/spells = owner.mind?.spell_list
	if(!length(spells) || owner.incapacitated())
		return FALSE
	usr = owner
	for(var/obj/effect/proc_holder/spell/S as anything in spells)
		if(S.charge_counter < S.charge_max || !S.can_cast(owner))
			continue
		if(istype(S, /obj/effect/proc_holder/spell/aimed))
			var/obj/effect/proc_holder/spell/aimed/A = S
			if(!has_clear_shot(target))
				continue
			owner.face_atom(target)
			// The action button arms it and the next click fires it (InterceptClickOn()), but arming is a ranged ability, which takes a
			// client: what the two clicks come to, done here.
			A.current_amount = A.projectile_amount
			if(!A.cast_check(FALSE, owner))
				continue
			A.perform(list(target), FALSE, owner)
			bot_log(src, "cast [S] at [target]")
			return TRUE
		else if(istype(S, /obj/effect/proc_holder/spell/targeted/projectile/magic_missile))
			S.Click()
			if(S.charge_counter >= S.charge_max) //it didn't go: a spell that's cast starts recharging
				if(world.time >= next_wizard_fail_note)
					next_wizard_fail_note = world.time + 1 MINUTES
					bot_log(src, "[S] wouldn't cast: robe [owner.wear_suit], hat [owner.head], [get_area_name(owner, TRUE)]")
				continue
			bot_log(src, "cast [S] at everybody about [target]")
			return TRUE
	return FALSE

/// Hurt: away, by blink or the jaunt, whichever's ready.
/datum/bot_brain/proc/wizard_escape()
	if(world.time < next_wizard_escape || owner.health > owner.maxHealth * 0.5)
		return FALSE
	usr = owner
	for(var/obj/effect/proc_holder/spell/S as anything in owner.mind?.spell_list)
		if(S.charge_counter < S.charge_max || !S.can_cast(owner))
			continue
		if(istype(S, /obj/effect/proc_holder/spell/targeted/turf_teleport/blink) || istype(S, /obj/effect/proc_holder/spell/targeted/ethereal_jaunt))
			next_wizard_escape = world.time + 10 SECONDS
			S.Click()
			bot_log(src, "cast [S] to get away")
			return TRUE
	return FALSE

/datum/bot_goal/traitor_kill/robust/wizard
	doing = "teaching somebody a lesson"
	breaks_in = TRUE

/datum/bot_goal/traitor_kill/robust/wizard/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/traitor_kill/S = new
	S.steps = list(new /datum/bot_step/paced/close_in(), new /datum/bot_step/paced/strike/robust())
	return list(S)

/datum/bot_goal/traitor_kill/robust/wizard/on_give_up(datum/bot_brain/bot)
	return //wizard_business() decides again

/datum/bot_goal/traitor_kill/robust/wizard/on_success(datum/bot_brain/bot)
	return
