// Whether every energy gun's charge overlay shows what's in its cell. Not part of the game: tools/gun_charge_check/run.sh
// Headless, in the lobby (SSobj doesn't fire there, so a self-charging gun only charges when this calls process()).
// Each gun is spawned, fired down shot by shot, recharged the way a recharger and a self-charger do it, switched through
// its modes at part charge, and EMP'd. After each step the overlays on it are read and compared with the cell:
// "empty" when the selected shot costs more than is left, otherwise CEILING(charge fraction * charge_sections) bars.
// One line per gun type: PASS, or FAIL with the first few wrong steps.

/datum/controller/master
	sleep_offline_after_initializations = FALSE

GLOBAL_VAR_INIT(gcc_passed, 0)
GLOBAL_VAR_INIT(gcc_failed, 0)
GLOBAL_LIST_EMPTY(gcc_states)

/proc/gcc_log(text)
	text2file(text, "data/gun_charge_check/results.txt")

/world/New()
	. = ..()
	spawn(0)
		gun_charge_check_run()

/proc/gcc_has_state(icon, state)
	var/list/states = GLOB.gcc_states["[icon]"]
	if(!states)
		states = list()
		for(var/s in icon_states(icon))
			states[s] = TRUE
		GLOB.gcc_states["[icon]"] = states
	return states[state]

/// What the gun's overlays show: "empty", a number of bars, "none", or "mixed: ..." when more than one reading is on it.
/// Missing states (drawn as nothing) are added to the missing list.
/proc/gcc_shown(obj/item/gun/energy/G, list/missing)
	var/static/image/reader = new
	var/static/regex/numbered = new(@"_charge(\d+)$")
	var/empties = 0
	var/list/levels = list()
	var/legacy = 0
	for(var/o in G.overlays)
		if(G.priority_overlays && (o in G.priority_overlays))
			continue
		reader.appearance = o
		var/state = reader.icon_state
		if(!gcc_has_state(reader.icon, state))
			missing |= "[state]"
			continue
		if(findtext(state, "_empty", -6))
			empties++
		else if(numbered.Find(state))
			levels += text2num(numbered.group[1])
		else if(findtext(state, "_charge"))
			legacy++
	var/list/readings = list()
	if(empties)
		readings += "empty[empties > 1 ? " x[empties]" : ""]"
	for(var/n in levels)
		readings += "[n]"
	if(legacy)
		readings += "[legacy]"
	if(!length(readings))
		return "none"
	if(length(readings) > 1)
		return "mixed: [jointext(readings, "+")]"
	return readings[1]

/proc/gcc_expected(obj/item/gun/energy/G)
	var/obj/item/ammo_casing/energy/shot = G.ammo_type[G.select]
	if(G.cell.charge < shot.e_cost)
		return "empty"
	return "[CEILING(clamp(G.cell.charge / G.cell.maxcharge, 0, 1) * G.charge_sections, 1)]"

/// Compares one step; returns a failure line or null
/proc/gcc_step(obj/item/gun/energy/G, step)
	var/list/missing = list()
	var/shown = gcc_shown(G, missing)
	var/expected = gcc_expected(G)
	if(shown == expected && !length(missing))
		return null
	if(expected == "empty" && shown == "none" && length(missing) == 1 && missing[1] == "[G.icon_state]_empty")
		return null // the sheet has no empty art for it (the mounted taser in items_cyborg.dmi): nothing is right
	var/obj/item/ammo_casing/energy/shot = G.ammo_type[G.select]
	return "[step]: [round(G.cell.charge)]/[G.cell.maxcharge] mode [G.select] (cost [shot.e_cost]) wants [expected], shows [shown][length(missing) ? ", missing state [jointext(missing, ", ")]" : ""]"

/proc/gcc_fire_once(obj/item/gun/energy/G)
	// what process_fire() does: load if drained-then-charged, fire the casing, process_chamber(), update_icon()
	if(!G.chambered && G.can_shoot())
		G.process_chamber()
	if(!G.chambered)
		return FALSE
	G.chambered.BB = null
	G.process_chamber()
	G.update_icon()
	return TRUE

/// Whether the gun's sheet has any charge art for it: [icon_state]..._charge... or [icon_state]_empty
/proc/gcc_has_charge_art(obj/item/gun/energy/G)
	for(var/s in icon_states(G.icon))
		if(findtext(s, G.icon_state) == 1 && (findtext(s, "_charge") || s == "[G.icon_state]_empty"))
			return TRUE
	return FALSE

/proc/gcc_check_gun(type, turf/T)
	if(ispath(type, /obj/item/gun/energy/dueling))
		return "SKIP [type] (needs its pair)"
	if(type == /obj/item/gun/energy || ispath(type, /obj/item/gun/energy/singulo))
		return "SKIP [type] (abstract or admin spawner, no charge art of its own)"
	var/obj/item/gun/energy/G = new type(T)
	if(QDELETED(G))
		return "SKIP [type] (deleted itself)"
	if(!G.automatic_charge_overlays || istype(G, /obj/item/gun/energy/beam_rifle))
		qdel(G)
		return "SKIP [type] (draws its own charge)"
	if(!gcc_has_charge_art(G))
		qdel(G)
		return "SKIP [type] (no charge art for [G.icon_state] in [G.icon])"
	if(!G.cell || !length(G.ammo_type))
		qdel(G)
		return "SKIP [type] (no cell or ammo)"
	if(G.cell.maxcharge >= 1e6) // infinite cells never move
		qdel(G)
		return "SKIP [type] (infinite cell)"
	var/list/fails = list()
	var/fail

	fail = gcc_step(G, "spawned")
	if(fail)
		fails += fail

	// fire down to empty, every mode in turn on the way
	var/shots = 0
	while(shots < 200 && gcc_fire_once(G))
		shots++
		fail = gcc_step(G, "after shot [shots]")
		if(fail)
			fails += fail
		if(shots % 3 == 0 && length(G.ammo_type) > 1)
			G.select_fire(null)
			G.update_icon()
			fail = gcc_step(G, "mode switch after shot [shots]")
			if(fail)
				fails += fail

	// recharger: give() a step at a time, the gun's update_icon() when it's taken out
	var/rate = max(G.cell.chargerate, 1)
	var/steps = 0
	while(G.cell.charge < G.cell.maxcharge && steps < 200)
		steps++
		G.cell.give(rate)
		G.update_icon()
		fail = gcc_step(G, "recharger step [steps]")
		if(fail)
			fails += fail

	// drained from one shot left to just short of one, the bar count the same (an EMP, a lit cigarette)
	var/obj/item/ammo_casing/energy/cost_shot = G.ammo_type[G.select]
	if(cost_shot.e_cost > 1)
		G.cell.charge = cost_shot.e_cost + 1
		G.update_icon()
		fail = gcc_step(G, "one shot left")
		if(fail)
			fails += fail
		G.cell.use(2)
		G.update_icon()
		fail = gcc_step(G, "just short of a shot")
		if(fail)
			fails += fail
		G.cell.give(G.cell.maxcharge)
		G.update_icon()

	// every mode at part charge
	G.cell.use(G.cell.maxcharge * 0.6)
	G.update_icon()
	for(var/i in 1 to length(G.ammo_type))
		G.attack_self(null)
		fail = gcc_step(G, "mode [G.select] at part charge")
		if(fail)
			fails += fail

	// a self-charger charging back up through process()
	if(G.selfcharge)
		G.cell.use(G.cell.charge)
		G.update_icon()
		var/ticks = 0
		while(G.cell.charge < G.cell.maxcharge && ticks < 2000)
			ticks++
			G.process()
			if(G.charge_tick == 0)
				fail = gcc_step(G, "self-charge tick [ticks]")
				if(fail)
					fails += fail

	// EMP from full
	G.cell.give(G.cell.maxcharge)
	G.update_icon()
	G.emp_act(EMP_LIGHT)
	fail = gcc_step(G, "after EMP")
	if(fail)
		fails += fail

	qdel(G)
	if(!length(fails))
		GLOB.gcc_passed++
		return "PASS [type] ([shots] shots)"
	GLOB.gcc_failed++
	var/list/out = list("FAIL [type] ([length(fails)] wrong steps)")
	for(var/i in 1 to min(4, length(fails)))
		out += "    [fails[i]]"
	return jointext(out, "\n")

/proc/gun_charge_check_run()
	UNTIL(SSticker.initialized)
	sleep(2 SECONDS)
	var/turf/T = locate(10, 10, 1)
	gcc_log("start, on [T] [AREACOORD(T)]")
	for(var/type in typesof(/obj/item/gun/energy))
		var/line
		try
			line = gcc_check_gun(type, T)
		catch(var/exception/e)
			GLOB.gcc_failed++
			line = "FAIL [type] (runtime: [e.name] at [e.file]:[e.line])"
		gcc_log(line)
	gcc_log("[GLOB.gcc_passed] passed, [GLOB.gcc_failed] failed")
	gcc_log("done")
	sleep(1 SECONDS)
	del(world)
