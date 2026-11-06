// The telecomms network as a map (tgui-next interfaces/common/TelecommsMap.js): each machine where it stands, its links,
// how busy it is and what's wrong with it (signal_quality.dm). Shown in the Traffic Control app's Network tab and in the
// telecommunications monitor for the machines it probed. Silent rules never show here. Included after traffic_control.dm,
// whose app ui_data this adds to.

/// Map data for a set of telecomms machines: list("nodes" = ..., "links" = ...)
/proc/tcomms_map_data(list/machines)
	var/list/nodes = list()
	var/list/links = list()
	var/list/included = list()
	for(var/obj/machinery/telecomms/T in machines)
		if(T.hide || QDELETED(T))
			continue
		included[T] = TRUE
	for(var/obj/machinery/telecomms/T in included)
		var/turf/at = get_turf(T)
		var/kind = "relay"
		if(istype(T, /obj/machinery/telecomms/hub))
			kind = "hub"
		else if(istype(T, /obj/machinery/telecomms/bus))
			kind = "bus"
		else if(istype(T, /obj/machinery/telecomms/processor))
			kind = "processor"
		else if(istype(T, /obj/machinery/telecomms/server))
			kind = "server"
		else if(istype(T, /obj/machinery/telecomms/receiver))
			kind = "receiver"
		else if(istype(T, /obj/machinery/telecomms/broadcaster))
			kind = "broadcaster"
		else if(istype(T, /obj/machinery/telecomms/message_server))
			kind = "message"
		var/temperature = T.machine_temperature()
		var/noise = round(min(1, T.own_noise() + T.heat_noise()) * 100)
		var/state = "ok"
		if(!T.on || T.overheated)
			state = "off"
		else if(T.stat & EMPED || noise >= 50)
			state = "fault"
		else if(noise >= 5)
			state = "warn"
		nodes += list(list(
			"ref" = REF(T),
			"kind" = kind,
			"name" = T.name,
			"id" = T.id,
			"x" = at ? at.x : 0,
			"y" = at ? at.y : 0,
			"z" = at ? at.z : 0,
			"remote" = at ? !is_station_level(at.z) : TRUE,
			"state" = state,
			"on" = T.on,
			"toggled" = T.toggled,
			"overheated" = T.overheated,
			"emped" = !!(T.stat & EMPED),
			"integrity" = T.max_integrity ? round(T.obj_integrity / T.max_integrity * 100) : 100,
			"traffic" = max(T.traffic, 0),
			"temperature" = round(temperature, 0.1),
			"noise" = noise,
		))
		for(var/obj/machinery/telecomms/other in T.links)
			if(!included[other])
				continue
			var/a = REF(T)
			var/b = REF(other)
			var/key = a < b ? "[a]-[b]" : "[b]-[a]"
			if(links[key])
				continue
			links[key] = list("a" = a, "b" = b)
	var/list/link_list = list()
	for(var/key in links)
		link_list += list(links[key])
	return list("nodes" = nodes, "links" = link_list)

/// Every telecomms machine of the station's network, and the relays it reaches elsewhere
/proc/tcomms_station_machines()
	var/list/out = list()
	for(var/obj/machinery/telecomms/T in GLOB.telecomms_list)
		var/turf/at = get_turf(T)
		if(!at)
			continue
		if(is_station_level(at.z) || istype(T, /obj/machinery/telecomms/relay))
			out += T
	return out

/datum/computer_file/program/traffic_control/ui_data(mob/user)
	. = ..()
	.["map"] = tcomms_map_data(tcomms_station_machines())

/obj/machinery/computer/telecomms/monitor/ui_data(mob/user)
	. = ..()
	.["map"] = tcomms_map_data(machinelist)

/obj/machinery/computer/telecomms/monitor/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, datum/tgui/master_ui = null, datum/ui_state/state = GLOB.default_state)
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "telecomms_monitor", name, 700, 640, master_ui, state)
		ui.open()
