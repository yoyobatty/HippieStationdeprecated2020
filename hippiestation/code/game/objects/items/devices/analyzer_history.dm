#define ANALYZER_HISTORY_LENGTH 20
#define ANALYZER_DELTA_PRESSURE 0.5 // kPa; smaller pressure changes than this aren't worth reporting
#define ANALYZER_DELTA_TEMPERATURE 0.5 // kelvin
#define ANALYZER_DELTA_PERCENT 0.5 // percentage points of a gas's share of the mix

/**
  * Gas analyzers keep a log of their last few readings, so a tech can walk a loop, fiddle with a pump and come back
  * to see what actually changed instead of trying to remember numbers from chat. Rescanning the same spot or object
  * prints what changed since the last reading of it, and the full log can be read (and cleared) from the item's verb.
  * The log lives on the device itself, so handing your analyzer to someone hands them your readings too.
  */
/obj/item/analyzer
	/// Oldest first. Each entry is an assoc list: time, stamp, label, key, pressure, temperature, moles, composition (gas name -> percent)
	var/list/scan_history

/obj/item/analyzer/examine(mob/user)
	. = ..()
	. += "<span class='notice'>It remembers its last [ANALYZER_HISTORY_LENGTH] readings. Right-click it and use <b>View Scan History</b> to read them.</span>"

/obj/item/analyzer/attack_self(mob/user)
	. = ..()
	if(user.stat || user.eye_blind || !isturf(user.loc))
		return
	var/turf/T = user.loc
	var/area/A = T.loc
	record_scan(user, T.return_air(), "[A.name] ([T.x], [T.y])", "turf [T.x],[T.y],[T.z]")

/obj/analyzer_act(mob/living/user, obj/item/I)
	. = ..()
	if(!. || !istype(I, /obj/item/analyzer))
		return
	var/obj/item/analyzer/scanner = I
	var/mixture = return_analyzable_air()
	if(!mixture)
		return
	if(!islist(mixture))
		scanner.record_scan(user, mixture, name, REF(src))
		return
	var/list/airs = mixture
	for(var/i in 1 to airs.len)
		scanner.record_scan(user, airs[i], "[name] (node [i])", "[REF(src)] node [i]")

/// Logs a reading of `air`, and tells the user what changed if this device has read the same `key` before.
/obj/item/analyzer/proc/record_scan(mob/user, datum/gas_mixture/air, label, key)
	if(!air)
		return
	var/total_moles = air.total_moles()
	var/list/composition = list()
	if(total_moles > 0)
		for(var/id in air.moles)
			var/amount = air.moles[id]
			if(amount > 0)
				composition[GAS_META[META_GAS_NAME][id]] = amount / total_moles * 100

	var/list/entry = list(
		"time" = world.time,
		"stamp" = station_time_timestamp("hh:mm:ss"),
		"label" = label,
		"key" = key,
		"pressure" = air.return_pressure(),
		"temperature" = air.temperature,
		"moles" = total_moles,
		"composition" = composition,
	)

	var/list/previous = find_previous_scan(key)
	if(!scan_history)
		scan_history = list()
	scan_history[++scan_history.len] = entry
	if(scan_history.len > ANALYZER_HISTORY_LENGTH)
		scan_history.Cut(1, 2)

	if(previous)
		to_chat(user, "<span class='notice'>[describe_change(previous, entry)]</span>")

/obj/item/analyzer/proc/find_previous_scan(key)
	for(var/i in length(scan_history) to 1 step -1)
		var/list/entry = scan_history[i]
		if(entry["key"] == key)
			return entry

/// One line describing how a reading differs from an earlier reading of the same place.
/obj/item/analyzer/proc/describe_change(list/before, list/after)
	var/elapsed = DisplayTimeText(after["time"] - before["time"], 1)
	var/list/changes = list()

	var/pressure_change = after["pressure"] - before["pressure"]
	if(abs(pressure_change) >= ANALYZER_DELTA_PRESSURE)
		changes += "pressure [signed_number(pressure_change)] kPa"
	var/temperature_change = after["temperature"] - before["temperature"]
	if(abs(temperature_change) >= ANALYZER_DELTA_TEMPERATURE)
		changes += "temperature [signed_number(temperature_change)] K"

	var/list/old_mix = before["composition"]
	var/list/new_mix = after["composition"]
	for(var/gas in old_mix | new_mix)
		var/old_share = old_mix[gas] || 0
		var/new_share = new_mix[gas] || 0
		if(abs(new_share - old_share) >= ANALYZER_DELTA_PERCENT)
			changes += "[gas] [round(old_share, 0.1)]% -&gt; [round(new_share, 0.1)]%"

	if(!changes.len)
		return "No significant change since the last reading here ([elapsed] ago)."
	return "Since the last reading here ([elapsed] ago): [changes.Join(", ")]."

/obj/item/analyzer/proc/signed_number(value)
	return "[value >= 0 ? "+" : ""][round(value, 0.01)]"

/obj/item/analyzer/verb/view_scan_history()
	set name = "View Scan History"
	set category = "Object"
	set src in usr

	if(!usr.canUseTopic(src, BE_CLOSE))
		return
	show_scan_history(usr)

/obj/item/analyzer/proc/show_scan_history(mob/user)
	var/list/dat = list()
	if(!length(scan_history))
		dat += "<i>No readings stored.</i>"
	else
		// Work out each reading's change against the previous reading of the same place, then list newest first.
		var/list/last_by_key = list()
		var/list/rows = list()
		for(var/list/entry in scan_history)
			var/list/previous = last_by_key[entry["key"]]
			var/change = previous ? "[signed_number(entry["pressure"] - previous["pressure"])] kPa<br>[signed_number(entry["temperature"] - previous["temperature"])] K" : "&mdash;"
			last_by_key[entry["key"]] = entry

			var/list/gases = list()
			var/list/composition = entry["composition"]
			for(var/gas in composition)
				if(composition[gas] >= 0.1)
					gases += "[gas] [round(composition[gas], 0.1)]%"

			rows.Insert(1, "<tr><td>[entry["stamp"]]</td><td>[html_encode(entry["label"])]</td><td>[round(entry["pressure"], 0.01)] kPa</td><td>[round(entry["temperature"], 0.1)] K<br>[round(entry["temperature"] - T0C, 0.1)] &deg;C</td><td>[round(entry["moles"], 0.01)]</td><td>[gases.len ? gases.Join("<br>") : "<i>empty</i>"]</td><td>[change]</td></tr>")

		dat += "<table style='width:100%' cellspacing='0' cellpadding='3' border='1'>"
		dat += "<tr><th>Time</th><th>Location</th><th>Pressure</th><th>Temperature</th><th>Moles</th><th>Composition</th><th>Change</th></tr>"
		dat += rows
		dat += "</table>"
		dat += "<br><a href='?src=[REF(src)];clear_history=1'>Clear history</a>"

	var/datum/browser/popup = new(user, "analyzer_history", "[name] &mdash; scan history", 640, 480)
	popup.set_content(dat.Join())
	popup.open()

/obj/item/analyzer/Topic(href, href_list)
	. = ..()
	if(!href_list["clear_history"] || !usr.canUseTopic(src, BE_CLOSE))
		return
	scan_history = null
	to_chat(usr, "<span class='notice'>You wipe [src]'s stored readings.</span>")
	show_scan_history(usr)

#undef ANALYZER_HISTORY_LENGTH
#undef ANALYZER_DELTA_PRESSURE
#undef ANALYZER_DELTA_TEMPERATURE
#undef ANALYZER_DELTA_PERCENT
