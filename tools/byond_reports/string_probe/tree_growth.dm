// Strings kept alive in a given order, every insert timed. Does the order matter on its own, and are there stalls?
// Tiny world only: dm tree_growth.dm, then dd tree_growth.dmb -invisible -params "case=ascending"
// Cases: ascending, descending, shuffled, ascending_short (fixed text with no long shared front)

#define TG_TOTAL 300000
#define TG_WINDOW 30000
#define TG_STALL_MS 1

/world
	fps = 20

/proc/tg_text(n, shape)
	return shape ? "a[num2text(n, 8, 16)]" : "\[0x21[num2text(n, 6, 16)]]"

/proc/tg_run(which)
	world.log << "BYOND [world.byond_version].[world.byond_build], case [which], [TG_TOTAL] strings"
	var/list/order = new/list(TG_TOTAL)
	for(var/i in 1 to TG_TOTAL)
		order[i] = which == "descending" ? TG_TOTAL - i : i
	if(which == "shuffled")
		for(var/i in TG_TOTAL to 2 step -1)
			order.Swap(i, rand(1, i))
	var/shape = which == "ascending_short"
	var/list/pieces = new/list(TG_TOTAL)
	for(var/i in 1 to TG_TOTAL)
		var/n = order[i]
		pieces[i] = num2text(n, 8, 16)
	var/list/kept = new/list(TG_TOTAL)
	var/front = shape ? "a" : "\[0x21"
	var/back = shape ? "" : "]"
	var/window_total = 0
	var/window_worst = 0
	var/stalls = 0
	var/stall_ms = 0
	var/last_stall = 0
	var/list/gaps = list()
	var/grand = 0
	for(var/i in 1 to TG_TOTAL)
		var/middle = pieces[i]
		var/t0 = world.tick_usage
		var/text = "[front][middle][back]"
		var/t1 = world.tick_usage
		kept[i] = text
		var/ms = (t1 - t0) * world.tick_lag
		window_total += ms
		grand += ms
		window_worst = max(window_worst, ms)
		if(ms > TG_STALL_MS)
			stalls++
			stall_ms += ms
			if(last_stall && length(gaps) < 12)
				gaps += i - last_stall
			last_stall = i
		if(!(i % TG_WINDOW))
			world.log << "up to [i]: mean [round(window_total * 1000 / TG_WINDOW, 0.1)] us, worst [round(window_worst, 0.1)] ms, [stalls] inserts over [TG_STALL_MS] ms so far, costing [round(stall_ms)] ms"
			window_total = 0
			window_worst = 0
			sleep(1)
	world.log << "all [TG_TOTAL]: [round(grand)] ms, gaps between stalls [jointext(gaps, " ")]"
	world.log << "done"
	del(world)

/world/New()
	. = ..()
	var/which = params["case"] || "ascending"
	spawn(5)
		tg_run(which)
