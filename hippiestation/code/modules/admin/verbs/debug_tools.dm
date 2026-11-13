// Debug verbs from tgstation, picked by the user 2026-11-13:
// - Allow Browser Inspect: Inspect (WebView2 DevTools) on the right-click menu of every browser control, so tgui windows,
//   the chat and the stat panel. A second use takes it off again (tg's only turns it on).
// - Profiler and Send Maps Profile (tgui-next DebugProfiler.js), in place of BYOND's own ?debug=profile pages (the user,
//   2026-11-13: "convert them to tgui"). Procs: the figures of whichever profiler SSprofiler runs (hippie_prof, or BYOND's
//   at its duty share), with a mark to see only what's been added since (BYOND's page clears instead, which would take the
//   round's figures from profiler.json and the lag alerts too). SendMaps: BYOND's profile of sending the map to clients,
//   started, stopped and cleared from the window, its parts as a tree.
// - Counts (tgui-next DebugCounts.js): running timers by the proc they'll call (tg's Check Timer Sources), and atoms or
//   datums by type (tg's Count Atoms/Datums, there a JSON download only). Each count shows the change since the last count
//   of that kind, so counting twice a while apart shows what's piling up. The JSON is still there as a download.

#define DEBUG_COUNTS_SHOWN 500
#define DEBUG_PROFILER_SHOWN 300

GLOBAL_LIST_INIT(admin_verbs_debug_tools, list(
	/client/proc/cmd_browser_inspect,
	/client/proc/cmd_profiler,
	/client/proc/cmd_sendmaps_profile,
	/client/proc/cmd_check_timer_sources,
	/client/proc/cmd_count_instances,
))

/// Whether BYOND's SendMaps profiler is on (it's one for the whole world)
GLOBAL_VAR_INIT(sendmaps_profiling, FALSE)

/client/var/browser_devtools = FALSE
/client/var/datum/debug_counts/debug_counts
/client/var/datum/debug_profiler/debug_profiler

/client/proc/cmd_browser_inspect()
	set name = "Allow Browser Inspect"
	set category = "Debug"
	set desc = "Inspect (DevTools) on the right-click menu of tgui windows, the chat and the stat panel. Again to take it off."
	if(!check_rights(R_DEBUG))
		return
	browser_devtools = !browser_devtools
	winset(src, null, list2params(list("browser-options" = browser_devtools ? "+devtools" : "-devtools")))
	to_chat(src, "<span class='notice'>Browser Inspect [browser_devtools ? "on: right-click a window, Inspect" : "off"].</span>")

/client/proc/cmd_profiler()
	set name = "Profiler"
	set category = "Debug"
	set desc = "The procs' times from the profiler, and BYOND's profile of sending the map."
	if(!check_rights(R_DEBUG))
		return
	open_debug_profiler("procs")

/client/proc/cmd_sendmaps_profile()
	set name = "Send Maps Profile"
	set category = "Debug"
	set desc = "BYOND's profile of sending the map to clients. Starts it if it's off."
	if(!check_rights(R_DEBUG))
		return
	if(!GLOB.sendmaps_profiling)
		debug_profiler_sendmaps(TRUE, usr)
	open_debug_profiler("sendmaps")

/client/proc/open_debug_profiler(tab)
	if(!debug_profiler)
		debug_profiler = new
	debug_profiler.tab = tab
	debug_profiler.refresh()
	debug_profiler.ui_interact(mob)

/// Turns BYOND's SendMaps profiler on or off, for everyone
/proc/debug_profiler_sendmaps(on, mob/user)
	if(on == GLOB.sendmaps_profiling)
		return
	GLOB.sendmaps_profiling = on
	world.Profile(on ? PROFILE_START : PROFILE_STOP, "sendmaps")
	log_admin("[key_name(user)] [on ? "started" : "stopped"] the SendMaps profiler.")

/client/proc/cmd_check_timer_sources()
	set name = "Check Timer Sources"
	set category = "Debug"
	set desc = "Running timers counted by the proc they'll call."
	if(!check_rights(R_DEBUG))
		return
	open_debug_counts("timers")

/client/proc/cmd_count_instances()
	set name = "Count Atoms/Datums"
	set category = "Debug"
	set desc = "Atoms or datums counted by type, with the change since the last count."
	if(!check_rights(R_DEBUG))
		return
	open_debug_counts("atoms")

/client/proc/open_debug_counts(kind)
	if(!debug_counts)
		debug_counts = new
	debug_counts.tab = kind
	if(kind == "timers")
		debug_counts.count("timers")
	debug_counts.rebuild()
	debug_counts.ui_interact(mob)

/datum/debug_counts
	/// timers, atoms or datums
	var/tab = "timers"
	/// count or change
	var/sort_by = "count"
	var/filter = ""
	/// kind = list(key = count): the latest count of each kind, and the one before it
	var/list/counts = list()
	var/list/before = list()
	/// kind = sum of the latest count, "hh:mm:ss" it was made at, and seconds it took
	var/list/totals = list()
	var/list/counted_at = list()
	var/list/took = list()
	/// Timers in the buckets, in the second queue (further off) and on client time
	var/list/queues = list(0, 0, 0)
	/// The kind being counted, or null
	var/busy
	/// The open tab's rows, filtered, sorted and cut to DEBUG_COUNTS_SHOWN. Made when something changes, not on each update.
	var/list/rows = list()
	var/matched = 0

/datum/debug_counts/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, datum/tgui/master_ui = null, datum/ui_state/state = GLOB.admin_state)
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "debug_counts", "Counts", 640, 600, master_ui, state)
		ui.set_autoupdate(FALSE)
		ui.open()

/// Counts one kind. Atoms and datums yield between ticks, so call those through INVOKE_ASYNC.
/datum/debug_counts/proc/count(kind)
	if(busy)
		return
	busy = kind
	var/started = REALTIMEOFDAY
	var/list/found = list()
	switch(kind)
		if("timers")
			var/list/in_queues = list(0, 0, 0)
			// each bucket holds the first of a ring of timers linked by next
			for(var/datum/timedevent/first as anything in SStimer.bucket_list)
				if(!first)
					continue
				var/datum/timedevent/T = first
				var/guard = 0
				do
					found[timer_source(T)]++
					in_queues[1]++
					T = T.next
				while(T && T != first && ++guard < 1000000)
			for(var/datum/timedevent/T as anything in SStimer.second_queue)
				found[timer_source(T)]++
				in_queues[2]++
			for(var/datum/timedevent/T as anything in SStimer.clienttime_timers)
				found[timer_source(T)]++
				in_queues[3]++
			queues = in_queues
		if("atoms")
			for(var/atom/A in world)
				found[A.type]++
				CHECK_TICK
		if("datums")
			for(var/datum/D)
				found[D.type]++
				CHECK_TICK
	var/total = 0
	for(var/key in found)
		total += found[key]
	before[kind] = counts[kind]
	counts[kind] = found
	totals[kind] = total
	counted_at[kind] = time2text(world.timeofday, "hh:mm:ss")
	took[kind] = round((REALTIMEOFDAY - started) / 10, 0.01)
	busy = null
	rebuild()
	SStgui.update_uis(src)

/// The object's type and the proc, like /obj/machinery/door/airlock/proc/close. A proc ref prints as its bare name
/// unless it's a global proc, which prints as /proc/name already.
/datum/debug_counts/proc/timer_source(datum/timedevent/T)
	if(!T.info_proc)
		return "(no callback)"
	var/proc_name = "[T.info_proc]"
	if(T.info_type == GLOBAL_PROC || copytext(proc_name, 1, 2) == "/")
		return proc_name
	return "[T.info_type]/proc/[proc_name]"

/datum/debug_counts/proc/rebuild()
	rows = list()
	matched = 0
	var/list/now = counts[tab]
	if(!now)
		return
	var/list/last = before[tab]
	var/list/all = list()
	for(var/key in now)
		var/name = "[key]"
		if(filter && !findtext(name, filter))
			continue
		var/n = now[key]
		all[++all.len] = list(name, n, last ? n - (last[key] || 0) : null)
	// gone since the last count: the change is the whole of it
	if(last)
		for(var/key in last)
			if(now[key])
				continue
			var/name = "[key]"
			if(filter && !findtext(name, filter))
				continue
			all[++all.len] = list(name, 0, -last[key])
	matched = all.len
	sortTim(all, sort_by == "change" ? GLOBAL_PROC_REF(cmp_debug_counts_change) : GLOBAL_PROC_REF(cmp_debug_counts_count))
	if(all.len > DEBUG_COUNTS_SHOWN)
		all.Cut(DEBUG_COUNTS_SHOWN + 1)
	for(var/list/R as anything in all)
		rows[++rows.len] = list("name" = R[1], "count" = R[2], "change" = R[3])

/proc/cmp_debug_counts_count(list/a, list/b)
	return b[2] - a[2] || sorttext(b[1], a[1])

/// Biggest growth first, and what shrank most last
/proc/cmp_debug_counts_change(list/a, list/b)
	return (b[3] || 0) - (a[3] || 0) || b[2] - a[2]

/datum/debug_counts/ui_data(mob/user)
	var/list/data = list()
	data["tab"] = tab
	data["sort"] = sort_by
	data["filter"] = filter
	data["busy"] = busy
	var/list/now = counts[tab]
	data["counted"] = !!now
	if(now)
		data["total"] = totals[tab]
		data["kinds"] = length(now)
		data["at"] = counted_at[tab]
		data["took"] = took[tab]
		data["has_before"] = !!before[tab]
		data["matched"] = matched
		data["rows"] = rows
		if(tab == "timers")
			data["queues"] = queues
	return data

/datum/debug_counts/ui_act(action, list/params)
	if(..())
		return
	if(!check_rights(R_DEBUG))
		return
	switch(action)
		if("tab")
			var/kind = params["kind"]
			if(!(kind in list("timers", "atoms", "datums")))
				return
			tab = kind
			if(kind == "timers")
				count("timers")
			rebuild()
		if("count")
			if(busy)
				return
			INVOKE_ASYNC(src, PROC_REF(count), tab)
		if("sort")
			sort_by = params["by"] == "change" ? "change" : "count"
			rebuild()
		if("filter")
			filter = trim("[params["text"]]", 100)
			rebuild()
		if("json")
			send_json(usr)
	return TRUE

/// The whole latest count of the open tab as a JSON download, biggest first
/datum/debug_counts/proc/send_json(mob/user)
	var/list/now = counts[tab]
	if(!now || !user?.client)
		return
	var/list/sorted = list()
	for(var/key in now)
		sorted["[key]"] = now[key]
	sortTim(sorted, GLOBAL_PROC_REF(cmp_numeric_dsc), associative = TRUE)
	var/path = "data/debug_counts_[user.ckey].json"
	fdel(path)
	text2file(json_encode(sorted), path)
	user << ftp(file(path), "[tab]_count_round_[GLOB.round_id].json")

/datum/debug_profiler
	/// procs or sendmaps
	var/tab = "procs"
	/// self, total or calls
	var/sort_by = "self"
	var/filter = ""
	/// The procs' figures at the last read: name = list(self, total, calls); calls is null from hippie_prof
	var/list/figures
	/// The figures at the mark, taken off each read's; null without a mark
	var/list/mark
	var/mark_at
	var/mark_real
	var/read_at
	var/read_real
	/// Seconds the server idled between ticks (hippie_prof), since the start or the mark
	var/idle
	/// The procs tab's rows, filtered, sorted and cut to DEBUG_PROFILER_SHOWN
	var/list/rows = list()
	var/matched = 0
	/// SendMaps' parts at the last read as a tree (their names go "A: B: C"), since Clear
	var/list/sendmaps_rows = list()
	var/sendmaps_read_at
	/// BYOND's own SendMaps figures at the last read and at Clear: name = list(value, calls). Clear takes these off for this
	/// window only. BYOND's clear would wipe them for every admin, and on 516.1688 it only works with a format given:
	/// world.Profile(PROFILE_CLEAR, "sendmaps") leaves the figures as they were, (PROFILE_CLEAR, "sendmaps", "json") clears.
	var/list/sendmaps_last = list()
	var/list/sendmaps_base
	var/sendmaps_cleared_at

/datum/debug_profiler/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, datum/tgui/master_ui = null, datum/ui_state/state = GLOB.admin_state)
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "debug_profiler", "Profiler", 720, 640, master_ui, state)
		ui.set_autoupdate(FALSE)
		ui.open()

/datum/debug_profiler/proc/engine_text()
	if(!SSprofiler?.profiling)
		return null
	if(SSprofiler.engine == "hippie")
		return "hippie_prof"
	if(SSprofiler.duty < 100 && REALTIMEOFDAY >= SSprofiler.full_until)
		return "BYOND's, on [SSprofiler.duty]% of the time"
	return "BYOND's"

/datum/debug_profiler/proc/refresh()
	if(tab == "procs")
		read_procs()
	else
		read_sendmaps()

/datum/debug_profiler/proc/read_procs()
	figures = null
	if(!SSprofiler?.profiling)
		rebuild()
		return
	var/raw
	if(SSprofiler.engine == "hippie")
		raw = hippie_prof("dump")
	else
		raw = world.Profile(PROFILE_REFRESH, null, "json")
		SSprofiler.after_read() // reading turns BYOND's on (PROFILE_REFRESH is PROFILE_START)
	figures = list()
	if(istext(raw) && findtext(raw, "\[") == 1)
		for(var/list/R in json_decode(raw))
			figures[R["name"]] = list(R["self"], R["total"], R["calls"])
	read_at = time2text(world.timeofday, "hh:mm:ss")
	read_real = REALTIMEOFDAY
	rebuild()

/datum/debug_profiler/proc/rebuild()
	rows = list()
	matched = 0
	idle = null
	if(!figures)
		return
	var/list/all = list()
	for(var/name in figures)
		var/list/F = figures[name]
		var/self = F[1]
		var/total = F[2]
		var/calls = F[3]
		var/list/M = mark ? mark[name] : null
		if(M)
			self -= M[1]
			total -= M[2]
			if(!isnull(calls))
				calls -= M[3] || 0
		if(name == "(idle: between ticks)")
			idle = self
			continue
		if(self <= 0 && total <= 0)
			continue
		if(filter && !findtext(name, filter))
			continue
		all[++all.len] = list(name, self, total, calls)
	matched = all.len
	switch(sort_by)
		if("total")
			sortTim(all, GLOBAL_PROC_REF(cmp_debug_profiler_total))
		if("calls")
			sortTim(all, GLOBAL_PROC_REF(cmp_debug_profiler_calls))
		else
			sortTim(all, GLOBAL_PROC_REF(cmp_debug_profiler_self))
	if(all.len > DEBUG_PROFILER_SHOWN)
		all.Cut(DEBUG_PROFILER_SHOWN + 1)
	for(var/list/R as anything in all)
		rows[++rows.len] = list("name" = R[1], "self" = R[2], "total" = R[3], "calls" = R[4])

/proc/cmp_debug_profiler_self(list/a, list/b)
	return b[2] - a[2]

/proc/cmp_debug_profiler_total(list/a, list/b)
	return b[3] - a[3]

/proc/cmp_debug_profiler_calls(list/a, list/b)
	return (b[4] || 0) - (a[4] || 0) || b[2] - a[2]

/datum/debug_profiler/proc/read_sendmaps()
	var/raw = world.Profile(PROFILE_REFRESH, "sendmaps", "json")
	if(!GLOB.sendmaps_profiling)
		world.Profile(PROFILE_STOP, "sendmaps") // reading turns it on
	sendmaps_rows = list()
	sendmaps_last = list()
	sendmaps_read_at = time2text(world.timeofday, "hh:mm:ss")
	if(!istext(raw) || findtext(raw, "\[") != 1)
		return
	// BYOND's rows aren't in tree order and leave some parents out ("SendMaps: Per client: HUD update" with no "SendMaps: Per
	// client"): each goes under its own parent, a missing parent made as a row without figures, children in BYOND's order
	var/list/by_path = list()
	var/list/children = list() // path = list(child paths); "" holds the roots
	for(var/list/R in json_decode(raw))
		var/path = "[R["name"]]"
		var/list/parts = splittext(path, ": ")
		for(var/i in 1 to parts.len)
			var/at = jointext(parts, ": ", 1, i + 1)
			if(by_path[at])
				continue
			by_path[at] = list("name" = parts[i], "depth" = i - 1, "value" = null, "calls" = null, "time" = FALSE)
			var/parent = i > 1 ? jointext(parts, ": ", 1, i) : ""
			if(!children[parent])
				children[parent] = list()
			children[parent] += at
		var/list/row = by_path[path]
		var/value = R["value"]
		var/calls = R["calls"]
		sendmaps_last[path] = list(value, calls)
		var/list/base = sendmaps_base ? sendmaps_base[path] : null
		if(base)
			value -= base[1]
			calls -= base[2]
		row["value"] = value
		row["calls"] = calls
		row["time"] = R["unit"] == "s"
	var/list/stack = list("")
	while(stack.len)
		var/at = stack[stack.len]
		stack.len--
		if(at != "")
			sendmaps_rows[++sendmaps_rows.len] = by_path[at]
		var/list/kids = children[at]
		for(var/i in length(kids) to 1 step -1)
			stack += kids[i]

/datum/debug_profiler/ui_data(mob/user)
	var/list/data = list()
	data["tab"] = tab
	if(tab == "procs")
		data["engine"] = engine_text()
		data["sort"] = sort_by
		data["filter"] = filter
		data["read_at"] = read_at
		data["mark_at"] = mark_at
		data["span"] = mark ? round((read_real - mark_real) / 10) : null
		data["idle"] = idle
		data["matched"] = matched
		data["has_calls"] = SSprofiler?.engine != "hippie"
		data["rows"] = rows
	else
		data["running"] = GLOB.sendmaps_profiling
		data["read_at"] = sendmaps_read_at
		data["cleared_at"] = sendmaps_cleared_at
		data["sm_rows"] = sendmaps_rows
	return data

/datum/debug_profiler/ui_act(action, list/params)
	if(..())
		return
	if(!check_rights(R_DEBUG))
		return
	switch(action)
		if("tab")
			if(!(params["tab"] in list("procs", "sendmaps")))
				return
			tab = params["tab"]
			refresh()
		if("refresh")
			refresh()
		if("mark")
			read_procs()
			mark = figures
			mark_at = read_at
			mark_real = read_real
			rebuild()
		if("unmark")
			mark = null
			mark_at = null
			rebuild()
		if("sort")
			sort_by = (params["by"] in list("self", "total", "calls")) ? params["by"] : "self"
			rebuild()
		if("filter")
			filter = trim("[params["text"]]", 100)
			rebuild()
		if("sm_start")
			debug_profiler_sendmaps(TRUE, usr)
			read_sendmaps()
		if("sm_stop")
			debug_profiler_sendmaps(FALSE, usr)
			read_sendmaps()
		if("sm_clear")
			read_sendmaps()
			sendmaps_base = sendmaps_last
			sendmaps_cleared_at = sendmaps_read_at
			read_sendmaps()
	return TRUE

#undef DEBUG_COUNTS_SHOWN
#undef DEBUG_PROFILER_SHOWN
