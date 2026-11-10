// hippie -- The Bot Crew panel (interfaces/BotCrew.js): every bot crewmember in a row, with what it's doing and the last thing it gave
// up on and why; a row opens its personality, grudges, hands and last lines. Admin verb "Bot Crew" in the Admin tab.
//
// The lines: bot_log() only puts a line together when something keeps it (~hippie_defines/bots_ai.dm). While a panel is open
// (GLOB.bot_crew_panel_open), every bot keeps its last BOT_PANEL_LINES of them here, so they're there to read; closed, it costs nothing.

#define BOT_PANEL_LINES 40

GLOBAL_VAR_INIT(bot_crew_panel_open, FALSE)
GLOBAL_LIST_EMPTY(bot_crew_panels)

/datum/bot_brain
	/// Its last lines, kept while a Bot Crew panel is open: list("12:04:11 picked up the wrench", ...)
	var/list/panel_lines
	/// The last goal it gave up on, and the last thing it said before: text, and when
	var/last_gave_up
	var/last_gave_up_at = 0

/datum/bot_brain/proc/remember_line(msg)
	var/static/regex/jump_link = regex(@" ?\(<a [^>]*>JMP</a>\)", "g") //bot_coord()'s link, for admin chat: the panel has its own Jump
	LAZYADD(panel_lines, "[station_time_timestamp("hh:mm:ss")] [jump_link.Replace(msg, "")]")
	if(length(panel_lines) > BOT_PANEL_LINES)
		panel_lines.Cut(1, 2)

/// From give_up_goal() (bot_goals.dm). What it was after, and why if the log says (only kept while a panel is open) or the last
/// route that failed does.
/datum/bot_brain/proc/note_gave_up(datum/bot_goal/goal)
	if(!goal)
		return
	var/what = goal.doing || bot_telemetry_short(goal.type)
	if(goal.target && goal.target != owner)
		what += " ([goal.target])"
	var/why = length(panel_lines) ? copytext(panel_lines[length(panel_lines)], 10) : last_path_fail_reason
	last_gave_up = why ? "[what]: [why]" : what
	last_gave_up_at = world.time

/client/add_admin_verbs()
	. = ..()
	if(holder && check_rights_for(src, R_ADMIN))
		verbs += /client/proc/cmd_bot_crew

/client/remove_admin_verbs()
	. = ..()
	verbs.Remove(/client/proc/cmd_bot_crew)

/client/proc/cmd_bot_crew()
	set name = "Bot Crew"
	set category = "Admin"
	set desc = "Every bot crewmember: what it's doing, what it gave up on and why"
	if(!check_rights(R_ADMIN))
		return
	holder.open_admin_tool("bot_crew", /datum/admin_tool_window/bot_crew)

/datum/admin_tool_window/bot_crew
	interface = "bot_crew"
	title = "Bot Crew"
	width = 980
	height = 640
	/// The bot whose row is open, as a weakref
	var/datum/weakref/open_bot

/datum/admin_tool_window/bot_crew/ui_interact(mob/user, ui_key, datum/tgui/ui, force_open, datum/tgui/master_ui, datum/ui_state/state)
	. = ..()
	GLOB.bot_crew_panels |= src
	GLOB.bot_crew_panel_open = TRUE

/datum/admin_tool_window/bot_crew/Destroy()
	GLOB.bot_crew_panels -= src
	if(!length(GLOB.bot_crew_panels))
		GLOB.bot_crew_panel_open = FALSE
		for(var/mob/living/carbon/human/H as anything in GLOB.bot_crew_members)
			H.bot_brain?.panel_lines = null
	return ..()

/// The state words for a bot, as the panel shows them
/proc/bot_panel_state(mob/living/carbon/human/H)
	if(H.stat == DEAD)
		return "dead"
	if(H.stat != CONSCIOUS)
		return "down"
	var/datum/bot_brain/B = H.bot_brain
	if(!B)
		return "no brain"
	if(B.is_shut_in())
		return "shut in"
	return B.state

/datum/admin_tool_window/bot_crew/ui_data(mob/user)
	. = list()
	var/list/rows = list()
	var/mob/living/carbon/human/opened = open_bot?.resolve()
	for(var/mob/living/carbon/human/H as anything in GLOB.bot_crew_members)
		var/datum/bot_brain/B = H.bot_brain
		if(QDELETED(H))
			continue
		var/list/row = list(
			"ref" = REF(H),
			"name" = H.real_name,
			"job" = H.mind?.assigned_role || "-",
			"antag" = H.mind?.special_role,
			"style" = B ? B.playstyle : null,
			"hardened" = B?.hardened,
			"greytider" = B?.greytider,
			"state" = bot_panel_state(H),
			"area" = get_area_name(H, TRUE),
		)
		if(B)
			var/datum/bot_goal/G = B.current_goal
			if(G)
				row["goal"] = G.doing || bot_telemetry_short(G.type)
				if(B.current_strategy && B.current_step_index && B.current_step_index <= length(B.current_strategy.steps))
					row["step"] = bot_telemetry_short(B.current_strategy.steps[B.current_step_index]?.type)
				if(G.target && G.target != H)
					row["target"] = "[G.target]"
			else if(B.state == "combat" && B.attacker) //BOT_STATE_COMBAT, defined in bot_brain.dm after this file
				row["goal"] = "fighting [B.attacker]"
			if(B.last_gave_up)
				row["gave_up"] = B.last_gave_up
				row["gave_up_ago"] = round((world.time - B.last_gave_up_at) / 10)
		rows += list(row)
		if(H == opened && B)
			.["open"] = open_detail(H, B)
	.["bots"] = rows
	.["open_ref"] = opened ? REF(opened) : null

/datum/admin_tool_window/bot_crew/proc/open_detail(mob/living/carbon/human/H, datum/bot_brain/B)
	var/list/grudges = list()
	for(var/datum/weakref/W as anything in B.grudges)
		var/mob/living/L = W.resolve()
		var/points = L ? B.grudge_with(L) : 0
		if(points >= 0.5)
			grudges += list(list("name" = L.name, "points" = round(points, 0.1)))
	var/list/held = list()
	for(var/obj/item/I in H.held_items)
		held += "[I]"
	var/list/worn = list()
	for(var/obj/item/I in list(H.wear_suit, H.head, H.back, H.belt, H.wear_id))
		worn += "[I]"
	return list(
		"ref" = REF(H),
		"diligence" = B.diligence,
		"sociability" = B.sociability,
		"nerve" = B.nerve,
		"temper" = B.temper,
		"competence" = B.competence,
		"strictness" = B.strictness,
		"habits" = B.habits?.Copy() || list(),
		"grudges" = grudges,
		"held" = held,
		"worn" = worn,
		"health" = round(H.health),
		"suspended" = B.suspended_goal ? (B.suspended_goal.doing || bot_telemetry_short(B.suspended_goal.type)) : null,
		"lines" = B.panel_lines?.Copy() || list(),
	)

/datum/admin_tool_window/bot_crew/ui_act(action, list/params)
	if(..())
		return
	var/mob/living/carbon/human/H = locate(params["ref"]) in GLOB.bot_crew_members
	switch(action)
		if("open")
			open_bot = (H && open_bot?.resolve() != H) ? WEAKREF(H) : null
		if("flw")
			if(H)
				holder.page_holder_link(list("adminplayerobservefollow" = REF(H)))
		if("vv")
			if(H)
				usr.client.debug_variables(H)
		if("vv_brain")
			if(H?.bot_brain)
				usr.client.debug_variables(H.bot_brain)
		if("jmp")
			var/turf/T = H && get_turf(H)
			if(T)
				holder.page_holder_link(list("adminplayerobservecoodjump" = 1, "X" = T.x, "Y" = T.y, "Z" = T.z))
		if("pp")
			if(H)
				holder.page_holder_link(list("adminplayeropts" = REF(H)))
	return TRUE

#undef BOT_PANEL_LINES
