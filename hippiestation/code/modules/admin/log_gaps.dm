// Things that weren't logged and should be, for admins investigating (Search Logs, log_search.dm). The ID console logged nothing
// (who gave whom what access, job changes, renames, job slots), so the card's access and names are compared before and after
// each use, which catches the window and the bot crew's own Topic() calls alike. APC channels switched off (a room's
// environment off is its air alarms and scrubbers off) weren't logged either. The user asked for log gaps closed, 2026-11-07.

/proc/log_gap_access_names(list/accesses)
	var/list/names = list()
	for(var/A in accesses)
		names += get_access_desc(A) || "access [A]"
	return english_list(names)

/// What changed on an ID card, and who changed it where
/obj/machinery/computer/card/proc/log_card_changes(mob/user, obj/item/card/id/card, list/had, old_job, old_name)
	if(!card || !had)
		return
	var/who = "[key_name(user)] at [src] ([AREACOORD(src)])"
	var/whose = "[old_name || card.registered_name || "an unnamed"]'s ID"
	var/list/gained = card.access - had
	var/list/lost = had - card.access
	if(gained.len)
		log_access("[who] gave [whose] [log_gap_access_names(gained)]")
	if(lost.len)
		log_access("[who] took [log_gap_access_names(lost)] off [whose]")
	if(card.assignment != old_job)
		log_access("[who] changed [whose] job from [old_job || "none"] to [card.assignment || "none"]")
	if(card.registered_name != old_name)
		log_access("[who] renamed [old_name || "an unnamed"]'s ID to [card.registered_name || "nothing"]")

/obj/machinery/computer/card/Topic(href, href_list)
	var/obj/item/card/id/card = modify
	var/list/had = card ? card.access.Copy() : null
	var/old_job = card?.assignment
	var/old_name = card?.registered_name
	. = ..()
	log_card_changes(usr, card, had, old_job, old_name)
	var/choice = href_list && href_list["choice"]
	if(choice in list("make_job_available", "make_job_unavailable", "prioritize_job"))
		log_access("[key_name(usr)] at [src] ([AREACOORD(src)]): [replacetext(choice, "_", " ")] [href_list["job"]]")

/obj/machinery/power/apc/ui_act(action, params)
	var/list/before = list("equipment" = equipment, "lighting" = lighting, "environment" = environ)
	. = ..()
	var/list/after = list("equipment" = equipment, "lighting" = lighting, "environment" = environ)
	var/static/list/setting_names = list("Off", "Auto (off)", "On", "Auto (on)")
	for(var/channel in before)
		if(before[channel] != after[channel])
			log_game("[key_name(usr)] set [src]'s [channel] from [setting_names[before[channel] + 1]] to [setting_names[after[channel] + 1]] in [AREACOORD(src)]")
	if(action == "overload" && usr?.has_unlimited_silicon_privilege)
		log_game("[key_name(usr)] overloaded the lights of [src] in [AREACOORD(src)]")

/// A cell timer started, stopped early (the prisoner let out) or its flash used: none of it was logged
/obj/machinery/door_timer/ui_act(action, params)
	var/was_timing = timing
	var/left = time_left()
	. = ..()
	switch(action)
		if("start")
			if(timing && !was_timing)
				log_game("[key_name(usr)] started [src] for [DisplayTimeText(time_left())] in [AREACOORD(src)]")
		if("stop")
			if(was_timing && !timing)
				log_game("[key_name(usr)] stopped [src] and opened the cell with [DisplayTimeText(left)] left in [AREACOORD(src)]")
		if("flash")
			log_game("[key_name(usr)] used [src]'s flash in [AREACOORD(src)]")
