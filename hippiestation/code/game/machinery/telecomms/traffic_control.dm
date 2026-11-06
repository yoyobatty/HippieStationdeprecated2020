// Telecomms traffic rules: a point-and-click NTSL, edited from the "Traffic Control" NTOS app (tgui-next
// NtosTrafficControl.js). Each rule matches radio messages by channel, speaker, job and a word, and does one thing to them:
// block, reroute to another channel, copy to another channel, replace the word, or garble (adds to the static of
// signal_quality.dm). An emagged computer can also rename the speaker and make rules silent: hidden from the rule list
// and leaving no server log of what they blocked or rerouted. Rules run at the channel's server, before it logs the message.
// The user's rulings, 2026-11-06.

#define TCOMMS_MAX_RULES 20
#define TCOMMS_RULE_TEXT_LEN 64

GLOBAL_LIST_EMPTY(tcomms_rules)
GLOBAL_VAR_INIT(tcomms_rule_ids, 0)
/// Rule changes as the app's history shows them: list(time, who, what). Silent rules' changes aren't kept here.
GLOBAL_LIST_EMPTY(tcomms_rule_history)

/// Actions any crew member with telecomms access may use
GLOBAL_LIST_INIT(tcomms_rule_actions, list("block", "reroute", "copy", "replace", "garble"))
/// Actions only an emagged computer offers
GLOBAL_LIST_INIT(tcomms_rule_actions_hacked, list("rename"))

/datum/tcomms_rule
	var/id
	var/enabled = TRUE
	// What it matches; null matches anything
	var/frequency
	var/speaker
	var/job
	var/word
	// What it does
	var/action = "block"
	var/target_frequency
	var/replace_with = ""
	var/garble = 50
	var/rename_to = ""
	var/silent = FALSE
	var/author = "Unknown"
	var/hits = 0

/datum/tcomms_rule/proc/matches(datum/signal/subspace/vocal/signal)
	if(frequency && signal.frequency != frequency)
		return FALSE
	if(speaker && !findtext(lowertext("[signal.data["name"]]"), lowertext(speaker)))
		return FALSE
	if(job && !findtext(lowertext("[signal.data["job"]]"), lowertext(job)))
		return FALSE
	if(word && !findtext(lowertext("[signal.data["message"]]"), lowertext(word)))
		return FALSE
	return TRUE

/datum/tcomms_rule/proc/apply(datum/signal/subspace/vocal/signal, obj/machinery/telecomms/server/server)
	switch(action)
		if("block")
			signal.data["reject"] = TRUE
		if("reroute")
			// Changed at the broadcaster: the server drops a signal that's no longer on a frequency it serves
			if(target_frequency)
				signal.data["reroute_to"] = target_frequency
		if("copy")
			if(target_frequency && target_frequency != signal.frequency)
				var/datum/signal/subspace/vocal/copy = signal.copy()
				copy.frequency = target_frequency
				copy.data["rules_applied"] = TRUE
				copy.data["noise_seen"] = list()
				server.relay_information(copy, /obj/machinery/telecomms/hub)
		if("replace")
			if(word)
				signal.data["message"] = replacetext(signal.data["message"], word, replace_with)
		if("garble")
			signal.data["noise"] = min(1, (signal.data["noise"] || 0) + garble / 100)
		if("rename")
			if(rename_to)
				signal.data["name"] = rename_to

/// "Common", "145.9" or "Any"
/proc/tcomms_channel_name(freq)
	if(!freq)
		return "Any"
	for(var/name in GLOB.radiochannels)
		if(GLOB.radiochannels[name] == freq)
			return name
	return format_frequency(freq)

/datum/tcomms_rule/proc/describe()
	var/list/conds = list()
	conds += "channel [tcomms_channel_name(frequency)]"
	if(speaker)
		conds += "speaker has '[speaker]'"
	if(job)
		conds += "job has '[job]'"
	if(word)
		conds += "message has '[word]'"
	var/what = action
	switch(action)
		if("reroute", "copy")
			what = "[action] to [tcomms_channel_name(target_frequency)]"
		if("replace")
			what = "replace with '[replace_with]'"
		if("garble")
			what = "garble [garble]%"
		if("rename")
			what = "rename to '[rename_to]'"
	return "if [conds.Join(", ")]: [what]"

/proc/tcomms_rule_history_add(who, what)
	GLOB.tcomms_rule_history.Insert(1, list(list("time" = station_time_timestamp(), "who" = who, "what" = what)))
	if(GLOB.tcomms_rule_history.len > 30)
		GLOB.tcomms_rule_history.Cut(31)

/// Runs the rules over a message at its server, once
/proc/tcomms_apply_rules(datum/signal/subspace/vocal/signal, obj/machinery/telecomms/server/server)
	if(!length(GLOB.tcomms_rules) || !istype(signal) || !signal.data || signal.data["rules_applied"])
		return
	signal.data["rules_applied"] = TRUE
	var/list/tags = list()
	for(var/datum/tcomms_rule/R in GLOB.tcomms_rules)
		if(!R.enabled || !R.matches(signal))
			continue
		R.hits++
		R.apply(signal, server)
		if(R.silent)
			if(R.action in list("block", "reroute"))
				signal.data["rule_hide_log"] = TRUE
		else
			tags += "#[R.id] [R.action]"
		if(R.action == "block")
			break
	if(tags.len)
		signal.data["rule_tags"] = tags.Join(", ")

/obj/machinery/telecomms/server/receive_information(datum/signal/subspace/vocal/signal, obj/machinery/telecomms/machine_from)
	if(!istype(signal) || !signal.data || !signal.data["message"] || !on || !is_freq_listening(signal))
		return ..()
	tcomms_apply_rules(signal, src)
	var/logs_before = log_entries.len
	. = ..()
	// The log entry this message just made: tagged with the rules that touched it, or gone if a silent rule hid it
	if(log_entries.len > logs_before || (logs_before >= 400 && log_entries.len))
		var/datum/comm_log_entry/entry = log_entries[log_entries.len]
		if(signal.data["rule_hide_log"])
			log_entries -= entry
		else if(signal.data["rule_tags"])
			entry.parameters["rules"] = signal.data["rule_tags"]

/obj/machinery/telecomms/broadcaster/receive_information(datum/signal/subspace/signal, obj/machinery/telecomms/machine_from)
	if(istype(signal) && signal.data && signal.data["reroute_to"])
		signal.frequency = signal.data["reroute_to"]
	return ..()

// The app

/datum/computer_file/program/traffic_control
	filename = "trafficctrl"
	filedesc = "Traffic Control"
	program_icon_state = "comm_monitor"
	extended_desc = "Rules for the station's telecommunications traffic: block, reroute, copy, filter and garble radio messages."
	transfer_access = ACCESS_TCOMSAT
	required_access = ACCESS_TCOMSAT
	requires_ntnet = TRUE
	network_destination = "telecommunications traffic control"
	usage_flags = PROGRAM_ALL
	size = 6
	tgui_id = "ntos_traffic_control"
	ui_x = 680
	ui_y = 640
	available_on_ntnet = TRUE

/// The same app off the hacked list: what an emagged computer can get without telecomms access
/datum/computer_file/program/traffic_control/cracked
	filename = "trafficctrl_x"
	filedesc = "Traffic Control (cracked)"
	extended_desc = "A cracked telecommunications traffic controller. Needs no access."
	transfer_access = null
	required_access = null
	available_on_ntnet = FALSE
	available_on_syndinet = TRUE

/datum/computer_file/program/traffic_control/proc/hacked()
	return computer && (computer.obj_flags & EMAGGED)

/datum/computer_file/program/traffic_control/proc/user_name(mob/user)
	var/obj/item/card/id/I = user.get_idcard(TRUE)
	return I?.registered_name || user.real_name || user.name

/datum/computer_file/program/traffic_control/ui_data(mob/user)
	var/list/data = get_header_data()
	var/hacked = hacked()
	data["hacked"] = hacked
	data["max_rules"] = TCOMMS_MAX_RULES
	var/list/rules = list()
	var/index = 0
	for(var/datum/tcomms_rule/R in GLOB.tcomms_rules)
		index++
		if(R.silent && !hacked)
			continue
		rules += list(list(
			"id" = R.id,
			"index" = index,
			"enabled" = R.enabled,
			"frequency" = R.frequency,
			"channel" = tcomms_channel_name(R.frequency),
			"speaker" = R.speaker,
			"job" = R.job,
			"word" = R.word,
			"action" = R.action,
			"target" = R.target_frequency ? tcomms_channel_name(R.target_frequency) : null,
			"replace_with" = R.replace_with,
			"garble" = R.garble,
			"rename_to" = R.rename_to,
			"silent" = R.silent,
			"author" = R.author,
			"hits" = R.hits,
			"text" = R.describe(),
		))
	data["rules"] = rules
	data["rule_count"] = length(GLOB.tcomms_rules)
	var/list/channels = list()
	for(var/name in GLOB.radiochannels)
		channels += list(list("name" = name, "frequency" = GLOB.radiochannels[name]))
	data["channels"] = channels
	data["actions"] = hacked ? GLOB.tcomms_rule_actions + GLOB.tcomms_rule_actions_hacked : GLOB.tcomms_rule_actions
	data["history"] = GLOB.tcomms_rule_history
	return data

/// A rule text field from the window: plain, short, or null for "anything"
/proc/tcomms_rule_text(text)
	text = trim(copytext(sanitize(text), 1, TCOMMS_RULE_TEXT_LEN))
	return length(text) ? text : null

/datum/computer_file/program/traffic_control/ui_act(action, list/params)
	if(..())
		return TRUE
	var/mob/user = usr
	var/hacked = hacked()
	switch(action)
		if("add_rule")
			if(length(GLOB.tcomms_rules) >= TCOMMS_MAX_RULES)
				to_chat(user, "<span class='warning'>Rule table full.</span>")
				return TRUE
			var/rule_action = params["action"]
			if(!(rule_action in GLOB.tcomms_rule_actions) && !(hacked && (rule_action in GLOB.tcomms_rule_actions_hacked)))
				return TRUE
			var/datum/tcomms_rule/R = new
			R.action = rule_action
			R.frequency = text2num(params["frequency"]) || null
			R.speaker = tcomms_rule_text(params["speaker"])
			R.job = tcomms_rule_text(params["job"])
			R.word = tcomms_rule_text(params["word"])
			R.target_frequency = text2num(params["target"]) || null
			R.replace_with = tcomms_rule_text(params["replace_with"]) || ""
			R.garble = clamp(round(text2num(params["garble"]) || 50), 5, 100)
			R.rename_to = tcomms_rule_text(params["rename_to"]) || ""
			R.silent = hacked && text2num(params["silent"]) ? TRUE : FALSE
			R.author = user_name(user)
			if(R.action in list("reroute", "copy"))
				if(!R.target_frequency)
					return TRUE
			if(R.action == "replace" && !R.word)
				return TRUE
			if(R.action == "rename" && !R.rename_to)
				return TRUE
			R.id = ++GLOB.tcomms_rule_ids
			GLOB.tcomms_rules += R
			log_game("[key_name(user)] added telecomms rule #[R.id][R.silent ? " (silent)" : ""]: [R.describe()]")
			if(!R.silent)
				tcomms_rule_history_add(R.author, "added #[R.id]: [R.describe()]")
			return TRUE
		if("toggle_rule", "delete_rule", "move_rule")
			var/datum/tcomms_rule/R
			for(var/datum/tcomms_rule/each in GLOB.tcomms_rules)
				if(each.id == text2num(params["id"]))
					R = each
			if(!R || (R.silent && !hacked))
				return TRUE
			switch(action)
				if("toggle_rule")
					R.enabled = !R.enabled
					if(!R.silent)
						tcomms_rule_history_add(user_name(user), "[R.enabled ? "enabled" : "disabled"] #[R.id]")
				if("delete_rule")
					GLOB.tcomms_rules -= R
					if(!R.silent)
						tcomms_rule_history_add(user_name(user), "deleted #[R.id]: [R.describe()]")
				if("move_rule")
					var/i = GLOB.tcomms_rules.Find(R)
					var/j = i + (params["dir"] == "up" ? -1 : 1)
					if(j >= 1 && j <= GLOB.tcomms_rules.len)
						GLOB.tcomms_rules.Swap(i, j)
			log_game("[key_name(user)] [action] telecomms rule #[R.id]")
			return TRUE

#undef TCOMMS_MAX_RULES
#undef TCOMMS_RULE_TEXT_LEN
