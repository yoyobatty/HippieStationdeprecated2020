// The Traffic Control app's Wiretap tab (tgui-next NtosTrafficControl.js): the servers' logs as a live feed, newest first,
// with their channel and time. On an emagged computer it can also delete log entries, wipe them all, and inject a fake
// message as anyone on any channel, sent through the receivers like any radio, so the rules, the static and the logs
// treat it as real. The user's rulings, 2026-11-06. Included after traffic_control.dm.

#define TCOMMS_WIRETAP_KEEP 300
#define TCOMMS_WIRETAP_SHOW 150

/// Recent server log entries for the feed: list(list(entry, server)), oldest first
GLOBAL_LIST_EMPTY(tcomms_wiretap)

/proc/tcomms_wiretap_add(datum/comm_log_entry/entry, obj/machinery/telecomms/server/server)
	GLOB.tcomms_wiretap += list(list(entry, server))
	if(GLOB.tcomms_wiretap.len > TCOMMS_WIRETAP_KEEP)
		GLOB.tcomms_wiretap.Cut(1, 2)

/// A server blown up stayed in the feed's entries (which already hid it): its entries go with it, or it's a hard delete
/obj/machinery/telecomms/server/Destroy()
	for(var/i in GLOB.tcomms_wiretap.len to 1 step -1)
		var/list/item = GLOB.tcomms_wiretap[i]
		if(item[2] == src)
			GLOB.tcomms_wiretap.Cut(i, i + 1)
	return ..()

/datum/computer_file/program/traffic_control
	var/tab = "network"

/datum/computer_file/program/traffic_control/ui_data(mob/user)
	. = ..()
	.["tab"] = tab
	if(tab != "wiretap")
		return
	var/list/logs = list()
	var/shown = 0
	for(var/i in GLOB.tcomms_wiretap.len to 1 step -1)
		var/list/item = GLOB.tcomms_wiretap[i]
		var/datum/comm_log_entry/entry = item[1]
		var/obj/machinery/telecomms/server/server = item[2]
		if(QDELETED(server) || !(entry in server.log_entries)) // deleted here or from a log browser
			continue
		var/list/P = entry.parameters
		logs += list(list(
			"ref" = REF(entry),
			"time" = P["time"],
			"channel" = tcomms_channel_name(P["frequency"]),
			"name" = P["name"],
			"job" = P["job"],
			"message" = P["message"],
			"corrupt" = entry.input_type == "Corrupt File",
			"rules" = P["rules"],
			"server" = server.id,
		))
		if(++shown >= TCOMMS_WIRETAP_SHOW)
			break
	.["logs"] = logs

/datum/computer_file/program/traffic_control/ui_act(action, list/params)
	. = ..()
	if(.)
		return
	var/mob/user = usr
	switch(action)
		if("tab")
			if(params["tab"] in list("network", "rules", "wiretap", "history"))
				tab = params["tab"]
			return TRUE
		if("delete_log")
			if(!hacked())
				return TRUE
			for(var/list/item in GLOB.tcomms_wiretap)
				var/datum/comm_log_entry/entry = item[1]
				if(REF(entry) != params["ref"])
					continue
				var/obj/machinery/telecomms/server/server = item[2]
				if(!QDELETED(server))
					server.log_entries -= entry
				GLOB.tcomms_wiretap -= list(item)
				log_game("[key_name(user)] deleted a telecomms log entry: [entry.parameters["name"]]: [entry.parameters["message"]]")
				break
			return TRUE
		if("wipe_logs")
			if(!hacked())
				return TRUE
			for(var/obj/machinery/telecomms/server/S in tcomms_station_machines())
				S.log_entries.Cut()
			GLOB.tcomms_wiretap.Cut()
			log_game("[key_name(user)] wiped the telecomms server logs")
			return TRUE
		if("inject")
			if(!hacked())
				return TRUE
			var/freq = text2num(params["frequency"])
			var/fake_name = tcomms_rule_text(params["name"])
			var/fake_job = tcomms_rule_text(params["job"]) || "Unknown"
			var/message = copytext(sanitize(params["message"]), 1, MAX_MESSAGE_LEN)
			if(!freq || !fake_name || !length(message))
				return TRUE
			var/atom/movable/where = computer.physical || computer
			// The speaker the radios will name, as a radio makes one for a real voice (say.dm)
			var/atom/movable/virtualspeaker/speaker = new(null, null, null)
			speaker.name = fake_name
			speaker.job = fake_job
			speaker.source = where
			var/datum/signal/subspace/vocal/signal = new(where, freq, speaker, /datum/language/common, message, list())
			signal.send_to_receivers()
			log_game("[key_name(user)] injected a telecomms message as [fake_name] ([fake_job]) on [tcomms_channel_name(freq)]: [message]")
			return TRUE

#undef TCOMMS_WIRETAP_KEEP
#undef TCOMMS_WIRETAP_SHOW
