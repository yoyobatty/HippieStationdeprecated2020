// Medical-role behavior: a bot doing the Doctor/CMO job notices injured crew while
// wandering and goes to patch them up with whatever's in its first aid kit, instead of
// only ever reacting when it personally gets attacked. Deliberately scoped to actual
// medical jobs, not every bot - a cargo tech stopping to bandage someone would look
// stranger than just leaving it to the people who signed up for it.
/datum/bot_brain/proc/is_medical_job()
	var/role = owner.mind?.assigned_role
	return role == "Medical Doctor" || role == "Chief Medical Officer"

// Same brute/burn thresholds as a real player would bother stopping for - scrapes and
// bruises get walked past, anything that'll actually kill them eventually doesn't.
/datum/bot_brain/proc/patient_needs_treatment(mob/living/carbon/human/H)
	if(H.stat == DEAD)
		return FALSE
	if(H.getBruteLoss() > 10 || H.getFireLoss() > 10)
		return TRUE
	if(H.stat == SOFT_CRIT || H.stat == UNCONSCIOUS)
		return TRUE
	return FALSE

/datum/bot_brain/proc/patient_injury_score(mob/living/carbon/human/H)
	. = H.getBruteLoss() + H.getFireLoss()
	if(H.stat != CONSCIOUS)
		. += 30

// Every /obj/item/stack/medical the bot is carrying, wherever it's stowed (hand, belt,
// first aid kit, backpack) - GetAllContents() walks nested storage same as a player
// digging through their own kit.
/datum/bot_brain/proc/get_medical_supplies()
	return owner.GetAllContents(/obj/item/stack/medical)

// Picks whichever supply matches the patient's WORSE damage type first (a burn victim
// gets ointment before a bruise pack, and vice versa) - same instinct a real doctor
// triaging at a glance would use, rather than blindly grabbing whatever's first in the kit.
/datum/bot_brain/proc/pick_treatment_item(mob/living/carbon/human/patient)
	var/list/supplies = get_medical_supplies()
	if(!supplies.len)
		return null
	var/burn_first = patient.getFireLoss() > patient.getBruteLoss()
	var/obj/item/stack/medical/bruise_pack/brute_pick
	var/obj/item/stack/medical/ointment/burn_pick
	for(var/obj/item/stack/medical/M in supplies)
		if(!M.get_amount())
			continue
		if(istype(M, /obj/item/stack/medical/bruise_pack) && !brute_pick)
			brute_pick = M
		else if(istype(M, /obj/item/stack/medical/ointment) && !burn_pick)
			burn_pick = M
	if(burn_first)
		return burn_pick || brute_pick
	return brute_pick || burn_pick

// Sent out for more once the current kit runs dry - tries a whole spare first aid kit
// first (any /obj/item/storage/firstaid subtype, wherever one's sitting unattended),
// then falls back to loose bruise packs/ointment directly. Reuses the same generic
// acquire_item_type goal every personal-objective fetch already uses (goals/
// acquire_item_type.dm) via suspend_goal_for() - same suspend/resume dance
// ensure_wrench/ensure_tools use for tools, just for medical supplies instead.
/datum/bot_brain/proc/restock_medical_supplies()
	for(var/wanted_type in list(/obj/item/storage/firstaid, /obj/item/stack/medical/bruise_pack, /obj/item/stack/medical/ointment))
		var/datum/bot_goal/acquire_item_type/sub = new()
		sub.item_type = wanted_type
		if(suspend_goal_for(sub))
			return TRUE
	return FALSE

// Aims at whichever organic limb is currently worst off, instead of always healing
// whatever zone_selected happened to be left on from the last click - heal_carbon()
// (stacks/medical.dm) only ever treats the single currently-selected zone.
/datum/bot_brain/proc/aim_at_worst_wound(mob/living/carbon/human/patient)
	var/obj/item/bodypart/worst
	var/worst_damage = 0
	for(var/obj/item/bodypart/B in patient.bodyparts)
		if(B.status != BODYPART_ORGANIC)
			continue
		var/dam = B.brute_dam + B.burn_dam
		if(dam > worst_damage)
			worst_damage = dam
			worst = B
	if(worst)
		owner.zone_selected = worst.body_zone

/datum/bot_goal/treat_patient/resolve_target(datum/bot_brain/bot)
	var/mob/living/carbon/human/best
	var/best_score
	for(var/mob/living/carbon/human/H in GLOB.alive_mob_list)
		if(H == bot.owner || H.z != bot.owner.z)
			continue
		if(H.stat != CONSCIOUS) //crit/unconscious goes to escort_to_sleeper instead - dragging someone in for a scrape is overkill, but a downed patient needs more than a bandage
			continue
		if(!bot.patient_needs_treatment(H))
			continue
		if(get_dist(bot.owner, H) > 40)
			continue
		var/score = bot.patient_injury_score(H) - get_dist(bot.owner, H)
		if(!best || score > best_score)
			best = H
			best_score = score
	target = best

/datum/bot_goal/treat_patient/get_strategies(datum/bot_brain/bot)
	return list(new /datum/bot_strategy/treat())

/datum/bot_goal/treat_patient/on_success(datum/bot_brain/bot)
	bot.continue_medical_round()

/datum/bot_strategy/treat/New()
	. = ..()
	steps = list(new /datum/bot_step/move_to(), new /datum/bot_step/treat_patient())

/datum/bot_strategy/treat/is_feasible(datum/bot_brain/bot)
	return TRUE

/datum/bot_step/treat_patient
	// One-shot per strategy attempt, same idea as ensure_wrench's tried_fetch - a
	// station with nothing left to restock from shouldn't burn a fresh suspend cycle
	// (goal_suspend_count) on every single re-check while still treating this patient.
	var/tried_restock = FALSE

/datum/bot_step/treat_patient/execute(datum/bot_brain/bot)
	var/mob/living/carbon/human/patient = bot.current_goal?.target
	if(!istype(patient) || QDELETED(patient) || !bot.patient_needs_treatment(patient))
		return GOAL_STEP_SUCCESS //nothing left to do - either treated already or beyond help
	if(!bot.owner.Adjacent(patient))
		return GOAL_STEP_FAIL
	var/obj/item/I = bot.pick_treatment_item(patient)
	if(!I)
		if(!tried_restock)
			tried_restock = TRUE
			if(bot.restock_medical_supplies())
				bot_log(bot, "out of medical supplies for [patient] - going to restock")
				return GOAL_STEP_PENDING
		bot_log(bot, "out of medical supplies for [patient], and nothing reachable to restock with")
		return GOAL_STEP_FAIL
	bot.aim_at_worst_wound(patient)
	bot.owner.changeNext_move(CLICK_CD_MELEE)
	bot.use_item_on(I, patient)
	bot_log(bot, "treating [patient] with [I]")
	if(!bot.patient_needs_treatment(patient))
		return GOAL_STEP_SUCCESS
	addtimer(CALLBACK(src, PROC_REF(continue_treat), bot), CLICK_CD_MELEE)
	return GOAL_STEP_PENDING

/datum/bot_step/treat_patient/proc/continue_treat(datum/bot_brain/bot)
	if(QDELETED(bot) || bot.state != BOT_STATE_GOAL || bot.current_strategy?.steps?[bot.current_step_index] != src)
		return //goal moved on (succeeded/failed/replaced) while we were waiting - don't act on stale state
	var/result = execute(bot)
	if(result != GOAL_STEP_PENDING)
		bot.advance_goal_step(result == GOAL_STEP_SUCCESS)

/datum/bot_brain/proc/try_medical_round()
	if(is_medical_job())
		// Priority order matches real triage: revive the dead first (nothing else
		// matters until their heart's beating), then get the incapacitated somewhere
		// that can actually stabilize them, then patch up whoever's just walking
		// around hurt.
		if(assign_goal(new /datum/bot_goal/revive_patient()))
			return TRUE
		if(assign_goal(new /datum/bot_goal/escort_to_sleeper()))
			return TRUE
		if(assign_goal(new /datum/bot_goal/treat_patient()))
			return TRUE
		// No patient needs attention right now - use the downtime to get medbay's
		// cryo setup in order, same priority a real doctor would use: get gas
		// flowing to the loop first, then get it cold, then make sure there's
		// something to actually heal with once someone's inside.
		if(assign_goal(new /datum/bot_goal/connect_cryo_canister()))
			return TRUE
		if(assign_goal(new /datum/bot_goal/activate_cryo_freezer()))
			return TRUE
		if(assign_goal(new /datum/bot_goal/load_cryo_beaker()))
			return TRUE
	// Chemists have no patient/cryo duties at all, and reach straight here - Doctors/
	// CMOs fall through to this too once medbay's fully caught up, using downtime to
	// keep the medicine supply stocked (goals/synthesize_medicine.dm).
	if(is_chem_producer_job())
		return assign_goal(new /datum/bot_goal/synthesize_medicine())
	return FALSE

// Chains straight into the next medical task instead of waiting out the normal
// wander-cycle pacing (next_medical_check_time, up to 15 real seconds) - a doctor who
// just finished bandaging one patient or wrenching one canister down doesn't wander off
// idly before checking whether there's more to do, they just do the next thing.
// Deferred one tick so state has actually settled back to BOT_STATE_WANDER first -
// assign_goal() refuses outright while state is still BOT_STATE_GOAL, which it still is
// at the exact moment on_success() runs (end_goal() hasn't returned yet).
/datum/bot_brain/proc/continue_medical_round()
	continue_goal_chain(CALLBACK(src, PROC_REF(try_medical_round)))

// ============================================================
// Revival: fetch paddles from a wall-mounted defibrillator, wield them, and shock a
// dead patient back to life - same as a real doctor grabbing the mount's paddles
// instead of carrying their own defib on every shift.
// ============================================================

/datum/bot_brain/proc/find_reachable_defib_mount()
	var/obj/machinery/defibrillator_mount/best
	var/best_dist
	for(var/obj/machinery/defibrillator_mount/M in GLOB.machines)
		if(M.z != owner.z || !M.defib || !M.defib.paddles || !M.defib.powered)
			continue
		if(M.defib.paddles.loc != M.defib) //someone else already has the paddles out
			continue
		var/dist = get_dist(owner, M)
		if(dist > 30)
			continue
		if(!best || dist < best_dist)
			best = M
			best_dist = dist
	return best

// Frees BOTH hands (stows what it can, drops the rest) - wielding the paddles needs the
// active hand AND the inactive hand empty, unlike ordinary tool use which only ever
// needed free_hand_for()'s single-hand version.
/datum/bot_brain/proc/free_both_hands()
	for(var/obj/item/I in owner.held_items)
		if(!I)
			continue
		stow_item(I)
		if(I in owner.held_items)
			owner.dropItemToGround(I)

/datum/bot_goal/revive_patient
	var/obj/machinery/defibrillator_mount/mount

/datum/bot_goal/revive_patient/resolve_target(datum/bot_brain/bot)
	var/obj/machinery/defibrillator_mount/M = bot.find_reachable_defib_mount()
	if(!M)
		return
	var/mob/living/carbon/human/best
	var/best_dist
	for(var/mob/living/carbon/human/H in GLOB.dead_mob_list)
		if(H.z != bot.owner.z)
			continue
		if(!M.defib.paddles.can_defib(H)) //reuses the paddles' own revivability check (time limit, damage caps, brain state, etc) rather than duplicating it
			continue
		var/dist = get_dist(bot.owner, H)
		if(dist > 60)
			continue
		if(!best || dist < best_dist)
			best = H
			best_dist = dist
	if(!best)
		return
	target = best
	mount = M

/datum/bot_goal/revive_patient/get_strategies(datum/bot_brain/bot)
	return list(new /datum/bot_strategy/revive(mount))

/datum/bot_goal/revive_patient/on_success(datum/bot_brain/bot)
	return_paddles(bot)
	bot.continue_medical_round()

/datum/bot_goal/revive_patient/on_give_up(datum/bot_brain/bot)
	return_paddles(bot)

/datum/bot_goal/revive_patient/proc/return_paddles(datum/bot_brain/bot)
	if(!mount || QDELETED(mount) || !mount.defib)
		return
	var/obj/item/twohanded/shockpaddles/paddles = mount.defib.paddles
	if(paddles && paddles.loc == bot.owner)
		if(paddles.wielded)
			paddles.unwield(bot.owner)
		paddles.snap_back()

/datum/bot_strategy/revive
	var/obj/machinery/defibrillator_mount/mount

/datum/bot_strategy/revive/New(obj/machinery/defibrillator_mount/M)
	. = ..()
	mount = M
	var/datum/bot_step/move_to/to_mount = new()
	to_mount.step_target = M
	steps = list(to_mount, new /datum/bot_step/grab_paddles(M), new /datum/bot_step/move_to(), new /datum/bot_step/defibrillate())

/datum/bot_strategy/revive/is_feasible(datum/bot_brain/bot)
	return mount && !QDELETED(mount)

/datum/bot_step/grab_paddles
	var/obj/machinery/defibrillator_mount/mount

/datum/bot_step/grab_paddles/New(obj/machinery/defibrillator_mount/M)
	. = ..()
	mount = M

/datum/bot_step/grab_paddles/execute(datum/bot_brain/bot)
	if(!mount || QDELETED(mount) || !mount.defib || !mount.defib.paddles)
		return GOAL_STEP_FAIL
	if(!bot.owner.Adjacent(mount))
		return GOAL_STEP_FAIL
	var/obj/item/twohanded/shockpaddles/paddles = mount.defib.paddles
	if(paddles.loc == bot.owner)
		if(!paddles.wielded)
			paddles.wield(bot.owner)
		return paddles.wielded ? GOAL_STEP_SUCCESS : GOAL_STEP_FAIL
	if(paddles.loc != mount.defib)
		return GOAL_STEP_FAIL //someone beat us to them
	bot.free_both_hands()
	mount.attack_hand(bot.owner)
	if(paddles.loc != bot.owner)
		return GOAL_STEP_FAIL
	paddles.wield(bot.owner)
	return paddles.wielded ? GOAL_STEP_SUCCESS : GOAL_STEP_FAIL

/datum/bot_step/defibrillate/execute(datum/bot_brain/bot)
	var/mob/living/carbon/human/patient = bot.current_goal?.target
	if(!istype(patient) || QDELETED(patient))
		return GOAL_STEP_FAIL
	if(patient.stat != DEAD)
		return GOAL_STEP_SUCCESS //already revived (by someone/something else)
	if(!bot.owner.Adjacent(patient))
		return GOAL_STEP_FAIL
	var/obj/item/twohanded/shockpaddles/paddles = locate(/obj/item/twohanded/shockpaddles) in bot.owner.held_items
	if(!paddles)
		return GOAL_STEP_FAIL
	if(!paddles.wielded)
		paddles.wield(bot.owner)
		if(!paddles.wielded)
			return GOAL_STEP_FAIL
	bot.owner.a_intent = INTENT_HELP
	bot.owner.zone_selected = BODY_ZONE_CHEST
	bot.owner.changeNext_move(CLICK_CD_MELEE)
	bot_log(bot, "shocking [patient] with the defibrillator")
	paddles.attack(patient, bot.owner) //yields for real time (do_after chain) - fine, same as climb_structure() elsewhere in this system
	return patient.stat != DEAD ? GOAL_STEP_SUCCESS : GOAL_STEP_FAIL

// ============================================================
// Escort: drag an incapacitated (but alive) patient to the nearest sleeper, or a cryo
// cell if no sleeper's reachable - a bandage doesn't fix someone who's unconscious,
// they need real medical machinery. Sleepers are always preferred since they need no
// setup; a cryo cell is still worth using even with no beaker loaded yet (the
// temperature-induced sleep/stabilization in cryo_cell/process() applies regardless of
// whether a beaker's present - requiring one first used to deadlock escort entirely
// against load_cryo_beaker, which only ever runs when there's nobody to escort).
// Distance is measured from the PATIENT, not the bot, since that's who actually needs
// to end up there.
/datum/bot_brain/proc/find_reachable_healing_machine(mob/living/patient)
	var/obj/machinery/sleeper/best_sleeper
	var/best_sleeper_dist
	for(var/obj/machinery/sleeper/S in GLOB.machines)
		if(S.z != owner.z || S.occupant)
			continue
		var/dist = get_dist(patient, S)
		if(dist > 60)
			continue
		if(!best_sleeper || dist < best_sleeper_dist)
			best_sleeper = S
			best_sleeper_dist = dist
	if(best_sleeper)
		return best_sleeper

	var/obj/machinery/atmospherics/components/unary/cryo_cell/best_cryo
	var/best_cryo_dist
	for(var/obj/machinery/atmospherics/components/unary/cryo_cell/C in GLOB.machines)
		if(C.z != owner.z || C.occupant)
			continue
		var/dist = get_dist(patient, C)
		if(dist > 60)
			continue
		if(!best_cryo || dist < best_cryo_dist)
			best_cryo = C
			best_cryo_dist = dist
	return best_cryo

/datum/bot_goal/escort_to_sleeper
	var/atom/machine_target

/datum/bot_goal/escort_to_sleeper/resolve_target(datum/bot_brain/bot)
	var/mob/living/carbon/human/best
	var/best_score
	for(var/mob/living/carbon/human/H in GLOB.alive_mob_list)
		if(H == bot.owner || H.z != bot.owner.z)
			continue
		if(H.stat == CONSCIOUS || H.stat == DEAD)
			continue
		if(get_dist(bot.owner, H) > 60)
			continue
		var/score = bot.patient_injury_score(H) - get_dist(bot.owner, H)
		if(!best || score > best_score)
			best = H
			best_score = score
	if(!best)
		return
	var/atom/M = bot.find_reachable_healing_machine(best)
	if(!M)
		return
	target = best
	machine_target = M

/datum/bot_goal/escort_to_sleeper/get_strategies(datum/bot_brain/bot)
	return list(new /datum/bot_strategy/escort(machine_target))

/datum/bot_goal/escort_to_sleeper/on_success(datum/bot_brain/bot)
	bot.owner.stop_pulling()
	bot.continue_medical_round()

/datum/bot_goal/escort_to_sleeper/on_give_up(datum/bot_brain/bot)
	bot.owner.stop_pulling()

/datum/bot_strategy/escort
	var/atom/machine_target

/datum/bot_strategy/escort/New(atom/M)
	. = ..()
	machine_target = M
	var/datum/bot_step/move_to/to_patient = new()
	var/datum/bot_step/move_to/to_machine = new()
	to_machine.step_target = M
	steps = list(to_patient, new /datum/bot_step/grab_patient(), to_machine, new /datum/bot_step/load_patient(M))

/datum/bot_strategy/escort/is_feasible(datum/bot_brain/bot)
	return machine_target && !QDELETED(machine_target)

/datum/bot_step/grab_patient/execute(datum/bot_brain/bot)
	var/mob/living/carbon/human/patient = bot.current_goal?.target
	if(!istype(patient) || QDELETED(patient) || patient.stat == DEAD)
		bot_log_verbose(bot, "grab_patient: patient invalid/gone/dead ([patient])")
		return GOAL_STEP_FAIL
	if(!bot.owner.Adjacent(patient))
		bot_log_verbose(bot, "grab_patient: not adjacent - bot @ [bot_coord(get_turf(bot.owner))], patient @ [bot_coord(get_turf(patient))]")
		return GOAL_STEP_FAIL
	if(bot.owner.pulling == patient)
		return GOAL_STEP_SUCCESS
	if(!patient.can_be_pulled(bot.owner, 0, bot.owner.move_force))
		bot_log_verbose(bot, "grab_patient: [patient].can_be_pulled() refused - anchored=[patient.anchored], throwing=[patient.throwing], patient move_resist=[patient.move_resist], bot move_force=[bot.owner.move_force]")
		return GOAL_STEP_FAIL
	bot.owner.start_pulling(patient)
	// /mob/living/start_pulling() (living.dm) has no explicit "return TRUE" on its
	// success path - it falls through into set_pull_offsets() and implicitly returns
	// null, unlike the base /atom/movable version this codebase's other callers assume.
	// Trusting that return value made this step report FAIL immediately after actually
	// successfully grabbing the patient (confirmed via attack.log: "grabbed ... passive
	// grab" logged the same tick this used to fail) - checking the real post-call state
	// instead of the unreliable return value.
	var/result = (bot.owner.pulling == patient)
	bot_log_verbose(bot, "grab_patient: start_pulling([patient]) -> pulling=[result]")
	return result ? GOAL_STEP_SUCCESS : GOAL_STEP_FAIL

/datum/bot_step/load_patient
	var/atom/machine_target

/datum/bot_step/load_patient/New(atom/M)
	. = ..()
	machine_target = M

/datum/bot_step/load_patient/execute(datum/bot_brain/bot)
	var/mob/living/carbon/human/patient = bot.current_goal?.target
	if(!istype(patient) || QDELETED(patient) || QDELETED(machine_target))
		return GOAL_STEP_FAIL
	if(!bot.owner.Adjacent(machine_target))
		return GOAL_STEP_FAIL
	if(bot.owner.pulling != patient && !bot.owner.Adjacent(patient))
		return GOAL_STEP_FAIL //lost them somewhere on the way over
	if(istype(machine_target, /obj/machinery/sleeper))
		var/obj/machinery/sleeper/S = machine_target
		if(S.occupant)
			return (S.occupant == patient) ? GOAL_STEP_SUCCESS : GOAL_STEP_FAIL
		S.MouseDrop_T(patient, bot.owner)
		if(S.occupant != patient)
			return GOAL_STEP_FAIL
		bot_log(bot, "loaded [patient] into [S]")
		S.inject_chem(pick(/datum/reagent/medicine/bicaridine, /datum/reagent/medicine/kelotane), bot.owner)
		return GOAL_STEP_SUCCESS
	if(istype(machine_target, /obj/machinery/atmospherics/components/unary/cryo_cell))
		var/obj/machinery/atmospherics/components/unary/cryo_cell/C = machine_target
		if(C.occupant)
			return (C.occupant == patient) ? GOAL_STEP_SUCCESS : GOAL_STEP_FAIL
		// Unlike /obj/machinery/sleeper (state_open = TRUE by default), a cryo cell
		// starts with its door CLOSED (cryo.dm:11) - close_machine() is a no-op unless
		// state_open is already TRUE, so MouseDrop_T() silently did nothing every time
		// without this: the patient never actually got inserted, confirmed in-game (the
		// bot "delivered" the patient but the cell stayed empty).
		if(!C.state_open)
			C.open_machine()
		C.MouseDrop_T(patient, bot.owner)
		if(C.occupant != patient)
			bot_log_verbose(bot, "load_patient: MouseDrop_T into [C] didn't take - state_open=[C.state_open], occupant=[C.occupant]")
			return GOAL_STEP_FAIL
		bot_log(bot, "loaded [patient] into [C]")
		C.on = TRUE
		C.update_icon()
		return GOAL_STEP_SUCCESS
	return GOAL_STEP_FAIL

// ============================================================
// Cryo setup: a real medbay's cryo loop needs someone to wrench an oxygen canister onto
// its connector port, turn the freezer on and set it to minimum, and drop a healing
// reagent beaker into each empty cell - none of which happens on its own. Each of the
// three is its own single-purpose goal (one task per trip, same convention as
// everything else in this file), tried only once no patient actually needs attention
// this tick (see try_medical_round() above). Every finder below only looks within a
// modest radius of an actual cryo cell, rather than grabbing the first wrenchable
// canister anywhere on the station regardless of what it's for.
// ============================================================

#define BOT_CRYO_SETUP_RADIUS 15
#define BOT_CRYO_SETUP_REACH 40

/datum/bot_brain/proc/find_disconnected_cryo_canister()
	for(var/obj/machinery/atmospherics/components/unary/cryo_cell/C in GLOB.machines)
		if(C.z != owner.z)
			continue
		for(var/obj/machinery/atmospherics/components/unary/portables_connector/P in range(BOT_CRYO_SETUP_RADIUS, C))
			if(P.z != owner.z || P.connected_device)
				continue
			var/obj/machinery/portable_atmospherics/canister/O = locate(/obj/machinery/portable_atmospherics/canister) in P.loc
			if(O && !O.connected_port && get_dist(owner, O) <= BOT_CRYO_SETUP_REACH)
				return O
	return null

/datum/bot_brain/proc/find_unset_cryo_freezer()
	for(var/obj/machinery/atmospherics/components/unary/cryo_cell/C in GLOB.machines)
		if(C.z != owner.z)
			continue
		for(var/obj/machinery/atmospherics/components/unary/thermomachine/freezer/F in range(BOT_CRYO_SETUP_RADIUS, C))
			if(F.z != owner.z)
				continue
			if(F.on && F.target_temperature <= F.min_temperature + 5)
				continue //already on and cold enough
			if(get_dist(owner, F) <= BOT_CRYO_SETUP_REACH)
				return F
	return null

/datum/bot_brain/proc/find_empty_cryo_cell()
	for(var/obj/machinery/atmospherics/components/unary/cryo_cell/C in GLOB.machines)
		if(C.z != owner.z || C.beaker || C.occupant)
			continue
		if(get_dist(owner, C) <= BOT_CRYO_SETUP_REACH)
			return C
	return null

// Prefers an already-mixed cryoxadone/clonexadone/pyroxadone beaker (the actual "cryo
// chemical" family - medicine_reagents.dm/medicine.dm) if one's sitting out somewhere
// reachable, same as a doctor grabbing the pre-made batch off the apothecary shelf
// instead of synthesizing more. Falls back to any beaker with something in it if none
// of those specifically exist yet - still better than an empty cell, just less
// effective. Doesn't synthesize cryoxadone itself (stable_plasma + acetone + mutagen at
// a chem dispenser) - that's a chemist's job, not folded into doctor behavior here.
/datum/bot_brain/proc/find_reachable_healing_beaker()
	var/obj/item/reagent_containers/glass/fallback
	for(var/obj/item/reagent_containers/glass/B as anything in bot_instances_of(/obj/item/reagent_containers/glass))
		if(!isturf(B.loc) || B.anchored)
			continue
		if(!B.reagents || !B.reagents.total_volume)
			continue
		var/turf/T = get_turf(B)
		if(!T || T.z != owner.z)
			continue
		if(B.reagents.has_reagent(/datum/reagent/medicine/cryoxadone) || B.reagents.has_reagent(/datum/reagent/medicine/clonexadone) || B.reagents.has_reagent(/datum/reagent/medicine/pyroxadone))
			return B
		if(!fallback)
			fallback = B
	return fallback

#undef BOT_CRYO_SETUP_RADIUS
#undef BOT_CRYO_SETUP_REACH

/datum/bot_goal/connect_cryo_canister
	var/obj/machinery/portable_atmospherics/canister/canister

/datum/bot_goal/connect_cryo_canister/resolve_target(datum/bot_brain/bot)
	var/obj/machinery/portable_atmospherics/canister/C = bot.find_disconnected_cryo_canister()
	if(!C)
		return
	target = C
	canister = C

/datum/bot_goal/connect_cryo_canister/get_strategies(datum/bot_brain/bot)
	return list(new /datum/bot_strategy/connect_canister(canister))

/datum/bot_goal/connect_cryo_canister/on_success(datum/bot_brain/bot)
	bot.continue_medical_round()

/datum/bot_strategy/connect_canister
	var/obj/machinery/portable_atmospherics/canister/canister

/datum/bot_strategy/connect_canister/New(obj/machinery/portable_atmospherics/canister/C)
	. = ..()
	canister = C
	steps = list(new /datum/bot_step/ensure_wrench(), new /datum/bot_step/move_to(), new /datum/bot_step/wrench_canister(C))

/datum/bot_strategy/connect_canister/is_feasible(datum/bot_brain/bot)
	return canister && !QDELETED(canister)

/datum/bot_step/ensure_wrench
	var/tried_fetch = FALSE

/datum/bot_step/ensure_wrench/execute(datum/bot_brain/bot)
	if(bot.can_eventually_provide_tool(/obj/item/wrench)) //hand drill counts - see bot_tool_transform_pairs
		return GOAL_STEP_SUCCESS
	if(!tried_fetch)
		tried_fetch = TRUE
		if(bot.seek_tool_for_obstacle(/obj/item/wrench))
			return GOAL_STEP_PENDING
	return GOAL_STEP_FAIL

/datum/bot_step/wrench_canister
	var/obj/machinery/portable_atmospherics/canister/canister

/datum/bot_step/wrench_canister/New(obj/machinery/portable_atmospherics/canister/C)
	. = ..()
	canister = C

/datum/bot_step/wrench_canister/execute(datum/bot_brain/bot)
	if(!canister || QDELETED(canister) || canister.connected_port)
		return GOAL_STEP_SUCCESS //already connected, by us or someone else
	if(!bot.owner.Adjacent(canister))
		return GOAL_STEP_FAIL
	var/obj/item/wrench/W = bot.find_or_transform_tool(/obj/item/wrench)
	if(!W)
		return GOAL_STEP_FAIL
	bot.owner.changeNext_move(CLICK_CD_MELEE)
	bot.use_item_on(W, canister)
	bot_log(bot, "wrenched [canister] onto its connector port")
	return canister.connected_port ? GOAL_STEP_SUCCESS : GOAL_STEP_FAIL

/datum/bot_goal/activate_cryo_freezer
	var/obj/machinery/atmospherics/components/unary/thermomachine/freezer/freezer

/datum/bot_goal/activate_cryo_freezer/resolve_target(datum/bot_brain/bot)
	var/obj/machinery/atmospherics/components/unary/thermomachine/freezer/F = bot.find_unset_cryo_freezer()
	if(!F)
		return
	target = F
	freezer = F

/datum/bot_goal/activate_cryo_freezer/get_strategies(datum/bot_brain/bot)
	return list(new /datum/bot_strategy/activate_freezer(freezer))

/datum/bot_goal/activate_cryo_freezer/on_success(datum/bot_brain/bot)
	bot.continue_medical_round()

/datum/bot_strategy/activate_freezer
	var/obj/machinery/atmospherics/components/unary/thermomachine/freezer/freezer

/datum/bot_strategy/activate_freezer/New(obj/machinery/atmospherics/components/unary/thermomachine/freezer/F)
	. = ..()
	freezer = F
	steps = list(new /datum/bot_step/move_to(), new /datum/bot_step/set_freezer_cold(F))

/datum/bot_strategy/activate_freezer/is_feasible(datum/bot_brain/bot)
	return freezer && !QDELETED(freezer)

/datum/bot_step/set_freezer_cold
	var/obj/machinery/atmospherics/components/unary/thermomachine/freezer/freezer

/datum/bot_step/set_freezer_cold/New(obj/machinery/atmospherics/components/unary/thermomachine/freezer/F)
	. = ..()
	freezer = F

/datum/bot_step/set_freezer_cold/execute(datum/bot_brain/bot)
	if(!freezer || QDELETED(freezer))
		return GOAL_STEP_FAIL
	if(!bot.owner.Adjacent(freezer))
		return GOAL_STEP_FAIL
	freezer.on = TRUE
	freezer.target_temperature = freezer.min_temperature
	freezer.use_power = ACTIVE_POWER_USE
	freezer.update_icon()
	bot_log(bot, "activated [freezer] and set it to minimum temperature")
	return GOAL_STEP_SUCCESS

/datum/bot_goal/load_cryo_beaker
	var/obj/machinery/atmospherics/components/unary/cryo_cell/cell

/datum/bot_goal/load_cryo_beaker/resolve_target(datum/bot_brain/bot)
	var/obj/machinery/atmospherics/components/unary/cryo_cell/C = bot.find_empty_cryo_cell()
	if(!C)
		return
	var/obj/item/reagent_containers/glass/B = bot.find_reachable_healing_beaker()
	if(!B)
		return
	cell = C
	target = B

/datum/bot_goal/load_cryo_beaker/get_strategies(datum/bot_brain/bot)
	return list(new /datum/bot_strategy/deliver_beaker(cell))

/datum/bot_goal/load_cryo_beaker/on_success(datum/bot_brain/bot)
	bot.continue_medical_round()

/datum/bot_strategy/deliver_beaker
	var/obj/machinery/atmospherics/components/unary/cryo_cell/cell

/datum/bot_strategy/deliver_beaker/New(obj/machinery/atmospherics/components/unary/cryo_cell/C)
	. = ..()
	cell = C
	var/datum/bot_step/move_to/to_cell = new()
	to_cell.step_target = C
	steps = list(new /datum/bot_step/move_to(), new /datum/bot_step/pickup_item(), to_cell, new /datum/bot_step/load_beaker(C))

/datum/bot_strategy/deliver_beaker/is_feasible(datum/bot_brain/bot)
	return cell && !QDELETED(cell)

/datum/bot_step/load_beaker
	var/obj/machinery/atmospherics/components/unary/cryo_cell/cell

/datum/bot_step/load_beaker/New(obj/machinery/atmospherics/components/unary/cryo_cell/C)
	. = ..()
	cell = C

/datum/bot_step/load_beaker/execute(datum/bot_brain/bot)
	if(!cell || QDELETED(cell) || cell.beaker || cell.occupant)
		return GOAL_STEP_SUCCESS //already sorted, by us or someone else
	if(!bot.owner.Adjacent(cell))
		return GOAL_STEP_FAIL
	var/obj/item/reagent_containers/glass/B = bot.current_goal?.target
	if(!istype(B) || QDELETED(B))
		bot_log_verbose(bot, "load_beaker: target invalid/gone ([B])")
		return GOAL_STEP_FAIL
	// try_pickup_target()/stow_item() (bot_items.dm) prefer real storage (a pocket/
	// backpack) over the hand, so B.loc is very often the BAG, not bot.owner directly,
	// right after a successful pickup - checking that exact equality failed every
	// delivery that stowed rather than held (confirmed in-game: "picked up the beaker"
	// logged fine, then this step failed the very next tick). GetAllContents() walks
	// nested storage the same way get_medical_supplies() above already does; use_item_on()
	// itself already knows how to pull a stowed item into hand regardless.
	if(!(B in bot.owner.GetAllContents()) && (!isturf(B.loc) || B.loc != get_turf(bot.owner)))
		bot_log_verbose(bot, "load_beaker: [B] is no longer with us (loc=[B.loc])")
		return GOAL_STEP_FAIL
	bot.owner.changeNext_move(CLICK_CD_MELEE)
	bot.use_item_on(B, cell)
	bot_log(bot, "loaded [B] into [cell]")
	return cell.beaker ? GOAL_STEP_SUCCESS : GOAL_STEP_FAIL
