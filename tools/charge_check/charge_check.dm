// Plastic explosives self-test (C4, X4): planted the way a player plants them, in the real engine, headless.
//
// Run:      tools/charge_check/run.sh   (builds its own copy, so hippiestation.dmb is left alone)
// Results:  data/charge_check/results.txt, one PASS/FAIL line per check and NOTE lines with what happened.
//
// Each check gets its own walled room in reserved space with station air. People stand round the charge and what each
// took is listed. Covered: X4 and C4 on plain and reinforced walls and on a floor, the thing a charge is planted on
// being deleted, fried and eaten, cremated, the screwdriver and multitool on X4's timer, sensors in an assembly (signaler,
// proximity, health) on a loose charge and a planted one, and a pile of C4 going off together.

/datum/controller/master/Initialize(delay, init_sss, tgs_prime)
	if("charge-check" in world.params)
		sleep_offline_after_initializations = FALSE //nobody connects to this, so the world has to keep ticking
		INVOKE_ASYNC(GLOBAL_PROC, GLOBAL_PROC_REF(run_charge_check))
	return ..()

#define CHARGE_CHECK_DIR "data/charge_check/"

/proc/run_charge_check()
	sleep(5 SECONDS)
	var/out = world.params["charge-check-out"] || CHARGE_CHECK_DIR
	fdel(out)
	GLOB.master_mode = "extended"
	SSticker.start_immediately = TRUE
	var/round_deadline = world.time + 3 MINUTES
	while(SSticker.current_state < GAME_STATE_PLAYING && world.time < round_deadline)
		sleep(1 SECONDS)
	var/datum/charge_check/test = new
	test.run_all()
	text2file(jointext(test.lines, "\n"), "[out]results.txt")
	log_world("CHARGE CHECK: done, [test.passed] passed, [test.failed] failed")
	Master.Shutdown()
	qdel(world)

/datum/charge_check
	var/list/lines = list()
	var/passed = 0
	var/failed = 0
	/// list(turf, dev, heavy, light, world.time) for each explosion
	var/list/booms = list()
	/// The room in use: its bottom left inside corner
	var/x0
	var/y0
	var/z0

/datum/charge_check/proc/check(name, condition, detail)
	if(condition)
		passed++
	else
		failed++
	lines += "[condition ? "PASS" : "FAIL"] [name][isnull(detail) ? "" : " - [detail]"]"

/datum/charge_check/proc/note(text)
	lines += "     [text]"

/datum/charge_check/proc/on_explosion(datum/source, turf/epicenter, dev, heavy, light)
	SIGNAL_HANDLER
	var/datum/gas_mixture/air = epicenter.return_air()
	booms += list(list(epicenter, dev, heavy, light, world.time, air ? round(air.return_pressure()) : 0))

/datum/charge_check/proc/run_all()
	check("round started", SSticker.current_state >= GAME_STATE_PLAYING, "state [SSticker.current_state]")
	RegisterSignal(SSdcs, COMSIG_GLOB_EXPLOSION, PROC_REF(on_explosion))
	var/list/checks = list("wall_x4", "wall_c4", "rwall_x4", "floor_x4", "x4_on_person", "target_deleted", "fried",
		"cremated", "x4_timer_tools", "c4_cut_detonator", "signaler", "prox_loose", "prox_planted", "health_carried", "health_planted", "chain", "stack", "pile",
		"lances")
	var/only = world.params["charge-check-only"] //some of them, by name, comma separated
	if(only)
		checks = splittext(only, ",")
	for(var/name in checks)
		lines += ""
		lines += "== [name]"
		try
			call(src, "check_[name]")()
		catch(var/exception/e)
			check("[name] ran to the end", FALSE, "[e] at [e.file]:[e.line]")
		sleep(2 SECONDS)

/// A fresh walled room `w` by `h` inside, with station air
/datum/charge_check/proc/build_room(w, h)
	var/datum/turf_reservation/reservation = SSmapping.RequestBlockReservation(w + 6, h + 6)
	if(!reservation)
		CRASH("no reservation")
	x0 = reservation.bottom_left_coords[1] + 3
	y0 = reservation.bottom_left_coords[2] + 3
	z0 = reservation.bottom_left_coords[3]
	var/area/test_area = new /area/bot_gym
	var/list/floors = list()
	for(var/x in x0 - 1 to x0 + w)
		for(var/y in y0 - 1 to y0 + h)
			var/turf/T = locate(x, y, z0)
			var/area/old_area = T.loc
			old_area.contents -= T
			test_area.contents += T
			T.change_area(old_area, test_area)
			if(x == x0 - 1 || x == x0 + w || y == y0 - 1 || y == y0 + h)
				T.ChangeTurf(/turf/closed/indestructible/riveted, flags = CHANGETURF_IGNORE_AIR)
			else
				floors += T.ChangeTurf(/turf/open/floor/plasteel, flags = CHANGETURF_IGNORE_AIR)
	for(var/turf/open/F in floors)
		F.air.parse_gas_string(OPENTURF_DEFAULT_ATMOS)
		F.update_visuals()
		SSair.add_to_active(F)
	sleep(1 SECONDS)

/// The room's tile at (dx, dy), 1 based
/datum/charge_check/proc/spot(dx, dy)
	return locate(x0 + dx - 1, y0 + dy - 1, z0)

/datum/charge_check/proc/make_human(turf/T, name)
	var/mob/living/carbon/human/H = new(T)
	H.real_name = name
	H.name = name
	H.equip_to_slot_or_del(new /obj/item/clothing/under/color/grey(H), ITEM_SLOT_ICLOTHING)
	return H

/// What a person took: damage, dead, or gibbed
/datum/charge_check/proc/hurt(mob/living/carbon/human/H)
	if(QDELETED(H))
		return "gibbed"
	return "[round(H.getBruteLoss() + H.getFireLoss())][H.stat == DEAD ? " dead" : ""]"

/datum/charge_check/proc/damage(mob/living/carbon/human/H)
	if(QDELETED(H))
		return 1000
	return H.getBruteLoss() + H.getFireLoss()

/// An assembly holder made of two parts, as a player makes one: both unsecured, put together (which secures them)
/datum/charge_check/proc/make_holder(type1, type2, turf/T)
	var/obj/item/assembly/A = new type1(T)
	var/obj/item/assembly/B = new type2(T)
	A.toggle_secure()
	B.toggle_secure()
	var/obj/item/assembly_holder/H = new(T)
	H.assemble(A, B, null)
	return H

/// `user` plants `charge` on `target` as a player does (in the hand, clicked on it, 3 s to plant)
/datum/charge_check/proc/plant(obj/item/grenade/plastic/charge, atom/target, mob/living/carbon/human/user)
	if(charge.loc != user)
		user.put_in_hands(charge)
	charge.afterattack(target, user, TRUE)

/datum/charge_check/proc/booms_since(count)
	return length(booms) - count

/// Where the last explosion went off, from (dx, dy) of the room, as "dx,dy" with its ranges
/datum/charge_check/proc/last_boom_text(count = 0)
	if(length(booms) <= count)
		return "none"
	var/list/B = booms[length(booms)]
	var/turf/T = B[1]
	return "at [T.x - x0 + 1],[T.y - y0 + 1] ([round(B[2], 0.1)], [round(B[3], 0.1)], [round(B[4], 0.1)]), [B[6]] kPa there"

/// A wall across the room at row `row`, and an X4 or C4 planted on its middle from the south: who took what on each side
/datum/charge_check/proc/wall_test(charge_type, wall_type, label)
	build_room(9, 13)
	for(var/x in 1 to 9)
		var/turf/T = spot(x, 7)
		T.ChangeTurf(wall_type, list(/turf/open/space, /turf/open/floor/plating))
	var/turf/wall = spot(5, 7)
	var/mob/living/carbon/human/planter = make_human(spot(5, 6), "Planter")
	var/mob/living/carbon/human/beside = make_human(spot(8, 6), "Beside")
	var/mob/living/carbon/human/behind = make_human(spot(5, 3), "Behind")
	var/mob/living/carbon/human/past1 = make_human(spot(5, 8), "Past1")
	var/mob/living/carbon/human/past4 = make_human(spot(5, 11), "Past4")
	var/mob/living/carbon/human/past_side = make_human(spot(8, 10), "PastSide")
	var/obj/item/grenade/plastic/charge = new charge_type(spot(5, 6))
	var/count = length(booms)
	plant(charge, wall, planter)
	check("[label]: planted", QDELETED(charge) || isnull(charge.loc) || charge.loc == null, "charge at [charge.loc]")
	sleep(13 SECONDS) //the 10 s fuse, and SSexplosions working through it
	check("[label]: went off", booms_since(count) >= 1, "[booms_since(count)] explosions, last [last_boom_text(count)]")
	var/turf/after = spot(5, 7)
	note("wall tile now [after.type]")
	note("planter (1 behind) [hurt(planter)], beside (3 along, planter's side) [hurt(beside)], behind (4 behind) [hurt(behind)]")
	note("past the wall: 1 on [hurt(past1)], 4 on [hurt(past4)], off to the side [hurt(past_side)]")
	return list(planter, beside, behind, past1, past4, past_side, after)

/datum/charge_check/proc/check_wall_x4()
	var/list/R = wall_test(/obj/item/grenade/plastic/x4, /turf/closed/wall, "X4 on a wall")
	var/turf/after = R[7]
	check("X4 on a wall: wall breached", !istype(after, /turf/closed), "[after.type]")
	check("X4 on a wall: the breach keeps its floor", istype(after, /turf/open/floor), "[after.type]")
	if(length(booms))
		var/list/B = booms[length(booms)]
		var/turf/T = B[1]
		check("X4 on a wall: blast on the far side", T.y > y0 + 6, last_boom_text())
	check("X4 on a wall: far side hit harder than the planter's side", damage(R[4]) > damage(R[1]), "past1 [hurt(R[4])] vs planter [hurt(R[1])]")
	check("X4 on a wall: 4 tiles on in line hit harder than off to the side", damage(R[5]) > damage(R[6]), "in line [hurt(R[5])] vs side [hurt(R[6])]")

/datum/charge_check/proc/check_wall_c4()
	var/list/R = wall_test(/obj/item/grenade/plastic/c4, /turf/closed/wall, "C4 on a wall")
	var/turf/after = R[7]
	check("C4 on a wall: wall breached", !istype(after, /turf/closed), "[after.type]")

/datum/charge_check/proc/check_rwall_x4()
	var/list/R = wall_test(/obj/item/grenade/plastic/x4, /turf/closed/wall/r_wall, "X4 on a reinforced wall")
	var/turf/after = R[7]
	check("X4 on a reinforced wall: wall breached", !istype(after, /turf/closed), "[after.type]")

/datum/charge_check/proc/check_floor_x4()
	build_room(9, 9)
	var/mob/living/carbon/human/planter = make_human(spot(5, 4), "Planter")
	var/mob/living/carbon/human/other = make_human(spot(5, 7), "Other")
	var/obj/item/grenade/plastic/x4/charge = new(spot(5, 4))
	var/count = length(booms)
	plant(charge, spot(5, 5), planter)
	sleep(13 SECONDS)
	check("X4 on a floor: went off", booms_since(count) >= 1, last_boom_text(count))
	if(length(booms))
		var/list/B = booms[length(booms)]
		check("X4 on a floor: round blast on the charge", B[1] == spot(5, 5), last_boom_text(count))
	note("planter [hurt(planter)], 2 past [hurt(other)]")

/datum/charge_check/proc/check_x4_on_person()
	build_room(9, 9)
	var/mob/living/carbon/human/planter = make_human(spot(5, 3), "Planter")
	var/mob/living/carbon/human/victim = make_human(spot(5, 4), "Victim")
	var/mob/living/carbon/human/past = make_human(spot(5, 6), "Past")
	var/obj/item/grenade/plastic/x4/charge = new(spot(5, 3))
	var/count = length(booms)
	plant(charge, victim, planter)
	sleep(13 SECONDS)
	check("X4 on a person: went off", booms_since(count) >= 1, last_boom_text(count))
	check("X4 on a person: they're gibbed", QDELETED(victim), hurt(victim))
	note("planter [hurt(planter)], 2 past [hurt(past)]")

/// Planted on a crowbar, and the crowbar's deleted before it goes off
/datum/charge_check/proc/check_target_deleted()
	build_room(9, 9)
	var/mob/living/carbon/human/planter = make_human(spot(5, 4), "Planter")
	var/obj/item/crowbar/bar = new(spot(5, 5))
	var/obj/item/grenade/plastic/c4/charge = new(spot(5, 4))
	var/count = length(booms)
	plant(charge, bar, planter)
	check("deleted target: planted", charge.target == bar, "target [charge.target]")
	qdel(bar)
	check("deleted target: the charge lets go of it", charge.target != bar, "still holds [charge.target]")
	sleep(13 SECONDS)
	check("deleted target: still goes off", booms_since(count) >= 1, last_boom_text(count))
	check("deleted target: charge used up", QDELETED(charge), "[charge] at [charge.loc]")

/datum/charge_check/proc/check_fried()
	build_room(9, 9)
	var/mob/living/carbon/human/planter = make_human(spot(5, 4), "Planter")
	var/mob/living/carbon/human/eater = make_human(spot(3, 3), "Eater")
	var/obj/item/crowbar/bar = new(spot(5, 5))
	var/obj/item/grenade/plastic/c4/charge = new(spot(5, 4))
	var/count = length(booms)
	plant(charge, bar, planter)
	var/obj/item/reagent_containers/food/snacks/deepfryholder/fried = new(spot(3, 3), bar)
	fried.fry(30)
	eater.put_in_hands(fried)
	fried.On_Consume(eater)
	note("fried crowbar with C4 on it eaten: crowbar [QDELETED(bar) ? "deleted" : "kept at [bar.loc]"]")
	sleep(13 SECONDS)
	check("fried and eaten target: charge still goes off", booms_since(count) >= 1, last_boom_text(count))
	note("eater [hurt(eater)]")
	// a loose C4 fried and eaten
	var/obj/item/grenade/plastic/c4/loose = new(spot(7, 7))
	var/obj/item/reagent_containers/food/snacks/deepfryholder/fried2 = new(spot(7, 7), loose)
	fried2.fry(30)
	eater.put_in_hands(fried2)
	fried2.On_Consume(eater)
	note("fried loose C4 eaten: C4 [QDELETED(loose) ? "deleted" : "kept at [loose.loc]"], explosions [booms_since(count) - 1]")

/datum/charge_check/proc/check_cremated()
	build_room(9, 9)
	var/mob/living/carbon/human/planter = make_human(spot(5, 4), "Planter")
	var/mob/living/carbon/human/corpse = make_human(spot(5, 5), "Corpse")
	corpse.death()
	var/obj/item/grenade/plastic/c4/charge = new(spot(5, 4))
	var/count = length(booms)
	plant(charge, corpse, planter)
	check("cremated: planted on the corpse", charge.target == corpse, "target [charge.target]")
	var/obj/structure/bodycontainer/crematorium/crem = new(spot(7, 7))
	corpse.forceMove(crem)
	crem.cremate(null)
	note("corpse [QDELETED(corpse) ? "cremated" : "still there"], charge at [charge.loc]")
	sleep(13 SECONDS)
	check("cremated: charge still goes off", booms_since(count) >= 1, last_boom_text(count))

/// Screwdriver and multitool on X4 go through the grenade timer, which counts in tenths of a second, but X4 counts in seconds
/datum/charge_check/proc/check_x4_timer_tools()
	build_room(9, 9)
	var/mob/living/carbon/human/planter = make_human(spot(5, 4), "Planter")
	var/obj/item/grenade/plastic/x4/charge = new(spot(5, 4))
	planter.put_in_hands(charge)
	var/obj/item/screwdriver/S = new(spot(5, 4))
	var/before = charge.det_time
	charge.attackby(S, planter)
	var/once = charge.det_time
	charge.attackby(S, planter)
	var/twice = charge.det_time
	note("det_time [before] -> screwdriver [once] -> screwdriver [twice] (X4 counts seconds, minimum 10)")
	check("X4 timer: screwdriver keeps it at 10 s or more", twice >= 10, "det_time [twice]")
	var/count = length(booms)
	var/started = world.time
	plant(charge, spot(5, 5), planter)
	var/planted_at = world.time
	sleep(2 SECONDS)
	var/early = booms_since(count)
	note("planted after [(planted_at - started) / 10] s; explosions within 2 s of planting: [early]")
	check("X4 timer: no instant blast after the screwdriver", !early, "[early] explosions within 2 s")
	sleep(12 SECONDS)

/// Wirecutters on C4 with its panel shut take the detonator assembly off
/datum/charge_check/proc/check_c4_cut_detonator()
	build_room(9, 9)
	var/mob/living/carbon/human/rigger = make_human(spot(5, 5), "Rigger")
	var/obj/item/grenade/plastic/c4/charge = new(spot(5, 5))
	var/obj/item/assembly_holder/H = make_holder(/obj/item/assembly/signaler, /obj/item/assembly/igniter, spot(5, 5))
	rigger.put_in_hands(H)
	charge.attackby(H, rigger)
	check("C4 detonator: attached", charge.nadeassembly == H)
	var/obj/item/wirecutters/cutters = new(spot(5, 5))
	var/count = length(booms)
	charge.attackby(cutters, rigger)
	check("C4 detonator: wirecutters take it off", isnull(charge.nadeassembly) && H.loc == spot(5, 5), "nadeassembly [charge.nadeassembly], assembly at [H.loc]")
	check("C4 detonator: cutting it off doesn't set it off", !booms_since(count))

/// A signaler in an assembly sets off a loose charge and a planted one
/datum/charge_check/proc/check_signaler()
	build_room(9, 9)
	var/mob/living/carbon/human/planter = make_human(spot(2, 2), "Planter")
	var/obj/item/grenade/plastic/c4/loose = new(spot(7, 7))
	var/obj/item/assembly_holder/H = make_holder(/obj/item/assembly/signaler, /obj/item/assembly/igniter, spot(2, 2))
	planter.put_in_hands(H)
	loose.attackby(H, planter)
	check("signaler: attached", loose.nadeassembly == H, "nadeassembly [loose.nadeassembly]")
	var/obj/item/assembly/signaler/S = H.a_left
	S.code = 7
	var/obj/item/assembly/signaler/remote = new(spot(2, 2))
	remote.code = 7
	var/count = length(booms)
	remote.signal()
	sleep(2 SECONDS)
	check("signaler: loose charge goes off", booms_since(count) >= 1, last_boom_text(count))
	// planted, with a long timer, set off by the signaler
	build_room(9, 9)
	planter = make_human(spot(5, 4), "Planter")
	var/obj/item/grenade/plastic/c4/planted = new(spot(5, 4))
	planted.det_time = 600
	var/obj/item/assembly_holder/H2 = make_holder(/obj/item/assembly/signaler, /obj/item/assembly/igniter, spot(5, 4))
	planter.put_in_hands(H2)
	planted.attackby(H2, planter)
	var/obj/item/assembly/signaler/S2 = H2.a_left
	S2.code = 9
	remote.code = 9
	var/turf/wall = spot(5, 5)
	wall.ChangeTurf(/turf/closed/wall, list(/turf/open/space, /turf/open/floor/plating))
	plant(planted, wall, planter)
	count = length(booms)
	remote.signal()
	sleep(2 SECONDS)
	check("signaler: planted charge goes off", booms_since(count) >= 1, last_boom_text(count))

/// A proximity sensor on a loose charge: somebody walks up
/datum/charge_check/proc/check_prox_loose()
	build_room(9, 9)
	var/obj/item/grenade/plastic/c4/charge = new(spot(5, 5))
	var/mob/living/carbon/human/rigger = make_human(spot(5, 4), "Rigger")
	var/obj/item/assembly_holder/H = make_holder(/obj/item/assembly/prox_sensor, /obj/item/assembly/igniter, spot(5, 4))
	rigger.put_in_hands(H)
	charge.attackby(H, rigger)
	var/obj/item/assembly/prox_sensor/P = H.a_left
	P.toggle_scan(TRUE)
	rigger.forceMove(spot(1, 1))
	sleep(1 SECONDS)
	var/mob/living/carbon/human/walker = make_human(spot(5, 9), "Walker")
	var/count = length(booms)
	for(var/y in list(8, 7, 6))
		walker.Move(spot(5, y), SOUTH)
		sleep(1 SECONDS)
	check("prox, loose: goes off when somebody walks up beside it", booms_since(count) >= 1, last_boom_text(count))
	if(!booms_since(count))
		walker.Move(spot(5, 5), SOUTH)
		sleep(2 SECONDS)
		note("walked onto its tile: [booms_since(count)] explosions")

/// A proximity sensor on a charge planted on a door: somebody walks up to the door
/datum/charge_check/proc/check_prox_planted()
	build_room(9, 9)
	var/turf/wall = spot(5, 5)
	wall.ChangeTurf(/turf/closed/wall, list(/turf/open/space, /turf/open/floor/plating))
	var/mob/living/carbon/human/rigger = make_human(spot(5, 4), "Rigger")
	var/obj/item/grenade/plastic/c4/charge = new(spot(5, 4))
	charge.det_time = 600
	rigger.put_in_hands(charge) //an armed one picked up goes off, as any armed proximity sensor does: put together in hand
	var/obj/item/assembly_holder/H = make_holder(/obj/item/assembly/prox_sensor, /obj/item/assembly/igniter, spot(5, 4))
	rigger.put_in_hands(H)
	charge.attackby(H, rigger)
	var/obj/item/assembly/prox_sensor/P = H.a_left
	P.toggle_scan(TRUE) //armed already, in hand
	var/count = length(booms)
	plant(charge, wall, rigger)
	rigger.forceMove(spot(1, 1))
	sleep(1 SECONDS)
	check("prox, planted: planting it armed doesn't set it off", !booms_since(count), "[booms_since(count)] explosions, [last_boom_text(count)]")
	var/mob/living/carbon/human/walker = make_human(spot(5, 9), "Walker")
	count = length(booms)
	for(var/y in list(8, 7, 6))
		walker.Move(spot(5, y), SOUTH)
		sleep(1 SECONDS)
	check("prox, planted: goes off when somebody walks up to the wall", booms_since(count) >= 1, last_boom_text(count))

/// A health sensor on a charge somebody carries: they go into crit
/datum/charge_check/proc/check_health_carried()
	build_room(9, 9)
	var/mob/living/carbon/human/carrier = make_human(spot(5, 5), "Carrier")
	var/obj/item/grenade/plastic/c4/charge = new(spot(5, 5))
	var/obj/item/assembly_holder/H = make_holder(/obj/item/assembly/health, /obj/item/assembly/igniter, spot(5, 5))
	var/obj/item/assembly/health/HS = H.a_left
	HS.toggle_scan()
	carrier.put_in_hands(H)
	charge.attackby(H, carrier)
	carrier.put_in_hands(charge)
	var/count = length(booms)
	sleep(3 SECONDS)
	check("health, carried: quiet while they're well", !booms_since(count), "[booms_since(count)] explosions")
	carrier.adjustBruteLoss(150)
	sleep(5 SECONDS)
	check("health, carried: goes off when they go into crit", booms_since(count) >= 1, last_boom_text(count))
	// in a pocket, where falling over doesn't drop it
	build_room(9, 9)
	carrier = make_human(spot(5, 5), "Carrier")
	charge = new(spot(5, 5))
	H = make_holder(/obj/item/assembly/health, /obj/item/assembly/igniter, spot(5, 5))
	HS = H.a_left
	HS.toggle_scan()
	carrier.put_in_hands(H)
	charge.attackby(H, carrier)
	check("health, in a pocket: put away", carrier.equip_to_slot_if_possible(charge, ITEM_SLOT_LPOCKET, disable_warning = TRUE), "at [charge.loc]")
	count = length(booms)
	carrier.adjustBruteLoss(150)
	sleep(5 SECONDS)
	check("health, in a pocket: goes off when they go into crit", booms_since(count) >= 1, last_boom_text(count))

/// A health sensor on a charge planted on somebody: they go into crit
/datum/charge_check/proc/check_health_planted()
	build_room(9, 9)
	var/mob/living/carbon/human/rigger = make_human(spot(5, 4), "Rigger")
	var/mob/living/carbon/human/wearer = make_human(spot(5, 5), "Wearer")
	var/obj/item/grenade/plastic/c4/charge = new(spot(5, 4))
	charge.det_time = 600
	var/obj/item/assembly_holder/H = make_holder(/obj/item/assembly/health, /obj/item/assembly/igniter, spot(5, 4))
	var/obj/item/assembly/health/HS = H.a_left
	HS.toggle_scan()
	rigger.put_in_hands(H)
	charge.attackby(H, rigger)
	plant(charge, wearer, rigger)
	var/count = length(booms)
	wearer.adjustBruteLoss(150)
	sleep(5 SECONDS)
	check("health, planted on them: goes off when they go into crit", booms_since(count) >= 1, last_boom_text(count))

/// A charge planted on a wall goes off when a heavy blast hits the wall, and not for a light one
/datum/charge_check/proc/check_chain()
	build_room(11, 11)
	var/turf/wall = spot(6, 6)
	wall.ChangeTurf(/turf/closed/wall, list(/turf/open/space, /turf/open/floor/plating))
	var/mob/living/carbon/human/rigger = make_human(spot(6, 5), "Rigger")
	var/obj/item/grenade/plastic/c4/planted = new(spot(6, 5))
	planted.det_time = 600
	plant(planted, wall, rigger)
	rigger.forceMove(spot(1, 1))
	// light: a C4 three tiles off
	var/obj/item/grenade/plastic/c4/far = new(spot(6, 3))
	var/count = length(booms)
	far.prime()
	sleep(3 SECONDS)
	check("chain: a light blast on its wall leaves it be", booms_since(count) == 1 && !QDELETED(planted), "[booms_since(count)] explosions")
	// heavy: an X4 on the floor beside the wall
	var/obj/item/grenade/plastic/x4/near = new(spot(6, 5))
	count = length(booms)
	near.prime()
	sleep(3 SECONDS)
	check("chain: a heavy blast on its wall sets it off", booms_since(count) == 2 && QDELETED(planted), "[booms_since(count)] explosions")

/// Charges touching go off as one bigger blast: C4 planted on C4 that's then planted on more C4 (the user's round-01.12.53, four planted
/// that way gave one ordinary blast), four on one wall, and one alone as it always was
/datum/charge_check/proc/check_stack()
	build_room(11, 11)
	var/mob/living/carbon/human/rigger = make_human(spot(6, 5), "Rigger")
	// One alone
	var/obj/item/grenade/plastic/c4/alone = new(spot(6, 5))
	alone.det_time = 10
	var/count = length(booms)
	plant(alone, spot(9, 9), rigger)
	sleep(13 SECONDS)
	var/list/B = length(booms) > count ? booms[length(booms)] : null
	check("stack: one C4 is as it was", booms_since(count) == 1 && B && B[2] == 0 && B[3] == 0 && round(B[4], 0.1) == 3, last_boom_text(count))
	// C4 on a loose C4, that C4 picked up and planted on another loose one
	build_room(11, 11)
	rigger = make_human(spot(6, 5), "Rigger")
	var/obj/item/grenade/plastic/c4/bottom = new(spot(6, 6))
	var/obj/item/grenade/plastic/c4/middle = new(spot(6, 5))
	var/obj/item/grenade/plastic/c4/top = new(spot(6, 5))
	top.det_time = 15
	middle.det_time = 30
	count = length(booms)
	plant(top, middle, rigger)
	plant(middle, bottom, rigger)
	check("stack: C4 on C4 on C4 planted", isnull(top.loc) && isnull(middle.loc), "top at [top.loc], middle at [middle.loc]")
	sleep(14 SECONDS)
	B = length(booms) > count ? booms[length(booms)] : null
	var/turf/at = B?[1]
	check("stack: C4 on C4 on C4 is one blast where the bottom one lies, three strong", booms_since(count) == 1 && at == spot(6, 6) && B[4] > 4, last_boom_text(count))
	check("stack: none of the three left", QDELETED(top) && QDELETED(middle) && QDELETED(bottom), "top [QDELETED(top)], middle [QDELETED(middle)], bottom [QDELETED(bottom)]")
	// Four on one wall
	build_room(11, 11)
	rigger = make_human(spot(6, 5), "Rigger")
	var/turf/wall = spot(6, 6)
	wall.ChangeTurf(/turf/closed/wall, list(/turf/open/space, /turf/open/floor/plating))
	var/list/four = list()
	for(var/i in 1 to 4)
		var/obj/item/grenade/plastic/c4/C = new(spot(6, 5))
		C.det_time = 20
		four += C
	count = length(booms)
	for(var/obj/item/grenade/plastic/c4/C as anything in four)
		plant(C, wall, rigger)
	rigger.forceMove(spot(1, 1))
	sleep(12 SECONDS)
	B = length(booms) > count ? booms[length(booms)] : null
	check("stack: four C4 on one wall are one blast with a heavy ring", booms_since(count) == 1 && B && B[3] > 0 && B[4] > 4.5, "[booms_since(count)] explosions, last [last_boom_text(count)]")

/// 150 C4 on one tile, one set off: how many go and how long the server's held up
/datum/charge_check/proc/check_pile()
	build_room(15, 15)
	var/turf/T = spot(8, 8)
	var/list/pile = list()
	for(var/i in 1 to 150)
		pile += new /obj/item/grenade/plastic/c4(T)
	var/count = length(booms)
	var/real_start = REALTIMEOFDAY
	var/game_start = world.time
	var/obj/item/grenade/plastic/c4/first = pile[1]
	first.prime()
	var/prime_ms = (REALTIMEOFDAY - real_start) * 100
	sleep(15 SECONDS)
	var/left = 0
	for(var/obj/item/grenade/plastic/c4/C in pile)
		if(!QDELETED(C))
			left++
	var/last_at = 0
	for(var/i in count + 1 to length(booms))
		var/list/B = booms[i]
		last_at = max(last_at, B[5])
	note("150 C4 on a tile, one set off: [booms_since(count)] explosions over [(last_at - game_start) / 10] s of game time, [left] C4 left, first prime() [prime_ms] ms")
	note("15 s of game time took [(REALTIMEOFDAY - real_start) / 10] s real")
	check("pile: the server keeps going", (REALTIMEOFDAY - real_start) < 60 SECONDS, "[(REALTIMEOFDAY - real_start) / 10] s real")
	check("pile: goes off as one big blast", booms_since(count) == 1 && left == 0, "[booms_since(count)] explosions, [left] left, last [last_boom_text(count)]")

/// Every grenade type made into an explosive lance (spear + grenade, crafted) and driven into somebody, ten at a time in rooms of
/// their own, and a few into a wall: does it go off, is the lance used up, and is anything left inside what it hit
/datum/charge_check/proc/check_lances()
	var/list/cases = list()
	for(var/type in subtypesof(/obj/item/grenade))
		cases += new /datum/lance_case(type, src, FALSE)
	for(var/type in list(/obj/item/grenade/plastic/c4, /obj/item/grenade/plastic/x4, /obj/item/grenade/iedcasing, /obj/item/grenade/syndieminibomb,
		/obj/item/grenade/flashbang, /obj/item/grenade/chem_grenade, /obj/item/grenade/chem_grenade/metalfoam))
		cases += new /datum/lance_case(type, src, TRUE)
	for(var/i = 1, i <= length(cases), i += 10)
		var/list/batch = cases.Copy(i, min(i + 10, length(cases) + 1))
		for(var/datum/lance_case/C as anything in batch)
			INVOKE_ASYNC(C, TYPE_PROC_REF(/datum/lance_case, try_it))
		var/deadline = world.time + 60 SECONDS
		while(world.time < deadline)
			var/done = TRUE
			for(var/datum/lance_case/C as anything in batch)
				if(!C.finished)
					done = FALSE
			if(done)
				break
			sleep(1 SECONDS)
	var/clean = 0
	for(var/datum/lance_case/C as anything in cases)
		var/label = "[C.grenade_type][C.into_wall ? " into a wall" : ""]"
		if(C.problem)
			check("lance: [label]", FALSE, "[C.problem][C.result ? " ([C.result])" : ""]")
		else
			clean++
			note("[label]: [C.result]")
	check("lances: every grenade type clean", clean == length(cases), "[clean] of [length(cases)]")

/datum/lance_case
	var/grenade_type
	var/datum/charge_check/test
	var/into_wall = FALSE
	var/finished = FALSE
	/// What went wrong, or null
	var/problem
	/// What happened
	var/result
	var/x0
	var/y0
	var/z0

/datum/lance_case/New(type, datum/charge_check/T, wall)
	grenade_type = type
	test = T
	into_wall = wall

/datum/lance_case/proc/try_it()
	try
		go()
	catch(var/exception/e)
		problem = "[e] at [e.file]:[e.line]"
	finished = TRUE

/datum/lance_case/proc/go()
	var/datum/turf_reservation/reservation = SSmapping.RequestBlockReservation(13, 13)
	if(!reservation)
		problem = "no room"
		return
	x0 = reservation.bottom_left_coords[1] + 3
	y0 = reservation.bottom_left_coords[2] + 3
	z0 = reservation.bottom_left_coords[3]
	var/area/test_area = new /area/bot_gym
	for(var/x in x0 - 1 to x0 + 7)
		for(var/y in y0 - 1 to y0 + 7)
			var/turf/T = locate(x, y, z0)
			var/area/old_area = T.loc
			old_area.contents -= T
			test_area.contents += T
			T.change_area(old_area, test_area)
			if(x == x0 - 1 || x == x0 + 7 || y == y0 - 1 || y == y0 + 7)
				T.ChangeTurf(/turf/closed/indestructible/riveted, flags = CHANGETURF_IGNORE_AIR)
			else
				var/turf/open/F = T.ChangeTurf(/turf/open/floor/plasteel, list(/turf/open/space, /turf/open/floor/plating), CHANGETURF_IGNORE_AIR)
				F.air.parse_gas_string(OPENTURF_DEFAULT_ATMOS)
				F.update_visuals()
				SSair.add_to_active(F)
	sleep(1 SECONDS)
	var/turf/stand = locate(x0 + 3, y0 + 2, z0)
	var/turf/front = locate(x0 + 3, y0 + 3, z0)
	var/atom/hit
	if(into_wall)
		hit = front.ChangeTurf(/turf/closed/wall, list(/turf/open/space, /turf/open/floor/plating))
	else
		hit = test.make_human(front, "Victim")
	var/mob/living/carbon/human/user = test.make_human(stand, "Lancer")
	var/obj/item/grenade/G = new grenade_type(stand)
	var/obj/item/twohanded/spear/S = new(stand)
	S.CheckParts(list(G))
	var/obj/item/twohanded/spear/explosive/lance = locate() in stand
	if(!lance)
		problem = "no lance made"
		return
	if(lance.explosive != G || G.loc != lance)
		problem = "the lance doesn't hold the grenade: [lance.explosive], grenade at [G.loc]"
		return
	user.put_in_hands(lance)
	lance.wield(user)
	if(!lance.wielded)
		problem = "couldn't wield it"
		return
	var/start = world.time
	lance.afterattack(hit, user, TRUE)
	sleep(12 SECONDS)
	var/booms = 0
	for(var/list/B as anything in test.booms)
		var/turf/E = B[1]
		if(B[5] >= start && E.z == z0 && E.x >= x0 - 1 && E.x <= x0 + 7 && E.y >= y0 - 1 && E.y <= y0 + 7)
			booms++
	var/list/out = list("[booms] explosion[booms == 1 ? "" : "s"]")
	if(!QDELETED(lance))
		problem = "lance still there at [lance.loc]"
	if(QDELETED(G))
		out += "grenade used up"
	else
		var/atom/where = G.loc
		out += "grenade left at [where] ([where?.type])"
		if(ismob(where) || where == hit || isclosedturf(where))
			problem = "grenade left inside [where]"
	if(!into_wall)
		var/mob/living/carbon/human/victim = hit
		out += "victim [test.hurt(victim)]"
	result = jointext(out, ", ")

#undef CHARGE_CHECK_DIR
