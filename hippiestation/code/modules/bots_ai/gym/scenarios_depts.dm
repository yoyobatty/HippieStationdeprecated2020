// Bot Gym scenarios for departments: bot_departments.dm. Whole rooms and whole rounds are a Bot Shift's business (BOT_CHAOS 1 and up): these
// are the pieces a shift can't be relied on to turn up.

/area/bot_gym
	/// Whose this arena counts as (bot_department_of()).
	var/department

/// A blast door and its button, in a department.
/datum/bot_scenario/duty/panel
	duty_type = /datum/bot_duty/blast_doors
	job = "Station Engineer"
	time_limit = 60 SECONDS
	max_goal_attempts = 60
	layout = list(
		"#########",
		"#B.....b#",
		"#.......#",
		"####p####",
		"#.......#",
		"#########")
	var/button_name = "Engineering Lockdown"
	var/door_id
	var/mob/living/carbon/human/threat

/datum/bot_scenario/duty/panel/build_tile(turf/T, char)
	switch(char)
		if("p")
			door_id = "bot_gym_panel_[REF(src)]"
			var/obj/machinery/door/poddoor/preopen/D = new(T)
			D.id = door_id
			place(char, D)
		if("b")
			var/obj/machinery/button/door/B = new(T)
			B.id = door_id
			B.name = button_name
			B.req_access = list()
			B.req_one_access = list()
			place(char, B)
		else
			return ..()

/datum/bot_scenario/duty/panel/post_spawn()
	..()
	arena_area.department = "engineering"
	var/obj/machinery/button/door/B = first_placed("b")
	B.id = door_id
	B.device = new /obj/item/assembly/control(B)
	var/obj/item/assembly/control/C = B.device
	C.id = door_id

/datum/bot_scenario/duty/panel/proc/make_threat()
	threat = stand_in(first_marker("."), "Grim Reaper")
	var/datum/bot_wanted/W = new
	W.severity = BOT_CRIME_MAJOR
	W.crime = "Murder"
	W.last_seen = get_turf(threat)
	W.last_seen_at = world.time
	GLOB.bot_security_wanted[WEAKREF(threat)] = W

/datum/bot_scenario/duty/panel/release_run()
	if(threat)
		GLOB.bot_security_wanted -= WEAKREF(threat)
	return ..()

/datum/bot_scenario/duty/panel/lockdown
	name = "dept: a threat in the department and the lockdown goes down, and comes up after"
	desc = "Somebody dangerous reported in Engineering. A strict engineer drops the lockdown, and lifts it when they've gone."
	time_limit = 120 SECONDS //doors aren't worked twice in a minute and a half
	var/stage = 0

/datum/bot_scenario/duty/panel/lockdown/post_spawn()
	..()
	brain.strictness = 0.9
	make_threat()

/datum/bot_scenario/duty/panel/lockdown/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	var/obj/machinery/door/poddoor/D = first_placed("p")
	if(!stage && D.density && !D.operating)
		stage = 1
		log_line("door's shut: the threat's over")
		QDEL_NULL(threat)
		return BOT_GYM_PENDING
	return stage && !D.density && !D.operating ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/duty/panel/easygoing
	name = "dept: an easygoing bot leaves the lockdown alone"
	desc = "The same threat, and somebody who can't be doing with it."
	expect_success = FALSE
	time_limit = 12 SECONDS

/datum/bot_scenario/duty/panel/easygoing/post_spawn()
	..()
	brain.strictness = 0.1
	brain.playstyle = BOT_STYLE_NORMAL
	make_threat()

/datum/bot_scenario/duty/panel/easygoing/check()
	var/obj/machinery/door/poddoor/D = first_placed("p")
	return D.density ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/set_door
	name = "dept: a door bolted open, and put right again"
	desc = "Science's easygoing staff bolt it open. Then somebody strict comes along, unbolts it and shuts it. Same panel, same tools."
	layout = list(
		"#########",
		"#B..D...#",
		"#########")
	time_limit = 40 SECONDS
	kit_backpack = list(/obj/item/screwdriver, /obj/item/multitool)
	var/stage = 0

/datum/bot_scenario/set_door/make_goal()
	return new /datum/bot_goal/set_door(first_placed("D"), !stage)

/datum/bot_scenario/set_door/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	var/obj/machinery/door/airlock/A = first_placed("D")
	if(!stage && A.locked && !A.density)
		stage = 1
		log_line("bolted open")
		return BOT_GYM_PENDING
	if(stage && !A.locked && !A.panel_open && A.density)
		return BOT_GYM_PASS
	return BOT_GYM_PENDING

/datum/bot_scenario/set_door/no_tools
	name = "dept: with no tools for the wires, it doesn't walk over to the door"
	desc = "Out to bolt the department's door open, with no screwdriver or multitool on it and none anywhere to fetch. It walked to the door and stood there, fifty times in twelve shifts."
	time_limit = 12 SECONDS
	max_goal_attempts = 1
	kit_backpack = null
	var/moves = 0

/datum/bot_scenario/set_door/no_tools/post_spawn()
	..()
	RegisterSignal(bot, COMSIG_MOVABLE_MOVED, PROC_REF(stepped))

/datum/bot_scenario/set_door/no_tools/proc/stepped()
	SIGNAL_HANDLER
	moves++

/datum/bot_scenario/set_door/no_tools/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(moves)
		fail_reason = "set off for the door with nothing to open its panel with"
		return BOT_GYM_FAIL
	return world.time > start_time + 6 SECONDS ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/set_door/no_tools/release_run()
	if(bot)
		UnregisterSignal(bot, COMSIG_MOVABLE_MOVED)
	return ..()

/datum/bot_scenario/raid
	name = "dept: a greytider hacks into a locked room for the gloves"
	desc = "Insulated gloves on a table behind a door its ID doesn't open. It goes in anyway, comes out wearing them, and leaves the door bolted open behind it."
	layout = list(
		"#########",
		"#B..D..y#",
		"#########")
	time_limit = 40 SECONDS
	max_goal_attempts = 1
	kit_backpack = list(/obj/item/screwdriver, /obj/item/multitool)

/datum/bot_scenario/raid/build_tile(turf/T, char)
	if(char == "y")
		place(char, new /obj/item/clothing/gloves/color/yellow(T))
		return
	..()
	if(char == "D")
		var/obj/machinery/door/airlock/A = first_placed("D")
		A.req_access = list(ACCESS_ENGINE)

/datum/bot_scenario/raid/post_spawn()
	..()
	brain.greytider = TRUE

/datum/bot_scenario/raid/make_goal()
	return new /datum/bot_goal/tide/raid(/obj/item/clothing/gloves/color/yellow)

/datum/bot_scenario/raid/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(!istype(bot.gloves, /obj/item/clothing/gloves/color/yellow))
		return BOT_GYM_PENDING
	var/obj/machinery/door/airlock/A = first_placed("D")
	if(!A.locked || A.density)
		fail_reason = "the door isn't left open"
		return BOT_GYM_FAIL
	return BOT_GYM_PASS

/datum/bot_scenario/raid/unreachable
	name = "dept: a greytider gives up on gloves it has no way to and takes the ones it can get"
	desc = "Insulated gloves walled up two steps off, as on the AI satellite, and another pair across the room. It set off for the nearer every time and gave up at the end of the route search."
	layout = list(
		"###########",
		"#..#y#....#",
		"#B.###...y#",
		"#.........#",
		"###########")
	time_limit = 40 SECONDS
	max_goal_attempts = 3

/datum/bot_scenario/raid/unreachable/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	return istype(bot.gloves, /obj/item/clothing/gloves/color/yellow) ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/raid/strayed_gets_out
	name = "dept: a greytider strayed in somewhere it has no access hacks its way back out for an everyday errand"
	desc = "In maintenance it hacked its way into, with no access, and an ordinary errand on the far side of a door its ID doesn't open. It gave the errand up at the end of the route search, and every errand after it for the rest of the shift."
	layout = list(
		"#########",
		"#B..D..i#",
		"#########")
	time_limit = 40 SECONDS
	max_goal_attempts = 1
	var/obj/item/kitchen/rollingpin/pin

/datum/bot_scenario/raid/strayed_gets_out/setup()
	..()
	pin = place("i", new /obj/item/kitchen/rollingpin(first_marker("i")))

/datum/bot_scenario/raid/strayed_gets_out/post_spawn()
	..()
	brain.gym_strayed = TRUE

/datum/bot_scenario/raid/strayed_gets_out/make_goal()
	return new /datum/bot_goal/take_item/exact(pin)

/datum/bot_scenario/raid/strayed_gets_out/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	return (pin in bot.GetAllContents()) ? BOT_GYM_PASS : BOT_GYM_PENDING

/// stray_doors() (bot_requests.dm) is for somewhere too big to count as shut in, which no arena is: the scenario asks it for the doors
/// and makes the call itself, as maybe_ask_to_be_let_out() does, and the rest is the bots'.
/datum/bot_scenario/strayed_asks_out
	name = "dept: somebody strayed into maintenance with no access asks to be let out, and walks out through the door held for it"
	desc = "No maintenance access, and in maintenance: it isn't shut in by the measure of a room, so it never asked, and every errand was given up at the end of the route search. It asks at the door out, and the colleague with access opens it and holds it."
	job = "Cook"
	layout = list(
		"###########",
		"#B...D...C#",
		"###########")
	time_limit = 60 SECONDS
	var/asked = FALSE
	var/mob/living/carbon/human/rescuer

/datum/bot_scenario/strayed_asks_out/setup()
	var/obj/machinery/door/airlock/A = first_placed("D")
	A.req_access = list(ACCESS_CAPTAIN)

/datum/bot_scenario/strayed_asks_out/post_spawn()
	brain.gym_strayed = TRUE
	brain.gym_scripted = FALSE
	brain.gym_asks_out = TRUE
	rescuer = second_bot(first_marker("C"), "Res Cuer")
	var/obj/item/card/id/C = new(rescuer)
	C.access = list(ACCESS_CAPTAIN)
	rescuer.equip_to_slot_or_del(C, ITEM_SLOT_ID)

/datum/bot_scenario/strayed_asks_out/make_goal()
	return null

/datum/bot_scenario/strayed_asks_out/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	var/turf/door = first_marker("D")
	if(!asked && world.time > start_time + 2 SECONDS)
		asked = TRUE
		var/list/doors = brain.stray_doors()
		if(!length(doors))
			fail_reason = "found no door to ask at"
			return BOT_GYM_FAIL
		brain.call_for(/datum/bot_request_kind/let_out, "I'm stuck in here with no maintenance access - could somebody let me out?", doors)
	return (isturf(bot.loc) && bot.x > door.x) ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/drop_off
	name = "collab: something left on another department's counter"
	desc = "A defibrillator for Medbay, carried over and left on the table, with a word on the radio."
	layout = list(
		"#########",
		"#B.....t#",
		"#########")
	time_limit = 20 SECONDS
	kit_backpack = list(/obj/item/healthanalyzer)

/datum/bot_scenario/drop_off/make_goal()
	return new /datum/bot_goal/drop_off(brain.find_carried_tool(/obj/item/healthanalyzer), /area/bot_gym, "Medbay")

/datum/bot_scenario/drop_off/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	return (locate(/obj/item/healthanalyzer) in get_turf(first_placed("t"))) ? BOT_GYM_PASS : BOT_GYM_PENDING

/// A department of the arena's own, to have a counter on
/area/bot_gym/drop_lab
	name = "Bot Gym lab"

/datum/bot_scenario/drop_off/counter
	name = "collab: left on the counter of a department it can't get into"
	desc = "Seven tables in a lab with no way in, and the lab's counter further along the hall than any of them. It looked at the six nearest tables, found no way to one, and gave up."
	layout = list(
		"##############",
		"#B...........#",
		"###########k##",
		"#iiiiiiilllll#",
		"##############")
	var/obj/structure/table/counter

/// i a table inside the lab, l the lab's floor, k its counter, in the wall between it and the hall
/datum/bot_scenario/drop_off/counter/setup()
	var/area/bot_gym/drop_lab/lab = new
	for(var/char in list("i", "l", "k"))
		for(var/turf/T as anything in markers[char])
			var/area/old_area = T.loc
			old_area.contents -= T
			lab.contents += T
			T.change_area(old_area, lab)
			if(char == "l")
				continue
			var/obj/structure/table/made = new(T)
			if(char == "k")
				counter = made

/datum/bot_scenario/drop_off/counter/make_goal()
	return new /datum/bot_goal/drop_off(brain.find_carried_tool(/obj/item/healthanalyzer), /area/bot_gym/drop_lab, "Science")

/datum/bot_scenario/drop_off/counter/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	return (locate(/obj/item/healthanalyzer) in get_turf(counter)) ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/griefed/dead_mans_switch
	name = "toxins: a valve on a health sensor goes off when its carrier goes down"
	desc = "The traitor's trick: a health sensor on the transfer valve, held in the hand, because it won't fit in a bag. Beaten into crit, it falls from the hand, the sensor reads them as it goes, and the valve opens by itself. Tanks of nothing here: the arena's got to last."
	layout = list(
		"#######",
		"#.BC..#",
		"#######")
	time_limit = 20 SECONDS
	var/obj/item/transfer_valve/valve

/datum/bot_scenario/griefed/dead_mans_switch/post_spawn()
	..()
	valve = new(bot)
	var/obj/item/tank/internals/oxygen/empty/one = new(valve)
	var/obj/item/tank/internals/oxygen/empty/two = new(valve)
	valve.tank_one = one
	valve.tank_two = two
	bot.put_in_hands(valve)
	var/obj/item/assembly/health/sensor = new(bot)
	bot.put_in_hands(sensor)
	brain.fit_trigger(valve, sensor)

/datum/bot_scenario/griefed/dead_mans_switch/grief()
	bot.apply_damage(105, BRUTE, BODY_ZONE_CHEST) //on the arm holding it, that cripples the arm, and it goes on the floor
	bot.updatehealth()

/datum/bot_scenario/griefed/dead_mans_switch/check()
	if(valve.attached_device && valve.valve_open)
		return BOT_GYM_PASS
	return BOT_GYM_PENDING

/// Nobody in the room to ask, nobody healing: a role-hopper says so and gets on with it.
/datum/bot_scenario/duty/hopper
	name = "hopper: nobody's healing and there's no HoP, so it picks that up itself"
	duty_type = /datum/bot_duty/cover_short_handed
	job = "Assistant"
	time_limit = 20 SECONDS
	layout = list(
		"#####",
		"#B..#",
		"#####")

/datum/bot_scenario/duty/hopper/post_spawn()
	..()
	brain.set_playstyle(BOT_STYLE_HOPPER)

/datum/bot_scenario/duty/hopper/check()
	if(brain.work_role() == "Medical Doctor" && brain.is_medical_job())
		return BOT_GYM_PASS
	return BOT_GYM_PENDING

/// Only a very competent one touches the engine, and only with the power going.
/datum/bot_scenario/duty/hopper/engine
	name = "hopper: the engine's nobody's job until the power goes, and then only a very competent one's"

/datum/bot_scenario/duty/hopper/engine/check()
	brain.competence = 1
	GLOB.bot_power_out_drill = FALSE
	var/power_on = brain.may_take_on("Station Engineer")
	GLOB.bot_power_out_drill = TRUE
	var/very_competent = brain.may_take_on("Station Engineer")
	brain.competence = 0.5
	var/middling = brain.may_take_on("Station Engineer")
	GLOB.bot_power_out_drill = null
	log_line("power on [power_on], very competent [very_competent], middling [middling]")
	return !power_on && very_competent && !middling ? BOT_GYM_PASS : BOT_GYM_FAIL

/datum/bot_scenario/griefed/charges
	name = "dept: the charge goes by the room, and by how they got in"
	desc = "Space Law: 109 anywhere, 209 at the engine, 309 on the Bridge, and 110, 210 and 310 for forcing the door."
	layout = list(
		"#######",
		"#.BC..#",
		"#######")
	time_limit = 5 SECONDS

/datum/bot_scenario/griefed/charges/check()
	var/list/wrong = list()
	if(bot_charge_code(bot_trespass_charge(new /area/hydroponics, FALSE)) != 109)
		wrong += "hydroponics"
	if(bot_charge_code(bot_trespass_charge(new /area/engine/engineering, FALSE)) != 209)
		wrong += "engineering"
	if(bot_charge_code(bot_trespass_charge(new /area/bridge, FALSE)) != 309)
		wrong += "the bridge"
	if(bot_charge_code(bot_trespass_charge(new /area/engine/engineering, TRUE)) != 210)
		wrong += "breaking into engineering"
	if(bot_charge_code(bot_trespass_charge(new /area/bridge, TRUE)) != 310)
		wrong += "breaking into the bridge"
	if(length(wrong))
		fail_reason = english_list(wrong)
		return BOT_GYM_FAIL
	return BOT_GYM_PASS

/datum/bot_scenario/duty/panel/bridge_hos
	name = "dept: the HoS drops the Bridge blast doors from inside, then has somewhere to be, and lets itself out with the button"
	desc = "A murderer is about. The HoS, strict, drops the blast doors on a room too big for the quick look for being shut in (over 60 tiles). Then it's sent out past them. It goes out by the button rather than finding no way out: in the user's Captain round every errand came back \"no path\" for a minute and a half."
	job = "Head of Security"
	button_name = "Bridge Blast Door Control"
	time_limit = 30 SECONDS
	layout = list(
		"###############",
		"#B...........b#",
		"#.............#",
		"#.............#",
		"#.............#",
		"#.............#",
		"#######p#######",
		"#......o......#",
		"###############")
	var/shut_at = 0

/datum/bot_scenario/duty/panel/bridge_hos/post_spawn()
	..()
	arena_area.department = "command"
	brain.strictness = 0.9
	make_threat()

/datum/bot_scenario/duty/panel/bridge_hos/issue_goal()
	if(!shut_at)
		return ..()
	if(!brain.current_goal && brain.state != BOT_STATE_COMBAT)
		goal_attempts++
		brain.assign_goal(new /datum/bot_goal/walk_up_to(first_marker("o")))

/datum/bot_scenario/duty/panel/bridge_hos/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	var/obj/machinery/door/poddoor/D = first_placed("p")
	if(!shut_at)
		if(D.density && !D.operating)
			shut_at = world.time
			log_line("doors down: now out past them")
		return BOT_GYM_PENDING
	return get_dist(bot, first_marker("o")) <= 1 ? BOT_GYM_PASS : BOT_GYM_PENDING
