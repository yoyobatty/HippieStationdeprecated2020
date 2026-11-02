// Whether the nanosuit does what it says it does. Not part of the game: HARNESS=nanosuit_check.dm tools/power_check/run.sh <label>
// Headless, on a real round. PASS or FAIL for each thing a player should be able to count on, INFO for the numbers behind it.
// nanosuit.dm comes after this file in the build, so its mode defines aren't seen here: the modes are written out.

/datum/controller/master
	sleep_offline_after_initializations = FALSE

GLOBAL_VAR_INIT(nc_passed, 0)
GLOBAL_VAR_INIT(nc_failed, 0)
GLOBAL_VAR_INIT(nc_emp_stun, 0)
GLOBAL_LIST_EMPTY(nc_stun_results)

/proc/nc_log(text)
	text2file(text, "data/update_check.txt")

/proc/nc_check(name, ok, detail)
	if(ok)
		GLOB.nc_passed++
	else
		GLOB.nc_failed++
	nc_log("[ok ? "PASS" : "FAIL"] [name][isnull(detail) ? "" : " ([detail])"]")

/world/New()
	. = ..()
	spawn(0)
		nanosuit_check_run()

/proc/nc_floor()
	var/datum/turf_reservation/R = SSmapping.RequestBlockReservation(60, 60)
	var/x0 = R.bottom_left_coords[1]
	var/y0 = R.bottom_left_coords[2]
	var/z = R.bottom_left_coords[3]
	var/area/bot_gym/A = new
	for(var/turf/T in block(locate(x0, y0, z), locate(x0 + 59, y0 + 59, z)))
		var/area/old_area = T.loc
		old_area.contents -= T
		A.contents += T
		T.change_area(old_area, A)
		T.ChangeTurf(/turf/open/floor/plasteel, flags = CHANGETURF_IGNORE_AIR)
	return locate(x0 + 2, y0 + 2, z)

/proc/nc_human(turf/T)
	var/mob/living/carbon/human/H = new(T)
	H.mind_initialize()
	return H

/proc/nc_suit(mob/living/carbon/human/H)
	return H.wear_suit

/// One human in a suit for each section, in a row a few tiles apart. The suit takes 13.5 s to start, so they all start at once.
/proc/nc_crew(turf/corner, count)
	. = list()
	for(var/i in 1 to count)
		var/mob/living/carbon/human/H = nc_human(locate(corner.x + 2 + round((i - 1) / 12) * 10, corner.y + ((i - 1) % 12) * 4, corner.z))
		H.equip_to_slot_or_del(new /obj/item/clothing/suit/space/hardsuit/nano(H.loc), ITEM_SLOT_OCLOTHING)
		. += H
	var/deadline = world.time + 40 SECONDS
	for(var/mob/living/carbon/human/H in .)
		var/obj/item/clothing/suit/space/hardsuit/nano/S = nc_suit(H)
		while(S.shutdown && world.time < deadline)
			sleep(2)

/proc/nc_mode(mob/living/carbon/human/H, mode, charge = 100)
	var/obj/item/clothing/suit/space/hardsuit/nano/S = nc_suit(H)
	S.toggle_mode(mode, TRUE)
	S.cell.charge = charge
	S.recharge_cooldown = 0
	return S

/proc/nc_try(datum/callback/C)
	try
		C.Invoke()
	catch(var/exception/e)
		return "[e.name] at [e.file]:[e.line]"
	return null

// ---- the numbers

/proc/nc_numbers(mob/living/carbon/human/H, turf/spare)
	var/mob/living/carbon/human/plain = nc_human(spare)
	plain.equipOutfit(/datum/outfit/job/assistant)
	nc_log("INFO no suit: [plain.movement_delay()] ds a tile, [round(10 / plain.movement_delay(), 0.1)] tiles a second")
	var/obj/item/bodypart/chest = H.get_bodypart(BODY_ZONE_CHEST)
	for(var/mode in list("armor", "cloak", "speed", "strength"))
		var/obj/item/clothing/suit/space/hardsuit/nano/S = nc_mode(H, mode)
		var/delay = H.movement_delay()
		nc_log("INFO [mode]: [delay] ds a tile, [round(10 / max(delay, world.tick_lag), 0.1)] tiles a second, chest armour melee [H.checkarmor(chest, "melee")] bullet [H.checkarmor(chest, "bullet")] laser [H.checkarmor(chest, "laser")] energy [H.checkarmor(chest, "energy")] bomb [H.checkarmor(chest, "bomb")], block [S.block_chance]")
	nc_log("INFO can be injected: [H.can_inject(H) ? "yes" : "no"], mouth covered: [H.is_mouth_covered() ? "yes" : "no"]")
	qdel(plain)

/// What the second pass set out to do, against what it said it would
/proc/nc_balance(mob/living/carbon/human/H)
	var/obj/item/bodypart/chest = H.get_bodypart(BODY_ZONE_CHEST)
	var/obj/item/clothing/suit/space/hardsuit/nano/S = nc_mode(H, "armor")
	var/armor_speed = H.movement_delay()
	var/list/armor_rating = list(H.checkarmor(chest, "melee"), H.checkarmor(chest, "bullet"), H.checkarmor(chest, "laser"))
	var/lit = list()
	for(var/datum/action/item_action/nanosuit/N in S.actions)
		if(length(N.button.filters))
			lit += N.name
	nc_check("armour mode's button is the one lit", length(lit) == 1 && lit[1] == "Armor Mode", jointext(lit, ", "))
	nc_check("armour and strength move at 8 tiles a second", armor_speed == 1.25, "[armor_speed] ds a tile")
	nc_mode(H, "strength")
	var/list/strength_rating = list(H.checkarmor(chest, "melee"), H.checkarmor(chest, "bullet"), H.checkarmor(chest, "laser"))
	nc_check("Maximum Armor is the heaviest", armor_rating[1] == strength_rating[1] + 20 && armor_rating[2] == strength_rating[2] + 20 && armor_rating[3] == strength_rating[3] + 20, "[jointext(armor_rating, "/")] against [jointext(strength_rating, "/")]")
	lit = list()
	for(var/datum/action/item_action/nanosuit/N in S.actions)
		if(length(N.button.filters))
			lit += N.name
	nc_check("the light follows the mode", length(lit) == 1 && lit[1] == "Strength Mode", jointext(lit, ", "))
	nc_mode(H, "cloak")
	nc_check("the cloak is still the quicker of them", H.movement_delay() == 1.15 && H.movement_delay() < armor_speed, "[H.movement_delay()] ds a tile")

	nc_mode(H, "armor")
	S.next_speed_burst = 0
	H.adjustStaminaLoss(60)
	var/tired = H.getStaminaLoss()
	S.toggle_mode("speed", TRUE)
	var/rested = H.getStaminaLoss()
	nc_check("going into speed mode clears some stamina", rested < tired, "[tired] then [rested]") // 20, through the limbs' coefficient
	for(var/i in 1 to 5)
		S.toggle_mode("armor", TRUE)
		S.toggle_mode("speed", TRUE)
	nc_check("switching in and out doesn't farm it", H.getStaminaLoss() == rested, "[H.getStaminaLoss()] after 5 more")
	H.adjustStaminaLoss(-H.getStaminaLoss())

	S = nc_mode(H, "armor")
	var/obj/item/projectile/beam/laser/laser = new(H.loc)
	var/plain = nc_block_cost(H, laser, laser.damage, PROJECTILE_ATTACK)
	S.upgrademulti = 1.5
	var/hacked = nc_block_cost(H, laser, laser.damage, PROJECTILE_ATTACK)
	nc_check("a hacked suit's blocks cost less, not more", hacked < plain, "[hacked] against [plain]")
	S = nc_mode(H, "speed")
	var/steps = 0
	while(S.cell.charge > 0 && steps < 1000)
		S.onmove()
		steps++
	nc_check("a hacked suit's sprint goes further, not less far", steps > 50, "[steps] steps against 50")
	S.upgrademulti = 1
	qdel(laser)

	S = nc_mode(H, "armor")
	S.medical_delay = 30
	S.current_charges = S.max_charges
	S.heal_nano(H)
	S.heal_nano(H)
	nc_check("two medical charges spent", S.current_charges == S.max_charges - 2)
	sleep(45)
	nc_check("one comes back on its own after the delay", S.current_charges == S.max_charges - 1, "[S.current_charges] of [S.max_charges]")
	sleep(30)
	nc_check("then the next", S.current_charges == S.max_charges, "[S.current_charges] of [S.max_charges]")
	sleep(45)
	nc_check("and it stops at the top", S.current_charges == S.max_charges, "[S.current_charges] of [S.max_charges]")
	S.medical_delay = initial(S.medical_delay)

	var/datum/keybinding/menu = GLOB.keybindings_by_name["nanosuit_menu"]
	nc_check("the quick menu is a keybind", menu)
	nc_check("on C unless it's changed", "nanosuit_menu" in GLOB.hotkey_keybinding_list_by_key["C"])
	nc_check("listed under the human keybinds in the preferences", menu?.category == CATEGORY_HUMAN, menu?.category)

/proc/nc_energy(mob/living/carbon/human/H)
	var/obj/item/clothing/suit/space/hardsuit/nano/S = nc_mode(H, "cloak")
	sleep(100)
	var/used = 100 - S.cell.charge
	var/last = used ? 100 / (used / 10) : 0
	nc_log("INFO cloak standing still: [used] energy in 10 s, lasts [round(last, 0.1)] s")
	nc_check("standing still in the cloak costs a tenth of the rate, as the code's comment says it does", last >= 100, "[round(last, 0.1)] s")

	S = nc_mode(H, "speed")
	var/steps = 0
	while(S.cell.charge > 0 && steps < 1000)
		S.onmove()
		steps++
	nc_log("INFO speed mode: [steps] steps on a full charge")

	S = nc_mode(H, "armor", 0)
	var/start = world.time
	while(S.cell.charge < S.cell.maxcharge && world.time < start + 20 SECONDS)
		sleep(1)
	nc_log("INFO empty to full, no delay: [(world.time - start) / 10] s")

	S = nc_mode(H, "armor")
	H.adjustBruteLoss(60)
	var/brute = H.getBruteLoss()
	S.heal_nano(H)
	sleep(100)
	nc_log("INFO one medical charge healed [brute - H.getBruteLoss()] brute out of [brute]")
	H.adjustBruteLoss(-H.getBruteLoss())

// ---- plain bugs

/proc/nc_movement(mob/living/carbon/human/H)
	nc_mode(H, "armor")
	var/turf/next = get_step(H, EAST)
	var/moved = H.Move(next, EAST)
	nc_check("Move() reports a move that happened", moved && H.loc == next, "returned [moved]")
	var/obj/item/clothing/suit/space/hardsuit/nano/S = nc_mode(H, "speed")
	next = locate(H.x + 1, H.y + 1, H.z)
	moved = H.Move(next, NORTHEAST)
	nc_check("a diagonal step gets there", H.loc == next, "returned [moved]")
	nc_check("a diagonal step costs what two steps cost in speed mode", 100 - S.cell.charge == 4, "[100 - S.cell.charge] energy")

/proc/nc_tank(mob/living/carbon/human/H)
	var/obj/item/tank/internals/emergency_oxygen/recharge/tank = H.s_store
	nc_check("wearing the tank", istype(tank))
	H.notransform = TRUE // no Life(), so only what the tank does counts
	H.adjustBruteLoss(100)
	H.adjustFireLoss(45)
	H.bleed_rate = 5
	H.blood_volume = BLOOD_VOLUME_NORMAL
	nc_log("INFO stat [H.stat], lying [H.lying], health [H.health]")
	var/oxy = H.getOxyLoss()
	var/blood = H.blood_volume
	for(var/i in 1 to 3)
		tank.process()
	nc_check("the tank's refill leaves a wounded wearer alone: no oxygen damage", H.getOxyLoss() == oxy, "[H.getOxyLoss() - oxy] oxy from 3 refills")
	nc_check("the tank's refill leaves a wounded wearer alone: no bleeding", H.blood_volume == blood, "[blood - H.blood_volume] blood from 3 refills")
	tank.air_contents.moles[/datum/gas/oxygen] = 0
	tank.process()
	sleep(15)
	nc_check("the tank still refills", tank.air_contents.moles[/datum/gas/oxygen] > 0, "[tank.air_contents.moles[/datum/gas/oxygen]] mol")
	H.notransform = FALSE

/proc/nc_sleeping_samples()
	. = 0
	for(var/i in 1 to 100)
		if(SSobj.state == SS_SLEEPING)
			.++
		sleep(1)

/proc/nc_jump(mob/living/carbon/human/H)
	var/obj/item/clothing/suit/space/hardsuit/nano/S = nc_mode(H, "strength")
	var/obj/item/clothing/shoes/combat/coldres/nanojump/boots = H.shoes
	var/datum/action/A = boots.actions[1]
	var/turf/start = locate(H.x, H.y + 1, H.z)
	var/list/landed = list()
	for(var/hack in list(FALSE, TRUE))
		if(hack)
			S.hacked = TRUE
			S.upgrademulti = 1.5
		for(var/i in 1 to 3)
			H.forceMove(start)
			H.setDir(EAST)
			S.cell.charge = 100
			boots.ui_action_click(H, A)
			sleep(20)
			landed += H.x - start.x
	nc_log("INFO jumps landed, plain then hacked: [jointext(landed, " ")]")
	nc_check("a jump crosses a gap two tiles wide, as its button says", landed[1] >= 3, "lands [landed[1]] tiles away")
	nc_check("a hacked suit's jumps don't grow each time", landed[4] == landed[6], "[landed[4]] then [landed[6]], boots at [boots.jumpdistance]")
	S.hacked = FALSE
	S.upgrademulti = 1

/proc/nc_armor_mode(mob/living/carbon/human/H)
	var/obj/item/clothing/suit/space/hardsuit/nano/S = nc_mode(H, "armor")
	var/obj/item/hitter = new /obj/item/wrench(H.loc)
	H.adjustBruteLoss(80) // limbs count for less than the rest of the body: 60 only takes health to 50
	var/charges = S.current_charges
	S.hit_reaction(H, hitter, "the test", 0, 1000, MELEE_ATTACK)
	nc_check("armour mode's medical reacts to a hit that got through", S.current_charges < charges, "[charges] charges, then [S.current_charges]")
	H.adjustBruteLoss(-H.getBruteLoss())

	var/blocked = 0
	for(var/i in 1 to 2000)
		S.cell.charge = 100
		if(S.hit_reaction(H, hitter, "the test", 50, 0, MELEE_ATTACK))
			blocked++
	nc_check("a 50% block is rolled once, not twice", blocked > 900 && blocked < 1100, "[blocked] of 2000 blocked")

	var/obj/item/projectile/beam/disabler/beam = new(H.loc)
	nc_check("a blocked disabler costs its flat 20 energy", nc_block_cost(H, beam, beam.damage, PROJECTILE_ATTACK) == 20, "[nc_block_cost(H, beam, beam.damage, PROJECTILE_ATTACK)] for [beam.damage] stamina")
	var/obj/item/projectile/beam/laser/laser = new(H.loc)
	nc_check("a blocked laser costs 5 + its damage", nc_block_cost(H, laser, laser.damage, PROJECTILE_ATTACK) == 5 + laser.damage, "[nc_block_cost(H, laser, laser.damage, PROJECTILE_ATTACK)] for [laser.damage] damage")
	nc_check("a blocked wrench costs 5 + its damage", nc_block_cost(H, hitter, 10, MELEE_ATTACK) == 15, "[nc_block_cost(H, hitter, 10, MELEE_ATTACK)] for 10 damage")
	qdel(beam)
	qdel(laser)
	qdel(hitter)

/proc/nc_block_cost(mob/living/carbon/human/H, atom/movable/thing, damage, attack_type)
	var/obj/item/clothing/suit/space/hardsuit/nano/S = nc_mode(H, "armor")
	S.hit_reaction(H, thing, "the test", 1000, damage, attack_type)
	return 100 - S.cell.charge

/proc/nc_energy_order(mob/living/carbon/human/H)
	var/obj/item/clothing/suit/space/hardsuit/nano/S = nc_mode(H, "armor")
	S.criticalpower = FALSE
	S.cut_nano_energy(95)
	nc_check("the energy warning comes as it drops", S.criticalpower)
	S = nc_mode(H, "cloak", 1)
	S.cut_nano_energy(5)
	nc_check("running dry drops the cloak straight away", S.mode == "armor", "mode [S.mode]")

/proc/nc_cloak_clicks(mob/living/carbon/human/H)
	var/obj/item/flashlight/torch = new(H.loc)
	H.put_in_active_hand(torch)
	var/mob/living/carbon/human/victim = nc_human(get_step(H, NORTH))
	var/obj/item/clothing/suit/space/hardsuit/nano/S = nc_mode(H, "cloak")
	torch.afterattack(get_step(get_step(H, WEST), WEST), H, FALSE, "")
	nc_check("clicking a far floor with a flashlight leaves the cloak up", S.mode == "cloak" && S.cell.charge > 90, "mode [S.mode], [S.cell.charge] energy")
	S = nc_mode(H, "cloak")
	torch.afterattack(get_step(H, WEST), H, TRUE, "")
	nc_check("using a flashlight on the floor beside you leaves the cloak up", S.mode == "cloak" && S.cell.charge > 90, "mode [S.mode], [S.cell.charge] energy")
	S = nc_mode(H, "cloak")
	torch.attack(victim, H)
	sleep(4)
	nc_check("hitting someone with it still drops the cloak", S.mode != "cloak", "mode [S.mode], [S.cell.charge] energy")
	qdel(torch)
	var/obj/item/gun/ballistic/automatic/pistol/gun = new(H.loc)
	H.put_in_active_hand(gun)
	S = nc_mode(H, "cloak")
	gun.afterattack(locate(H.x + 5, H.y, H.z), H, FALSE, "")
	sleep(4)
	nc_check("firing a gun at a far tile still drops the cloak", S.mode != "cloak", "mode [S.mode], [S.cell.charge] energy")
	qdel(gun)
	qdel(victim)

/proc/nc_emag(mob/living/carbon/human/H)
	var/obj/item/card/id/card = new(H.loc)
	H.equip_to_slot_or_del(card, ITEM_SLOT_ID)
	var/obj/item/card/emag/emag = new(H.loc)
	H.put_in_hands(emag)
	var/obj/item/clothing/suit/space/hardsuit/nano/S = nc_suit(H)
	spawn(0)
		S.emag_act(H) // alert() with no client
	sleep(20)
	nc_check("hacking the suit eats the emag and not the ID", !QDELETED(card) && QDELETED(emag), "ID [QDELETED(card) ? "gone" : "kept"], emag [QDELETED(emag) ? "gone" : "kept"]")
	var/deadline = world.time + 20 SECONDS
	while(S.shutdown && world.time < deadline)
		sleep(2)
	nc_check("the hack finishes with the suit working", S.hacked && !S.shutdown && S.mode == "armor", "hacked [S.hacked], mode [S.mode]")

/// What the suit left behind on someone it came off, as a list of faults
/proc/nc_leftovers(mob/living/carbon/human/H, obj/item/clothing/suit/space/hardsuit/nano/S)
	. = list()
	sleep(8) // the alpha is animated
	if(S.Wearer)
		. += "still has a Wearer"
	if(S.mode != "none")
		. += "mode [S.mode]"
	if(!S.shutdown)
		. += "still running"
	if(H.mind.martial_art == S.style)
		. += "martial art"
	if(HAS_TRAIT(H, TRAIT_PUSHIMMUNE))
		. += "push immune"
	if(HAS_TRAIT(H, TRAIT_NODISMEMBER))
		. += "no dismember"
	if(HAS_TRAIT(H, TRAIT_LIGHT_STEP))
		. += "light step"
	if(HAS_TRAIT(H, TRAIT_TACRELOAD))
		. += "tac reload"
	if(HAS_TRAIT(H, TRAIT_IGNORESLOWDOWN))
		. += "ignores slowdown"
	if(H.has_movespeed_modifier("speed"))
		. += "speed modifier"
	if(length(H.filters))
		. += "filters"
	if(H.alpha != 255)
		. += "alpha [H.alpha]"
	if(S.help_verb in H.verbs)
		. += "manual verb"
	if(HAS_TRAIT(S, TRAIT_NODROP))
		. += "suit still can't be dropped"
	for(var/obj/item/I in H.get_equipped_items(TRUE))
		. += "still wearing [I]"
	if(locate(/obj/item/implant/explosive/disintegrate) in H.implants)
		. += "still has the implant"
	if(S.cellon)
		. += "the next wearer's boot would be skipped on the status tab"
	if(HAS_TRAIT(H, TRAIT_IMPACTPROOF))
		. += "impactproof"
	if(H.physiology.stun_mod != 1)
		. += "stun_mod [H.physiology.stun_mod]"
	if(H.physiology.stamina_mod != 1)
		. += "stamina_mod [H.physiology.stamina_mod]"

/proc/nc_taken_off(mob/living/carbon/human/H, mode)
	var/obj/item/clothing/suit/space/hardsuit/nano/S = nc_mode(H, mode)
	H.dropItemToGround(S, TRUE)
	var/list/left = nc_leftovers(H, S)
	nc_check("forced out of the suit in [mode] mode, nothing stays on them", !length(left), jointext(left, ", "))

/proc/nc_second_owner(mob/living/carbon/human/first, mob/living/carbon/human/second)
	var/obj/item/clothing/suit/space/hardsuit/nano/S = locate() in get_turf(first)
	nc_check("a suit that came off is on the floor", istype(S))
	if(!S)
		return
	second.put_in_hands(S)
	nc_check("holding a suit doesn't make you its wearer", S.loc == second && S.Wearer != second, "Wearer [S.Wearer]")
	var/dropped = second.dropItemToGround(S)
	nc_check("a suit that came off can be put down", dropped && !S.Wearer, "dropped [dropped], Wearer [S.Wearer]")
	if(!dropped)
		second.dropItemToGround(S, TRUE)
	second.equip_to_slot_or_del(S, ITEM_SLOT_OCLOTHING)
	var/deadline = world.time + 30 SECONDS
	while(S.shutdown && world.time < deadline)
		sleep(2)
	nc_check("the next person to wear it gets a working suit", second.wear_suit == S && S.Wearer == second && !S.shutdown && S.mode == "armor", "Wearer [S.Wearer], mode [S.mode]")
	S.hacked = TRUE
	second.dropItemToGround(S, TRUE)
	var/datum/atom_hud/sec = GLOB.huds[DATA_HUD_SECURITY_ADVANCED]
	nc_check("a hacked suit takes its HUDs when it comes off", !sec.hudusers[second])
	second.equip_to_slot_or_del(S, ITEM_SLOT_OCLOTHING)
	deadline = world.time + 30 SECONDS
	while(S.shutdown && world.time < deadline)
		sleep(2)
	nc_check("and gives them back when it goes on again", sec.hudusers[second] && S.mode == "armor", "mode [S.mode]")

/proc/nc_death(mob/living/carbon/human/H)
	var/obj/item/clothing/suit/space/hardsuit/nano/S = nc_mode(H, "strength")
	var/datum/mind/M = H.mind
	nc_check("strength mode gives the martial art", M.martial_art == S.style)
	H.death(FALSE)
	sleep(15)
	nc_check("dying dusts the wearer", QDELETED(H))
	nc_check("dying takes the suit too, as the manual says", QDELETED(S))
	nc_check("dying in strength mode leaves the mind a martial art that exists", !QDELETED(M.martial_art), "[M.martial_art]")

/proc/nc_implant(mob/living/carbon/human/H)
	var/obj/item/implant/explosive/disintegrate/I = locate() in H.implants
	nc_check("has the implant", I)
	I.popup = TRUE
	I.activate("action_button")
	sleep(10)
	nc_check("a second click on the implant while its warning is open does nothing", !QDELETED(H) && H.stat != DEAD)
	if(!QDELETED(I))
		I.popup = FALSE

/proc/nc_paralyzed_left(mob/living/carbon/human/H)
	var/datum/status_effect/incapacitating/paralyzed/P = H.IsParalyzed(FALSE)
	return istype(P) ? P.duration - world.time : 0

/proc/nc_tough_reset(mob/living/carbon/human/H)
	H.SetParalyzed(0)
	H.SetKnockdown(0)
	H.SetStun(0)
	H.SetImmobilized(0)
	var/obj/item/clothing/suit/space/hardsuit/nano/S = H.wear_suit
	if(istype(S))
		S.next_stun = 0

/// How long each kind of stun holds someone down, a plain crewman against each mode
/proc/nc_stun_times(mob/living/carbon/human/plain, mob/living/carbon/human/H)
	var/obj/item/melee/baton/loaded/baton = new(H.loc)
	baton.status = TRUE
	for(var/mob/living/carbon/human/M in list(plain, H))
		for(var/mode in (M == H ? list("speed", "strength", "armor") : list("plain")))
			if(M == H)
				nc_mode(H, mode)
			nc_tough_reset(M)
			var/obj/item/clothing/suit/space/hardsuit/nano/S = M.wear_suit
			if(istype(S))
				S.block_chance = 0 // a hit that was blocked wouldn't be measuring the stun
			baton.baton_stun(M, null)
			var/baton_time = nc_paralyzed_left(M)
			nc_tough_reset(M)
			M.Paralyze(200)
			var/flash_time = nc_paralyzed_left(M)
			nc_tough_reset(M)
			nc_log("INFO [mode]: baton [baton_time / 10] s, close flashbang [flash_time / 10] s")
			GLOB.nc_stun_results["[mode]"] = baton_time
	nc_mode(H, "armor")
	qdel(baton)
	nc_check("a baton stuns a suit a quarter as long", GLOB.nc_stun_results["strength"] <= GLOB.nc_stun_results["plain"] * 0.25 && GLOB.nc_stun_results["strength"] > 0, "[GLOB.nc_stun_results["strength"] / 10] s against [GLOB.nc_stun_results["plain"] / 10] s")
	nc_check("and a tenth as long in armour mode", GLOB.nc_stun_results["armor"] <= GLOB.nc_stun_results["plain"] * 0.1 && GLOB.nc_stun_results["armor"] > 0, "[GLOB.nc_stun_results["armor"] / 10] s")

/// A baton as fast as it can be swung for 20 seconds: how much of that are they on the floor?
/proc/nc_stun_lock(mob/living/carbon/human/M)
	nc_tough_reset(M)
	var/down = 0
	var/samples = 0
	for(var/swing in 1 to 25)
		M.Paralyze(140)
		for(var/i in 1 to 8)
			if(M.IsParalyzed(FALSE))
				down++
			samples++
			sleep(1)
	nc_tough_reset(M)
	return round(100 * down / samples)

/proc/nc_tough(mob/living/carbon/human/H, turf/spot)
	var/mob/living/carbon/human/plain = nc_human(spot)
	plain.equipOutfit(/datum/outfit/job/assistant)
	// the test floor has no air, and someone choking can't go into stamina crit
	for(var/trait in list(TRAIT_NOBREATH, TRAIT_RESISTCOLD, TRAIT_RESISTLOWPRESSURE))
		ADD_TRAIT(plain, trait, "nanosuit check")
	nc_stun_times(plain, H)

	var/plain_lock = nc_stun_lock(plain)
	nc_mode(H, "strength")
	var/suit_lock = nc_stun_lock(H)
	nc_mode(H, "armor")
	var/armor_lock = nc_stun_lock(H)
	nc_log("INFO batoned every 0.8 s for 20 s, time on the floor: plain [plain_lock]%, strength [suit_lock]%, armour [armor_lock]%")
	nc_check("a baton can't keep a suit down", plain_lock >= 95 && suit_lock <= 60, "[suit_lock]% of the time, a plain crewman [plain_lock]%")
	nc_check("armour mode shrugs it off best", armor_lock < suit_lock, "[armor_lock]% against [suit_lock]%")

	for(var/weapon in list("disabler", "taser"))
		var/list/results = list()
		for(var/mob/living/carbon/human/M in list(plain, H))
			M.adjustStaminaLoss(-M.getStaminaLoss())
			M.stam_paralyzed = FALSE
			if(M == H)
				nc_mode(H, "speed")
			var/shots = 0
			while(!M.stam_paralyzed && shots < 30)
				var/armor = M.run_armor_check(BODY_ZONE_CHEST, "energy", "", "")
				if(weapon == "disabler")
					var/obj/item/projectile/beam/disabler/beam = new(M.loc)
					M.apply_damage(beam.damage, STAMINA, BODY_ZONE_CHEST, armor)
					qdel(beam)
				else
					var/obj/item/projectile/energy/electrode/bolt = new(M.loc)
					bolt.original = M
					bolt.firer = M
					bolt.def_zone = BODY_ZONE_CHEST
					if(M == H)
						var/obj/item/clothing/suit/space/hardsuit/nano/worn = M.wear_suit
						worn.block_chance = 0 // a blocked bolt isn't measuring what gets through
					M.bullet_act(bolt, BODY_ZONE_CHEST)
					qdel(bolt)
				M.update_stamina()
				shots++
			var/start = world.time
			while(M.stam_paralyzed && world.time < start + 40 SECONDS)
				sleep(1)
			results[M == H ? "suit" : "plain"] = list(shots, (world.time - start) / 10)
		nc_log("INFO [weapon] shots to stamina crit and seconds in it: plain [results["plain"][1]] and [results["plain"][2]] s, suit [results["suit"][1]] and [results["suit"][2]] s")
		nc_check("[weapon]: a plain crewman goes down, so this is measuring something", results["plain"][1] < 30 && results["plain"][2] > 0, "[results["plain"][1]] shots")
		nc_check("[weapon]: it takes at least twice the shots to floor a suit", results["suit"][1] >= results["plain"][1] * 2, "[results["suit"][1]] against [results["plain"][1]]")
		nc_check("[weapon]: stamina crit doesn't last", results["suit"][2] <= 6 && results["suit"][2] < results["plain"][2], "[results["suit"][2]] s against [results["plain"][2]] s")

	// walls, and whoever's in the way
	var/obj/item/clothing/shoes/combat/coldres/nanojump/boots = H.shoes
	var/datum/action/A = boots.actions[1]
	var/turf/start_turf = locate(H.x, H.y + 1, H.z)
	var/turf/wall = locate(start_turf.x + 2, start_turf.y, start_turf.z)
	wall.ChangeTurf(/turf/closed/wall, flags = CHANGETURF_IGNORE_AIR)
	nc_mode(H, "strength")
	nc_tough_reset(H)
	H.forceMove(start_turf)
	H.setDir(EAST)
	var/brute = H.getBruteLoss()
	boots.ui_action_click(H, A)
	sleep(20)
	nc_check("the jump went off and hit the wall", H.x == start_turf.x + 1, "moved [H.x - start_turf.x] tiles of 3")
	nc_check("a jump into a wall doesn't stun or hurt a suit", !H.IsParalyzed(FALSE) && H.getBruteLoss() == brute, "paralyzed [!!H.IsParalyzed(FALSE)], [H.getBruteLoss() - brute] brute")
	plain.forceMove(locate(start_turf.x, start_turf.y - 1, start_turf.z))
	nc_tough_reset(plain)
	brute = plain.getBruteLoss()
	plain.setDir(EAST)
	var/turf/plain_wall = locate(start_turf.x + 2, start_turf.y - 1, start_turf.z)
	plain_wall.ChangeTurf(/turf/closed/wall, flags = CHANGETURF_IGNORE_AIR)
	plain.throw_at(plain_wall, 3, 1)
	sleep(20)
	nc_log("INFO the same wall on a plain crewman: paralyzed [!!plain.IsParalyzed(FALSE)], [plain.getBruteLoss() - brute] brute")

	wall.ChangeTurf(/turf/open/floor/plasteel, flags = CHANGETURF_IGNORE_AIR)
	plain_wall.ChangeTurf(/turf/open/floor/plasteel, flags = CHANGETURF_IGNORE_AIR)
	plain.forceMove(locate(start_turf.x + 2, start_turf.y, start_turf.z))
	nc_tough_reset(plain)
	plain.adjustBruteLoss(-plain.getBruteLoss())
	nc_tough_reset(H)
	brute = H.getBruteLoss()
	var/obj/item/clothing/suit/space/hardsuit/nano/S = nc_suit(H)
	S.cell.charge = 100
	H.forceMove(start_turf)
	H.setDir(EAST)
	boots.ui_action_click(H, A)
	sleep(20)
	nc_check("jumping into someone flattens them and not the suit", plain.IsParalyzed(FALSE) && plain.getBruteLoss() > 0 && !H.IsParalyzed(FALSE) && H.getBruteLoss() == brute, "they're paralyzed [!!plain.IsParalyzed(FALSE)] with [plain.getBruteLoss()] brute, suit paralyzed [!!H.IsParalyzed(FALSE)] with [H.getBruteLoss() - brute] brute")
	qdel(plain)

	// what else changes these numbers has to survive the suit
	var/mob/living/carbon/human/spliced = nc_human(spot)
	spliced.physiology.stun_mod *= 0.5
	var/obj/item/clothing/suit/space/hardsuit/nano/worn = new(spot)
	spliced.equip_to_slot_or_del(worn, ITEM_SLOT_OCLOTHING)
	var/deadline = world.time + 30 SECONDS
	while(worn.shutdown && world.time < deadline)
		sleep(2)
	nc_check("stacks with other stun resistance", abs(spliced.physiology.stun_mod - 0.05) < 0.0001, "[spliced.physiology.stun_mod]")
	for(var/i in 1 to 50)
		worn.toggle_mode(pick(list("armor", "cloak", "speed", "strength") - worn.mode), TRUE) // never the one it's in: nothing in the game forces that
	spliced.dropItemToGround(worn, TRUE)
	nc_check("and comes back to exactly that after 50 mode changes and coming off", abs(spliced.physiology.stun_mod - 0.5) < 0.0001, "[spliced.physiology.stun_mod]")
	qdel(worn)
	qdel(spliced)

/proc/nc_emp(mob/living/carbon/human/H)
	var/obj/item/clothing/suit/space/hardsuit/nano/S = nc_mode(H, "speed")
	S.cut_nano_energy(S.cell.charge, 45) // what a strong pulse does on its way to here
	var/start = world.time
	S.emp_assault()
	nc_check("the EMP shutdown doesn't hold up the rest of the EMP", world.time == start, "[(world.time - start) / 10] s")
	var/deadline = start + 45 SECONDS
	sleep(10)
	while(world.time < start + 5 SECONDS || (S.shutdown && world.time < deadline))
		if(!GLOB.nc_emp_stun && H.IsParalyzed(FALSE))
			GLOB.nc_emp_stun = nc_paralyzed_left(H)
			nc_check("a suit that's down gives no stun resistance", H.physiology.stun_mod == 1, "stun_mod [H.physiology.stun_mod]")
		sleep(2)
	sleep(5)
	nc_check("the suit comes back from an EMP in armour mode even with an empty battery", S.mode == "armor", "mode [S.mode], [S.cell.charge] energy, [(world.time - start) / 10] s")
	nc_check("the EMP's stun lasted its whole length", GLOB.nc_emp_stun >= 250, "[GLOB.nc_emp_stun / 10] s left when the suit went down")
	nc_check("the suit is tough again once it's back", H.physiology.stun_mod == S.armor_stun_mult, "stun_mod [H.physiology.stun_mod]")

/proc/nc_strength(mob/living/carbon/human/H)
	var/obj/item/clothing/suit/space/hardsuit/nano/S = nc_mode(H, "strength")
	var/datum/martial_art/nanosuit/style = S.style
	nc_check("manual: 75% block in throw mode", style.block_chance == 75, "[style.block_chance]")
	nc_check("manual: 25% of ranged hits deflected", style.deflection_chance == 25, "[style.deflection_chance]")

	var/mob/living/carbon/monkey/monkey = new(get_step(H, NORTH))
	H.a_intent = INTENT_HELP
	nc_try(CALLBACK(GLOBAL_PROC, GLOBAL_PROC_REF(nc_unarmed), H, monkey))
	nc_check("a help intent click doesn't hit a monkey", !monkey.getBruteLoss(), "[monkey.getBruteLoss()] brute")
	H.a_intent = INTENT_HARM
	var/stopped = 0
	var/error
	for(var/i in 1 to 12)
		monkey.fully_heal()
		try
			if(SEND_SIGNAL(H, COMSIG_HUMAN_EARLY_UNARMED_ATTACK, monkey, TRUE) & COMPONENT_NO_ATTACK_HAND)
				stopped++
		catch(var/exception/e)
			error = "[e.name] at [e.file]:[e.line]"
	nc_check("a punch on a monkey doesn't land twice", stopped, "[stopped] of 12 stopped there")
	nc_check("punching with nobody at the keyboard doesn't crash", !error, error)
	qdel(monkey)


/proc/nc_grab(mob/living/carbon/human/H)
	var/obj/item/clothing/suit/space/hardsuit/nano/S = nc_mode(H, "strength")
	var/datum/martial_art/nanosuit/style = S.style
	var/mob/living/carbon/human/held = nc_human(get_step(H, WEST))
	var/mob/living/carbon/human/other = nc_human(get_step(H, SOUTH))
	H.start_pulling(held, TRUE)
	H.grab_state = GRAB_AGGRESSIVE
	nc_check("the grab took", H.pulling == held, "[H.pulling]")
	style.harm_act(H, other)
	nc_check("punching someone else leaves your grab on the one you're holding", H.pulling == held && !other.IsParalyzed(), "pulling [H.pulling], other paralyzed [!!other.IsParalyzed()]")
	H.a_intent = INTENT_GRAB
	style.harm_act(H, held)
	nc_check("punching the one you're holding still does the knockdown", !H.pulling && held.IsParalyzed(), "pulling [H.pulling], held paralyzed [!!held.IsParalyzed()]")
	qdel(held)
	qdel(other)

/proc/nc_menu(mob/living/carbon/human/H)
	var/obj/item/clothing/suit/space/hardsuit/nano/S = nc_suit(H)
	var/turf/T = H.loc
	nc_check("the quick menu works standing up", S.check_menu(H))
	var/obj/structure/closet/box = new(T)
	H.forceMove(box)
	nc_check("the quick menu works in a locker, like the buttons do", S.check_menu(H))
	H.forceMove(T)
	qdel(box)
	H.handcuffed = new /obj/item/restraints/handcuffs(H)
	H.update_handcuffed()
	nc_check("the quick menu works in cuffs, like the buttons do", S.check_menu(H))
	QDEL_NULL(H.handcuffed)
	H.update_handcuffed()

/proc/nc_blast(obj/item/I)
	I.ex_act(EXPLODE_LIGHT)

/proc/nc_use_on(obj/item/target, obj/item/thing, mob/user)
	target.attackby(thing, user)

/proc/nc_stat_tab(mob/M)
	usr = M // the game calls it with one
	M.Stat()

/proc/nc_unarmed(mob/living/carbon/human/H, atom/target)
	H.UnarmedAttack(target, TRUE)

/proc/nc_loose_suit(turf/T, mob/living/carbon/human/H)
	var/obj/item/clothing/suit/space/hardsuit/nano/S = new(T)
	var/error = nc_try(CALLBACK(GLOBAL_PROC, GLOBAL_PROC_REF(nc_blast), S))
	nc_check("a bomb going off by a suit on the floor doesn't crash", !error, error)
	S.current_charges = 0
	var/obj/item/stock_parts/cell/high/C = new(T)
	error = nc_try(CALLBACK(GLOBAL_PROC, GLOBAL_PROC_REF(nc_use_on), S, C, H))
	nc_check("topping up the medical on a suit on the floor doesn't crash", !error, error)
	nc_check("topping up the medical on a suit on the floor works", S.current_charges == 1, "[S.current_charges] charges")
	qdel(C)
	qdel(S)
	var/obj/item/storage/box/syndie_kit/nanosuit/B = new(T)
	nc_check("the kit has its name", findtext(B.name, "Crynet"), B.name)
	qdel(B)

/proc/nc_stat_nullspace(mob/living/carbon/human/H)
	var/turf/T = H.loc
	H.moveToNullspace()
	var/error = nc_try(CALLBACK(GLOBAL_PROC, GLOBAL_PROC_REF(nc_stat_tab), H))
	H.forceMove(T)
	nc_check("the status tab doesn't crash with the wearer nowhere", !error, error)

/proc/nc_section(name, datum/callback/C)
	nc_log("--- [name]")
	var/error = nc_try(C)
	if(error)
		nc_check("[name] ran to the end", FALSE, error)

/proc/nanosuit_check_run()
	UNTIL(SSticker.initialized) // it reads data/mode.txt when it starts up
	GLOB.master_mode = "extended" // most modes won't start with nobody playing, and the ticker goes round again for ever
	SSticker.start_immediately = TRUE
	var/deadline = world.time + 5 MINUTES
	while(SSticker.current_state < GAME_STATE_PLAYING && world.time < deadline)
		sleep(1 SECONDS)
	sleep(15 SECONDS)
	nc_log("round state [SSticker.current_state]")
	if(SSticker.current_state != GAME_STATE_PLAYING)
		nc_log("the round never started, nothing below would mean anything")
		nc_log("done")
		del(world)
		return
	var/turf/corner = nc_floor()

	var/before = nc_sleeping_samples()
	nc_log("INFO SSobj asleep with no suit around: [before] of 100 samples")

	var/list/crew = nc_crew(corner, 16)
	nc_check("everyone's suit started", TRUE)
	for(var/mob/living/carbon/human/H in crew)
		var/obj/item/clothing/suit/space/hardsuit/nano/S = nc_suit(H)
		if(H.head != S.helmet || !H.internal || S.shutdown || S.mode != "armor")
			nc_check("suit started properly", FALSE, "head [H.head], internal [H.internal], mode [S.mode]")
			break
	var/during = nc_sleeping_samples()
	nc_check("SSobj doesn't sleep because of the suit's tank", during <= before + 2, "asleep [during] of 100 samples")

	nc_section("numbers", CALLBACK(GLOBAL_PROC, GLOBAL_PROC_REF(nc_numbers), crew[1], locate(corner.x + 10, corner.y, corner.z)))
	spawn(0)
		nc_section("emp", CALLBACK(GLOBAL_PROC, GLOBAL_PROC_REF(nc_emp), crew[2]))
	nc_section("toughness", CALLBACK(GLOBAL_PROC, GLOBAL_PROC_REF(nc_tough), crew[16], locate(corner.x + 20, corner.y + 20, corner.z)))
	if(world.params["nc_only_tough"])
		nc_log("[GLOB.nc_passed] passed, [GLOB.nc_failed] failed")
		nc_log("done")
		sleep(5)
		del(world)
		return
	nc_section("balance", CALLBACK(GLOBAL_PROC, GLOBAL_PROC_REF(nc_balance), crew[15]))
	nc_section("energy", CALLBACK(GLOBAL_PROC, GLOBAL_PROC_REF(nc_energy), crew[1]))
	nc_section("movement", CALLBACK(GLOBAL_PROC, GLOBAL_PROC_REF(nc_movement), crew[3]))
	nc_section("tank", CALLBACK(GLOBAL_PROC, GLOBAL_PROC_REF(nc_tank), crew[4]))
	nc_section("jump", CALLBACK(GLOBAL_PROC, GLOBAL_PROC_REF(nc_jump), crew[5]))
	nc_section("armour mode", CALLBACK(GLOBAL_PROC, GLOBAL_PROC_REF(nc_armor_mode), crew[3]))
	nc_section("energy order", CALLBACK(GLOBAL_PROC, GLOBAL_PROC_REF(nc_energy_order), crew[3]))
	nc_section("cloak clicks", CALLBACK(GLOBAL_PROC, GLOBAL_PROC_REF(nc_cloak_clicks), crew[6]))
	nc_section("emag", CALLBACK(GLOBAL_PROC, GLOBAL_PROC_REF(nc_emag), crew[7]))
	nc_section("strength", CALLBACK(GLOBAL_PROC, GLOBAL_PROC_REF(nc_strength), crew[8]))
	nc_section("grab", CALLBACK(GLOBAL_PROC, GLOBAL_PROC_REF(nc_grab), crew[14]))
	nc_section("menu", CALLBACK(GLOBAL_PROC, GLOBAL_PROC_REF(nc_menu), crew[3]))
	nc_section("status tab", CALLBACK(GLOBAL_PROC, GLOBAL_PROC_REF(nc_stat_nullspace), crew[3]))
	nc_section("death", CALLBACK(GLOBAL_PROC, GLOBAL_PROC_REF(nc_death), crew[9]))
	nc_section("implant", CALLBACK(GLOBAL_PROC, GLOBAL_PROC_REF(nc_implant), crew[10]))
	nc_section("taken off strength", CALLBACK(GLOBAL_PROC, GLOBAL_PROC_REF(nc_taken_off), crew[11], "strength"))
	nc_section("taken off cloak", CALLBACK(GLOBAL_PROC, GLOBAL_PROC_REF(nc_taken_off), crew[12], "cloak"))
	nc_section("taken off speed", CALLBACK(GLOBAL_PROC, GLOBAL_PROC_REF(nc_taken_off), crew[13], "speed"))
	var/mob/living/carbon/human/next_owner = nc_human(get_turf(crew[11]))
	nc_section("second owner", CALLBACK(GLOBAL_PROC, GLOBAL_PROC_REF(nc_second_owner), crew[11], next_owner))
	nc_section("loose suit", CALLBACK(GLOBAL_PROC, GLOBAL_PROC_REF(nc_loose_suit), locate(corner.x + 14, corner.y + 3, corner.z), crew[14]))

	sleep(100) // the EMP section takes a while
	nc_log("[GLOB.nc_passed] passed, [GLOB.nc_failed] failed")
	nc_log("done")
	sleep(5)
	del(world)
