// Whether materials survive a round trip through the ore redemption machine and the ore silo: nothing made, nothing lost.
// Not part of the game: tools/ore_check/run.sh. Headless, on a real round (testbench map). For every material and every
// alloy the ORM offers: take 10 out through its own window (Release/Smelt), put what came out back (into the silo when the
// ORM is linked to it, into the ORM when it stands alone, and the other way round), and compare every stored material
// before and after. Also the silo's own Eject. PASS/FAIL per trip, INFO for what each trip did.

/datum/controller/master
	sleep_offline_after_initializations = FALSE

/datum/tgui/ore_check_stub/New()
	status = UI_INTERACTIVE

GLOBAL_VAR_INIT(oc_passed, 0)
GLOBAL_VAR_INIT(oc_failed, 0)

/proc/oc_log(text)
	text2file(text, "data/ore_check/results.txt")

/proc/oc_check(name, ok, detail)
	if(ok)
		GLOB.oc_passed++
	else
		GLOB.oc_failed++
	oc_log("[ok ? "PASS" : "FAIL"] [name][isnull(detail) ? "" : " ([detail])"]")

/world/New()
	. = ..()
	spawn(0)
		ore_check_run()

/proc/oc_floor()
	var/datum/turf_reservation/R = SSmapping.RequestBlockReservation(30, 30)
	var/x0 = R.bottom_left_coords[1]
	var/y0 = R.bottom_left_coords[2]
	var/z = R.bottom_left_coords[3]
	var/area/bot_gym/A = new
	for(var/turf/T in block(locate(x0, y0, z), locate(x0 + 29, y0 + 29, z)))
		var/area/old_area = T.loc
		old_area.contents -= T
		A.contents += T
		T.change_area(old_area, A)
		T.ChangeTurf(/turf/open/floor/plasteel, flags = CHANGETURF_IGNORE_AIR)
	return locate(x0, y0, z)

/proc/oc_amounts(datum/component/material_container/C)
	. = list()
	for(var/id in C.materials)
		var/datum/material/M = C.materials[id]
		.[id] = M.amount

/// "metal 200 -> 210" for every material that changed
/proc/oc_changes(list/before, list/after)
	var/list/out = list()
	for(var/id in before)
		if(abs(before[id] - after[id]) > 0.01)
			out += "[copytext(id, length(id[1]) + 1)] [before[id] / MINERAL_MATERIAL_AMOUNT] -> [after[id] / MINERAL_MATERIAL_AMOUNT]"
	return out.Join(", ")

/proc/oc_fill(datum/component/material_container/C, sheets)
	C.total_amount = 0
	for(var/id in C.materials)
		var/datum/material/M = C.materials[id]
		M.amount = sheets * MINERAL_MATERIAL_AMOUNT
		C.total_amount += M.amount

/// Everything the ORM put out (a stack per sheet type), picked up off its output tile
/proc/oc_output(obj/machinery/mineral/ore_redemption/orm)
	. = list()
	for(var/obj/item/stack/S in get_step(orm, orm.output_dir))
		. += S
	for(var/obj/item/stack/S in orm.loc)
		. += S

/// One trip: `action` (Release or Smelt) 10 of `id` out of the ORM, then each stack that came out handed in to `deposit_into`
/proc/oc_trip(label, obj/machinery/mineral/ore_redemption/orm, datum/component/material_container/store, atom/deposit_into, mob/living/carbon/human/user, action, id)
	var/list/before = oc_amounts(store)
	var/datum/tgui/ore_check_stub/stub = new
	usr = user
	orm.ui_act(action, list("id" = id, "sheets" = 10), stub)
	var/list/out = oc_output(orm)
	var/list/made = list()
	for(var/obj/item/stack/S in out)
		made += "[S.amount] [S.singular_name]"
	var/list/mid = oc_amounts(store)
	for(var/obj/item/stack/S in out)
		user.put_in_active_hand(S)
		deposit_into.attackby(S, user)
		if(!QDELETED(S)) // what wasn't taken
			qdel(S)
	var/list/after = oc_amounts(store)
	var/took = oc_changes(before, mid)
	var/net = oc_changes(before, after)
	oc_check("[label]: [action] [id] and hand it back", !length(net), "out: [made.Join(", ") || "nothing"]; taking it cost [took || "nothing"]; net change [net || "none"]")

/proc/oc_user(turf/T)
	var/mob/living/carbon/human/H = new(T)
	H.mind_initialize()
	H.a_intent = INTENT_HELP
	return H

/proc/oc_alloys(obj/machinery/mineral/ore_redemption/orm)
	. = list()
	for(var/v in orm.stored_research.researched_designs)
		. += v

/// The user's way (2026-11-10): Smelt every alloy and Release every material in 50s until there's nothing left, then
/// click the ORM with every stack that came out (the real click chain, melee_attack_chain), and compare with the start.
/proc/oc_drain(label, obj/machinery/mineral/ore_redemption/orm, datum/component/material_container/store, mob/living/carbon/human/user, atom/deposit_into)
	var/list/start = oc_amounts(store)
	var/datum/tgui/ore_check_stub/stub = new
	usr = user
	var/smelts = 0
	var/releases = 0
	for(var/id in oc_alloys(orm))
		var/datum/design/D = SSresearch.techweb_design_by_id(id)
		for(var/i in 1 to 40)
			if(!orm.can_smelt_alloy(D))
				break
			orm.ui_act("Smelt", list("id" = id, "sheets" = 50), stub)
			smelts++
	for(var/id in store.materials)
		var/datum/material/M = store.materials[id]
		for(var/i in 1 to 40)
			if(M.amount < MINERAL_MATERIAL_AMOUNT)
				break
			orm.ui_act("Release", list("id" = id, "sheets" = 50), stub)
			releases++
	var/list/emptied = oc_amounts(store)
	var/list/stacks = oc_output(orm)
	var/sheets_out = 0
	for(var/obj/item/stack/S in stacks)
		sheets_out += S.amount
	var/left_in_hand = 0
	for(var/obj/item/stack/S in stacks)
		user.put_in_active_hand(S)
		S.melee_attack_chain(user, deposit_into || orm)
		if(!QDELETED(S))
			left_in_hand += S.amount
			qdel(S)
	var/list/after = oc_amounts(store)
	oc_log("INFO [label]: [smelts] smelts and [releases] releases, [length(stacks)] stacks of [sheets_out] sheets out; emptied to [oc_changes(start, emptied) || "no change"]")
	oc_check("[label]: everything out and clicked back into [deposit_into || orm] comes to what was there", !length(oc_changes(start, after)), "net change [oc_changes(start, after) || "none"]")
	oc_check("[label]: no sheets left over in hand", !left_in_hand, "[left_in_hand] left")

/proc/ore_check_run()
	UNTIL(SSticker.initialized)
	GLOB.master_mode = "extended"
	SSticker.start_immediately = TRUE
	var/deadline = world.time + 5 MINUTES
	while(SSticker.current_state < GAME_STATE_PLAYING && world.time < deadline)
		sleep(1 SECONDS)
	sleep(5 SECONDS)
	oc_log("round state [SSticker.current_state]")
	var/turf/C = oc_floor()

	// Linked: an ORM on the silo, as the station's is
	var/obj/machinery/ore_silo/silo = new(locate(C.x + 2, C.y + 2, C.z))
	var/obj/machinery/mineral/ore_redemption/orm = new(locate(C.x + 6, C.y + 6, C.z))
	orm.req_access = list()
	var/datum/component/remote_materials/R = orm.materials
	if(R.mat_container)
		R.mat_container.retrieve_all()
		qdel(R.mat_container)
	R.silo = silo
	silo.connected += R
	R.mat_container = silo.GetComponent(/datum/component/material_container)
	var/datum/component/material_container/silo_mats = R.mat_container
	var/mob/living/carbon/human/U = oc_user(locate(C.x + 6, C.y + 4, C.z))
	oc_fill(silo_mats, 200)
	oc_log("--- ORM linked to the silo, sheets back into the silo")
	for(var/id in silo_mats.materials)
		oc_trip("linked", orm, silo_mats, silo, U, "Release", id)
	for(var/id in oc_alloys(orm))
		oc_trip("linked", orm, silo_mats, silo, U, "Smelt", id)
	oc_log("--- ORM linked to the silo, sheets back into the ORM")
	for(var/id in silo_mats.materials)
		oc_trip("linked", orm, silo_mats, orm, U, "Release", id)
	for(var/id in oc_alloys(orm))
		oc_trip("linked", orm, silo_mats, orm, U, "Smelt", id)

	oc_log("--- the silo's own Eject, back into the silo")
	for(var/id in silo_mats.materials)
		var/list/before = oc_amounts(silo_mats)
		silo.Topic(null, list("ejectsheet" = id, "eject_amt" = "10"))
		for(var/obj/item/stack/S in silo.drop_location())
			U.put_in_active_hand(S)
			silo.attackby(S, U)
			if(!QDELETED(S))
				qdel(S)
		oc_check("silo eject [id] and hand it back", !length(oc_changes(before, oc_amounts(silo_mats))), oc_changes(before, oc_amounts(silo_mats)) || null)

	// Standalone: an ORM with its own storage, the silo's untouched
	var/obj/machinery/mineral/ore_redemption/lone = new(locate(C.x + 16, C.y + 16, C.z))
	lone.req_access = list()
	var/datum/component/material_container/lone_mats = lone.materials.mat_container
	oc_check("a new ORM off the station stores locally", lone_mats && !lone.materials.silo)
	if(lone_mats)
		oc_fill(lone_mats, 200)
		var/mob/living/carbon/human/U2 = oc_user(locate(C.x + 16, C.y + 14, C.z))
		var/list/silo_before = oc_amounts(silo_mats)
		oc_log("--- standalone ORM, sheets back into it")
		for(var/id in lone_mats.materials)
			oc_trip("standalone", lone, lone_mats, lone, U2, "Release", id)
		for(var/id in oc_alloys(lone))
			oc_trip("standalone", lone, lone_mats, lone, U2, "Smelt", id)
		oc_check("the standalone ORM's trips left the silo alone", !length(oc_changes(silo_before, oc_amounts(silo_mats))), oc_changes(silo_before, oc_amounts(silo_mats)) || null)

	// Drained the user's way, with uneven amounts (upgraded ORMs leave fractions of a sheet)
	oc_log("--- drained to nothing and clicked back in, linked")
	for(var/id in silo_mats.materials)
		var/datum/material/M = silo_mats.materials[id]
		M.amount = 137.35 * MINERAL_MATERIAL_AMOUNT
	silo_mats.total_amount = 0
	for(var/id in silo_mats.materials)
		var/datum/material/M = silo_mats.materials[id]
		silo_mats.total_amount += M.amount
	oc_drain("linked", orm, silo_mats, U)

	// What the user did in round-08.58.42: released from the ORM, then clicked the cargo techfab two tiles north with every stack
	oc_log("--- drained, then clicked into a cargo techfab on the silo")
	var/obj/machinery/rnd/production/techfab/department/cargo/fab = new(locate(C.x + 6, C.y + 8, C.z))
	var/datum/component/remote_materials/FR = fab.materials
	if(FR.mat_container && !FR.silo)
		FR.mat_container.retrieve_all()
		qdel(FR.mat_container)
	FR.silo = silo
	silo.connected += FR
	FR.mat_container = silo_mats
	oc_fill(silo_mats, 120)
	oc_drain("techfab", orm, silo_mats, U, fab)
	if(lone_mats)
		oc_log("--- drained to nothing and clicked back in, standalone")
		oc_fill(lone_mats, 83)
		oc_drain("standalone", lone, lone_mats, oc_user(locate(C.x + 16, C.y + 13, C.z)))

	// The 2026-11-10 fixes and the new window's actions
	oc_log("--- more than a stack at once, and forged counts")
	var/datum/tgui/ore_check_stub/stub = new
	usr = U
	var/datum/material/metal = silo_mats.materials[MAT_METAL]
	oc_fill(silo_mats, 200)
	silo_mats.retrieve_sheets(120, MAT_METAL, get_turf(U))
	oc_check("ejecting 120 of 200 costs 120", metal.amount == 80 * MINERAL_MATERIAL_AMOUNT, "[metal.amount / MINERAL_MATERIAL_AMOUNT] left")
	for(var/obj/item/stack/S in get_turf(U))
		qdel(S)
	oc_fill(silo_mats, 137)
	orm.ui_act("Release", list("id" = MAT_METAL, "all" = 1), stub)
	var/out = 0
	for(var/obj/item/stack/sheet/metal/S in oc_output(orm))
		out += S.amount
	oc_check("Release All gives every sheet, in stacks of 50", metal.amount == 0 && out == 137, "[metal.amount / MINERAL_MATERIAL_AMOUNT] left, [out] out")
	for(var/obj/item/stack/S in oc_output(orm))
		qdel(S)
	oc_fill(silo_mats, 200)
	var/list/before = oc_amounts(silo_mats)
	orm.ui_act("Smelt", list("id" = "plasteel", "sheets" = -10), stub)
	orm.ui_act("Smelt", list("id" = "plasteel", "sheets" = 0), stub)
	orm.ui_act("Release", list("id" = MAT_GLASS, "sheets" = -10), stub)
	oc_check("negative and zero counts change nothing", !length(oc_changes(before, oc_amounts(silo_mats))) && !length(oc_output(orm)), oc_changes(before, oc_amounts(silo_mats)) || null)
	orm.ui_act("Smelt", list("id" = "plasteel", "all" = 1), stub)
	var/plasteel = 0
	for(var/obj/item/stack/sheet/plasteel/S in oc_output(orm))
		plasteel += S.amount
	var/inside = 0
	for(var/obj/item/stack/S in orm)
		inside += S.amount
	oc_check("Smelt All makes 200 plasteel, all of it out of the machine", plasteel == 200 && !inside, "[plasteel] out, [inside] left inside")
	for(var/obj/item/stack/S in oc_output(orm))
		qdel(S)

	oc_log("[GLOB.oc_passed] passed, [GLOB.oc_failed] failed")
	oc_log("done")
	sleep(5)
	del(world)
