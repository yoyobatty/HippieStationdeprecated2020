// Which ticks really run late in a bot shift, and what took the time. A tick counts as late when the MC finishes it past 100%.
// Times each processed object, machine and timer callback that takes HH_ITEM_MS or more, plus hard deletes and shuttle docking, and fires
// station-wide events late in the shift. Not part of the game:
// HARNESS=../string_probe/hitch_hunt.dm PARAMS="bot-shift=30&bot-crew=fill:20&bot-events=1&bot-quiet=1&timewarp=0" SECONDS_LIMIT=280 bash tools/byond_reports/ref_stall/hippie_check.sh

#define HH_ITEM_MS 3
#define HH_MAX_LATE 400

GLOBAL_VAR_INIT(hh_ready, FALSE)
GLOBAL_VAR_INIT(hh_phase, "boot")
GLOBAL_LIST_EMPTY(hh_tick)
GLOBAL_LIST_EMPTY(hh_late)
GLOBAL_LIST_EMPTY(hh_items)
GLOBAL_VAR_INIT(hh_ticks, 0)

/proc/hh_log(text)
	text2file(text, "data/ref_stall.txt")

/// One slow item: into this tick's story and the running totals.
/proc/hh_item(label, ms)
	if(!GLOB.hh_ready)
		return
	GLOB.hh_tick += "[label] [round(ms, 0.1)]"
	var/list/entry = GLOB.hh_items[label]
	if(!entry)
		entry = list(0, 0, 0)
		GLOB.hh_items[label] = entry
	entry[1]++
	entry[2] += ms
	entry[3] = max(entry[3], ms)

/datum/controller/master/RunQueue()
	. = ..()
	if(!GLOB.hh_ready || GLOB.hh_phase == "boot")
		return
	GLOB.hh_ticks++
	var/usage = TICK_USAGE
	if(usage > 100 && length(GLOB.hh_late) < HH_MAX_LATE)
		GLOB.hh_late += "[GLOB.hh_phase] [round(world.time / 10)]s [round(usage)]% over by [round((usage - 100) * world.tick_lag, 0.1)] ms: [jointext(GLOB.hh_tick, ", ")]"
	GLOB.hh_tick.Cut()

/datum/controller/subsystem/ignite(resumed = FALSE)
	set waitfor = FALSE
	var/t0 = world.tick_usage
	var/time0 = world.time
	. = ..()
	if(GLOB.hh_ready && world.time == time0)
		var/ms = (world.tick_usage - t0) * world.tick_lag
		if(ms >= HH_ITEM_MS)
			GLOB.hh_tick += "\[[name] [round(ms, 0.1)]]"

/datum/controller/subsystem/processing/fire(resumed = 0)
	if (!resumed)
		currentrun = processing.Copy()
	var/list/current_run = currentrun
	while(current_run.len)
		var/datum/thing = current_run[current_run.len]
		current_run.len--
		var/t0 = world.tick_usage
		if(QDELETED(thing))
			processing -= thing
		else if(thing.process(wait) == PROCESS_KILL)
			STOP_PROCESSING(src, thing)
		var/ms = (world.tick_usage - t0) * world.tick_lag
		if(ms >= HH_ITEM_MS)
			hh_item("[name]: [thing?.type]", ms)
		if (MC_TICK_CHECK)
			return

/datum/controller/subsystem/machines/fire(resumed = 0)
	if (!resumed)
		var/t_power = world.tick_usage
		for(var/datum/powernet/Powernet in powernets)
			Powernet.reset()
		var/power_ms = (world.tick_usage - t_power) * world.tick_lag
		if(power_ms >= HH_ITEM_MS)
			hh_item("Machines: powernet reset", power_ms)
		src.currentrun = processing.Copy()
	var/list/currentrun = src.currentrun
	var/seconds = wait * 0.1
	while(currentrun.len)
		var/obj/machinery/thing = currentrun[currentrun.len]
		currentrun.len--
		var/t0 = world.tick_usage
		if(!QDELETED(thing) && thing.process(seconds) != PROCESS_KILL)
			if(thing.use_power)
				thing.auto_use_power()
		else
			processing -= thing
			if (!QDELETED(thing))
				thing.datum_flags &= ~DF_ISPROCESSING
		var/ms = (world.tick_usage - t0) * world.tick_lag
		if(ms >= HH_ITEM_MS)
			hh_item("Machines: [thing?.type]", ms)
		if (MC_TICK_CHECK)
			return

/datum/callback/InvokeAsync(...)
	set waitfor = FALSE
	var/t0 = world.tick_usage
	var/time0 = world.time
	var/what = "[delegate]"
	var/owner = object
	. = ..()
	if(world.time == time0)
		var/ms = (world.tick_usage - t0) * world.tick_lag
		if(ms >= HH_ITEM_MS)
			var/owner_text = istype(owner, /datum) ? "[owner:type]" : "[owner]"
			hh_item("callback [what] on [owner_text]", ms)

/datum/controller/subsystem/garbage/HardDelete(datum/D)
	var/what = "[D?.type]"
	var/t0 = world.tick_usage
	. = ..()
	var/ms = (world.tick_usage - t0) * world.tick_lag
	if(ms >= HH_ITEM_MS)
		hh_item("hard delete: [what]", ms)

/obj/docking_port/mobile/initiate_docking(obj/docking_port/stationary/new_dock, movement_direction, force=FALSE)
	var/t0 = world.tick_usage
	. = ..()
	hh_item("shuttle docking: [name]", (world.tick_usage - t0) * world.tick_lag)

/area/power_change()
	var/t0 = world.tick_usage
	. = ..()
	var/ms = (world.tick_usage - t0) * world.tick_lag
	if(ms >= HH_ITEM_MS)
		hh_item("area power_change", ms)

/proc/hh_summary(title)
	hh_log("=== [title]: [GLOB.hh_ticks] ticks, [length(GLOB.hh_late)] late")
	var/list/order = list()
	for(var/label in GLOB.hh_items)
		order[label] = GLOB.hh_items[label][2]
	sortTim(order, GLOBAL_PROC_REF(cmp_numeric_dsc), associative = TRUE)
	var/shown = 0
	for(var/label in order)
		var/list/entry = GLOB.hh_items[label]
		hh_log("[round(entry[2])] ms in [entry[1]] calls, worst [round(entry[3], 0.1)]: [label]")
		if(++shown >= 24)
			break

/proc/hh_fire(phase, datum/callback/what)
	GLOB.hh_phase = phase
	hh_log("firing [phase] at [round(world.time / 10)]s")
	var/t0 = world.tick_usage
	what.Invoke()
	hh_log("[phase] took [round((world.tick_usage - t0) * world.tick_lag, 0.1)] ms in the call itself")
	sleep(400)
	GLOB.hh_phase = "play"

/proc/hh_event(event_type)
	for(var/datum/round_event_control/event in SSevents.control)
		if(istype(event, event_type))
			event.runEvent()
			return

/proc/hh_run()
	UNTIL(SSticker.initialized)
	UNTIL(SSticker.current_state >= GAME_STATE_PLAYING)
	GLOB.hh_ready = TRUE
	sleep(600)
	GLOB.hh_phase = "play"
	sleep(11400)
	hh_summary("twenty minutes of play")
	for(var/line in GLOB.hh_late)
		hh_log(line)
	var/played = length(GLOB.hh_late)
	GLOB.hh_items.Cut()
	hh_fire("grid check", CALLBACK(GLOBAL_PROC, GLOBAL_PROC_REF(hh_event), /datum/round_event_control/grid_check))
	hh_fire("power failure", CALLBACK(GLOBAL_PROC, GLOBAL_PROC_REF(power_failure)))
	hh_fire("power restore", CALLBACK(GLOBAL_PROC, GLOBAL_PROC_REF(power_restore)))
	hh_fire("aurora", CALLBACK(GLOBAL_PROC, GLOBAL_PROC_REF(hh_event), /datum/round_event_control/aurora_caelus))
	hh_summary("station-wide events")
	for(var/i in played + 1 to length(GLOB.hh_late))
		hh_log(GLOB.hh_late[i])
	hh_registry_check()
	hh_log("done")
	del(world)

/world/New()
	. = ..()
	spawn(0)
		hh_run()

// Inside the costs: what a slow brain was doing, and the pieces of shuttles, events and weather.
/proc/hh_part(label, t0)
	var/ms = (world.tick_usage - t0) * world.tick_lag
	if(ms >= HH_ITEM_MS)
		hh_item(label, ms)

/datum/bot_brain/process(delta_time)
	var/t0 = world.tick_usage
	var/list/tally = GLOB.astar_tally
	var/turfs0 = tally["turfs"]
	var/searches0 = tally["searches"]
	var/was_state = state
	var/was_goal = current_goal ? current_goal.type : null
	var/hazards_due = GLOB.bot_hazards_refresh_at
	. = ..()
	var/ms = (world.tick_usage - t0) * world.tick_lag
	if(GLOB.bot_hazards_refresh_at != hazards_due)
		hh_item("brain ran bot_refresh_hazards in this call", ms)
	if(ms >= 10)
		hh_item("brain over 10 ms: state [was_state], [was_goal], [tally["searches"] - searches0] searches, [tally["turfs"] - turfs0] turfs", ms)

/datum/bot_brain/handle_combat()
	var/t0 = world.tick_usage
	. = ..()
	hh_part("brain part: handle_combat", t0)

/datum/bot_brain/handle_goal()
	var/t0 = world.tick_usage
	. = ..()
	hh_part("brain part: handle_goal", t0)

/datum/bot_brain/handle_arrest()
	var/t0 = world.tick_usage
	. = ..()
	hh_part("brain part: handle_arrest", t0)

/datum/bot_brain/handle_wander()
	var/t0 = world.tick_usage
	. = ..()
	hh_part("brain part: handle_wander", t0)

/datum/bot_brain/handle_idle_chat()
	var/t0 = world.tick_usage
	. = ..()
	hh_part("brain part: handle_idle_chat", t0)

/datum/bot_brain/keep_an_eye_out()
	var/t0 = world.tick_usage
	. = ..()
	hh_part("brain part: keep_an_eye_out", t0)

/datum/bot_brain/mind_air_supply()
	var/t0 = world.tick_usage
	. = ..()
	hh_part("brain part: mind_air_supply", t0)

/datum/bot_brain/maybe_ask_to_be_let_out()
	var/t0 = world.tick_usage
	. = ..()
	hh_part("brain part: maybe_ask_to_be_let_out", t0)

/datum/bot_brain/mind_the_dark()
	var/t0 = world.tick_usage
	. = ..()
	hh_part("brain part: mind_the_dark", t0)

/datum/bot_brain/try_spot_wanted()
	var/t0 = world.tick_usage
	. = ..()
	hh_part("brain part: try_spot_wanted", t0)

/datum/bot_brain/forget_deleted()
	var/t0 = world.tick_usage
	. = ..()
	hh_part("brain part: forget_deleted", t0)

/datum/bot_brain/mind_hands()
	var/t0 = world.tick_usage
	. = ..()
	hh_part("brain part: mind_hands", t0)

/datum/bot_brain/mind_being_held()
	var/t0 = world.tick_usage
	. = ..()
	hh_part("brain part: mind_being_held", t0)

/datum/round_event/process()
	var/t0 = world.tick_usage
	var/what = type
	. = ..()
	hh_part("event: [what]", t0)

/datum/weather/update_areas()
	var/t0 = world.tick_usage
	. = ..()
	hh_part("weather update_areas: [type]", t0)

/datum/controller/subsystem/shuttle/generate_transit_dock(obj/docking_port/mobile/M)
	var/t0 = world.tick_usage
	. = ..()
	hh_part("shuttle: generate_transit_dock", t0)

/obj/docking_port/mobile/check()
	var/t0 = world.tick_usage
	. = ..()
	hh_part("shuttle: check on [name]", t0)

/obj/docking_port/stationary/transit/Destroy(force)
	var/t0 = world.tick_usage
	. = ..()
	hh_part("shuttle: transit dock Destroy", t0)

/datum/turf_reservation/Destroy()
	var/t0 = world.tick_usage
	. = ..()
	hh_part("shuttle: turf_reservation Destroy", t0)

/datum/bot_brain/try_escape_pool()
	var/t0 = world.tick_usage
	. = ..()
	hh_part("brain part: try_escape_pool", t0)

/datum/bot_brain/try_put_self_out()
	var/t0 = world.tick_usage
	. = ..()
	hh_part("brain part: try_put_self_out", t0)

/datum/bot_brain/check_duty_interrupts()
	var/t0 = world.tick_usage
	. = ..()
	hh_part("brain part: check_duty_interrupts", t0)

/datum/bot_brain/mind_stasis()
	var/t0 = world.tick_usage
	. = ..()
	hh_part("brain part: mind_stasis", t0)

/datum/bot_brain/run_goal_chain_link(...)
	var/t0 = world.tick_usage
	var/list/tally = GLOB.astar_tally
	var/turfs0 = tally["turfs"]
	var/what = current_goal ? current_goal.type : null
	. = ..()
	var/ms = (world.tick_usage - t0) * world.tick_lag
	if(ms >= 20)
		hh_item("goal chain link: [what], [tally["turfs"] - turfs0] turfs, [ms >= 40 ? "large" : "medium"]", ms)

/// Every tracked type's list against a fresh world scan: the registry must hold exactly what a scan finds.
/proc/hh_registry_check()
	var/list/tracked = GLOB.bot_type_registry
	var/missing = 0
	var/extra = 0
	var/scanned = 0
	var/list/seen = list()
	var/list/examples = list()
	for(var/obj/O in world)
		if(QDELETED(O))
			continue
		scanned++
		seen[O] = TRUE
		for(var/type in tracked)
			if(istype(O, type) && !tracked[type][O])
				missing++
				if(length(examples) < 6)
					examples += "missing [O.type] from [type]"
	var/total = 0
	for(var/type in tracked)
		for(var/obj/O as anything in tracked[type])
			total++
			if(!seen[O] && !QDELETED(O))
				extra++
				if(length(examples) < 6)
					examples += "extra [O.type] in [type]"
	hh_log("registry check: [length(tracked)] tracked types, [total] entries, [scanned] objs scanned, [missing] missing, [extra] extra [jointext(examples, "; ")]")
