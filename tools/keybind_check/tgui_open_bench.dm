// How long a tgui window takes from open() to its first paint, with a real client (BYOND 516, WebView2). Each machine's window is
// opened, timed and closed several times: the first open of a connection, then repeats. The page reports when navigation started
// (performance.timeOrigin) and when it first painted (first-contentful-paint, or window.__hippiePaintedAt__ when a window is reused
// and doesn't navigate). Server and client share the machine's clock; times are ms within a 1000 s cycle, since a float can't hold
// epoch ms. Not part of the game: HARNESS=tgui_open_bench.dm MAP=testbench tools/keybind_check/run.sh tgui_open
// OPENS=<n> in data/tgui_open_bench_opens (default 6) sets the opens per machine.

GLOBAL_VAR_INIT(keycheck_running, FALSE)
GLOBAL_LIST_EMPTY(tob_probes)
GLOBAL_VAR_INIT(tob_probe_count, 0)

/datum/preferences/save_preferences()
	return FALSE

/datum/preferences/save_character()
	return FALSE

/proc/kc_log(text)
	text2file(text, "data/keycheck.txt")

/client/New()
	if(fexists("data/tgui_open_bench_nopool")) // the A side of an A/B: every window the old way
		GLOB.tgui_pool_enabled = FALSE
	. = ..()
	if(. && !GLOB.keycheck_running)
		GLOB.keycheck_running = TRUE
		spawn(10)
			tgui_open_bench_run(src)

/client/Topic(href, href_list, hsrc)
	if(href_list["probe"])
		GLOB.tob_probes[href_list["probe"]] = href_list["value"]
		return
	return ..()

/// Now, in ms within a 1000 s cycle
/proc/tob_now()
	var/stamp = "[rustg_unix_timestamp()]"
	var/dot = findtext(stamp, ".")
	var/whole = dot ? copytext(stamp, 1, dot) : stamp
	var/frac = dot ? text2num("0[copytext(stamp, dot)]") : 0
	return text2num(copytext(whole, -3)) * 1000 + frac * 1000

/// b - a within the cycle
/proc/tob_diff(a, b)
	. = b - a
	if(. < -500000)
		. += 1000000
	else if(. > 500000)
		. -= 1000000

/proc/tob_median(list/values)
	if(!length(values))
		return -1
	var/list/sorted = sortList(values.Copy(), GLOBAL_PROC_REF(cmp_numeric_asc))
	return sorted[round((length(sorted) + 1) / 2)]

/proc/tob_probe_js(label)
	return {"(function () {
var origin = performance.timeOrigin;
var fcp = performance.getEntriesByType('paint').filter(function (e) { return e.name === 'first-contentful-paint'; })\[0\];
var paint = window.__hippiePaintedAt__ || (fcp ? origin + fcp.startTime : 0);
var bundle = performance.getEntriesByType('resource').filter(function (r) { return /tgui\\.bundle\\.js/.test(r.name); })\[0\];
var v = \[(origin % 1e6).toFixed(1), paint ? (paint % 1e6).toFixed(1) : -1, bundle ? bundle.duration.toFixed(1) : -1, document.getElementById('Layout__content') ? 1 : 0, window.__hippieMounts__ || 0\].join(',');
window.chrome.webview.postMessage('byond://?probe=[label]&value=' + v);
})();"}

/// Opens M's window for H, waits for it, asks the page for its timings, closes it. Returns the open-to-paint ms, or -1.
/proc/tob_open_once(client/C, mob/living/carbon/human/H, obj/machinery/M, label)
	M.stat = 0
	var/t0 = tob_now()
	M.ui_interact(H)
	var/datum/tgui/ui = SStgui.get_open_ui(H, M, "main")
	if(!ui)
		kc_log("FAIL [label]: no window opened")
		return -1
	var/deadline = world.time + 10 SECONDS
	while(!ui.initialized && world.time < deadline)
		sleep(world.tick_lag)
	var/init_ms = tob_diff(t0, tob_now())
	if(!ui.initialized)
		kc_log("FAIL [label]: never initialized")
		ui.close()
		return -1
	sleep(25) // let it paint
	var/probe = "p[++GLOB.tob_probe_count]" // the label has a # in it, which a URL takes for its fragment
	C << output(url_encode(tob_probe_js(probe)), ui.window_output_id("eval"))
	deadline = world.time + 5 SECONDS
	while(isnull(GLOB.tob_probes[probe]) && world.time < deadline)
		sleep(1)
	var/answer = GLOB.tob_probes[probe]
	ui.close()
	if(!answer)
		kc_log("FAIL [label]: the page never answered")
		return -1
	var/list/v = splittext(answer, ",")
	var/origin = text2num(v[1])
	var/paint = text2num(v[2])
	var/total = paint >= 0 ? tob_diff(t0, paint) : -1
	kc_log("[label]: initialize [round(init_ms)] ms, window up to navigation [round(tob_diff(t0, origin))] ms, navigation to paint [paint >= 0 ? round(tob_diff(origin, paint)) : "none"] ms, OPEN TO PAINT [round(total)] ms, bundle [v[3]] ms, rendered [v[4]], mounts [v[5]]")
	return total

/proc/tgui_open_bench_run(client/C)
	var/opens = 6
	if(fexists("data/tgui_open_bench_opens"))
		opens = text2num(trim(file2text("data/tgui_open_bench_opens"))) || opens
	GLOB.master_mode = "extended"
	SSticker.start_immediately = TRUE
	var/wait_for_round = world.time + 3 MINUTES
	while(SSticker.current_state < GAME_STATE_PLAYING && world.time < wait_for_round)
		sleep(1 SECONDS)
	sleep(3 SECONDS)
	var/turf/home = get_turf(pick(SSjob.latejoin_trackers))
	var/mob/living/carbon/human/H = new(home)
	H.mind_initialize()
	H.equipOutfit(/datum/outfit/job/assistant)
	H.ckey = C.ckey
	sleep(3 SECONDS)
	kc_log("round state [SSticker.current_state], mob [C.mob], [opens] opens a machine, pool [GLOB.tgui_pool_enabled ? "on" : "off"]")
	var/list/machines = list(
		"space heater" = /obj/machinery/space_heater,
		"SMES" = /obj/machinery/power/smes,
		"R&D console" = /obj/machinery/computer/rdconsole/core,
		"canister" = /obj/machinery/portable_atmospherics/canister/oxygen,
	)
	var/list/summary = list()
	for(var/name in machines)
		var/type = machines[name]
		var/obj/machinery/M = new type(home)
		var/list/firsts = list()
		var/list/repeats = list()
		for(var/i in 1 to opens)
			var/ms = tob_open_once(C, H, M, "[name] #[i]")
			if(ms >= 0)
				if(i == 1)
					firsts += ms
				else
					repeats += ms
			sleep(10)
		summary += "[name]: first [round(tob_median(firsts))] ms, repeats median [round(tob_median(repeats))] ms ([length(repeats)] of [opens - 1])"
		qdel(M)
	for(var/line in summary)
		kc_log("SUMMARY [line]")
	kc_log("done")
