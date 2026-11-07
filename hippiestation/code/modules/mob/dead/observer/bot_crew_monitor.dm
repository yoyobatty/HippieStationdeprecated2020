// Bot Crew monitor (tgui-next BotCrewMonitor.js): every bot crewmember's job, what it's doing in its own words
// (describe_activity(), bot_chatter.dm), its goal and step, health, where it is and its last few goal and action
// events, with Follow. For ghosts (Ghost > Bot Crew) and admins; what a bot really is (its antagonist roles) only shows
// to admins. The user's pick, 2026-11-06. It only reads the bots: nothing in bots_ai changes, and the events come off
// the telemetry hook every bot already calls (telemetry_event(), bot_telemetry.dm).

/// How many events each bot keeps for the monitor
#define BOT_MONITOR_EVENTS 8

/datum/bot_brain
	/// The monitor's last few events: list(world.time, kind, text)
	var/list/monitor_events

/datum/bot_brain/telemetry_event(kind, list/fields)
	. = ..()
	var/text = bot_monitor_event_text(kind, fields)
	if(!text)
		return
	LAZYADD(monitor_events, list(list(world.time, kind, text)))
	if(length(monitor_events) > BOT_MONITOR_EVENTS)
		monitor_events.Cut(1, 2)

/// What an event says on the monitor, or null for the ones too small to show (pickups, drags, clicks)
/proc/bot_monitor_event_text(kind, list/fields)
	switch(kind)
		if("goal_start")
			return "Started [fields?["goal"]][fields?["target"] ? " on [fields["target"]]" : ""]"
		if("goal_end")
			var/result = fields?["result"]
			var/static/list/results = list("success" = "Finished", "gave_up" = "Gave up on", "dropped" = "Dropped")
			return "[results[result] || "Ended"] [fields?["goal"]]"
		if("pursuit")
			return "Took up [fields?["pursuit"]][fields?["why"] ? " ([fields["why"]])" : ""]"
		if("ui_action")
			return "Worked [fields?["machine"]] ([fields?["action"]])"
		if("use")
			return "Used [fields?["item"] || "something"][fields?["target"] ? " on [fields["target"]]" : ""]"
		if("internals")
			return "Internals [fields?["on"] ? "on" : "off"]"
		if("manifest", "download", "mule", "struggle")
			return capitalize(kind)
	return null

/// One a client, kept on the client (no mob held, so a ghost that goes away isn't kept)
/datum/bot_crew_monitor

/datum/bot_crew_monitor/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, \
									datum/tgui/master_ui = null, datum/ui_state/state = GLOB.always_state)
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "bot_crew_monitor", "Bot Crew", 960, 640, master_ui, state)
		ui.open()

/// Ghosts and admins, whatever body an admin is in
/datum/bot_crew_monitor/ui_status(mob/user, datum/ui_state/state)
	if(!user.client || user.client.bot_crew_monitor != src)
		return UI_CLOSE
	if(isobserver(user) || user.client.holder)
		return UI_INTERACTIVE
	return UI_CLOSE

/datum/bot_crew_monitor/ui_data(mob/user)
	var/admin = !!user.client?.holder
	var/list/bots = list()
	for(var/datum/bot_brain/B in GLOB.bot_brains)
		var/mob/living/carbon/human/H = B.owner
		if(QDELETED(H))
			continue
		var/status = "Alive"
		if(H.stat == DEAD)
			status = "Dead"
		else if(H.stat != CONSCIOUS)
			status = "Down"
		var/list/bot = list(
			"ref" = REF(B),
			"name" = H.real_name,
			"job" = B.work_role() || "-",
			"state" = B.state,
			"doing" = H.stat == DEAD ? null : B.describe_activity(),
			"goal" = B.current_goal ? bot_telemetry_short(B.current_goal.type) : null,
			"step" = B.current_strategy && B.current_step_index ? bot_telemetry_short(B.current_strategy.steps[min(B.current_step_index, length(B.current_strategy.steps))]?.type) : null,
			"health" = round(max(0, H.health / H.maxHealth) * 100),
			"status" = status,
			"area" = get_area_name(H, TRUE),
			"style" = B.playstyle,
		)
		if(admin)
			var/list/antags = list()
			for(var/datum/antagonist/A in H.mind?.antag_datums)
				antags += A.name
			bot["antag"] = antags.Join(", ")
		var/list/events = list()
		for(var/i in length(B.monitor_events) to 1 step -1)
			var/list/event = B.monitor_events[i]
			events += list(list(
				"ago" = round((world.time - event[1]) / 10),
				"kind" = event[2],
				"text" = event[3],
			))
		bot["events"] = events
		bots += list(bot)
	return list("bots" = bots, "admin" = admin)

/datum/bot_crew_monitor/ui_act(action, list/params)
	if(..())
		return TRUE
	if(action == "follow")
		var/datum/bot_brain/B = locate(params["ref"]) in GLOB.bot_brains
		if(!B || QDELETED(B.owner))
			return
		var/mob/dead/observer/ghost = usr
		if(istype(ghost))
			ghost.ManualFollow(B.owner)
		else if(usr.client?.holder)
			usr.client.jumptomob(B.owner)
		return TRUE

/client
	var/datum/bot_crew_monitor/bot_crew_monitor

/mob/dead/observer/verb/bot_crew()
	set category = "Ghost"
	set name = "Bot Crew"
	set desc = "What every bot crewmember is doing"
	if(!client)
		return
	if(!client.bot_crew_monitor)
		client.bot_crew_monitor = new
	client.bot_crew_monitor.ui_interact(src)

#undef BOT_MONITOR_EVENTS
