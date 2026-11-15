// Testkit events: one stream of what happened, each with a sequence number, world.time and real time. Kept in memory for "events"
// (the last TESTKIT_EVENTS_KEPT) and written to data/testkit/events.jsonl. Hooked by redefining the game's procs here, after the
// game's own definitions, so the game's files are untouched: the testkit build is the only one with these.
//
// Kinds: death, attack, explosion, say, door.open/door.close, runtime, hard_delete, mc_alert, bot.<telemetry kind>, bot.goal,
// bot.gave_up, bot.done, bot.state, bot.watch, testkit.*, check.*, gym.*

/datum/testkit
	var/event_seq = 0
	var/list/events = list()
	/// kind prefix -> FALSE for ones not recorded. Doors and footsteps are off unless asked for.
	var/list/off_kinds = list("door" = TRUE, "bot.click" = TRUE, "bot.pull" = TRUE, "bot.sit" = TRUE)
	/// What's been counted since boot: runtime, hard_delete, mc_alert, death
	var/list/counters = list("runtime" = 0, "hard_delete" = 0, "mc_alert" = 0, "death" = 0, "attack" = 0)
	/// "file:line" -> list(count, error)
	var/list/runtime_sites = list()
	/// type -> count
	var/list/hard_deleted = list()
	/// name -> list(counters copy, runtime sites copy, hard deletes copy, event_seq)
	var/list/marks = list()
	/// last attacker by target ref, for deaths
	var/list/last_attacker = list()

/datum/testkit/proc/events_boot()
	RegisterSignal(SSdcs, COMSIG_GLOB_MOB_DEATH, PROC_REF(on_death))
	RegisterSignal(SSdcs, COMSIG_GLOB_EXPLOSION, PROC_REF(on_explosion))

/// Whether a kind is recorded: its own switch, or its prefix's ("bot.goal" -> "bot")
/datum/testkit/proc/wants(kind)
	if(off_kinds[kind])
		return FALSE
	var/dot = findtext(kind, ".")
	if(dot && off_kinds[copytext(kind, 1, dot)])
		return FALSE
	return TRUE

/datum/testkit/proc/event(kind, list/fields)
	if(!wants(kind))
		return
	var/list/record = list("seq" = ++event_seq, "k" = kind, "t" = world.time, "rt" = REALTIMEOFDAY)
	if(fields)
		record += fields
	var/text = json_encode(record)
	events += text
	if(length(events) > TESTKIT_EVENTS_KEPT)
		events.Cut(1, length(events) - TESTKIT_EVENTS_KEPT + 1)
	hippie_log_append(dir + "events.jsonl", text)

/// Where a thing is, for an event
/datum/testkit/proc/at(atom/A)
	var/turf/T = get_turf(A)
	return T ? list(T.x, T.y, T.z) : null

/datum/testkit/proc/events_since(since, list/kinds, limit = 200, match)
	var/list/found = list()
	var/first_seq = event_seq - length(events) + 1
	var/start = max(1, (text2num("[since]") || 0) - first_seq + 2)
	for(var/i in start to length(events))
		var/text = events[i]
		if(length(kinds))
			var/kind_ok = FALSE
			for(var/kind in kinds)
				if(findtext(text, "\"k\":\"[kind]"))
					kind_ok = TRUE
					break
			if(!kind_ok)
				continue
		if(match && !findtext(text, match))
			continue
		found += list(json_decode(text))
		if(length(found) >= limit)
			break
	return found

/datum/testkit/proc/cmd_events(list/a)
	var/list/kinds = islist(a["kinds"]) ? a["kinds"] : (a["kinds"] ? splittext(a["kinds"], ",") : null)
	var/list/found = events_since(a["since"], kinds, clamp(text2num("[a["limit"]]") || 200, 1, 2000), a["match"])
	return list("seq" = event_seq, "events" = found)

/datum/testkit/proc/cmd_record(list/a)
	var/list/kinds = islist(a["kinds"]) ? a["kinds"] : splittext("[a["kinds"]]", ",")
	var/on = a["on"] != 0
	for(var/kind in kinds)
		if(on)
			off_kinds -= kind
		else
			off_kinds[kind] = TRUE
	return list("off" = off_kinds)

/datum/testkit/proc/cmd_mark(list/a)
	var/name = a["name"] || "default"
	marks[name] = list("counters" = counters.Copy(), "sites" = testkit_copy_sites(runtime_sites), "hard" = hard_deleted.Copy(), "seq" = event_seq, "t" = world.time)
	return list("mark" = name, "seq" = event_seq)

/datum/testkit/proc/cmd_invariants(list/a)
	var/list/mark = marks[a["mark"] || "default"] || list("counters" = list(), "sites" = list(), "hard" = list(), "seq" = 0, "t" = 0)
	var/list/before = mark["counters"]
	var/list/delta = list()
	for(var/k in counters)
		delta[k] = counters[k] - (before[k] || 0)
	var/list/sites = list()
	var/list/old_sites = mark["sites"]
	for(var/site in runtime_sites)
		var/list/now = runtime_sites[site]
		var/list/then = old_sites[site]
		var/n = now["count"] - (then ? then["count"] : 0)
		if(n > 0)
			sites[site] = list("count" = n, "error" = now["error"])
	var/list/hard = list()
	var/list/old_hard = mark["hard"]
	for(var/type in hard_deleted)
		var/n = hard_deleted[type] - (old_hard[type] || 0)
		if(n > 0)
			hard[type] = n
	var/list/alerts = events_since(mark["seq"], list("mc_alert"), 50)
	var/clean = !delta["runtime"] && !delta["hard_delete"] && !delta["mc_alert"]
	return list("clean" = clean, "since" = (world.time - mark["t"]) / 10, "counts" = delta, "runtime_sites" = sites, "hard_deletes" = hard,
		"mc_alerts" = alerts, "mc" = list("tick_usage" = world.tick_usage, "cpu" = world.cpu, "paused" = Master.processing <= 0,
		"timers" = length(SStimer.timer_id_dict), "failsafe_ok" = !Failsafe || Failsafe.lasttick + 100 > world.time))

// ---------------------------------------------------------------------------------------------
// Hooks
// ---------------------------------------------------------------------------------------------

/datum/testkit/proc/on_death(datum/source, mob/living/M, gibbed)
	SIGNAL_HANDLER
	counters["death"]++
	var/list/attacker = last_attacker[REF(M)]
	event("death", list("ref" = REF(M), "name" = M.real_name, "type" = "[M.type]", "at" = at(M), "gibbed" = gibbed,
		"bot" = ishuman(M) && M:bot_brain ? TRUE : FALSE, "job" = M.mind?.assigned_role,
		"brute" = M.getBruteLoss(), "burn" = M.getFireLoss(), "tox" = M.getToxLoss(), "oxy" = M.getOxyLoss(),
		"killer" = attacker ? attacker["name"] : null, "with" = attacker ? attacker["with"] : null, "how" = attacker ? attacker["how"] : null))

/datum/testkit/proc/on_explosion(datum/source, turf/epicenter, devastation, heavy, light, took, orig_dev, orig_heavy, orig_light)
	SIGNAL_HANDLER
	event("explosion", list("at" = at(epicenter), "ranges" = list(orig_dev, orig_heavy, orig_light), "took" = took))

/proc/testkit_copy_sites(list/sites)
	. = list()
	for(var/site in sites)
		var/list/entry = sites[site]
		.[site] = entry.Copy()

/// log_combat() (atoms.dm) logs the attacker's side through here, with GLOB.round_log_target the one it was done to
/atom/log_message(message, message_type, color=null, log_globally=TRUE)
	. = ..()
	var/datum/testkit/kit = GLOB.testkit
	if(!kit || message_type != LOG_ATTACK || !log_globally)
		return
	var/atom/target = GLOB.round_log_target
	kit.counters["attack"]++
	var/user_name = ismob(src) ? src:real_name : "[src]"
	var/target_name = ismob(target) ? target:real_name : "[target]"
	if(ismob(target) && target != src)
		kit.last_attacker[REF(target)] = list("name" = user_name, "how" = "[message]")
		if(length(kit.last_attacker) > 2000)
			kit.last_attacker.Cut(1, 1001)
	if(kit.wants("attack"))
		kit.event("attack", list("by" = user_name, "by_ref" = REF(src), "target" = target_name, "target_ref" = target ? REF(target) : null,
			"what" = "[message]", "at" = kit.at(target || src), "hp" = isliving(target) ? target:health : null))

/atom/log_talk(message, message_type, tag=null, log_globally=TRUE, forced_by=null)
	. = ..()
	var/datum/testkit/kit = GLOB.testkit
	if(kit && log_globally && kit.wants("say"))
		kit.event("say", list("by" = ismob(src) ? src:real_name : name, "ref" = REF(src), "text" = "[message]", "type" = message_type,
			"tag" = tag, "at" = kit.at(src), "bot" = ishuman(src) && src:bot_brain ? TRUE : FALSE))

/obj/machinery/door/open()
	. = ..()
	if(. && GLOB.testkit?.wants("door.open"))
		GLOB.testkit.event("door.open", list("ref" = REF(src), "name" = name, "at" = GLOB.testkit.at(src)))

/obj/machinery/door/airlock/open(forced=0)
	. = ..()
	if(. && GLOB.testkit?.wants("door.open"))
		GLOB.testkit.event("door.open", list("ref" = REF(src), "name" = name, "at" = GLOB.testkit.at(src), "forced" = forced))

/obj/machinery/door/close()
	. = ..()
	if(. && GLOB.testkit?.wants("door.close"))
		GLOB.testkit.event("door.close", list("ref" = REF(src), "name" = name, "at" = GLOB.testkit.at(src)))

/obj/machinery/door/airlock/close(forced=0)
	. = ..()
	if(. && GLOB.testkit?.wants("door.close"))
		GLOB.testkit.event("door.close", list("ref" = REF(src), "name" = name, "at" = GLOB.testkit.at(src), "forced" = forced))

/// Runs inside the error handler: list work only
/world/Error(exception/E)
	GLOB.testkit?.note_exception(E)
	return ..()

/// A runtime counted and its site kept: from world/Error(), and from the testkit's own try/catch (a caught one never reaches Error())
/datum/testkit/proc/note_exception(exception/E, caught_in)
	if(!E)
		return
	counters["runtime"]++
	var/site = "[E.file]:[E.line]"
	var/list/entry = runtime_sites[site]
	if(!entry)
		entry = list("count" = 0, "error" = "[E.name]")
		runtime_sites[site] = entry
	entry["count"]++
	if(entry["count"] <= 3)
		event("runtime", list("site" = site, "error" = "[E.name]", "desc" = copytext("[E.desc]", 1, 600), "caught_in" = caught_in))

/datum/controller/subsystem/garbage/HardDelete(datum/D)
	var/datum/testkit/kit = GLOB.testkit
	if(kit)
		kit.counters["hard_delete"]++
		var/type = "[D.type]"
		kit.hard_deleted[type] = (kit.hard_deleted[type] || 0) + 1
		kit.event("hard_delete", list("type" = type))
	return ..()

/// mc_watchdog_alert() (mc_watchdog.dm) raises its alerts as the "server" kind
/datum/controller/subsystem/admin_alerts/raise(kind, text, bad, atom/where, atom/actor, atom/target, merge_key, merge_window = 2 MINUTES, chat_links)
	var/datum/testkit/kit = GLOB.testkit
	if(kit && kind == "server")
		kit.counters["mc_alert"]++
		kit.event("mc_alert", list("text" = "[text]"))
	return ..()

// ---------------------------------------------------------------------------------------------
// Bots
// ---------------------------------------------------------------------------------------------


/datum/bot_brain/telemetry_event(kind, list/fields)
	. = ..()
	var/datum/testkit/kit = GLOB.testkit
	if(kit && kit.wants("bot.[kind]"))
		var/list/record = list("bot" = owner?.real_name, "ref" = REF(owner), "at" = kit.at(owner), "goal" = bot_telemetry_short(current_goal?.type))
		if(fields)
			for(var/k in fields)
				record[k] = kit.out(fields[k], 1)
		kit.event("bot.[kind]", record)

/datum/bot_brain/assign_goal(datum/bot_goal/goal)
	. = ..()
	var/datum/testkit/kit = GLOB.testkit
	if(kit && kit.wants("bot.goal"))
		kit.event("bot.goal", list("bot" = owner?.real_name, "ref" = REF(owner), "goal" = bot_telemetry_short(goal?.type),
			"target" = goal?.target ? "[goal.target]" : null, "taken" = !!., "at" = kit.at(owner)))

/datum/bot_brain/give_up_goal()
	var/datum/bot_goal/goal = current_goal
	var/datum/testkit/kit = GLOB.testkit
	if(kit && goal && kit.wants("bot.gave_up"))
		kit.event("bot.gave_up", list("bot" = owner?.real_name, "ref" = REF(owner), "goal" = bot_telemetry_short(goal.type),
			"target" = goal.target ? "[goal.target]" : null, "path_fail" = last_path_fail_reason, "at" = kit.at(owner),
			"last" = length(panel_lines) ? panel_lines[length(panel_lines)] : null))
	return ..()

/datum/bot_brain/goal_succeeded()
	var/datum/bot_goal/goal = current_goal
	var/datum/testkit/kit = GLOB.testkit
	if(kit && goal && kit.wants("bot.done"))
		kit.event("bot.done", list("bot" = owner?.real_name, "ref" = REF(owner), "goal" = bot_telemetry_short(goal.type),
			"target" = goal.target ? "[goal.target]" : null, "at" = kit.at(owner)))
	return ..()
