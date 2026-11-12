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
//
// The user's ruling (2026-11-12): spells, not fists; it keeps its robes and staff; a loadout by personality. A wizard in the live round
// n1_wizard fought with its fists for most of the round. Here blink and mutate need the staff in hand (hippie staff_req, spell.dm), and the
// staff spent the round in the bag, so the getaway never went; and a wizard stripped of its robe never went back for it.
//
//  - The book by who it is: a hothead blows things up (fireball, missiles, mutate), a bold one buys the battlemage armour and a staff of
//    chaos (Mjolnir was tried: a bot sets a two-hander down for anything else in hand, and fought with a metal rod and its feet),
//    a sociable joker plays tricks (the barnyard curse, wands, knock, the jaunt); otherwise the old standby.
//  - What it bought is picked up and used: the armour on, the wand belt on, the hammer in hand.
//  - The staff stays in its hand, and comes out of the bag for a spell that needs it.
//  - Robe or hat gone: back on from the floor or the bag, or off whoever took them once they're down.
//  - In a fight: mutate first if it has it, a forcewall when hurt and cornered, smoke as it gets away, the curse on whoever's nearest.

/// Spells it buys, in this order, while the book has the points: the old standby.
GLOBAL_LIST_INIT(bot_wizard_spells, list(/datum/spellbook_entry/fireball, /datum/spellbook_entry/magicm, /datum/spellbook_entry/blink, /datum/spellbook_entry/jaunt, /datum/spellbook_entry/mutate))

/// What a wizard buys by who it is (wizard_pick_loadout()). Ten points each.
GLOBAL_LIST_INIT(bot_wizard_loadouts, list(
	"destroyer" = list(/datum/spellbook_entry/fireball, /datum/spellbook_entry/magicm, /datum/spellbook_entry/mutate, /datum/spellbook_entry/blink, /datum/spellbook_entry/smoke, /datum/spellbook_entry/forcewall),
	"battlemage" = list(/datum/spellbook_entry/item/battlemage, /datum/spellbook_entry/item/staffchaos, /datum/spellbook_entry/blink, /datum/spellbook_entry/fireball, /datum/spellbook_entry/forcewall, /datum/spellbook_entry/smoke),
	"trickster" = list(/datum/spellbook_entry/blink, /datum/spellbook_entry/jaunt, /datum/spellbook_entry/item/wands, /datum/spellbook_entry/barnyard, /datum/spellbook_entry/knock, /datum/spellbook_entry/smoke),
	"classic" = list(/datum/spellbook_entry/fireball, /datum/spellbook_entry/magicm, /datum/spellbook_entry/blink, /datum/spellbook_entry/jaunt, /datum/spellbook_entry/mutate),
))

/// The robes and hats spells take (spell.dm can_cast()).
GLOBAL_LIST_INIT(bot_wizard_clothes, typecacheof(list(/obj/item/clothing/suit/wizrobe, /obj/item/clothing/suit/space/hardsuit/wizard,
	/obj/item/clothing/head/wizard, /obj/item/clothing/head/helmet/space/hardsuit/wizard, /obj/item/clothing/suit/space/hardsuit/shielded/wizard,
	/obj/item/clothing/head/helmet/space/hardsuit/shielded/wizard)))

/datum/bot_brain
	var/bot_wizard = FALSE
	var/wizard_shopped = FALSE
	var/next_wizard_escape = 0
	var/next_wizard_fail_note = 0
	/// "destroyer", "battlemage", "trickster" or "classic"
	var/wizard_loadout
	var/next_wizard_dress = 0

/// A wizard from the round type (bot_round_type.dm) or an admin, with a brain already. bot_spawn_wizards() sets its own up.
/datum/antagonist/wizard/on_gain()
	. = ..()
	var/mob/living/carbon/human/H = owner?.current
	if(!istype(H) || !H.bot_brain || H.bot_brain.bot_wizard)
		return
	H.bot_brain.bot_wizard = TRUE
	H.bot_brain.bot_traitor = TRUE
	H.bot_brain.set_playstyle(BOT_STYLE_ROBUST)
	log_game("BOT WIZARD: [H.real_name] at [AREACOORD(H)]")

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
	// Cuffed: out by the jaunt or blink, as a player does (they need no hands), and nothing else till then. It used to pick a victim, fail
	// to reach them, and pick again, every few seconds for as long as it was held (live round n1_wizard: 43 goals given up).
	if(owner.handcuffed)
		wizard_escape(TRUE)
		return FALSE
	if(!here || !is_station_level(here.z) && !gym_run)
		return wizard_teleport_in()
	if(wizard_get_dressed())
		return TRUE
	if(!owner.get_active_held_item() || !owner.get_inactive_held_item())
		wizard_hold_staff() //in a free hand, ready: a spell that needs it takes it out of the bag anyway (wizard_cast_at())
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

/// Which book a wizard buys, leaning by who it is. Thresholds made five wizards in six battlemages (their playstyle's nerve is high).
/datum/bot_brain/proc/wizard_pick_loadout()
	var/list/weights = list(
		"destroyer" = 10 + round(30 * temper),
		"battlemage" = 10 + round(20 * nerve),
		"trickster" = 10 + round(30 * sociability * (1 - temper)),
		"classic" = 20,
	)
	return pickweight(weights)

/// A spell at a time off the book's links, while there are points for them: its loadout, then the old standby with what's left.
/datum/bot_brain/proc/wizard_buy_spells(obj/item/spellbook/book)
	if(!length(book.entries))
		book.prepare_spells() //opening it
	usr = owner
	wizard_loadout = wizard_loadout || wizard_pick_loadout()
	bot_log(src, "wizard's book: [wizard_loadout]")
	for(var/path in GLOB.bot_wizard_loadouts[wizard_loadout] + GLOB.bot_wizard_spells)
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
	wizard_take_purchases()

/// What the book summoned at its feet: picked up, and on or in hand.
/datum/bot_brain/proc/wizard_take_purchases()
	for(var/obj/item/I in get_turf(owner))
		if(istype(I, /obj/item/clothing/suit/space/hardsuit/shielded/wizard))
			var/obj/item/old = owner.wear_suit
			if(wear(I, ITEM_SLOT_OCLOTHING) && old)
				put_away(old) //the robe in the bag, for if the armour goes
			var/obj/item/clothing/suit/space/hardsuit/H = I
			if(H.helmet && !istype(owner.head, H.helmet.type))
				H.ToggleHelmet()
		else if(istype(I, /obj/item/storage/belt/wands))
			wear(I, ITEM_SLOT_BELT)
		else if(istype(I, /obj/item/twohanded/mjollnir) || istype(I, /obj/item/gun/magic/staff))
			try_pickup_target(I, TRUE)
		else if(istype(I, /obj/item/gun/magic/wand))
			try_pickup_target(I, TRUE)

/// The staff in a hand: blink and mutate won't go without it (staff_req, spell.dm). Out of the bag if it's in there.
/datum/bot_brain/proc/wizard_catalyst()
	for(var/obj/item/I in owner.held_items)
		if(I.GetComponent(/datum/component/spell_catalyst))
			return I
	for(var/obj/item/I in owner.GetAllContents())
		if(I.GetComponent(/datum/component/spell_catalyst))
			return I
	return null

/datum/bot_brain/proc/wizard_hold_staff()
	var/obj/item/C = wizard_catalyst()
	if(!C || (C in owner.held_items))
		return !!C
	return ready_in_hand(C)

/datum/bot_brain/proc/wizard_robed()
	return is_type_in_typecache(owner.wear_suit, GLOB.bot_wizard_clothes) && is_type_in_typecache(owner.head, GLOB.bot_wizard_clothes)

/// Robe or hat gone: on again from the bag or the floor, or off whoever has them once they're down. TRUE if it's seeing to it.
/datum/bot_brain/proc/wizard_get_dressed()
	if(wizard_robed() || world.time < next_wizard_dress)
		return FALSE
	next_wizard_dress = world.time + 3 SECONDS
	var/need_suit = !is_type_in_typecache(owner.wear_suit, GLOB.bot_wizard_clothes)
	var/need_hat = !is_type_in_typecache(owner.head, GLOB.bot_wizard_clothes)
	var/list/near = owner.GetAllContents() + view(BOT_SIGHT_RANGE, owner)
	for(var/obj/item/clothing/C in near)
		if(!is_type_in_typecache(C, GLOB.bot_wizard_clothes) || C == owner.wear_suit || C == owner.head)
			continue
		var/is_suit = istype(C, /obj/item/clothing/suit)
		if(is_suit ? !need_suit : !need_hat)
			continue
		var/atom/movable/holder = bot_outermost_holder(C)
		if(holder == owner)
			if(wear(C, is_suit ? ITEM_SLOT_OCLOTHING : ITEM_SLOT_HEAD))
				bot_log(src, "back in its [C.name]")
				return TRUE
			continue
		var/mob/living/carbon/human/H = holder
		if(istype(H))
			if(H.stat == CONSCIOUS && !H.handcuffed)
				bot_log(src, "[H] has its [C.name]: going for them")
				bot_say(owner, pick("That's MY robe!", "Give that back, mortal!", "You dare wear my vestments?!"))
				return assign_goal(new /datum/bot_goal/traitor_kill/robust/wizard(null, H))
			if(!owner.Adjacent(H))
				pursue(H, "follow", force = TRUE)
				return TRUE
			human_pause(H)
			if(H.transferItemToLoc(C, get_turf(owner)))
				try_pickup_target(C, TRUE)
			return TRUE
		if(isturf(C.loc))
			if(!owner.Adjacent(C))
				pursue(C, "item", force = TRUE)
				return TRUE
			try_pickup_target(C, TRUE)
			return TRUE
	return FALSE

/// Rooms nobody picks off the scroll's menu: the scroll drops you anywhere in the room, and in these that's inside the engine's
/// electrified grilles. A wizard went to Port Engineering, where the engineers were starting the tesla, and shocked itself to death on them.
GLOBAL_LIST_INIT(bot_wizard_no_landing, typecacheof(list(/area/engine/engineering, /area/engine/port_engineering, /area/engine/supermatter,
	/area/engine/engine_room, /area/engine/atmospherics_engine, /area/engine/engine_smes, /area/engine/gravity_generator)))

/// The scroll's menu, to wherever the crew are thickest: a room with somebody to fight in it.
/datum/bot_brain/proc/wizard_teleport_in()
	var/obj/item/teleportation_scroll/scroll = locate() in owner.GetAllContents()
	if(!scroll || scroll.uses <= 0)
		return FALSE
	// A room with people in it, but not Security: a wizard who picked the busiest room at the start of the shift landed in the Security
	// Office with four officers at their briefing, was cuffed and stripped of the robe in two seconds, and couldn't cast a spell for the
	// rest of the round (live round n0_wizard, 2026-11-10). A player picks somewhere with a crowd and no guns.
	var/list/crowd = list() //area name -> how many
	var/list/guarded = list() //area name -> TRUE where Security is
	for(var/mob/living/carbon/human/H in GLOB.carbon_list)
		if(H.stat == DEAD || !is_station_level(H.z) || !H.mind?.assigned_role)
			continue
		var/area/A = get_area(H)
		if(is_type_in_typecache(A, GLOB.bot_wizard_no_landing))
			continue
		for(var/name in GLOB.teleportlocs)
			if(GLOB.teleportlocs[name] == A)
				crowd[name]++
				if((H.mind.assigned_role in GLOB.security_positions) || istype(A, /area/security) || istype(A, /area/ai_monitored/security))
					guarded[name] = TRUE
				break
	for(var/name in guarded)
		crowd -= name
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
		if(S.charge_counter < S.charge_max)
			continue
		if(S.staff_req && !wizard_hold_staff())
			continue
		if(!S.can_cast(owner))
			continue
		// Mutate first, before anything else: the hulk and the laser eyes for the rest of the fight
		if(istype(S, /obj/effect/proc_holder/spell/targeted/genetic/mutate))
			if(owner.dna?.check_mutation(HULK))
				continue
			cast_without_waiting(S)
			bot_log(src, "cast [S] on itself")
			return TRUE
		// Hurt and somebody close: a wall between
		if(istype(S, /obj/effect/proc_holder/spell/targeted/forcewall))
			if(owner.health > owner.maxHealth * 0.6 || get_dist(owner, target) > 2)
				continue
			owner.face_atom(target)
			cast_without_waiting(S)
			bot_log(src, "cast [S] against [target]")
			return TRUE
		if(istype(S, /obj/effect/proc_holder/spell/targeted/barnyardcurse))
			var/mob/living/carbon/C = target
			if(!istype(C) || istype(C.wear_mask, /obj/item/clothing/mask/pig/cursed) || istype(C.wear_mask, /obj/item/clothing/mask/cowmask/cursed) || istype(C.wear_mask, /obj/item/clothing/mask/horsehead/cursed) || get_dist(owner, target) > S.range)
				continue
			if(!S.cast_check(FALSE, owner))
				continue
			S.perform(list(target), TRUE, owner)
			bot_log(src, "cursed [target]")
			return TRUE
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

/// Something to hit them with from where it is, nearly ready: a spell off cooldown in the next few seconds, or a wand or staff that can
/// fire. Then it holds at three or four tiles (a step back if they're on it) instead of walking in to punch. In the first batch
/// after the spells were fixed, wizards still threw 267 punches in six shifts, closing in every time a spell was cooling down.
/datum/bot_brain/proc/wizard_keeps_range(mob/living/target)
	var/dist = get_dist(owner, target)
	if(dist > 5 || owner.incapacitated())
		return FALSE
	var/soon = FALSE
	for(var/obj/effect/proc_holder/spell/S as anything in owner.mind?.spell_list)
		if((istype(S, /obj/effect/proc_holder/spell/aimed) || istype(S, /obj/effect/proc_holder/spell/targeted/projectile/magic_missile) || istype(S, /obj/effect/proc_holder/spell/targeted/barnyardcurse)) && S.charge_max - S.charge_counter <= 80)
			soon = TRUE
			break
	if(!soon)
		for(var/obj/item/gun/G in owner.GetAllContents())
			if(G.can_shoot())
				soon = TRUE
				break
	if(!soon)
		return FALSE
	stop_pursuit()
	if(dist <= 2)
		step_back_from(target)
	owner.face_atom(target)
	return TRUE

/// Hurt, or held (`held`): away, by blink or the jaunt, whichever's ready.
/datum/bot_brain/proc/wizard_escape(held = FALSE)
	if(world.time < next_wizard_escape || (!held && owner.health > owner.maxHealth * 0.5))
		return FALSE
	usr = owner
	for(var/obj/effect/proc_holder/spell/S as anything in owner.mind?.spell_list) //smoke behind it first
		if(istype(S, /obj/effect/proc_holder/spell/targeted/smoke) && S.charge_counter >= S.charge_max && S.can_cast(owner))
			cast_without_waiting(S)
			break
	for(var/obj/effect/proc_holder/spell/S as anything in owner.mind?.spell_list)
		if(S.charge_counter < S.charge_max)
			continue
		if(S.staff_req && !wizard_hold_staff()) //blink takes the staff in hand (hippie staff_req)
			continue
		if(!S.can_cast(owner))
			continue
		if(istype(S, /obj/effect/proc_holder/spell/targeted/turf_teleport/blink) || istype(S, /obj/effect/proc_holder/spell/targeted/ethereal_jaunt))
			next_wizard_escape = world.time + 10 SECONDS
			cast_without_waiting(S) //the jaunt sleeps through its whole length: not on the reflex loop
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

/// A spell's button pressed, without waiting for it to finish.
/datum/bot_brain/proc/cast_without_waiting(obj/effect/proc_holder/spell/S)
	set waitfor = FALSE
	usr = owner
	S.Click()
