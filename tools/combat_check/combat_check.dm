// Whether the human combat and damage fixes of 2026-11-10 do what they say. Not part of the game: tools/combat_check/run.sh
// Headless, on a real round (testbench map). PASS or FAIL for each fix it can drive without a client, plus a few
// regressions (a plain weapon hit, a punch, a neck grab that follows its holder). Each test gets its own corner of an
// empty reserved floor, so a static discharge or a thrown star can't reach the next one.

/datum/controller/master
	sleep_offline_after_initializations = FALSE

GLOBAL_VAR_INIT(cc_passed, 0)
GLOBAL_VAR_INIT(cc_failed, 0)
GLOBAL_VAR(cc_corner)
GLOBAL_VAR_INIT(cc_next_spot, 0)

/proc/cc_log(text)
	text2file(text, "data/combat_check/results.txt")

/proc/cc_check(name, ok, detail)
	if(ok)
		GLOB.cc_passed++
	else
		GLOB.cc_failed++
	cc_log("[ok ? "PASS" : "FAIL"] [name][isnull(detail) ? "" : " ([detail])"]")

/world/New()
	. = ..()
	spawn(0)
		combat_check_run()

/proc/cc_floor()
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
	return locate(x0, y0, z)

/// The middle of the next free 9x9 square of the floor.
/proc/cc_spot()
	var/turf/C = GLOB.cc_corner
	var/i = GLOB.cc_next_spot++
	return locate(C.x + (i % 6) * 10 + 4, C.y + round(i / 6) * 10 + 4, C.z)

/proc/cc_human(turf/T)
	var/mob/living/carbon/human/H = new(T)
	H.mind_initialize()
	return H

/proc/cc_try(datum/callback/C)
	try
		C.Invoke()
	catch(var/exception/e)
		return "[e.name] at [e.file]:[e.line]"
	return null

/proc/cc_section(name, proc_name)
	cc_log("--- [name]")
	var/error = cc_try(CALLBACK(GLOBAL_PROC, proc_name))
	if(error)
		cc_check("[name] ran to the end", FALSE, error)

// ---- the tests

/proc/cc_monk()
	var/turf/T = cc_spot()
	var/mob/living/carbon/human/M = cc_human(T)
	var/mob/living/carbon/human/A = cc_human(get_step(T, EAST))
	var/datum/martial_art/monk/style = new
	style.teach(M)
	var/obj/item/storage/toolbox/mechanical/box = new(A.loc)
	A.put_in_active_hand(box)
	A.a_intent = INTENT_HARM
	A.zone_selected = BODY_ZONE_CHEST
	var/landed = 0
	for(var/i in 1 to 30)
		var/before = M.getBruteLoss()
		box.attack(M, A)
		if(M.getBruteLoss() > before)
			landed++
	cc_check("a monk takes damage from the weapon hits that get through", landed > 0, "[landed] of 30 hurt")

/proc/cc_nanites()
	var/mob/living/carbon/human/H = cc_human(cc_spot())
	H.AddComponent(/datum/component/nanites, 100)
	var/datum/component/nanites/N = H.GetComponent(/datum/component/nanites)
	H.electrocute_act(10, "a test wire", 1, TRUE)
	cc_check("a shock costs a human nanites", N && N.nanite_volume < 100, "[N?.nanite_volume] of 100 left")

/proc/cc_voltagel()
	var/turf/T = cc_spot()
	var/mob/living/carbon/human/H = cc_human(T)
	var/obj/item/reagent_containers/glass/beaker/large/B = new(T)
	B.reagents.add_reagent(/datum/reagent/voltagel, 10)
	B.reagents.add_reagent(/datum/reagent/water, 10)
	cc_check("a big static discharge burns (not stamina)", H.getFireLoss() > 0 && H.getStaminaLoss() == 0, "burn [H.getFireLoss()], stamina [H.getStaminaLoss()]")
	cc_check("a big static discharge stuns", H.IsParalyzed())
	var/turf/T2 = cc_spot()
	var/mob/living/carbon/human/H2 = cc_human(T2)
	var/obj/item/reagent_containers/glass/beaker/large/B2 = new(T2)
	B2.reagents.add_reagent(/datum/reagent/voltagel, 2)
	B2.reagents.add_reagent(/datum/reagent/water, 2)
	cc_check("a small static discharge burns", H2.getFireLoss() > 0, "burn [H2.getFireLoss()]")
	cc_check("a small static discharge doesn't stun", !H2.IsParalyzed())

/proc/cc_disarm_self()
	var/turf/T = cc_spot()
	var/mob/living/carbon/human/H = cc_human(T)
	var/obj/item/storage/toolbox/mechanical/box = new(T)
	H.put_in_active_hand(box)
	H.a_intent = INTENT_DISARM
	for(var/i in 1 to 40)
		H.dna.species.spec_attack_hand(H, H)
	cc_check("disarming yourself does nothing", !H.IsParalyzed() && H.get_active_held_item() == box)

/proc/cc_armor_zone()
	var/mob/living/carbon/human/H = cc_human(cc_spot())
	H.equip_to_slot_or_del(new /obj/item/clothing/suit/armor/bulletproof(H), ITEM_SLOT_OCLOTHING)
	var/wrong = 0
	for(var/i in 1 to 200)
		if(H.getarmor(BODY_ZONE_CHEST, "bullet") != 60)
			wrong++
	cc_check("a chest hit always reads the chest's armor", !wrong, "[wrong] of 200 read another limb")

/proc/cc_maxed_limb()
	var/mob/living/carbon/human/H = cc_human(cc_spot())
	var/obj/item/bodypart/L = H.get_bodypart(BODY_ZONE_L_LEG)
	L.receive_damage(L.max_damage, 0)
	H.apply_damage(30, STAMINA, BODY_ZONE_L_LEG)
	cc_check("a wrecked limb still takes stamina", L.stamina_dam > 0, "brute [L.brute_dam]/[L.max_damage], stamina [L.stamina_dam]")

/proc/cc_robot_head()
	var/turf/T = cc_spot()
	var/mob/living/carbon/human/H = cc_human(T)
	var/mob/living/carbon/human/A = cc_human(get_step(T, EAST))
	var/obj/item/bodypart/head/HD = H.get_bodypart(BODY_ZONE_HEAD)
	HD.name = "cyborg head" // what the name check tripped on
	var/obj/item/storage/toolbox/mechanical/box = new(A.loc)
	A.put_in_active_hand(box)
	A.a_intent = INTENT_HARM
	A.zone_selected = BODY_ZONE_HEAD
	for(var/i in 1 to 40)
		box.attack(H, A)
	cc_check("blunt hits to a head named otherwise still do brain damage", H.getBrainLoss() > 0, "brain [H.getBrainLoss()]")

/proc/cc_throw_zone()
	var/turf/T = cc_spot()
	var/mob/living/carbon/human/H = cc_human(T)
	var/mob/living/carbon/human/A = cc_human(get_step(T, EAST))
	A.zone_selected = BODY_ZONE_L_ARM
	var/in_arm = 0
	var/same_limb = 0
	var/trials = 20
	for(var/i in 1 to trials)
		H.fully_heal()
		var/obj/item/throwing_star/S = new(get_step(T, EAST))
		S.thrownby = A
		var/datum/thrownthing/TT = new
		TT.thrower = A
		TT.thrownthing = S
		TT.target = H
		TT.speed = 10
		H.hitby(S, FALSE, FALSE, throwingdatum = TT)
		for(var/X in H.bodyparts)
			var/obj/item/bodypart/BP = X
			if(S in BP.embedded_objects)
				if(BP.body_zone == BODY_ZONE_L_ARM)
					in_arm++
				if(BP.brute_dam > 0)
					same_limb++
				BP.embedded_objects -= S
		qdel(S)
	cc_check("a thrown star lands where it was aimed (80% like melee)", in_arm >= trials * 0.6, "[in_arm] of [trials] in the left arm")
	cc_check("it embeds in the limb it hurt", same_limb == trials, "[same_limb] of [trials]")

/proc/cc_emp_limb()
	var/mob/living/carbon/human/H = cc_human(cc_spot())
	var/obj/item/bodypart/l_arm/robot/R = new
	R.replace_limb(H, TRUE)
	H.emp_act(EMP_HEAVY)
	var/left = H.AmountParalyzed()
	cc_check("an EMP'd robotic limb stuns for about 5 s", left > 0 && left <= 60, "[left] ds")

/proc/cc_bleeding()
	var/mob/living/carbon/human/H = cc_human(cc_spot())
	var/obj/item/bodypart/l_arm/robot/R = new
	R.replace_limb(H, TRUE)
	R.receive_damage(30)
	H.bleed_rate = 0
	H.handle_blood()
	cc_check("a damaged prosthetic doesn't bleed", H.bleed_rate == 0, "bleed rate [H.bleed_rate]")
	var/mob/living/carbon/human/H2 = cc_human(cc_spot())
	var/obj/item/bodypart/L = H2.get_bodypart(BODY_ZONE_L_ARM)
	L.receive_damage(30)
	H2.bleed_rate = 0
	H2.handle_blood()
	cc_check("a damaged real arm still bleeds", H2.bleed_rate > 0, "bleed rate [H2.bleed_rate]")

/proc/cc_stamcrit()
	var/mob/living/carbon/human/H = cc_human(cc_spot())
	H.apply_damage(150, STAMINA, BODY_ZONE_CHEST)
	cc_check("stamina crit drops you the moment it lands", !(H.mobility_flags & MOBILITY_MOVE) && !(H.mobility_flags & MOBILITY_STAND), "stamina [H.getStaminaLoss()], stamcrit [H.stam_paralyzed], flags [H.mobility_flags]")

/proc/cc_baton()
	var/turf/T = cc_spot()
	var/mob/living/carbon/human/H = cc_human(T)
	var/mob/living/carbon/human/A = cc_human(get_step(T, EAST))
	var/obj/item/melee/baton/loaded/B = new(T)
	B.status = TRUE
	B.baton_stun(H, A)
	cc_check("a baton makes you stutter", H.stuttering > 0, "stuttering [H.stuttering]")

/proc/cc_carp()
	var/turf/T = cc_spot()
	var/mob/living/carbon/human/A = cc_human(T)
	var/mob/living/carbon/human/D = cc_human(get_step(T, EAST))
	var/datum/martial_art/the_sleeping_carp/C = new
	C.teach(A)
	var/obj/item/storage/toolbox/mechanical/box = new(D.loc)
	D.put_in_active_hand(box)
	C.wristWrench(A, D)
	cc_check("Wrist Wrench works on someone standing", !D.get_active_held_item() && D.IsStun())
	var/mob/living/carbon/human/reader = cc_human(get_step(T, NORTH))
	var/obj/item/book/granter/martial/carp/book = new(T)
	cc_check("someone without the art can read the carp book", !book.already_known(reader))

/proc/cc_cqc()
	var/turf/T = cc_spot()
	var/mob/living/carbon/human/A = cc_human(T)
	var/mob/living/carbon/human/D = cc_human(get_step(T, EAST))
	var/datum/martial_art/cqc/Q = new
	Q.teach(A)
	Q.add_to_streak("D", D)
	Q.add_to_streak("D", D)
	Q.harm_act(A, D)
	var/brute = D.getBruteLoss()
	cc_check("Consecutive CQC is one hit of 25, no extra punch", brute >= 24 && brute <= 26, "brute [brute]")
	var/mob/living/carbon/human/cook = cc_human(get_step(T, NORTH))
	var/datum/martial_art/cqc/under_siege/U = new
	U.teach(cook)
	cook.in_throw_mode = TRUE
	var/blocked = 0
	for(var/i in 1 to 30)
		if(cook.check_block())
			blocked++
	cc_check("the cook's CQC doesn't block outside the kitchen", !U.can_use(cook) && !blocked, "[blocked] of 30 blocked")

/proc/cc_armstrong()
	var/turf/T = cc_spot()
	var/mob/living/carbon/human/A = cc_human(T)
	var/mob/living/carbon/human/D = cc_human(get_step(T, EAST))
	var/datum/martial_art/armstrong/style = new
	style.teach(A)
	A.a_intent = INTENT_HELP
	A.dna.species.spec_attack_hand(A, A)
	cc_check("an Armstrong user checking themself doesn't punch themself", A.getBruteLoss() == 0, "brute [A.getBruteLoss()]")
	D.Paralyze(100)
	A.dna.species.spec_attack_hand(A, D)
	cc_check("an Armstrong user's help on someone down isn't a punch", D.getBruteLoss() == 0, "brute [D.getBruteLoss()]")

/proc/cc_elite_cqc()
	var/turf/T = cc_spot()
	var/mob/living/carbon/human/A = cc_human(T)
	var/mob/living/carbon/human/D = cc_human(get_step(T, EAST))
	var/datum/martial_art/elite_cqc/E = new
	E.teach(A)
	E.Gib(A, D)
	cc_check("Elite CQC stomps a living target instead of gibbing it", !QDELETED(D) && D.getBruteLoss() >= 80, "[QDELETED(D) ? "gibbed" : "brute [D.getBruteLoss()]"]")

/proc/cc_burst_lock()
	var/turf/T = cc_spot()
	var/mob/living/carbon/human/A = cc_human(T)
	var/obj/item/gun/ballistic/automatic/c20r/G = new(T)
	A.put_in_active_hand(G)
	ADD_TRAIT(A, TRAIT_PACIFISM, "combat_check")
	G.process_fire(locate(T.x + 3, T.y, T.z), A)
	sleep(2 SECONDS)
	cc_check("a burst gun a pacifist tried isn't locked for good", !G.firing_burst)

/proc/cc_kill_grab()
	var/turf/T = cc_spot()
	var/mob/living/carbon/human/A = cc_human(T)
	var/mob/living/carbon/human/D = cc_human(get_step(T, EAST))
	var/broke = 0
	for(var/i in 1 to 300)
		if(D.pulledby != A)
			A.start_pulling(D, supress_message = TRUE)
		A.grab_state = GRAB_KILL
		D.resist_grab()
		if(D.pulledby != A)
			broke++
	cc_check("a strangling grab can be broken now and then (~10%)", broke >= 10 && broke <= 60, "[broke] of 300")

/proc/cc_pin()
	var/turf/T = cc_spot()
	var/turf/W = get_step(T, EAST)
	W.ChangeTurf(/turf/closed/wall)
	W = get_step(T, EAST)
	var/mob/living/carbon/human/H = cc_human(T)
	var/mob/living/carbon/human/A = cc_human(get_step(T, WEST))
	var/obj/item/projectile/rod/P = new(T)
	P.dir = EAST
	P.def_zone = BODY_ZONE_CHEST
	P.firer = A
	P.Impale(H)
	cc_check("a fully drawn rod pins someone to the wall behind them", H.pinned_to == W && H.anchored)
	for(var/X in H.bodyparts) // the rod falls out, as embedded things do
		var/obj/item/bodypart/BP = X
		for(var/obj/item/I in BP.embedded_objects)
			BP.embedded_objects -= I
			I.forceMove(T)
	H.handle_status_effects()
	cc_check("once the rod's out they come off the wall", !H.pinned_to && !H.anchored && !W.pinned)

/proc/cc_dwarf()
	var/mob/living/carbon/human/H = cc_human(cc_spot())
	H.set_species(/datum/species/dwarf)
	H.reagents.add_reagent(/datum/reagent/consumable/ethanol/beer, 10)
	for(var/i in 1 to 5)
		H.reagents.metabolize(H, can_overdose = TRUE)
	var/left = H.reagents.get_reagent_amount(/datum/reagent/consumable/ethanol/beer)
	cc_check("a dwarf's drink gets used up", left < 10, "[left] of 10 left")

/proc/cc_butt()
	var/turf/T = cc_spot()
	var/mob/living/carbon/human/H = cc_human(T)
	var/mob/living/carbon/human/A = cc_human(get_step(T, EAST))
	var/obj/item/organ/butt/B = H.getorgan(/obj/item/organ/butt)
	if(B)
		B.Remove(H)
		qdel(B)
	A.zone_selected = BODY_ZONE_PRECISE_GROIN
	var/error = cc_try(CALLBACK(H, TYPE_PROC_REF(/mob/living/carbon/human, checkbuttinspect), A))
	cc_check("grabbing at the groin of someone with no butt doesn't error", !error, error)

/proc/cc_chest_godmode()
	var/mob/living/carbon/human/H = cc_human(cc_spot())
	H.status_flags |= GODMODE
	var/organs = length(H.internal_organs)
	var/obj/item/bodypart/chest/C = H.get_bodypart(BODY_ZONE_CHEST)
	C.dismember()
	cc_check("a godmode chest keeps its organs", length(H.internal_organs) == organs, "[length(H.internal_organs)] of [organs]")

/proc/cc_missing_limb_punch()
	var/turf/T = cc_spot()
	var/mob/living/carbon/human/A = cc_human(T)
	var/mob/living/carbon/human/D = cc_human(get_step(T, EAST))
	var/obj/item/bodypart/arm = D.get_bodypart(BODY_ZONE_L_ARM)
	arm.drop_limb()
	A.a_intent = INTENT_HARM
	A.zone_selected = BODY_ZONE_L_ARM
	var/landed = 0
	for(var/i in 1 to 20)
		var/before = D.getBruteLoss()
		A.dna.species.harm(A, D, null)
		if(D.getBruteLoss() > before)
			landed++
	cc_check("punches at a missing arm land on the chest", landed >= 12, "[landed] of 20 landed")

/proc/cc_bat()
	var/turf/T = cc_spot()
	var/mob/living/carbon/human/A = cc_human(T)
	var/mob/living/carbon/human/D = cc_human(get_step(T, EAST))
	var/mob/living/carbon/human/D2 = cc_human(get_step(T, NORTH))
	D.equip_to_slot_or_del(new /obj/item/clothing/head/helmet(D), ITEM_SLOT_HEAD)
	var/obj/item/melee/baseball_bat/bat = new(T)
	A.put_in_active_hand(bat)
	bat.do_special_attack(D, A, TRUE)
	bat.do_special_attack(D2, A, TRUE)
	cc_check("a helmet softens Head Bash", D.getBrainLoss() > 0 && D.getBrainLoss() < D2.getBrainLoss(), "helmet [D.getBrainLoss()], bare [D2.getBrainLoss()]")

// ---- what has to still work

/proc/cc_regressions()
	var/turf/T = cc_spot()
	var/mob/living/carbon/human/A = cc_human(T)
	var/mob/living/carbon/human/D = cc_human(get_step(T, EAST))
	var/obj/item/storage/toolbox/mechanical/box = new(T)
	A.put_in_active_hand(box)
	A.a_intent = INTENT_HARM
	A.zone_selected = BODY_ZONE_CHEST
	for(var/i in 1 to 5)
		box.attack(D, A)
	cc_check("a toolbox still hurts an ordinary human", D.getBruteLoss() >= 30, "brute [D.getBruteLoss()]")

	var/turf/T2 = cc_spot()
	var/mob/living/carbon/human/G = cc_human(T2)
	var/mob/living/carbon/human/V = cc_human(get_step(T2, EAST))
	G.a_intent = INTENT_GRAB
	G.start_pulling(V, supress_message = TRUE)
	V.grippedby(G, TRUE)
	V.grippedby(G, TRUE)
	cc_check("a neck grab still lands", G.pulling == V && G.grab_state == GRAB_NECK, "state [G.grab_state]")
	for(var/i in 1 to 3)
		G.Move(get_step(G, NORTH), NORTH)
		sleep(2)
	cc_check("a neck-grabbed victim still goes along with the holder", G.pulling == V && get_dist(G, V) <= 1, "pulling [G.pulling], distance [get_dist(G, V)]")

/proc/combat_check_run()
	UNTIL(SSticker.initialized)
	GLOB.master_mode = "extended"
	SSticker.start_immediately = TRUE
	var/deadline = world.time + 5 MINUTES
	while(SSticker.current_state < GAME_STATE_PLAYING && world.time < deadline)
		sleep(1 SECONDS)
	sleep(5 SECONDS)
	cc_log("round state [SSticker.current_state]")
	if(SSticker.current_state != GAME_STATE_PLAYING)
		cc_log("the round never started")
		cc_log("done")
		del(world)
		return
	GLOB.cc_corner = cc_floor()
	cc_section("monk", /proc/cc_monk)
	cc_section("nanites", /proc/cc_nanites)
	cc_section("voltagel", /proc/cc_voltagel)
	cc_section("disarm self", /proc/cc_disarm_self)
	cc_section("armor zone", /proc/cc_armor_zone)
	cc_section("maxed limb", /proc/cc_maxed_limb)
	cc_section("robot head", /proc/cc_robot_head)
	cc_section("throw zone", /proc/cc_throw_zone)
	cc_section("emp limb", /proc/cc_emp_limb)
	cc_section("bleeding", /proc/cc_bleeding)
	cc_section("stamcrit", /proc/cc_stamcrit)
	cc_section("baton", /proc/cc_baton)
	cc_section("carp", /proc/cc_carp)
	cc_section("cqc", /proc/cc_cqc)
	cc_section("armstrong", /proc/cc_armstrong)
	cc_section("elite cqc", /proc/cc_elite_cqc)
	cc_section("burst lock", /proc/cc_burst_lock)
	cc_section("kill grab", /proc/cc_kill_grab)
	cc_section("pin", /proc/cc_pin)
	cc_section("dwarf", /proc/cc_dwarf)
	cc_section("butt", /proc/cc_butt)
	cc_section("chest godmode", /proc/cc_chest_godmode)
	cc_section("missing limb punch", /proc/cc_missing_limb_punch)
	cc_section("bat", /proc/cc_bat)
	cc_section("regressions", /proc/cc_regressions)
	cc_log("[GLOB.cc_passed] passed, [GLOB.cc_failed] failed")
	cc_log("done")
	sleep(5)
	del(world)
