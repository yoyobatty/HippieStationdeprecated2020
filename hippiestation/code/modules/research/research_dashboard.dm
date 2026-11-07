// The research dashboard, research piece 3: the R&D server controller's window (tgui-next ResearchDashboard.js) shows where the
// station's research points come from this shift and over the last hour, what's been researched, what's nearest to affordable
// and when, and the servers. Every point that reaches the science techweb goes through add_point_type() or add_point_list();
// the ledger hooks those and names the source from the proc that called them (BYOND's caller), so no source of points has to
// be told about it. The user left research's design to me, 2026-11-06.

/// The sources, in the order (and colours) the dashboard draws them
GLOBAL_LIST_INIT(research_sources, list("Servers", "Bombs", "Experiments", "Samples", "Analysis", "Engines", "Gas reactions", "Other"))

GLOBAL_DATUM_INIT(research_ledger, /datum/research_ledger, new)

#define LEDGER_MINUTES 60
#define LEDGER_RESEARCHED 6

/datum/research_ledger
	/// Source = points this shift
	var/list/totals = list()
	/// Finished minutes, oldest first, each source = points
	var/list/minutes = list()
	/// The minute under way
	var/list/current = list()
	var/minute_started = 0
	var/spent = 0
	/// The last nodes researched, newest first: list(name, cost, world.time)
	var/list/researched = list()

/// Where points came from, by the proc that added them (past the techweb's own procs)
/datum/research_ledger/proc/source_of(callee/from)
	var/static/list/by_path = list(
		"/datum/controller/subsystem/research" = "Servers",
		"/obj/machinery/doppler_array" = "Bombs",
		"/datum/science_experiment" = "Experiments",
		"/datum/sample_board" = "Samples",
		"/obj/machinery/rnd/destructive_analyzer" = "Analysis",
		"/obj/machinery/power/rad_collector" = "Engines",
		"/obj/machinery/power/tesla_coil" = "Engines",
		"/datum/gas_reaction" = "Gas reactions",
	)
	while(from && findtext("[from.proc]", "/datum/techweb/") == 1)
		from = from.caller
	if(!from)
		return "Other"
	var/path = "[from.proc]"
	for(var/prefix in by_path)
		if(findtext(path, prefix) == 1)
			return by_path[prefix]
	return "Other"

/datum/research_ledger/proc/record(amount, callee/from)
	if(amount <= 0)
		return
	roll_minutes()
	var/source = source_of(from)
	totals[source] += amount
	current[source] += amount

/// Closes the minutes that have passed
/datum/research_ledger/proc/roll_minutes()
	if(!minute_started)
		minute_started = world.time
		return
	var/passed = round((world.time - minute_started) / (1 MINUTES))
	if(passed <= 0)
		return
	minutes += list(current)
	current = list()
	for(var/i in 2 to min(passed, LEDGER_MINUTES))
		minutes += list(list()) // nothing came in
	if(minutes.len > LEDGER_MINUTES)
		minutes.Cut(1, minutes.len - LEDGER_MINUTES + 1)
	minute_started += passed * (1 MINUTES)

/datum/research_ledger/proc/node_researched(datum/techweb_node/node, cost)
	spent += max(0, cost)
	researched.Insert(1, list(list(node.display_name, max(0, cost), world.time)))
	if(researched.len > LEDGER_RESEARCHED)
		researched.Cut(LEDGER_RESEARCHED + 1)

/// One minute as numbers in the sources' order
/datum/research_ledger/proc/minute_row(list/minute)
	. = list()
	for(var/source in GLOB.research_sources)
		. += round(minute[source] || 0)

/// Points a minute over the last five whole minutes (or the minute so far, early on)
/datum/research_ledger/proc/per_minute()
	var/count = min(5, minutes.len)
	if(!count)
		var/elapsed = world.time - minute_started
		if(elapsed < 10 SECONDS)
			return 0
		var/so_far = 0
		for(var/source in current)
			so_far += current[source]
		return so_far * (1 MINUTES) / elapsed
	var/sum = 0
	for(var/i in minutes.len - count + 1 to minutes.len)
		var/list/minute = minutes[i]
		for(var/source in minute)
			sum += minute[source]
	return sum / count

/datum/research_ledger/proc/dashboard_data()
	roll_minutes()
	var/datum/techweb/web = SSresearch.science_tech
	var/points = web.research_points[TECHWEB_POINT_TYPE_GENERIC] || 0
	var/rate = per_minute()
	. = list()
	.["points"] = round(points)
	.["per_minute"] = round(rate)
	.["spent"] = round(spent)
	.["sources"] = GLOB.research_sources
	// This shift, and the last ten minutes, by source
	var/list/shift = list()
	var/list/recent = list()
	for(var/source in GLOB.research_sources)
		shift += round(totals[source] || 0)
		var/sum = current[source] || 0
		for(var/i in max(1, minutes.len - 9) to minutes.len)
			var/list/minute = minutes[i]
			sum += minute[source] || 0
		recent += round(sum)
	.["shift"] = shift
	.["recent"] = recent
	var/list/chart = list()
	for(var/list/minute in minutes)
		chart += list(minute_row(minute))
	chart += list(minute_row(current))
	.["chart"] = chart
	.["minute_progress"] = round((world.time - minute_started) / (1 MINUTES), 0.01)
	// Researched, and what's nearest to affordable
	var/total_nodes = 0
	for(var/id in SSresearch.techweb_nodes)
		if(!web.hidden_nodes[id])
			total_nodes++
	.["researched_count"] = length(web.researched_nodes)
	.["node_count"] = total_nodes
	var/list/last = list()
	for(var/list/entry in researched)
		last += list(list("name" = entry[1], "cost" = round(entry[2]), "minutes_ago" = round((world.time - entry[3]) / (1 MINUTES))))
	.["last_researched"] = last
	var/list/costs = list()
	for(var/id in web.available_nodes)
		if(web.researched_nodes[id] || web.hidden_nodes[id])
			continue
		var/datum/techweb_node/node = SSresearch.techweb_node_by_id(id)
		if(!node)
			continue
		var/list/price = node.get_price(web)
		costs[node] = price[TECHWEB_POINT_TYPE_GENERIC] || 0
	sortTim(costs, GLOBAL_PROC_REF(cmp_numeric_asc), associative = TRUE)
	var/list/next = list()
	for(var/datum/techweb_node/node as anything in costs)
		var/cost = costs[node]
		var/short = max(0, cost - points)
		next += list(list("name" = node.display_name, "cost" = round(cost), "short" = round(short), "eta" = (short && rate > 0) ? CEILING(short / rate, 1) : null))
		if(next.len >= 6)
			break
	.["next"] = next
	// The servers. With one server's worth of income (the default), any one running pays it all and heat doesn't change it.
	var/list/servers = list()
	var/running = 0
	for(var/obj/machinery/rnd/server/S in GLOB.machines)
		var/status = "Running"
		if(S.stat & BROKEN)
			status = "Broken"
		else if(S.stat & NOPOWER)
			status = "No power"
		else if(S.stat & EMPED)
			status = "EMP"
		if(S.working)
			running++
		var/temperature = S.get_env_temp()
		servers += list(list(
			"name" = S.name,
			"status" = status,
			"working" = S.working,
			"temperature" = round(temperature - T0C, 0.1),
			"hot" = SSresearch.multiserver_calculation && temperature > S.temp_tolerance_high,
		))
	.["servers"] = servers
	.["servers_running"] = running
	.["server_income"] = SSresearch.multiserver_calculation ? null : round((SSresearch.single_server_income[TECHWEB_POINT_TYPE_GENERIC] || 0) * 60)

// The hooks

/datum/techweb/add_point_type(type, amount)
	. = ..()
	if(. && type == TECHWEB_POINT_TYPE_GENERIC && src == SSresearch.science_tech)
		GLOB.research_ledger.record(amount, caller)

/datum/techweb/add_point_list(list/pointlist)
	. = ..()
	if(src == SSresearch.science_tech && pointlist && SSresearch.point_types[TECHWEB_POINT_TYPE_GENERIC])
		GLOB.research_ledger.record(pointlist[TECHWEB_POINT_TYPE_GENERIC], caller)

/datum/techweb/research_node(datum/techweb_node/node, force = FALSE, auto_adjust_cost = TRUE, get_that_dosh = TRUE)
	var/before = research_points[TECHWEB_POINT_TYPE_GENERIC] || 0
	. = ..()
	if(. && istype(node) && src == SSresearch.science_tech)
		GLOB.research_ledger.node_researched(node, before - (research_points[TECHWEB_POINT_TYPE_GENERIC] || 0))

// The window: the R&D server controller

/obj/machinery/computer/rdservercontrol/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, \
										datum/tgui/master_ui = null, datum/ui_state/state = GLOB.default_state)
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "research_dashboard", name, 780, 680, master_ui, state)
		ui.open()

/obj/machinery/computer/rdservercontrol/ui_data(mob/user)
	return GLOB.research_ledger.dashboard_data()

#undef LEDGER_MINUTES
#undef LEDGER_RESEARCHED
