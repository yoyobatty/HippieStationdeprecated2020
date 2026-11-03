// Nuclear operatives: a team of bots with the game's own nuke op antagonist datum (bot-nukeops=N on a Bot Shift, or
// bot_spawn_nukeops()). They play it the way a team of players does:
//
//  - At the base: the uplink (an emag for the doors, an energy sword), then aboard the infiltrator. The shuttle's suit storage
//    units have their hardsuits: the suit on, the helmet up, the mask, and a full oxygen tank out of the shuttle's dispenser in
//    the suit's storage for the suit's jetpack to run off.
//  - The leader flies them to the station once they're all aboard and suited, or once they've waited long enough.
//  - At the station: the disk. Whoever's carrying it gets killed for it and searched; a disk lying about gets picked up. The pinpointer
//    every operative carries says where it is, which is why they know.
//  - The one with the disk takes it back to the nuke on the shuttle, puts it in, enters the code, sets the shortest timer and arms it.
//    The shuttle's docked on the station's z-level, which is close enough for the station to go with it.
//  - Then they hold the shuttle: anybody who comes aboard to stop it gets killed.
//
// They're loud from the start (gone_loud()): no job, no small talk, and what they say is what an antagonist says.

/// How long the leader waits for the team before going anyway.
#define BOT_OPS_LAUNCH_WAIT (5 MINUTES)
/// How close to the nuke they hold once it's armed, and how far they look for anybody coming for it.
#define BOT_OPS_HOLD 4
#define BOT_OPS_GUARD 8

/datum/bot_nuke_team
	var/list/members = list()
	var/datum/bot_brain/leader
	var/obj/machinery/nuclearbomb/nuke
	var/code
	var/launched = FALSE
	var/launch_at = 0
	/// id -> the blast door or shutter: see door_shut().
	var/list/doors = list()
	/// Brain -> the suit storage unit it's taking its suit from.
	var/list/units_claimed = list()

GLOBAL_DATUM(bot_nuke_team, /datum/bot_nuke_team)

/datum/bot_brain
	var/datum/bot_nuke_team/op_team
	var/op_shopped = FALSE
	var/op_bought_suit = FALSE
	var/op_arrival_noted = FALSE
	var/op_space_note_at = 0
	var/op_tank_tried = FALSE
	var/op_resuit_at = 0

/// count operatives, the first of them the leader, each with a brain. The datum dresses them and puts them at the base.
/proc/bot_spawn_nukeops(count)
	if(count <= 0 || !length(GLOB.nukeop_start))
		return 0
	var/datum/bot_nuke_team/team = new
	GLOB.bot_nuke_team = team
	team.launch_at = world.time + BOT_OPS_LAUNCH_WAIT
	var/datum/team/nuclear/antag_team
	for(var/i in 1 to count)
		var/mob/living/carbon/human/H = new(GLOB.nukeop_start[1])
		H.mind_initialize()
		H.mind.assigned_role = "Nuclear Operative"
		var/datum/antagonist/nukeop/N = i == 1 ? new /datum/antagonist/nukeop/leader : new /datum/antagonist/nukeop
		H.mind.add_antag_datum(N, antag_team)
		antag_team = N.nuke_team
		var/datum/bot_brain/B = new(H)
		B.op_team = team
		B.set_playstyle(BOT_STYLE_ROBUST)
		B.bot_traitor = TRUE //the antagonist talk and the hostility of a traitor who's been found out (goals/robust.dm)
		team.members += B
		if(i == 1)
			team.leader = B
	team.nuke = antag_team?.tracked_nuke
	team.code = antag_team?.memorized_code
	log_game("BOT OPS: [count] operatives, nuke [team.nuke ? AREACOORD(team.nuke) : "missing"]")
	return count

/datum/bot_nuke_team/proc/living_members()
	. = list()
	for(var/datum/bot_brain/B as anything in members)
		if(!QDELETED(B.owner) && B.owner.stat != DEAD)
			. += B

/// Everybody alive is aboard and suited, or they've waited long enough.
/datum/bot_nuke_team/proc/ready_to_go()
	if(world.time >= launch_at)
		return TRUE
	for(var/datum/bot_brain/B as anything in living_members())
		if(!istype(get_area(B.owner), /area/shuttle/syndicate) || !B.op_suited())
			return FALSE
	return TRUE

/// The blast doors and shutters on the way, by id: "nukeop_ready" between the base and the dock, which the leader's
/// "mission launch control" opens, and "smindicate", the infiltrator's own hatch.
/datum/bot_nuke_team/proc/door_shut(id)
	var/obj/machinery/door/poddoor/P = doors[id]
	if(!P)
		for(var/obj/machinery/door/poddoor/candidate in GLOB.machines)
			if(candidate.id == id)
				P = candidate
				doors[id] = P
				break
	return P && !QDELETED(P) && P.density

/// Presses the button that works that door, wherever it is on this z-level. The hatch's is on the door's own tile, in reach from
/// the dock and from inside.
/datum/bot_brain/proc/op_press_for(id)
	var/obj/machinery/door/poddoor/P = op_team.doors[id]
	if(!P || P.z != owner.z)
		return FALSE
	for(var/obj/machinery/button/door/B in GLOB.machines)
		if(B.id == id && B.z == owner.z && B.allowed(owner))
			return assign_goal(new /datum/bot_goal/press_door_button(B, P))
	return FALSE

/// The hatch's button is on the hatch's own tile. From inside, that's a step away; from the dock, it's from inside the dock's
/// airlock, stood in the doorway.
/datum/bot_goal/op_hatch
	doing = "opening the hatch"
	var/obj/machinery/door/poddoor/door
	var/obj/machinery/button/door/button
	/// The tile it presses from.
	var/turf/doorway

/datum/bot_goal/op_hatch/New(obj/machinery/door/poddoor/P)
	. = ..()
	door = P
	for(var/obj/machinery/button/door/B in get_turf(P))
		if(B.id == P.id)
			button = B

/datum/bot_goal/op_hatch/resolve_target(datum/bot_brain/bot)
	target = null
	if(QDELETED(door) || QDELETED(button) || door.z != bot.owner.z)
		return
	for(var/d in GLOB.cardinals)
		var/turf/T1 = get_step(door, d)
		if(!isopenturf(T1))
			continue
		if(!(locate(/obj/machinery/door) in T1) && bot.can_walk_lawfully_to(T1))
			doorway = T1
			target = T1
			return
		var/turf/T2 = get_step(T1, d)
		if(isopenturf(T2) && (locate(/obj/machinery/door/airlock) in T1) && bot.can_walk_lawfully_to(T2))
			doorway = T1
			target = T2
			return

/datum/bot_goal/op_hatch/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/op_simple/S = new
	S.steps = list(new /datum/bot_step/move_to(), new /datum/bot_step/paced/op_hatch())
	return list(S)

/datum/bot_step/paced/op_hatch
	max_clicks = 12

/datum/bot_step/paced/op_hatch/start(datum/bot_brain/bot)
	return TRUE

/datum/bot_step/paced/op_hatch/do_click(datum/bot_brain/bot)
	var/datum/bot_goal/op_hatch/G = bot.current_goal
	if(!istype(G) || QDELETED(G.button) || QDELETED(G.door) || !G.door.density)
		return FALSE
	if(bot.owner.Adjacent(G.button))
		bot.human_pause(G.button)
		bot.owner.face_atom(G.button)
		bot.telemetry_clicked(G.button)
		G.button.attack_hand(bot.owner)
		wait_for = 2 SECONDS
		return TRUE
	var/far = get_dist(bot.owner, G.doorway)
	if(far >= 1 && far <= 4) //walking to a tile stops a step short of it: the last few, and into the doorway, by hand
		var/turf/next = get_step_towards(bot.owner, G.doorway)
		bot.owner.Move(next, get_dir(bot.owner, next)) //into an airlock, the first bump opens it and the next walks in
		wait_for = 1 SECONDS
		return TRUE
	bot_log(bot, "can't get at [G.button] from [AREACOORD(bot.owner)]: the doorway's [G.doorway ? AREACOORD(G.doorway) : "nowhere"]")
	return FALSE

/datum/bot_step/paced/op_hatch/finish(datum/bot_brain/bot)
	var/datum/bot_goal/op_hatch/G = bot.current_goal
	return istype(G) && !QDELETED(G.door) && !G.door.density ? GOAL_STEP_SUCCESS : GOAL_STEP_FAIL

/// The infiltrator's own console: not the recall terminal at the base, which is the same type underneath.
/proc/bot_ops_console()
	for(var/obj/machinery/computer/shuttle/syndicate/C in GLOB.machines)
		if(C.type == /obj/machinery/computer/shuttle/syndicate && istype(get_area(C), /area/shuttle/syndicate))
			return C
	return null

/// Tries spots out from the station's external airlocks, the shuttle turned each way, with the navigation computer's own check on
/// every tile it would land on, and designates the first that's clear: the custom location the shuttle console then flies to.
/proc/bot_ops_designate_landing(datum/bot_brain/bot)
	var/obj/machinery/computer/camera_advanced/shuttle_docker/nav
	for(var/obj/machinery/computer/camera_advanced/shuttle_docker/D in GLOB.navigation_computers)
		if(D.shuttleId == "syndicate" && D.shuttle_port)
			nav = D
			break
	if(!nav)
		log_game("BOT OPS: no navigation computer connected to the shuttle")
		return FALSE
	var/list/airlocks = list()
	for(var/obj/machinery/door/airlock/external/A in GLOB.machines)
		if(is_station_level(A.z) && !istype(get_area(A), /area/shuttle))
			airlocks += A
	var/tried = 0
	for(var/obj/machinery/door/airlock/external/A as anything in shuffle(airlocks))
		for(var/d in GLOB.cardinals)
			var/turf/out = get_step(A, d) //the way out: a catwalk or a bit of plating first, often enough
			for(var/i in 1 to 3)
				if(!out || isspaceturf(out))
					break
				out = get_step(out, d)
			if(!isspaceturf(out))
				continue
			tried++
			for(var/dist in list(4, 7, 10, 13))
				var/turf/spot = get_ranged_target_turf(A, d, dist)
				for(var/pdir in GLOB.cardinals)
					if(!bot_ops_landing_clear(nav, spot, pdir))
						continue
					if(!nav.my_port)
						var/obj/docking_port/mobile/M = nav.shuttle_port
						nav.my_port = new()
						nav.my_port.name = nav.shuttlePortName
						nav.my_port.id = nav.shuttlePortId
						nav.my_port.height = M.height
						nav.my_port.width = M.width
						nav.my_port.dheight = M.dheight
						nav.my_port.dwidth = M.dwidth
						nav.my_port.hidden = M.hidden
					nav.my_port.setDir(pdir)
					nav.my_port.forceMove(spot)
					bot.telemetry_ui_action(nav, "designate landing at [AREACOORD(spot)]")
					log_game("BOT OPS: landing designated at [AREACOORD(spot)], by [A] ([get_area_name(A, TRUE)])")
					return TRUE
	log_game("BOT OPS: no landing found: [length(airlocks)] external airlocks, [tried] facing space")
	return FALSE

/proc/bot_ops_landing_clear(obj/machinery/computer/camera_advanced/shuttle_docker/nav, turf/spot, pdir)
	if(!spot)
		return FALSE
	var/list/bounds = nav.shuttle_port.return_coords(spot.x, spot.y, pdir)
	var/list/overlappers = SSshuttle.get_dock_overlap(bounds[1], bounds[2], bounds[3], bounds[4], spot.z)
	var/turf/c1 = locate(min(bounds[1], bounds[3]), min(bounds[2], bounds[4]), spot.z)
	var/turf/c2 = locate(max(bounds[1], bounds[3]), max(bounds[2], bounds[4]), spot.z)
	if(!c1 || !c2)
		return FALSE
	for(var/turf/T as anything in block(c1, c2))
		if(nav.checkLandingTurf(T, overlappers) != SHUTTLE_DOCKER_LANDING_CLEAR)
			return FALSE
	return TRUE

/// The suit's jetpack drinks from the tank in the suit's storage, a little every step it's on: on for a step into space or
/// somewhere with no gravity, off again on a floor, the way a player flicks it.
/datum/bot_brain/proc/op_mind_jetpack(turf/next_node)
	var/obj/item/tank/jetpack/J = owner.get_jetpack()
	if(!J || !is_eva_ready())
		return
	var/need = isspaceturf(next_node) || isspaceturf(get_turf(owner)) || !next_node.has_gravity()
	if(J.on != need)
		J.cycle(owner)

/proc/bot_ops_shuttle()
	return SSshuttle.getShuttle("syndicate")

/proc/bot_ops_at_station()
	var/obj/docking_port/mobile/S = bot_ops_shuttle()
	return S && S.mode == SHUTTLE_IDLE && is_station_level(S.z)

/// The real disk, wherever it is.
/proc/bot_find_nuke_disk()
	for(var/obj/item/disk/nuclear/D as anything in bot_instances_of(/obj/item/disk/nuclear))
		if(!QDELETED(D) && !D.fake)
			return D
	return null

/datum/bot_brain/proc/op_suited()
	var/obj/item/clothing/suit/space/hardsuit/suit = owner.wear_suit
	return istype(suit) && suit.suittoggled && (suit.clothing_flags & STOPSPRESSUREDAMAGE) && istype(owner.s_store, /obj/item/tank/internals) && (owner.wear_mask?.clothing_flags & MASKINTERNALS)

/datum/bot_duty/nuke_op
	name = "the operation"
	tier = BOT_DUTY_URGENT
	priority = 9
	interval_min = 20
	interval_max = 40

/datum/bot_duty/nuke_op/applies_to(datum/bot_brain/bot)
	return !!bot.op_team

/datum/bot_duty/nuke_op/next_look(datum/bot_brain/bot)
	return rand(interval_min, interval_max)

/datum/bot_duty/nuke_op/try_start(datum/bot_brain/bot)
	return bot.op_business()

/datum/bot_brain/proc/op_business()
	var/datum/bot_nuke_team/team = op_team
	if(owner.incapacitated() || !team)
		return FALSE
	if(owner.health <= owner.maxHealth * health_to_run_at() && patch_up()) //goals/robust.dm
		return TRUE
	if(!team.launched)
		if(!op_shopped)
			op_shopped = TRUE
			if(assign_goal(new /datum/bot_goal/op_shop()))
				return TRUE
		if(team.door_shut("nukeop_ready")) //the leader's to open, once they're kitted out
			return src == team.leader ? op_press_for("nukeop_ready") : FALSE
	if(team.door_shut("smindicate") && assign_goal(new /datum/bot_goal/op_hatch(team.doors["smindicate"])))
		return TRUE
	if(!team.launched)
		if(!op_suited())
			var/suited = istype(owner.wear_suit, /obj/item/clothing/suit/space/hardsuit)
			var/obj/machinery/suit_storage_unit/U = suited ? null : op_find_suit() //three on the shuttle: the rest buy theirs. In one already, the rest's
			//out of the bag (the survival box's mask and tank), not another unit
			if((U || suited || !op_bought_suit) && assign_goal(new /datum/bot_goal/op_suit_up(U)))
				return TRUE
		if(!op_tank_tried && op_tank_small())
			op_tank_tried = TRUE
			var/obj/structure/tank_dispenser/D = op_tank_dispenser()
			if(D && assign_goal(new /datum/bot_goal/op_tank(D)))
				return TRUE
		if(!istype(get_area(owner), /area/shuttle/syndicate))
			return assign_goal(new /datum/bot_goal/op_board())
		if(src == team.leader && team.ready_to_go())
			return assign_goal(new /datum/bot_goal/op_launch())
		return FALSE
	if(!bot_ops_at_station())
		return FALSE //on the way
	if(!op_arrival_noted)
		op_arrival_noted = TRUE
		var/obj/item/tank/jetpack/J = owner.get_jetpack()
		log_game("BOT OPS: [owner] at the station: eva ready [is_eva_ready()], space [can_path_through_space()], jetpack [J ? (J.on ? "on" : "off") : "none"], mask [owner.wear_mask], suit storage [owner.s_store]")
	var/obj/item/tank/jetpack/pack = owner.get_jetpack()
	if(!can_path_through_space() && world.time >= op_space_note_at)
		op_space_note_at = world.time + 1 MINUTES
		var/obj/item/tank/internals/T = eva_tank()
		log_game("BOT OPS: [owner] can't cross space: eva ready [is_eva_ready()], jetpack [pack ? (pack.on ? "on" : "off") : "none"], low air [low_air_stay_in], tank [T] [T ? round(T.air_contents.return_pressure()) : 0] kPa, internals [owner.internal], suit [owner.wear_suit], helmet up [istype(owner.wear_suit, /obj/item/clothing/suit/space/hardsuit) ? owner.wear_suit:vars["suittoggled"] : "-"], mask [owner.wear_mask]")
	// Stripped by Security, or the helmet's down: suited again, off the uplink if the suit's gone, or nobody's crossing back to the nuke.
	if(!op_suited() && world.time >= op_resuit_at && !owner.handcuffed)
		op_resuit_at = world.time + 1 MINUTES
		if(assign_goal(new /datum/bot_goal/op_suit_up()))
			return TRUE
	var/obj/machinery/nuclearbomb/N = team.nuke
	if(QDELETED(N))
		return op_hunt_crew()
	if(N.timing)
		return op_hold()
	var/obj/item/disk/nuclear/disk = bot_find_nuke_disk()
	if(disk && (disk in owner.GetAllContents()))
		return assign_goal(new /datum/bot_goal/op_arm(N))
	if(disk && disk.loc == N)
		return assign_goal(new /datum/bot_goal/op_arm(N)) //somebody put it in and didn't finish
	if(!disk)
		return op_hold()
	var/mob/living/carrier
	for(var/atom/A = disk.loc; A && !isturf(A); A = A.loc)
		if(isliving(A))
			carrier = A
			break
	if(carrier)
		var/mob/living/carbon/human/op = carrier
		if(istype(op) && op.bot_brain?.op_team)
			return op_hold() //one of us has it
		if(istype(carrier.loc, /obj/machinery) || istype(carrier.loc, /obj/structure/closet)) //a sleeper, say: out they come first
			return assign_goal(new /datum/bot_goal/op_eject(carrier.loc))
		return assign_goal(new /datum/bot_goal/traitor_kill/robust/op_disk(null, carrier))
	return assign_goal(new /datum/bot_goal/op_grab_disk(disk))

/// Armed: anybody coming for it dies; otherwise it stays close.
/datum/bot_brain/proc/op_hold()
	var/obj/machinery/nuclearbomb/N = op_team.nuke
	if(QDELETED(N))
		return op_hunt_crew()
	for(var/mob/living/carbon/human/H in view(BOT_OPS_GUARD, N))
		if(H.stat != DEAD && !H.bot_brain?.op_team && !is_nuclear_operative(H) && assign_goal(new /datum/bot_goal/traitor_kill/robust/op_disk(null, H)))
			return TRUE
	if(get_dist(owner, N) > BOT_OPS_HOLD)
		return assign_goal(new /datum/bot_goal/op_board(N))
	return FALSE

/// Nothing to arm and nothing to guard: whoever's about.
/datum/bot_brain/proc/op_hunt_crew()
	for(var/mob/living/carbon/human/H in view(BOT_SIGHT_RANGE, owner))
		if(H.stat != DEAD && !H.bot_brain?.op_team && !is_nuclear_operative(H) && assign_goal(new /datum/bot_goal/traitor_kill/robust/op_disk(null, H)))
			return TRUE
	return FALSE

/// One of the shuttle's suit storage units with a suit still in it, that none of the others has gone for: three people
/// making for the nearest one leaves two of them with nothing.
/datum/bot_brain/proc/op_find_suit()
	var/obj/machinery/suit_storage_unit/mine = op_team.units_claimed[src]
	if(mine && !QDELETED(mine) && mine.suit)
		return mine
	var/obj/machinery/suit_storage_unit/best
	for(var/obj/machinery/suit_storage_unit/syndicate/U in GLOB.machines)
		if(!U.suit || U.z != owner.z || (U in op_team.units_claimed))
			continue
		if(!best || get_dist(owner, U) < get_dist(owner, best))
			best = U
	if(best)
		op_team.units_claimed[src] = best
	return best

// ---------------------------------------------------------------------------------------------
// At the base
// ---------------------------------------------------------------------------------------------

/datum/bot_goal/op_shop
	doing = "gearing up"

/datum/bot_goal/op_shop/resolve_target(datum/bot_brain/bot)
	target = bot.owner

/datum/bot_goal/op_shop/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/op_simple/S = new
	S.steps = list(new /datum/bot_step/op_shop())
	return list(S)

/datum/bot_strategy/op_simple/is_feasible(datum/bot_brain/bot)
	return bot.current_goal?.target && !QDELETED(bot.current_goal.target)

/// An emag for the station's doors and a sword, off the uplink.
/datum/bot_step/op_shop/execute(datum/bot_brain/bot)
	for(var/path in list(/obj/item/card/emag, /obj/item/melee/transforming/energy/sword/saber))
		if(!bot.find_carried_tool(path) && bot.buy_from_uplink(path)) //goals/traitor.dm
			var/obj/item/I = bot.find_carried_tool(path)
			bot_log(bot, "bought [I || "nothing"] off the uplink")
			bot.put_away(I)
	return GOAL_STEP_SUCCESS

/datum/bot_goal/op_suit_up
	doing = "suiting up"
	var/obj/machinery/suit_storage_unit/unit

/datum/bot_goal/op_suit_up/New(obj/machinery/suit_storage_unit/U)
	. = ..()
	unit = U

/datum/bot_goal/op_suit_up/resolve_target(datum/bot_brain/bot)
	target = unit ? (QDELETED(unit) ? null : unit) : bot.owner //no unit: the uplink, then dressing on the spot

/datum/bot_goal/op_suit_up/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/op_simple/S = new
	S.steps = list(new /datum/bot_step/move_to(), new /datum/bot_step/paced/op_suit_up())
	return list(S)

/// The unit's door, then the suit, the mask, a tank into the suit's storage, the helmet up and the suit's jetpack on: a click each.
/datum/bot_step/paced/op_suit_up
	max_clicks = 10
	var/stage = 0

/datum/bot_step/paced/op_suit_up/start(datum/bot_brain/bot)
	stage = 0
	return bot.owner.Adjacent(bot.current_goal?.target)

/datum/bot_step/paced/op_suit_up/do_click(datum/bot_brain/bot)
	var/obj/machinery/suit_storage_unit/U = bot.current_goal?.target
	var/mob/living/carbon/human/H = bot.owner
	if(!istype(U))
		U = null //bought: dressing on the spot
	else if(QDELETED(U) || (stage <= 2 && !H.Adjacent(U))) //the rest is putting on what's already in hand
		return FALSE
	bot.human_pause(U || H)
	switch(stage++)
		if(0)
			if(!U)
				if(!(locate(/obj/item/clothing/suit/space/hardsuit) in H.GetAllContents()))
					bot.op_bought_suit = TRUE
					for(var/path in list(/obj/item/clothing/suit/space/hardsuit/syndi, /obj/item/clothing/suit/space/hardsuit/syndi/elite))
						if(bot.buy_from_uplink(path)) //goals/traitor.dm
							bot_log(bot, "bought [path] off the uplink: the shuttle's units are taken")
							break
			else if(!U.state_open)
				bot.telemetry_ui_action(U, "door")
				U.open_machine(0)
		if(1)
			if(istype(H.wear_suit, /obj/item/clothing/suit/space/hardsuit))
				return TRUE
			if(!U)
				var/obj/item/clothing/suit/space/hardsuit/bought = locate() in H.GetAllContents()
				if(!bought || !bot.op_put_on(bought, ITEM_SLOT_OCLOTHING))
					return FALSE
				wait_for = max(1 SECONDS, bought.equip_delay_self)
				return TRUE
			var/obj/item/clothing/suit/space/hardsuit/suit = U.suit
			if(!suit)
				bot_log(bot, "[U] has no suit in it")
				return FALSE
			U.suit = null
			bot.telemetry_ui_action(U, "dispense suit")
			bot.op_take_dispensed(suit, U)
			if(!bot.op_put_on(suit, ITEM_SLOT_OCLOTHING))
				return FALSE
			wait_for = max(1 SECONDS, suit.equip_delay_self)
		if(2)
			if(!H.wear_mask)
				var/obj/item/clothing/mask/M = U?.mask
				if(M)
					U.mask = null
					bot.telemetry_ui_action(U, "dispense mask")
					bot.op_take_dispensed(M, U)
				else
					M = locate(/obj/item/clothing/mask/gas/syndicate) in H.GetAllContents() //the survival box has one too
				if(M)
					bot.op_put_on(M, ITEM_SLOT_MASK)
		if(3)
			if(istype(H.s_store, /obj/item/tank/internals))
				return TRUE
			var/obj/item/tank/internals/T = locate() in H.GetAllContents() //the survival box in the bag has one
			if(!T)
				bot_log(bot, "no tank to put in the suit's storage")
				return FALSE
			if(H.s_store) //the pistol, say: it goes in the bag
				var/obj/item/old = H.s_store
				if(H.temporarilyRemoveItemFromInventory(old))
					H.put_in_hands(old)
					bot.stow_or_drop(old)
			bot.op_put_on(T, ITEM_SLOT_SUITSTORE)
		if(4)
			var/obj/item/clothing/suit/space/hardsuit/suit = H.wear_suit
			if(istype(suit) && !suit.suittoggled)
				if(H.head) //the code's paper ended up worn there by the bag being full: in the bag, or a hand
					var/obj/item/hat = H.head
					if(H.temporarilyRemoveItemFromInventory(hat))
						H.put_in_hands(hat)
						if(!SEND_SIGNAL(H.back, COMSIG_TRY_STORAGE_INSERT, hat, H, TRUE))
							H.dropItemToGround(hat)
				suit.ToggleHelmet()
				if(!suit.suittoggled)
					bot_log(bot, "the helmet won't go up: head [H.head], helmet [suit.helmet]")
			var/obj/item/clothing/head/helmet/space/hardsuit/syndi/helmet = istype(suit) ? suit.helmet : null
			if(istype(helmet) && !helmet.on && H.head == helmet) //combat mode: no good for space
				helmet.attack_self(H)
		if(5)
			return FALSE //the jetpack stays off until it's needed (op_mind_jetpack()): it runs off the tank they breathe from
	return TRUE

/// The unit puts it out on its own tile, and the one who pressed the button picks it straight up: left there, with four others
/// crowding round the units, somebody else's hand got to it first and the one who dispensed it went without.
/datum/bot_brain/proc/op_take_dispensed(obj/item/I, obj/machinery/suit_storage_unit/U)
	I.forceMove(get_turf(U))
	free_hand_for(I)
	owner.put_in_hands(I)

/// Into a hand, then on: a click each, with the wait for getting into it done as the pause before (do_after() won't run for a bot
/// partway through a step).
/datum/bot_brain/proc/op_put_on(obj/item/I, slot)
	var/mob/living/carbon/human/H = owner
	if(!(I in H.held_items))
		free_hand_for(I) //the sword or the emag goes in the bag first
		if(isturf(I.loc))
			try_pickup_target(I)
		else
			H.put_in_hands(I) //out of the box in the bag
	if(H.get_item_by_slot(slot) == I)
		return TRUE //picking it up put it on
	if(!(I in H.held_items) || !H.equip_to_slot_if_possible(I, slot, FALSE, TRUE, TRUE, TRUE))
		bot_log(src, "couldn't put on [I]: it's at [I.loc]")
		return FALSE
	bot_log(src, "put on [I]")
	return TRUE

/datum/bot_step/paced/op_suit_up/finish(datum/bot_brain/bot)
	var/mob/living/carbon/human/H = bot.owner
	if(!bot.op_suited())
		bot_log(bot, "not suited after stage [stage]: suit [H.wear_suit], mask [H.wear_mask], suit storage [H.s_store]")
		return GOAL_STEP_FAIL
	return GOAL_STEP_SUCCESS

/// The suit's jetpack takes a puff from the tank in its storage at every step through space, and the survival box's two litres is
/// about eighty steps: there and back is more than that, and an operative who runs dry drifts and suffocates. So, the way a player
/// does before the crossing, a full oxygen tank out of the shuttle's dispenser goes in the suit's storage instead.
/datum/bot_brain/proc/op_tank_small()
	var/obj/item/tank/internals/T = owner.s_store
	return !istype(T) || T.volume < 10

/datum/bot_brain/proc/op_tank_dispenser()
	for(var/obj/structure/tank_dispenser/D as anything in bot_instances_of(/obj/structure/tank_dispenser))
		if(D.oxygentanks > 0 && D.z == owner.z && istype(get_area(D), /area/shuttle/syndicate))
			return D

/datum/bot_goal/op_tank
	doing = "getting a full tank"
	var/obj/structure/tank_dispenser/dispenser

/datum/bot_goal/op_tank/New(obj/structure/tank_dispenser/D)
	. = ..()
	dispenser = D

/datum/bot_goal/op_tank/resolve_target(datum/bot_brain/bot)
	target = QDELETED(dispenser) ? null : dispenser

/datum/bot_goal/op_tank/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/op_simple/S = new
	S.steps = list(new /datum/bot_step/move_to(), new /datum/bot_step/paced/op_tank())
	return list(S)

/// A tank off the dispenser, then the little one out of the suit's storage into the bag and the full one in: a click each.
/datum/bot_step/paced/op_tank
	max_clicks = 3
	var/stage = 0

/datum/bot_step/paced/op_tank/start(datum/bot_brain/bot)
	stage = 0
	return bot.owner.Adjacent(bot.current_goal?.target)

/datum/bot_step/paced/op_tank/do_click(datum/bot_brain/bot)
	var/obj/structure/tank_dispenser/D = bot.current_goal?.target
	var/mob/living/carbon/human/H = bot.owner
	if(!istype(D) || QDELETED(D))
		return FALSE
	bot.human_pause(D)
	switch(stage++)
		if(0)
			var/obj/item/tank/internals/oxygen/tank = locate() in D
			if(!tank || !H.Adjacent(D))
				return FALSE
			bot.make_hand_free()
			bot.telemetry_ui_action(D, "take an oxygen tank")
			if(!H.put_in_hands(tank))
				return FALSE
			D.oxygentanks--
			D.update_icon()
			bot_log(bot, "took [tank] out of [D]")
		if(1)
			var/obj/item/tank/internals/oxygen/tank = locate() in H.held_items
			if(!tank)
				return FALSE
			var/obj/item/old = H.s_store
			if(old && H.temporarilyRemoveItemFromInventory(old)) //the valve shuts itself once it's off them (Life())
				H.put_in_hands(old) //on the floor if the other hand's full
			bot.op_put_on(tank, ITEM_SLOT_SUITSTORE)
			bot.stow_or_drop(old) //only now: put away first, it'd go straight back in the suit's storage
			return FALSE
	return TRUE

/datum/bot_step/paced/op_tank/finish(datum/bot_brain/bot)
	return bot.op_tank_small() ? GOAL_STEP_FAIL : GOAL_STEP_SUCCESS

/// Aboard, beside the console; or, given somewhere, within a few tiles of it.
/datum/bot_goal/op_board
	doing = "getting aboard"
	breaks_in = TRUE
	var/atom/spot

/datum/bot_goal/op_board/New(atom/A)
	. = ..()
	spot = A

/datum/bot_goal/op_board/resolve_target(datum/bot_brain/bot)
	if(spot && !QDELETED(spot))
		target = spot
		return
	target = bot_ops_console()

/datum/bot_goal/op_board/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/op_simple/S = new
	S.steps = list(new /datum/bot_step/move_to())
	return list(S)

/datum/bot_goal/op_launch
	doing = "flying us in"

/datum/bot_goal/op_launch/resolve_target(datum/bot_brain/bot)
	target = bot_ops_console()

/datum/bot_goal/op_launch/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/op_simple/S = new
	S.steps = list(new /datum/bot_step/move_to(), new /datum/bot_step/op_launch())
	return list(S)

/// The console's link for a dock by the station.
/datum/bot_step/op_launch/execute(datum/bot_brain/bot)
	var/obj/machinery/computer/shuttle/syndicate/C = bot.current_goal?.target
	if(!istype(C) || !bot.owner.Adjacent(C))
		bot_log(bot, "not at the console: [C ? AREACOORD(C) : "none"] from [AREACOORD(bot.owner)]")
		return GOAL_STEP_FAIL
	var/obj/docking_port/mobile/M = bot_ops_shuttle()
	var/list/docks = list()
	for(var/id in params2list(C.possible_destinations))
		var/obj/docking_port/stationary/D = SSshuttle.getDock(id)
		if(D && is_station_level(D.z) && id != "syndicate_custom" && M?.canDock(D) == SHUTTLE_CAN_DOCK)
			docks += id
	bot.human_pause(C)
	bot.owner.face_atom(C)
	if(!length(docks)) //the map's own docks don't fit this shuttle: the navigation computer, the way players always do it
		if(!bot_ops_designate_landing(bot))
			bot_log(bot, "nowhere by the station the shuttle fits")
			return GOAL_STEP_FAIL
		docks += "syndicate_custom"
	var/dock = pick(docks)
	bot.telemetry_ui_action(C, "move to [dock]")
	usr = bot.owner
	C.Topic(null, list("move" = dock))
	var/obj/docking_port/mobile/S = bot_ops_shuttle()
	if(!S || S.mode == SHUTTLE_IDLE)
		var/obj/docking_port/stationary/D = SSshuttle.getDock(dock)
		bot_log(bot, "the shuttle didn't go for [dock]: console stat [C.stat], allowed [C.allowed(bot.owner)], can use [bot.owner.canUseTopic(C)], shuttle [S ? "mode [S.mode], can dock [S.canDock(D)]" : "missing"], docks [english_list(docks)]")
		return GOAL_STEP_FAIL
	bot.op_team.launched = TRUE
	log_game("BOT OPS: launched for [dock]")
	bot_say(bot.owner, pick(";Here we go.", ";Launching. Weapons ready.", ";Moving out. Get the disk."))
	return GOAL_STEP_SUCCESS

// ---------------------------------------------------------------------------------------------
// The disk and the nuke
// ---------------------------------------------------------------------------------------------

/// Whoever has the disk: killed for it, then searched.
/datum/bot_goal/traitor_kill/robust/op_disk
	doing = "after the disk"
	breaks_in = TRUE

/datum/bot_goal/traitor_kill/robust/op_disk/resolve_target(datum/bot_brain/bot)
	target = victim()

/datum/bot_goal/traitor_kill/robust/op_disk/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/traitor_kill/S = new
	S.steps = list(new /datum/bot_step/move_to(), new /datum/bot_step/paced/close_in(), new /datum/bot_step/paced/strike/robust(), new /datum/bot_step/op_take_disk())
	return list(S)

/datum/bot_goal/traitor_kill/robust/op_disk/on_give_up(datum/bot_brain/bot)
	return //no chain of victims for an operative: op_business() decides again

/datum/bot_goal/traitor_kill/robust/op_disk/on_success(datum/bot_brain/bot)
	return

/// Off the body: out of whatever it's in, a worn bag or a pocket.
/datum/bot_step/op_take_disk/execute(datum/bot_brain/bot)
	var/datum/bot_goal/traitor_kill/G = bot.current_goal
	var/mob/living/carbon/human/body = G?.victim()
	var/obj/item/disk/nuclear/disk = bot_find_nuke_disk()
	if(!istype(body) || !disk || !(disk in body.GetAllContents()))
		return GOAL_STEP_SUCCESS //they didn't have it after all, or never did
	if(!bot.owner.Adjacent(body) || body.stat != DEAD && !body.IsUnconscious())
		return GOAL_STEP_FAIL
	var/obj/item/worn = disk
	while(worn.loc != body && isitem(worn.loc))
		worn = worn.loc
	bot.human_pause(body)
	if(worn.loc == body)
		bot.free_hand_for(null)
		if(worn in body.held_items)
			body.dropItemToGround(worn) //the strip panel's hand slot
		else
			for(var/slot in GLOB.bot_clone_dress_order) //goals/cloning.dm: every slot a body wears things in
				if(body.get_item_by_slot(slot) == worn)
					bot.owner.stripPanelUnequip(worn, body, slot)
					break
	if(disk.loc != bot.owner && !(disk in bot.owner.held_items))
		disk.forceMove(get_turf(bot.owner)) //out of the bag it came in
		bot.try_pickup_target(disk)
	if(!(disk in bot.owner.GetAllContents()))
		return GOAL_STEP_FAIL
	bot_say(bot.owner, pick(";Got the disk.", ";Disk secured. Heading to the nuke.", ";I have the disk!"))
	bot.put_away(disk)
	return GOAL_STEP_SUCCESS

/// Whoever's got the disk is shut in something: the eject button, or the door.
/datum/bot_goal/op_eject
	doing = "after the disk"
	breaks_in = TRUE
	var/atom/movable/box

/datum/bot_goal/op_eject/New(atom/movable/A)
	. = ..()
	box = A

/datum/bot_goal/op_eject/resolve_target(datum/bot_brain/bot)
	target = QDELETED(box) ? null : box

/datum/bot_goal/op_eject/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/op_simple/S = new
	S.steps = list(new /datum/bot_step/move_to(), new /datum/bot_step/op_eject())
	return list(S)

/datum/bot_step/op_eject/execute(datum/bot_brain/bot)
	var/atom/movable/A = bot.current_goal?.target
	if(!A || !bot.owner.Adjacent(A))
		return GOAL_STEP_FAIL
	bot.human_pause(A)
	bot.telemetry_clicked(A)
	if(istype(A, /obj/machinery))
		var/obj/machinery/M = A
		M.open_machine()
	else if(istype(A, /obj/structure/closet))
		var/obj/structure/closet/C = A
		if(!C.open(bot.owner))
			C.bust_open()
	return GOAL_STEP_SUCCESS

/datum/bot_goal/op_grab_disk
	doing = "after the disk"
	breaks_in = TRUE
	var/obj/item/disk/nuclear/disk

/datum/bot_goal/op_grab_disk/New(obj/item/disk/nuclear/D)
	. = ..()
	disk = D

/datum/bot_goal/op_grab_disk/resolve_target(datum/bot_brain/bot)
	target = QDELETED(disk) ? null : bot_outermost_holder(disk)

/datum/bot_goal/op_grab_disk/get_strategies(datum/bot_brain/bot)
	if(isitem(target))
		return list(new /datum/bot_strategy/grab_item())
	if(istype(target, /obj/structure/closet))
		return list(new /datum/bot_strategy/emag_theft(/obj/item/disk/nuclear), new /datum/bot_strategy/brute_force/theft(/obj/item/disk/nuclear))
	return list(new /datum/bot_strategy/brute_force/theft(/obj/item/disk/nuclear))

/datum/bot_goal/op_arm
	doing = "arming the nuke"
	breaks_in = TRUE
	var/obj/machinery/nuclearbomb/nuke

/datum/bot_goal/op_arm/New(obj/machinery/nuclearbomb/N)
	. = ..()
	nuke = N

/datum/bot_goal/op_arm/resolve_target(datum/bot_brain/bot)
	target = QDELETED(nuke) ? null : nuke

/datum/bot_goal/op_arm/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/op_simple/S = new
	S.steps = list(new /datum/bot_step/move_to(), new /datum/bot_step/paced/op_arm())
	return list(S)

/// The panel the way it goes: the disk in, the code and Enter, the timer and Enter (which takes the safety off), Arm.
/// ui_act() won't run without an open window, so each button's effect is done here, a click at a time.
/datum/bot_step/paced/op_arm
	max_clicks = 6
	var/stage = 0

/datum/bot_step/paced/op_arm/start(datum/bot_brain/bot)
	stage = 0
	return bot.owner.Adjacent(bot.current_goal?.target)

/datum/bot_step/paced/op_arm/do_click(datum/bot_brain/bot)
	var/obj/machinery/nuclearbomb/N = bot.current_goal?.target
	if(!istype(N) || QDELETED(N) || !bot.owner.Adjacent(N) || N.exploded)
		return FALSE
	bot.human_pause(N)
	bot.owner.face_atom(N)
	switch(stage++)
		if(0)
			if(!N.auth)
				var/obj/item/disk/nuclear/disk = locate() in bot.owner.GetAllContents()
				if(!disk || !bot.ready_in_hand(disk))
					return FALSE
				bot.telemetry_ui_action(N, "insert disk")
				bot.use_item_on(disk, N)
				if(N.auth != disk)
					return FALSE
		if(1)
			bot.telemetry_ui_action(N, "keypad code, E")
			if(N.r_code != bot.op_team.code)
				bot_log(bot, "the code doesn't match this nuke")
				return FALSE
			N.yes_code = TRUE
			N.update_ui_mode()
			wait_for = 3 SECONDS //five digits
		if(2)
			bot.telemetry_ui_action(N, "keypad timer [N.minimum_timer_set], E")
			N.timer_set = N.minimum_timer_set
			if(N.safety)
				N.set_safety()
			N.update_ui_mode()
		if(3)
			bot.telemetry_ui_action(N, "arm")
			if(!N.timing)
				N.set_active()
			N.update_ui_mode()
			if(N.timing)
				log_game("BOT OPS: [bot.owner] armed the nuke at [AREACOORD(N)]")
				bot_say(bot.owner, pick(";Nuke's armed. Hold the shuttle.", ";It's armed. Nobody gets near it.", ";Armed. Ninety seconds."))
			return FALSE
	return TRUE

/datum/bot_step/paced/op_arm/finish(datum/bot_brain/bot)
	var/obj/machinery/nuclearbomb/N = bot.current_goal?.target
	return istype(N) && N.timing ? GOAL_STEP_SUCCESS : GOAL_STEP_FAIL

#undef BOT_OPS_LAUNCH_WAIT
#undef BOT_OPS_HOLD
#undef BOT_OPS_GUARD
