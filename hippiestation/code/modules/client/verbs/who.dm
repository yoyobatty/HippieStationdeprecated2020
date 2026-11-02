/client/verb/mentorwho()
	set category = "Mentor"
	set name = "Mentorwho"
	var/msg = "<b>Current Mentors:</b>\n"
	for(var/X in GLOB.mentors)
		var/client/C = X
		if(!C)
			GLOB.mentors -= C
			continue // weird runtime that happens randomly
		var/suffix = ""
		if(holder)
			if(isobserver(C.mob))
				suffix += " - Observing"
			else if(istype(C.mob,/mob/dead/new_player))
				suffix += " - Lobby"
			else
				suffix += " - Playing"

			if(C.is_afk())
				suffix += " (AFK)"
		msg += "\t[C][suffix]\n"
	to_chat(src, msg)

/client/verb/who()
	set name = "Who"
	set category = "OOC"

	to_chat(src, who_list())

/client/proc/who_list()
	var/msg = ""

	var/list/Lines = list()
	if(length(GLOB.admins))
		Lines += "<b>Admins:</b>"
		for(var/X in GLOB.admins)
			var/client/C = X
			if(C && C.holder && !C.holder.fakekey)
				Lines += "\t <font color='#FF0000'>[C.key] ([C.holder.rank])</font>[show_admin_info(C)] ([round(C.avgping, 1)]ms)"
	if(length(GLOB.mentors))
		Lines += "<b>Mentors:</b>"
		for(var/X in GLOB.mentors)
			var/client/C = X
			if(C)
				Lines += "\t <font color='#0033CC'>[C.key]</font>[show_admin_info(C)] ([round(C.avgping, 1)]ms)"

	Lines += "<b>Players:</b>"
	var/list/players = list()
	for(var/X in GLOB.clients)
		var/client/C = X
		if(!C) continue
		var/key = C.key
		if(C.holder && C.holder.fakekey)
			key = C.holder.fakekey
		players += "\t [key][show_admin_info(C)] ([round(C.avgping, 1)]ms)"
	// The bot crew are on the list with everyone else. Admins get told which they are.
	for(var/mob/living/carbon/human/H as anything in GLOB.bot_crew_members)
		if(H.mind?.bot_handle)
			players += "\t [H.mind.bot_handle][show_bot_info(H)] ([H.mind.bot_ping + rand(-4, 4)]ms)"
	Lines += sortList(players)

	for(var/line in Lines)
		msg += "[line]\n"

	msg += "<b>Total Players: [length(players)]</b>"
	return msg

/client/proc/show_bot_info(mob/living/carbon/human/H)
	if(!check_rights_for(src, R_ADMIN))
		return ""
	return " <i>(bot)</i>[show_mob_info(H)]"

/client/proc/show_admin_info(var/client/C)
	if(!C)
		return ""

	if(!check_rights_for(src, R_ADMIN))
		return ""

	var/entry = ""
	if(C.holder && C.holder.fakekey)
		entry += " <i>(as [C.holder.fakekey])</i>"
	return entry + show_mob_info(C.mob)

/client/proc/show_mob_info(mob/M)
	var/entry = ""
	if (isnewplayer(M))
		entry += " - <font color='darkgray'><b>In Lobby</b></font>"
	else
		entry += " - Playing as [M.real_name]"
		switch(M.stat)
			if(UNCONSCIOUS)
				entry += " - <font color='darkgray'><b>Unconscious</b></font>"
			if(DEAD)
				if(isobserver(M))
					var/mob/dead/observer/O = M
					if(O.started_as_observer)
						entry += " - <font color='gray'>Observing</font>"
					else
						entry += " - <font color='black'><b>DEAD</b></font>"
				else
					entry += " - <font color='black'><b>DEAD</b></font>"
		if(is_special_character(M))
			entry += " - <b><font color='red'>Antagonist</font></b>"
	entry += " (<A HREF='?_src_=holder;[HrefToken()];adminmoreinfo=\ref[M]'>?</A>)"
	return entry

/client/verb/adminwho()
	set category = "Admin"
	set name = "Adminwho"

	var/msg = "<b>Current Admins:</b>\n"
	if(check_rights_for(src, R_ADMIN))
		for(var/X in GLOB.admins)
			var/client/C = X
			if(!check_rights_for(C, R_ADMIN))
				continue
			msg += "\t[C] is a [C.holder.rank]"

			if(C.holder.fakekey)
				msg += " <i>(as [C.holder.fakekey])</i>"

			if(isobserver(C.mob))
				msg += " - Observing"
			else if(isnewplayer(C.mob))
				msg += " - Lobby"
			else
				msg += " - Playing"

			if(C.is_afk())
				msg += " (AFK)"
			msg += "\n"
	else
		for(var/X in GLOB.admins)
			var/client/C = X
			if(!check_rights_for(C, R_ADMIN))
				continue
			if(C.is_afk())
				continue //Don't show afk admins to adminwho
			if(!C.holder.fakekey)
				msg += "\t[C] is a [C.holder.rank]\n"
		msg += "<span class='info'>Adminhelps are also sent to Discord. If no admins are available in game adminhelp anyways and an admin on Discord will see it and respond.</span>"
	to_chat(src, msg)
