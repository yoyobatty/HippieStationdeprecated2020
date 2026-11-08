/client/proc/create_poll()
	set name = "Create Poll"
	set category = "Special Verbs"
	if(!check_rights(R_POLL))
		return
	if(!SSdbcore.Connect())
		to_chat(src, "<span class='danger'>Failed to establish database connection.</span>", confidential=TRUE)
		return
	var/polltype = tgui_input_list(usr, "Choose poll type.", "Poll Type", list("Single Option","Text Reply","Rating","Multiple Choice", "Instant Runoff Voting"))
	var/choice_amount = 0
	switch(polltype)
		if("Single Option")
			polltype = POLLTYPE_OPTION
		if("Text Reply")
			polltype = POLLTYPE_TEXT
		if("Rating")
			polltype = POLLTYPE_RATING
		if("Multiple Choice")
			polltype = POLLTYPE_MULTI
			choice_amount = tgui_input_number(usr, "How many choices should be allowed?", "Select choice amount")
			switch(choice_amount)
				if(0)
					to_chat(src, "Multiple choice poll must have at least one choice allowed.", confidential=TRUE)
					return
				if(1)
					polltype = POLLTYPE_OPTION
				if(null)
					return
		if ("Instant Runoff Voting")
			polltype = POLLTYPE_IRV
		else
			return 0
	var/starttime = SQLtime()
	var/endtime = tgui_input_text(usr, "Set end time for poll as format YYYY-MM-DD HH:MM:SS. All times in server time. HH:MM:SS is optional and 24-hour. Must be later than starting time for obvious reasons.", "Set end time", SQLtime(), allow_cancel = FALSE)
	if(!endtime)
		return
	endtime = sanitizeSQL(endtime)
	var/datum/DBQuery/query_validate_time = SSdbcore.NewQuery("SELECT IF(STR_TO_DATE('[endtime]','%Y-%c-%d %T') > NOW(), STR_TO_DATE('[endtime]','%Y-%c-%d %T'), 0)")
	if(!query_validate_time.warn_execute() || QDELETED(usr) || !src)
		qdel(query_validate_time)
		return
	if(query_validate_time.NextRow())
		var/checktime = text2num(query_validate_time.item[1])
		if(!checktime)
			to_chat(src, "Datetime entered is improperly formatted or not later than current server time.", confidential=TRUE)
			qdel(query_validate_time)
			return
		endtime = query_validate_time.item[1]
	qdel(query_validate_time)
	var/adminonly
	switch(tgui_alert(usr, "Admin only poll?", null, list("Yes", "No", "Cancel")))
		if("Yes")
			adminonly = 1
		if("No")
			adminonly = 0
		else
			return
	var/dontshow
	switch(tgui_alert(usr, "Hide poll results from tracking until completed?", null, list("Yes", "No", "Cancel")))
		if("Yes")
			dontshow = 1
		if("No")
			dontshow = 0
		else
			return
	var/sql_ckey = sanitizeSQL(ckey)
	var/question = tgui_input_text(usr, "Write your question", "Question", multiline = TRUE)
	if(!question)
		return
	if(length(question) > 255) //the column sizes, which strict mode refuses to overflow rather than cut
		to_chat(src, "The question can't be longer than 255 characters.", confidential=TRUE)
		return
	question = sanitizeSQL(question)
	var/list/sql_option_list = list()
	if(polltype != POLLTYPE_TEXT)
		var/add_option = 1
		while(add_option)
			var/option = tgui_input_text(usr, "Write your option", "Option", multiline = TRUE)
			if(!option)
				return
			if(length(option) > 255)
				to_chat(src, "An option can't be longer than 255 characters.", confidential=TRUE)
				continue
			option = sanitizeSQL(option)
			var/default_percentage_calc = 0
			if(polltype != POLLTYPE_IRV)
				switch(tgui_alert(usr, "Should this option be included by default when poll result percentages are generated?", null, list("Yes", "No", "Cancel")))
					if("Yes")
						default_percentage_calc = 1
					if("No")
						default_percentage_calc = 0
					else
						return
			var/minval = 0
			var/maxval = 0
			var/descmin = ""
			var/descmid = ""
			var/descmax = ""
			if(polltype == POLLTYPE_RATING)
				//left as numbers: escaped they were text, so "5" >= "10" refused a 5 to 10 scale and a minimum of 0 was a runtime
				minval = tgui_input_number(usr, "Set minimum rating value.", "Minimum rating")
				if(isnull(minval))
					return
				maxval = tgui_input_number(usr, "Set maximum rating value.", "Maximum rating")
				if(isnull(maxval))
					return
				if(minval >= maxval)
					to_chat(src, "Maximum rating value can't be less than or equal to minimum rating value", confidential=TRUE)
					continue
				descmin = tgui_input_text(usr, "Optional: Set description for minimum rating", "Minimum rating description", multiline = TRUE)
				if(descmin)
					descmin = sanitizeSQL(descmin)
				else if(descmin == null)
					return
				descmid = tgui_input_text(usr, "Optional: Set description for median rating", "Median rating description", multiline = TRUE)
				if(descmid)
					descmid = sanitizeSQL(descmid)
				else if(descmid == null)
					return
				descmax = tgui_input_text(usr, "Optional: Set description for maximum rating", "Maximum rating description", multiline = TRUE)
				if(descmax)
					descmax = sanitizeSQL(descmax)
				else if(descmax == null)
					return
				if(length(descmin) > 32 || length(descmid) > 32 || length(descmax) > 32)
					to_chat(src, "Rating descriptions can't be longer than 32 characters.", confidential=TRUE)
					continue
			sql_option_list += list(list("text" = "'[option]'", "minval" = "'[minval]'", "maxval" = "'[maxval]'", "descmin" = "'[descmin]'", "descmid" = "'[descmid]'", "descmax" = "'[descmax]'", "default_percentage_calc" = "'[default_percentage_calc]'"))
			switch(tgui_alert(usr, " ", null, list("Add option", "Finish", "Cancel")))
				if("Add option")
					add_option = 1
				if("Finish")
					add_option = 0
				else
					return 0
	var/m1 = "[key_name(usr)] has created a new server poll. Poll type: [polltype] - Admin Only: [adminonly ? "Yes" : "No"] - Question: [question]"
	var/m2 = "[key_name_admin(usr)] has created a new server poll. Poll type: [polltype] - Admin Only: [adminonly ? "Yes" : "No"]<br>Question: [question]"
	var/datum/DBQuery/query_polladd_question = SSdbcore.NewQuery("INSERT INTO [format_table_name("poll_question")] (polltype, starttime, endtime, question, adminonly, multiplechoiceoptions, createdby_ckey, createdby_ip, dontshow) VALUES ('[polltype]', '[starttime]', '[endtime]', '[question]', '[adminonly]', '[choice_amount]', '[sql_ckey]', INET_ATON('[address]'), '[dontshow]')")
	if(!query_polladd_question.warn_execute())
		qdel(query_polladd_question)
		return
	qdel(query_polladd_question)
	if(polltype != POLLTYPE_TEXT)
		var/pollid = 0
		var/datum/DBQuery/query_get_id = SSdbcore.NewQuery("SELECT LAST_INSERT_ID()")
		if(!query_get_id.warn_execute())
			qdel(query_get_id)
			return
		if(query_get_id.NextRow())
			pollid = query_get_id.item[1]
		qdel(query_get_id)
		for(var/list/i in sql_option_list)
			i |= list("pollid" = "'[pollid]'")
		SSdbcore.MassInsert(format_table_name("poll_option"), sql_option_list, warn = 1)
	log_admin(m1)
	message_admins(m2)
