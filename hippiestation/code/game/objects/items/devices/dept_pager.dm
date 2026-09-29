// Department pager: a head of staff pages their department. Every PDA whose owner works there triple-beeps and shows the
// page - who sent it, what it says, and where they were standing - with an Acknowledge link, which tells whoever holds
// the pager who's answering and from where. Pages travel as PDA messages (see /obj/item/pda/proc/receive_page()), so they
// need the message server up, just like the man-down beacon's alerts.

/// How long a pager takes to recharge between pages
#define PAGER_COOLDOWN (15 SECONDS)
/// How long after a page it can still be acknowledged
#define PAGER_ACK_WINDOW (5 MINUTES)
/// The longest custom page
#define PAGER_MAX_LENGTH 120

/obj/item/dept_pager
	name = "command pager"
	desc = "A pager that sends an urgent message, and where you are, to the PDA of everyone in a department. They can acknowledge it so you know who's coming."
	icon = 'hippiestation/icons/obj/dept_gear.dmi'
	icon_state = "pager-cmd"
	item_state = "radio"
	lefthand_file = 'icons/mob/inhands/misc/devices_lefthand.dmi'
	righthand_file = 'icons/mob/inhands/misc/devices_righthand.dmi'
	w_class = WEIGHT_CLASS_SMALL
	slot_flags = ITEM_SLOT_BELT
	flags_1 = CONDUCT_1
	materials = list(MAT_METAL = 100, MAT_GLASS = 50)
	/// Who it pages, as the page shows it
	var/department = "Command"
	/// Crew monitor department codes (GLOB.crewmonitor.jobs, by tens: 10 security, 20 medical...) of the jobs it pages
	var/list/department_codes = list()
	/// Job titles it pages as well
	var/list/department_jobs = list()
	/// When it last paged, for the cooldown and the acknowledgement window
	var/last_page = -PAGER_COOLDOWN
	/// Counts up with each page, so an old page's Acknowledge links stop working
	var/page_id = 0
	/// What the last page said, for examine
	var/last_message
	/// "Name (Job)" of each PDA sent the last page
	var/list/last_recipients = list()
	/// "Name (Job), from <area>" of everyone who acknowledged the last page
	var/list/acknowledged = list()

/obj/item/dept_pager/engineering
	name = "engineering pager"
	icon_state = "pager-eng"
	department = "Engineering"
	department_codes = list(40)

/obj/item/dept_pager/medical
	name = "medical pager"
	icon_state = "pager-med"
	department = "Medical"
	department_codes = list(20)

/obj/item/dept_pager/science
	name = "science pager"
	icon_state = "pager-sci"
	department = "Science"
	department_codes = list(30)

/obj/item/dept_pager/security
	name = "security pager"
	icon_state = "pager-sec"
	department = "Security"
	department_codes = list(10)

/obj/item/dept_pager/supply
	name = "supply pager"
	icon_state = "pager-sup"
	department = "Supply"
	department_codes = list(50)

/obj/item/dept_pager/service
	name = "service pager"
	icon_state = "pager-srv"
	department = "Service"
	department_codes = list(60)

/obj/item/dept_pager/command/Initialize()
	. = ..()
	department_jobs = GLOB.command_positions.Copy()

/obj/item/dept_pager/examine(mob/user)
	. = ..()
	. += "<span class='notice'>It pages the [department] department.</span>"
	if(last_message)
		. += "<span class='notice'>Last page: \"[last_message]\", sent to [length(last_recipients)] PDA\s.</span>"
		if(length(acknowledged))
			. += "<span class='notice'>Acknowledged by [english_list(acknowledged)].</span>"
		else
			. += "<span class='notice'>Nobody has acknowledged it.</span>"

/// Whether a PDA's owner works in the department this pages
/obj/item/dept_pager/proc/pages_job(job)
	if(job in department_jobs)
		return TRUE
	var/code = GLOB.crewmonitor.jobs[job]
	if(isnull(code))
		return FALSE
	return (code - (code % 10)) in department_codes

/obj/item/dept_pager/attack_self(mob/user)
	if(world.time < last_page + PAGER_COOLDOWN)
		to_chat(user, "<span class='warning'>[src] is still recharging.</span>")
		return
	var/where = get_area_name(user, TRUE)
	var/list/presets = list(
		"Report to my location" = "Report to [where].",
		"Return to the department" = "All [department] staff: return to your department.",
		"Emergency, all hands" = "EMERGENCY: all [department] staff to [where], now!",
		"Custom message..." = null)
	var/choice = input(user, "Page the [department] department:", name) as null|anything in presets
	if(!choice)
		return
	var/message = presets[choice]
	if(!message)
		message = stripped_input(user, "Page message (your location is sent with it):", name, "", PAGER_MAX_LENGTH)
	if(!message || !user.canUseTopic(src, BE_CLOSE))
		return
	send_page(user, message)

/obj/item/dept_pager/proc/send_page(mob/living/user, message)
	if(world.time < last_page + PAGER_COOLDOWN)
		to_chat(user, "<span class='warning'>[src] is still recharging.</span>")
		return FALSE
	var/where = get_area_name(user, TRUE)
	var/obj/item/card/id/id_card = user.get_idcard(TRUE)
	var/sender_name = id_card?.registered_name || user.name
	var/sender_job = id_card?.assignment || "Unknown"

	var/list/targets = list()
	for(var/obj/item/pda/P in GLOB.PDAs)
		if(!P.owner || !P.ownjob || P.owner == sender_name || !pages_job(P.ownjob))
			continue
		targets += "[P.owner] ([P.ownjob])"
	if(!length(targets))
		to_chat(user, "<span class='warning'>[src] finds nobody in [department] with a PDA to page.</span>")
		return

	var/datum/signal/subspace/messaging/pda/signal = new(src, list(
		"name" = sender_name,
		"job" = sender_job,
		"message" = message,
		"targets" = targets,
		"page" = TRUE,
		"page_department" = department,
		"page_location" = where,
		"page_ref" = REF(src),
		"page_id" = page_id + 1
	))
	signal.send_to_receivers()
	if(!signal.data["done"])
		to_chat(user, "<span class='warning'>[src] beeps: no response from the messaging server.</span>")
		playsound(src, 'sound/machines/twobeep.ogg', 30, TRUE)
		return

	page_id++
	last_page = world.time
	last_message = message
	last_recipients = targets
	acknowledged = list()
	playsound(src, 'sound/machines/terminal_prompt_confirm.ogg', 30, TRUE)
	to_chat(user, "<span class='notice'>You page [department] ([length(targets)] PDA\s): \"[message]\"</span>")
	user.log_talk(message, LOG_PDA, tag = "department page to [department]")
	var/ghost_message = "<span class='name'>[sender_name] </span><span class='game say'>paged [department]</span>: <span class='message'>\"[message]\"</span> ([where])"
	for(var/mob/M in GLOB.player_list)
		if(isobserver(M) && M.client && (M.client.prefs.chat_toggles & CHAT_GHOSTPDA))
			to_chat(M, "[FOLLOW_LINK(M, user)] [ghost_message]")

/obj/item/dept_pager/Topic(href, href_list)
	. = ..()
	if(!href_list["ack"])
		return
	var/mob/living/responder = usr
	if(!istype(responder) || responder.stat)
		return
	var/obj/item/pda/P = locate(href_list["pda"]) in GLOB.PDAs
	if(!P || !(P in responder.GetAllContents())) // you answer on the PDA you're carrying
		return
	if(text2num(href_list["ack"]) != page_id || world.time > last_page + PAGER_ACK_WINDOW)
		to_chat(responder, "<span class='warning'>That page is no longer active.</span>")
		return
	var/entry = "[P.owner] ([P.ownjob]), from [get_area_name(responder, TRUE)]"
	for(var/existing in acknowledged)
		if(findtext(existing, "[P.owner] ([P.ownjob])") == 1)
			return
	acknowledged += entry
	to_chat(responder, "<span class='notice'>You acknowledge the page.</span>")
	playsound(src, 'sound/machines/twobeep.ogg', 40, TRUE)
	var/mob/living/holder = get(src, /mob/living)
	if(holder)
		to_chat(holder, "<span class='notice'>[icon2html(src, holder)] [entry] acknowledged your page.</span>")

/// A page from a department pager: louder than a message, with where the sender was and a link to acknowledge it
/obj/item/pda/proc/receive_page(datum/signal/subspace/messaging/pda/signal)
	var/sender = "[signal.data["name"]] ([signal.data["job"]])"
	tnote += "<i><b>&larr; PAGE to [signal.data["page_department"]] from [sender], at [signal.data["page_location"]]:</b></i><br>[signal.format_message()]<br>"
	if(!silent)
		playsound(src, 'sound/machines/triple_beep.ogg', 60, TRUE)
		audible_message("[icon2html(src, hearers(src))] *PAGE*", null, 4)
	var/mob/living/L = get(src, /mob/living)
	if(L && L.stat != UNCONSCIOUS)
		to_chat(L, "<span class='boldnotice'>[icon2html(src, L)] PAGE to [signal.data["page_department"]] from [sender]: [signal.format_message()]</span> <span class='notice'>(at [signal.data["page_location"]])</span> <a href='byond://?src=[signal.data["page_ref"]];ack=[signal.data["page_id"]];pda=[REF(src)]'>Acknowledge</a>")
	update_icon()
	add_overlay(icon_alert)

// A closer look (examine it twice): how to use it
/obj/item/dept_pager/examine_more(mob/user)
	. = ..()
	. += "<span class='notice'>Use it in hand to page the [department] department: pick a preset or write your own message. Your location goes with the page.</span>"
	. += "<span class='notice'>Everyone in the department gets it on their PDA, with a link to acknowledge it, and the pager shows who acknowledged. It needs the message server running, and takes [DisplayTimeText(PAGER_COOLDOWN)] to recharge between pages.</span>"


#undef PAGER_COOLDOWN
#undef PAGER_ACK_WINDOW
#undef PAGER_MAX_LENGTH
