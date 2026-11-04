#define MAX_ADMINBANS_PER_ADMIN 1
#define MAX_ADMINBANS_PER_HEADMIN 3

//checks the client's ban cache, or SSbans' copy of the bans for someone who isn't connected, if ckey is banned from one or more roles
//doesn't return any details, use only for if statements. It never queries or sleeps, so it's safe to call from anywhere.
/proc/is_banned_from(player_ckey, roles)
	player_ckey = ckey(player_ckey) //some callers have a key
	if(!player_ckey)
		return FALSE
	var/list/check = list() //lowercased: the ghost spawners asked for "lavaland" and the panel bans "Lavaland"
	if(islist(roles))
		for(var/R in roles)
			check += lowertext(R)
	else
		check += lowertext(roles)
	var/is_admin = GLOB.admin_datums[player_ckey] || GLOB.deadmins[player_ckey]
	var/client/C = GLOB.directory[player_ckey]
	if(!C)
		return SSbans.role_banned(player_ckey, check, is_admin)
	if(isnull(C.ban_cache)) //login hasn't built it yet: from the copy for now, which needs no query
		var/list/cache = list()
		SSbans.add_to_cache(cache, player_ckey, is_admin, FALSE, C.computer_id)
		C.ban_cache = cache
	for(var/R in check)
		if(R in C.ban_cache)
			var/expire_rt = C.ban_cache[R]
			if(!expire_rt || expire_rt > world.realtime)
				return TRUE //they're banned from at least one role, no need to keep checking
	return FALSE

//checks DB ban table if a ckey, ip and/or cid is banned from a specific role
//returns an associative nested list of each matching row's ban id, bantime, ban round id, expiration time, ban duration, applies to admins, reason, key, ip, cid and banning admin's key in that order, or null if the query failed
/proc/is_banned_from_with_details(player_ckey, player_ip, player_cid, role)
	if(!player_ckey && !player_ip && !player_cid)
		return
	role = sanitizeSQL(role)
	var/list/where_list = list()
	if(player_ckey)
		player_ckey = sanitizeSQL(player_ckey)
		where_list += "ckey = '[player_ckey]'"
	if(player_ip)
		player_ip = sanitizeSQL(player_ip)
		where_list += "ip = INET_ATON('[player_ip]')"
	if(player_cid)
		player_cid = sanitizeSQL(player_cid)
		where_list += "computerid = '[player_cid]'"
	var/where = "([where_list.Join(" OR ")])"
	var/datum/DBQuery/query_check_ban = SSdbcore.NewQuery("SELECT id, bantime, round_id, expiration_time, TIMESTAMPDIFF(MINUTE, bantime, expiration_time), applies_to_admins, reason, IFNULL((SELECT byond_key FROM [format_table_name("player")] WHERE [format_table_name("player")].ckey = [format_table_name("ban")].ckey), ckey), INET_NTOA(ip), computerid, IFNULL((SELECT byond_key FROM [format_table_name("player")] WHERE [format_table_name("player")].ckey = [format_table_name("ban")].a_ckey), a_ckey) FROM [format_table_name("ban")] WHERE role = '[role]' AND [where] AND unbanned_datetime IS NULL AND (expiration_time IS NULL OR expiration_time > NOW()) ORDER BY bantime DESC")
	if(!query_check_ban.Execute())
		qdel(query_check_ban)
		return
	. = list()
	while(query_check_ban.NextRow())
		. += list(list("id" = query_check_ban.item[1], "bantime" = query_check_ban.item[2], "round_id" = query_check_ban.item[3], "expiration_time" = query_check_ban.item[4], "duration" = query_check_ban.item[5], "applies_to_admins" = query_check_ban.item[6], "reason" = query_check_ban.item[7], "key" = query_check_ban.item[8], "ip" = query_check_ban.item[9], "computerid" = query_check_ban.item[10], "admin_key" = query_check_ban.item[11]))
	qdel(query_check_ban)

//A client's role bans, on their key or the computer they're on, as role = the world.realtime it ends (0 for permanent): the
//database's when it answers, and the bans kept on this server that it hasn't got. Built at login and whenever one of their bans
//changes; until then is_banned_from() uses the copy.
/proc/build_ban_cache(client/C)
	if(!istype(C))
		return
	var/player_ckey = C.ckey
	var/player_cid = C.computer_id
	if(player_cid)
		SSbans.known_cids[player_ckey] = player_cid
	var/is_admin = GLOB.admin_datums[player_ckey] || GLOB.deadmins[player_ckey]
	var/list/cache = list()
	var/db_checked = CONFIG_GET(flag/sql_enabled) && SSdbcore.Connect() && SSbans.db_cache_rows(cache, player_ckey, player_cid, is_admin)
	SSbans.add_to_cache(cache, player_ckey, is_admin, db_checked, player_cid)
	if(!QDELETED(C))
		C.ban_cache = cache

//TRUE (and tells them) if this admin already has as many admin bans on as they're allowed; role bans made together count once
/datum/admins/proc/over_admin_ban_limit()
	var/admin_ckey = usr.client.ckey
	var/list/bantimes = list()
	var/db_checked = FALSE
	if(CONFIG_GET(flag/sql_enabled) && SSdbcore.Connect())
		var/datum/DBQuery/query_check_adminban_count = SSdbcore.NewQuery("SELECT DISTINCT bantime FROM [format_table_name("ban")] WHERE a_ckey = '[sanitizeSQL(admin_ckey)]' AND applies_to_admins = 1 AND unbanned_datetime IS NULL AND (expiration_time IS NULL OR expiration_time > NOW())")
		if(!query_check_adminban_count.warn_execute())
			qdel(query_check_adminban_count)
			return TRUE
		while(query_check_adminban_count.NextRow())
			bantimes[query_check_adminban_count.item[1]] = TRUE
		qdel(query_check_adminban_count)
		db_checked = TRUE
	for(var/bantime in SSbans.admin_ban_times(admin_ckey, local_only = db_checked))
		bantimes[bantime] = TRUE
	var/max_adminbans = MAX_ADMINBANS_PER_ADMIN
	if((rank.can_edit_rights & R_EVERYTHING) == R_EVERYTHING) //edit rights are a more effective way to check hierarchical rank since many non-headmins have R_PERMISSIONS now
		max_adminbans = MAX_ADMINBANS_PER_HEADMIN
	if(bantimes.len >= max_adminbans)
		to_chat(usr, "<span class='danger'>You've already logged [max_adminbans] admin ban(s) or more. Do not abuse this function!</span>", confidential=TRUE)
		return TRUE
	return FALSE

//The player's key, and their IP and CID from their last connection if asked for: from the database, or from their client if
//they're connected. Returns list(key, ip, cid), or null if the admin backed out.
/datum/admins/proc/ban_lookup_player(player_key, player_ip, player_cid, use_last_connection, ip_check, cid_check, action)
	var/player_ckey = ckey(player_key)
	var/seen = FALSE
	if(CONFIG_GET(flag/sql_enabled) && SSdbcore.Connect())
		var/datum/DBQuery/query_ban_get_player = SSdbcore.NewQuery("SELECT byond_key, INET_NTOA(ip), computerid FROM [format_table_name("player")] WHERE ckey = '[sanitizeSQL(player_ckey)]'")
		if(!query_ban_get_player.warn_execute())
			qdel(query_ban_get_player)
			return
		if(query_ban_get_player.NextRow())
			seen = TRUE
			player_key = query_ban_get_player.item[1]
			if(use_last_connection)
				if(ip_check)
					player_ip = query_ban_get_player.item[2]
				if(cid_check)
					player_cid = query_ban_get_player.item[3]
		qdel(query_ban_get_player)
	if(!seen)
		var/client/online = GLOB.directory[player_ckey]
		if(online)
			seen = TRUE
			player_key = online.key
			if(use_last_connection)
				if(ip_check)
					player_ip = online.address
				if(cid_check)
					player_cid = online.computer_id
	if(!seen)
		var/question
		if(CONFIG_GET(flag/sql_enabled))
			if(use_last_connection)
				question = "[player_key]/([player_ckey]) has not been seen before, unable to use IP and CID from last connection. Are you sure you want to [action] a ban for them?"
			else
				question = "[player_key]/([player_ckey]) has not been seen before, are you sure you want to [action] a ban for them?"
		else if(use_last_connection)
			question = "[player_key]/([player_ckey]) isn't connected, and with no database there's no record of their last IP and CID. Do you want to [action] the ban without them?"
		if(question && alert(usr, question, "Unknown key", "Yes", "No", "Cancel") != "Yes")
			return
	return list(player_key, player_ip, player_cid)

/datum/admins/proc/ban_panel(player_key, player_ip, player_cid, role, duration = 1440, applies_to_admins, reason, edit_id, page, admin_key)
	var/panel_height = 620
	if(edit_id)
		panel_height = 240
	var/datum/browser/panel = new(usr, "banpanel", "Banning Panel", 910, panel_height)
	panel.add_stylesheet("banpanelcss", 'html/admin/banpanel.css')
	if(usr.client.prefs.tgui_fancy) //some browsers (IE8) have trouble with unsupported css3 elements and DOM methods that break the panel's functionality, so we won't load those if a user is in no frills tgui mode since that's for similar compatability support
		panel.add_stylesheet("banpanelcss3", 'html/admin/banpanel_css3.css')
		panel.add_script("banpaneljs", 'html/admin/banpanel.js')
	var/list/output = list("<form method='get' action='?src=[REF(src)]'>[HrefTokenFormField()]")
	output += {"<input type='hidden' name='src' value='[REF(src)]'>
	<label class='inputlabel checkbox'>Key:
	<input type='checkbox' id='keycheck' name='keycheck' value='1'[player_key ? " checked": ""]>
	<div class='inputbox'></div></label>
	<input type='text' name='keytext' size='26' value='[player_key]'>
	<label class='inputlabel checkbox'>IP:
	<input type='checkbox' id='ipcheck' name='ipcheck' value='1'[isnull(duration) ? " checked" : ""]>
	<div class='inputbox'></div></label>
	<input type='text' name='iptext' size='18' value='[player_ip]'>
	<label class='inputlabel checkbox'>CID:
	<input type='checkbox' id='cidcheck' name='cidcheck' value='1' checked>
	<div class='inputbox'></div></label>
	<input type='text' name='cidtext' size='14' value='[player_cid]'>
	<br>
	<label class='inputlabel checkbox'>Use IP and CID from last connection of key
	<input type='checkbox' id='lastconn' name='lastconn' value='1' [(isnull(duration) && !player_ip) || (!player_cid) ? " checked": ""]>
	<div class='inputbox'></div></label>
	<label class='inputlabel checkbox'>Applies to Admins
	<input type='checkbox' id='applyadmins' name='applyadmins' value='1'[applies_to_admins ? " checked": ""]>
	<div class='inputbox'></div></label>
	<input type='submit' value='Submit'>
	<br>
	<div class='row'>
		<div class='column left'>
			Duration type
			<br>
			<label class='inputlabel radio'>Permanent
			<input type='radio' id='permanent' name='radioduration' value='permanent'[isnull(duration) ? " checked" : ""]>
			<div class='inputbox'></div></label>
			<br>
			<label class='inputlabel radio'>Temporary
			<input type='radio' id='temporary' name='radioduration' value='temporary'[duration ? " checked" : ""]>
			<div class='inputbox'></div></label>
			<input type='text' name='duration' size='7' value='[duration]'>
			<div class="select">
				<select name='intervaltype'>
					<option value='SECOND'>Seconds</option>
					<option value='MINUTE' selected>Minutes</option>
					<option value='HOUR'>Hours</option>
					<option value='DAY'>Days</option>
					<option value='WEEK'>Weeks</option>
					<option value='MONTH'>Months</option>
					<option value='YEAR'>Years</option>
				</select>
			</div>
		</div>
		<div class='column middle'>
			Ban type
			<br>
			<label class='inputlabel radio'>Server
			<input type='radio' id='server' name='radioban' value='server'[role == "Server" ? " checked" : ""][edit_id ? " disabled" : ""]>
			<div class='inputbox'></div></label>
			<br>
			<label class='inputlabel radio'>Role
			<input type='radio' id='role' name='radioban' value='role'[role == "Server" ? "" : " checked"][edit_id ? " disabled" : ""]>
			<div class='inputbox'></div></label>
			<br><small>With a CID, a role ban holds every key on that computer.</small>
		</div>
		<div class='column right'>
			Severity
			<br>
			<label class='inputlabel radio'>None
			<input type='radio' id='none' name='radioseverity' value='none'[edit_id ? " disabled" : ""]>
			<div class='inputbox'></div></label>
			<label class='inputlabel radio'>Medium
			<input type='radio' id='medium' name='radioseverity' value='medium'[edit_id ? " disabled" : ""]>
			<div class='inputbox'></div></label>
			<br>
			<label class='inputlabel radio'>Minor
			<input type='radio' id='minor' name='radioseverity' value='minor'[edit_id ? " disabled" : ""]>
			<div class='inputbox'></div></label>
			<label class='inputlabel radio'>High
			<input type='radio' id='high' name='radioseverity' value='high'[edit_id ? " disabled" : ""]>
			<div class='inputbox'></div></label>
		</div>
		<div class='column'>
			Reason
			<br>
			<textarea class='reason' name='reason'>[reason]</textarea>
		</div>
	</div>
	"}
	if(edit_id)
		output += {"<label class='inputlabel checkbox'>Mirror edits to matching bans
		<input type='checkbox' id='mirroredit' name='mirroredit' value='1'>
		<div class='inputbox'></div></label>
		<input type='hidden' name='editid' value='[edit_id]'>
		<input type='hidden' name='oldkey' value='[player_key]'>
		<input type='hidden' name='oldip' value='[player_ip]'>
		<input type='hidden' name='oldcid' value='[player_cid]'>
		<input type='hidden' name='oldapplies' value='[applies_to_admins]'>
		<input type='hidden' name='oldduration' value='[duration]'>
		<input type='hidden' name='oldreason' value='[reason]'>
		<input type='hidden' name='page' value='[page]'>
		<input type='hidden' name='adminkey' value='[admin_key]'>
		<br>
		When ticked, edits here will also affect bans created with matching ckey, IP, CID and time. Use this to edit all role bans which were made at the same time.
		"}
	else
		output += "<input type='hidden' name='roleban_delimiter' value='1'>"
		//there's not always a client to use the bancache of so to avoid many individual queries from using is_banned_form we'll build a cache to use here
		var/banned_from = list()
		if(player_key)
			var/player_ckey = ckey(player_key)
			if(CONFIG_GET(flag/sql_enabled) && SSdbcore.Connect())
				var/datum/DBQuery/query_get_banned_roles = SSdbcore.NewQuery("SELECT role FROM [format_table_name("ban")] WHERE ckey = '[sanitizeSQL(player_ckey)]' AND role <> 'server' AND unbanned_datetime IS NULL AND (expiration_time IS NULL OR expiration_time > NOW())")
				if(!query_get_banned_roles.warn_execute())
					qdel(query_get_banned_roles)
					return
				while(query_get_banned_roles.NextRow())
					banned_from += query_get_banned_roles.item[1]
				qdel(query_get_banned_roles)
			for(var/datum/ban_record/B in SSbans.matching(player_ckey))
				banned_from |= B.role
		var/break_counter = 0
		output += "<div class='row'><div class='column'><label class='rolegroup command'><input type='checkbox' name='Command' class='hidden' [usr.client.prefs.tgui_fancy ? " onClick='toggle_checkboxes(this, \"_dep\")'" : ""]>Command</label><div class='content'>"
		//all heads are listed twice so have a javascript call to toggle both their checkboxes when one is pressed
		//for simplicity this also includes the captain even though it doesn't do anything
		for(var/job in GLOB.command_positions)
			if(break_counter > 0 && (break_counter % 3 == 0))
				output += "<br>"
			output += {"<label class='inputlabel checkbox'>[job]
						<input type='checkbox' id='[job]_com' name='[job]' class='Command' value='1'[usr.client.prefs.tgui_fancy ? " onClick='toggle_head(this, \"_dep\")'" : ""]>
						<div class='inputbox[(job in banned_from) ? " banned" : ""]'></div></label>
			"}
			break_counter++
		output += "</div></div>"
		//standard departments all have identical handling
		var/list/job_lists = list("Security" = GLOB.security_positions,
							"Engineering" = GLOB.engineering_positions,
							"Medical" = GLOB.medical_positions,
							"Science" = GLOB.science_positions,
							"Supply" = GLOB.supply_positions)
		for(var/department in job_lists)
			//the first element is the department head so they need the same javascript call as above
			output += "<div class='column'><label class='rolegroup [ckey(department)]'><input type='checkbox' name='[department]' class='hidden' [usr.client.prefs.tgui_fancy ? " onClick='toggle_checkboxes(this, \"_com\")'" : ""]>[department]</label><div class='content'>"
			output += {"<label class='inputlabel checkbox'>[job_lists[department][1]]
						<input type='checkbox' id='[job_lists[department][1]]_dep' name='[job_lists[department][1]]' class='[department]' value='1'[usr.client.prefs.tgui_fancy ? " onClick='toggle_head(this, \"_com\")'" : ""]>
						<div class='inputbox[(job_lists[department][1] in banned_from) ? " banned" : ""]'></div></label>
			"}
			break_counter = 1
			for(var/job in job_lists[department] - job_lists[department][1]) //skip the first element since it's already been done
				if(break_counter % 3 == 0)
					output += "<br>"
				output += {"<label class='inputlabel checkbox'>[job]
							<input type='checkbox' name='[job]' class='[department]' value='1'>
							<div class='inputbox[(job in banned_from) ? " banned" : ""]'></div></label>
				"}
				break_counter++
			output += "</div></div>"
		//departments/groups that don't have command staff would throw a javascript error since there's no corresponding reference for toggle_head()
		var/list/headless_job_lists = list("Silicon" = GLOB.nonhuman_positions,
										"Abstract" = list("Appearance", "Emote", "OOC"))
		for(var/department in headless_job_lists)
			output += "<div class='column'><label class='rolegroup [ckey(department)]'><input type='checkbox' name='[department]' class='hidden' [usr.client.prefs.tgui_fancy ? " onClick='toggle_checkboxes(this, \"_com\")'" : ""]>[department]</label><div class='content'>"
			break_counter = 0
			for(var/job in headless_job_lists[department])
				if(break_counter > 0 && (break_counter % 3 == 0))
					output += "<br>"
				output += {"<label class='inputlabel checkbox'>[job]
							<input type='checkbox' name='[job]' class='[department]' value='1'>
							<div class='inputbox[(job in banned_from) ? " banned" : ""]'></div></label>
				"}
				break_counter++
			output += "</div></div>"
		var/list/long_job_lists = list("Civilian" = GLOB.civilian_positions,
									"Ghost and Other Roles" = list(ROLE_BRAINWASHED, ROLE_DEATHSQUAD, ROLE_DRONE, ROLE_LAVALAND, ROLE_MIND_TRANSFER, ROLE_PAI, ROLE_POSIBRAIN, ROLE_SENTIENCE, ROLE_HOLOPARASITE, ROLE_DEFECTIVE_CLONE, ROLE_SANTA, ROLE_MEESEEKS), // hippie -- add holopara bans
									"Antagonist Positions" = list(ROLE_ABDUCTOR, ROLE_ALIEN, ROLE_BLOB,
									ROLE_BROTHER, ROLE_CHANGELING, ROLE_CULTIST,
									ROLE_DEVIL, ROLE_INTERNAL_AFFAIRS, ROLE_MALF,
									ROLE_MONKEY, ROLE_NINJA, ROLE_OPERATIVE,
									ROLE_OVERTHROW, ROLE_REV, ROLE_REVENANT,
									ROLE_REV_HEAD, ROLE_SERVANT_OF_RATVAR, ROLE_SYNDICATE,
									ROLE_TRAITOR, ROLE_WIZARD, ROLE_OBSESSED, ROLE_HIVE,
									ROLE_VAMPIRE, ROLE_SHADOWLING, ROLE_GANG, ROLE_INFILTRATOR, ROLE_KOTD, //hippie's own antagonists: their checks were there, but nothing could ban from them
									CATBAN, CLUWNEBAN, CRABBAN)) //ROLE_REV_HEAD is excluded from this because rev jobbans are handled by ROLE_REV // Hippie edit -- Adds cluwne, crab, and cat bans
		for(var/department in long_job_lists)
			output += "<div class='column'><label class='rolegroup long [ckey(department)]'><input type='checkbox' name='[department]' class='hidden' [usr.client.prefs.tgui_fancy ? " onClick='toggle_checkboxes(this, \"_com\")'" : ""]>[department]</label><div class='content'>"
			break_counter = 0
			for(var/job in long_job_lists[department])
				if(break_counter > 0 && (break_counter % 10 == 0))
					output += "<br>"
				output += {"<label class='inputlabel checkbox'>[job]
							<input type='checkbox' name='[job]' class='[department]' value='1'>
							<div class='inputbox[(job in banned_from) ? " banned" : ""]'></div></label>
				"}
				break_counter++
			output += "</div></div>"
		output += "</div>"
	output += "</form>"
	panel.set_content(jointext(output, ""))
	panel.open()

/datum/admins/proc/ban_parse_href(list/href_list)
	if(!check_rights(R_BAN))
		return
	var/static/regex/ipv4 = new(@"^\d{1,3}(\.\d{1,3}){3}$")
	var/list/error_state = list()
	var/player_key
	var/ip_check = FALSE
	var/player_ip
	var/cid_check = FALSE
	var/player_cid
	var/use_last_connection = FALSE
	var/applies_to_admins = FALSE
	var/duration
	var/interval
	var/severity
	var/reason
	var/mirror_edit
	var/edit_id
	var/old_key
	var/old_ip
	var/old_cid
	var/old_applies
	var/page
	var/admin_key
	var/list/changes = list()
	var/list/roles_to_ban = list()
	if(href_list["keycheck"])
		player_key = href_list["keytext"]
		if(!player_key)
			error_state += "Key was ticked but none was provided."
	if(href_list["ipcheck"])
		ip_check = TRUE
	if(href_list["cidcheck"])
		cid_check = TRUE
	if(href_list["lastconn"])
		if(player_key)
			use_last_connection = TRUE
	else
		if(ip_check)
			player_ip = trim(href_list["iptext"])
			if(!player_ip && !use_last_connection)
				error_state += "IP was ticked but none was provided."
			else if(player_ip && !ipv4.Find(player_ip)) //a mistyped one would be stored as nothing and match no one
				error_state += "[player_ip] isn't an IP address."
		if(cid_check)
			player_cid = trim(href_list["cidtext"])
			if(!player_cid && !use_last_connection)
				error_state += "CID was ticked but none was provided."
	if(!use_last_connection && !player_ip && !player_cid && !player_key)
		error_state += "At least a key, IP or CID must be provided."
	if(use_last_connection && !ip_check && !cid_check)
		error_state += "Use last connection was ticked, but neither IP nor CID was."
	if(href_list["applyadmins"])
		applies_to_admins = TRUE
	switch(href_list["radioduration"])
		if("permanent")
			duration = null
		if("temporary")
			duration = href_list["duration"]
			interval = href_list["intervaltype"]
			if(!duration)
				error_state += "Temporary ban was selected but no duration was provided."
			else if(!(text2num(duration) > 0))
				error_state += "The duration has to be a number above 0."
		else
			error_state += "No duration was selected."
	reason = href_list["reason"]
	if(!reason)
		error_state += "No reason was provided."
	else if(length_char(reason) > BAN_REASON_MAX) //the database refuses anything longer
		error_state += "The reason is [length_char(reason)] characters long; the most it can be is [BAN_REASON_MAX]."
	if(href_list["editid"])
		edit_id = href_list["editid"]
		if(href_list["mirroredit"])
			mirror_edit = TRUE
		old_key = href_list["oldkey"]
		old_ip = href_list["oldip"]
		old_cid = href_list["oldcid"]
		page = href_list["page"]
		admin_key = href_list["adminkey"]
		if(player_key != old_key)
			changes += list("Key" = "[old_key] to [player_key]")
		if(player_ip != old_ip)
			changes += list("IP" = "[old_ip] to [player_ip]")
		if(player_cid != old_cid)
			changes += list("CID" = "[old_cid] to [player_cid]")
		old_applies = text2num(href_list["oldapplies"])
		if(applies_to_admins != old_applies)
			changes += list("Applies to admins" = "[old_applies] to [applies_to_admins]")
		if(duration != href_list["oldduration"])
			changes += list("Duration" = "[href_list["oldduration"]] MINUTE to [duration] [interval]")
		if(reason != href_list["oldreason"])
			changes += list("Reason" = "[href_list["oldreason"]]<br>to<br>[reason]")
		if(!changes.len)
			error_state += "No changes were detected."
	else
		severity = href_list["radioseverity"]
		if(!severity)
			error_state += "No severity was selected."
		switch(href_list["radioban"])
			if("server")
				roles_to_ban += "Server"
			if("role")
				href_list.Remove("Command", "Security", "Engineering", "Medical", "Science", "Supply", "Silicon", "Abstract", "Civilian", "Ghost and Other Roles", "Antagonist Positions") //remove the role banner hidden input values
				if(href_list[href_list.len] == "roleban_delimiter")
					error_state += "Role ban was selected but no roles to ban were selected."
				else
					var/delimiter_pos = href_list.Find("roleban_delimiter")
					href_list.Cut(1, delimiter_pos+1)//remove every list element before and including roleban_delimiter so we have a list of only the roles to ban
					for(var/key in href_list) //flatten into a list of only unique keys
						roles_to_ban |= key
			else
				error_state += "No ban type was selected."
	if(error_state.len)
		to_chat(usr, "<span class='danger'>Ban not [edit_id ? "edited" : "created"] because the following errors were present:\n[error_state.Join("\n")]</span>", confidential=TRUE)
		return
	if(edit_id)
		edit_ban(edit_id, player_key, ip_check, player_ip, cid_check, player_cid, use_last_connection, applies_to_admins, duration, interval, reason, mirror_edit, old_key, old_ip, old_cid, old_applies, page, admin_key, changes)
	else
		create_ban(player_key, ip_check, player_ip, cid_check, player_cid, use_last_connection, applies_to_admins, duration, interval, severity, reason, roles_to_ban)

/datum/admins/proc/create_ban(player_key, ip_check, player_ip, cid_check, player_cid, use_last_connection, applies_to_admins, duration, interval, severity, reason, list/roles_to_ban)
	if(!check_rights(R_BAN))
		return
	var/player_ckey = ckey(player_key)
	if(player_ckey)
		var/list/found = ban_lookup_player(player_key, player_ip, player_cid, use_last_connection, ip_check, cid_check, "create")
		if(!found)
			return
		player_key = found[1]
		player_ip = found[2]
		player_cid = found[3]
	if(applies_to_admins && over_admin_ban_limit())
		return
	duration = text2num(duration)
	if(!(interval in BAN_INTERVALS)) //it goes into the query unquoted, so escaping can't make it safe
		interval = "MINUTE"
	var/time_message = "[duration] [lowertext(interval)]" //no DisplayTimeText because our duration is of variable interval type
	if(duration > 1) //pluralize the interval if necessary
		time_message += "s"
	var/note_reason = "Banned from [roles_to_ban[1] == "Server" ? "the server" : " Roles: [roles_to_ban.Join(", ")]"] [isnull(duration) ? "permanently" : "for [time_message]"] - [reason]"
	var/list/clients_online = GLOB.clients.Copy()
	var/list/admins_online = list()
	for(var/client/C in clients_online)
		if(C.holder) //deadmins aren't included since they wouldn't show up on adminwho
			admins_online += C
	var/kn = key_name(usr)
	var/kna = key_name_admin(usr)
	//raw values: sanitizeSQL() gives nothing with no database, so they're escaped when they're written to it
	var/list/intervals = BAN_INTERVALS
	var/bantime = SQLtime()
	var/list/new_bans = list()
	for(var/role in roles_to_ban)
		var/datum/ban_record/B = new
		B.role = role
		B.ckey = player_ckey
		B.key = player_key
		B.ip = player_ip
		B.cid = player_cid
		B.bantime = bantime
		B.bantime_rt = world.realtime
		if(duration)
			B.amount = duration
			B.unit = interval
			B.expire_rt = world.realtime + duration * intervals[interval] * 10
		B.applies_to_admins = applies_to_admins
		B.reason = reason
		B.round_id = GLOB.round_id
		B.a_ckey = usr.client.ckey
		B.a_key = usr.client.key
		B.a_ip = usr.client.address
		B.a_cid = usr.client.computer_id
		B.who = clients_online.Join(", ")
		B.adminwho = admins_online.Join(", ")
		new_bans += B
	var/stored = SSbans.add_bans(new_bans)
	if(!stored)
		return
	if(stored == "local" && CONFIG_GET(flag/sql_enabled))
		to_chat(usr, "<span class='danger'>The database couldn't be reached. The ban is saved on this server and enforced here, and it goes to the database when the database is back.</span>", confidential=TRUE)
	var/target = ban_target_string(player_key, player_ip, player_cid)
	var/msg = "has created a [isnull(duration) ? "permanent" : "temporary [time_message]"] [applies_to_admins ? "admin " : ""][roles_to_ban[1] == "Server" ? "server ban" : "role ban from [roles_to_ban.len] roles"] for [target]."
	log_admin_private("[kn] [msg][roles_to_ban[1] == "Server" ? "" : " Roles: [roles_to_ban.Join(", ")]"] Reason: [reason]")
	message_admins("[kna] [msg][roles_to_ban[1] == "Server" ? "" : " Roles: [roles_to_ban.Join("\n")]"]\nReason: [reason]")
	if(applies_to_admins)
		send2irc("BAN ALERT","[kn] [msg]")
	if(player_ckey)
		if(stored == "database") //notes need the database
			create_message("note", player_ckey, usr.client.ckey, note_reason, null, null, 0, 0, null, 0, severity)
		hippie_on_jobban(get_mob_by_key(player_ckey), roles_to_ban) // hippie -- apply stuff like catify on jobban
	var/client/C = GLOB.directory[player_ckey]
	var/datum/admin_help/AH = admin_ticket_log(player_ckey, msg)
	var/appeal_url = "No ban appeal url set!"
	appeal_url = CONFIG_GET(string/banappeals)
	var/is_admin = FALSE
	if(C)
		build_ban_cache(C)
		to_chat(C, "<span class='boldannounce'>You have been [applies_to_admins ? "admin " : ""]banned by [usr.client.key] from [roles_to_ban[1] == "Server" ? "the server" : " Roles: [roles_to_ban.Join(", ")]"].\nReason: [reason]</span><br><span class='danger'>This ban is [isnull(duration) ? "permanent." : "temporary, it will be removed in [time_message]."] The round ID is [GLOB.round_id].</span><br><span class='danger'>To appeal this ban go to [appeal_url]</span>", confidential=TRUE)
		if(GLOB.admin_datums[C.ckey] || GLOB.deadmins[C.ckey])
			is_admin = TRUE
		if(roles_to_ban[1] == "Server" && (!is_admin || (is_admin && applies_to_admins)))
			qdel(C)
	if(roles_to_ban[1] == "Server" && AH)
		AH.Resolve()
	for(var/client/i in GLOB.clients - C)
		if((player_ip && i.address == player_ip) || (player_cid && i.computer_id == player_cid)) //a ban with no IP would otherwise match the host, whose address is null
			build_ban_cache(i)
			to_chat(i, "<span class='boldannounce'>You have been [applies_to_admins ? "admin " : ""]banned by [usr.client.key] from [roles_to_ban[1] == "Server" ? "the server" : " Roles: [roles_to_ban.Join(", ")]"].\nReason: [reason]</span><br><span class='danger'>This ban is [isnull(duration) ? "permanent." : "temporary, it will be removed in [time_message]."] The round ID is [GLOB.round_id].</span><br><span class='danger'>To appeal this ban go to [appeal_url]</span>", confidential=TRUE)
			if(GLOB.admin_datums[i.ckey] || GLOB.deadmins[i.ckey])
				is_admin = TRUE
			if(roles_to_ban[1] == "Server" && (!is_admin || (is_admin && applies_to_admins)))
				qdel(i)

/datum/admins/proc/unban_panel(player_key, admin_key, player_ip, player_cid, page = 0)
	if(!check_rights(R_BAN))
		return
	var/datum/browser/unban_panel = new(usr, "unbanpanel", "Unbanning Panel", 850, 600)
	unban_panel.add_stylesheet("unbanpanelcss", 'html/admin/unbanpanel.css')
	var/list/output = list("<div class='searchbar'>")
	output += {"<form method='get' action='?src=[REF(src)]'>[HrefTokenFormField()]
	<input type='hidden' name='src' value='[REF(src)]'>
	Key:<input type='text' name='searchunbankey' size='18' value='[player_key]'>
	Admin Key:<input type='text' name='searchunbanadminkey' size='18' value='[admin_key]'>
	IP:<input type='text' name='searchunbanip' size='12' value='[player_ip]'>
	CID:<input type='text' name='searchunbancid' size='10' value='[player_cid]'>
	<input type='submit' value='Search'>
	</form>
	</div>
	<div class='main'>
	"}
	if(player_key || admin_key || player_ip || player_cid)
		var/bansperpage = 10
		page = max(0, text2num(page) || 0)
		var/use_db = CONFIG_GET(flag/sql_enabled) && SSdbcore.Connect()
		if(CONFIG_GET(flag/sql_enabled) && !use_db)
			output += "<div class='banbox'><div class='header banned'>The database can't be reached. These are this server's copy of the bans: the database's active ones as they were last copied, and the ones made here.</div></div>"
		//bans made here that the database hasn't got yet are on every page, above its own
		var/list/unsent = list()
		for(var/datum/ban_record/B in SSbans.search(player_key, admin_key, player_ip, player_cid))
			if(use_db && !B.is_local())
				continue
			unsent += list(ban_row(B))
		var/list/rows = list()
		var/bancount = 0
		if(use_db)
			var/list/searchlist = list()
			if(player_key)
				searchlist += "ckey = '[sanitizeSQL(ckey(player_key))]'"
			if(admin_key)
				searchlist += "a_ckey = '[sanitizeSQL(ckey(admin_key))]'"
			if(player_ip)
				searchlist += "ip = INET_ATON('[sanitizeSQL(player_ip)]')"
			if(player_cid)
				searchlist += "computerid = '[sanitizeSQL(player_cid)]'"
			var/search = searchlist.Join(" AND ")
			var/datum/DBQuery/query_unban_count_bans = SSdbcore.NewQuery("SELECT COUNT(id) FROM [format_table_name("ban")] WHERE [search]")
			if(!query_unban_count_bans.warn_execute())
				qdel(query_unban_count_bans)
				return
			if(query_unban_count_bans.NextRow())
				bancount = text2num(query_unban_count_bans.item[1])
			qdel(query_unban_count_bans)
			var/limit = " LIMIT [bansperpage * page], [bansperpage]"
			var/datum/DBQuery/query_unban_search_bans = SSdbcore.NewQuery({"SELECT id, bantime, round_id, role, expiration_time, TIMESTAMPDIFF(MINUTE, bantime, expiration_time), IF(expiration_time < NOW(), 1, NULL), applies_to_admins, reason, IFNULL((SELECT byond_key FROM [format_table_name("player")] WHERE [format_table_name("player")].ckey = [format_table_name("ban")].ckey), ckey), INET_NTOA(ip), computerid, IFNULL((SELECT byond_key FROM [format_table_name("player")] WHERE [format_table_name("player")].ckey = [format_table_name("ban")].a_ckey), a_ckey), IF(edits IS NOT NULL, 1, NULL), unbanned_datetime, IFNULL((SELECT byond_key FROM [format_table_name("player")] WHERE [format_table_name("player")].ckey = [format_table_name("ban")].unbanned_ckey), unbanned_ckey), unbanned_round_id FROM [format_table_name("ban")] WHERE [search] ORDER BY id DESC[limit]"})
			if(!query_unban_search_bans.warn_execute())
				qdel(query_unban_search_bans)
				return
			while(query_unban_search_bans.NextRow())
				var/list/item = query_unban_search_bans.item
				//we don't cast duration as num because if the duration is large enough to be converted to scientific notation by byond then the + character gets lost when passed through href causing SQL to interpret '4.321e 007' as '4'
				rows += list(list("id" = item[1], "bantime" = item[2], "round_id" = item[3], "role" = item[4], "expiration_time" = item[5], "duration" = item[6], "expired" = item[7], "applies_to_admins" = text2num(item[8]), "reason" = item[9], "key" = item[10], "ip" = item[11], "cid" = item[12], "admin_key" = item[13], "edits" = item[14], "unban_datetime" = item[15], "unban_key" = item[16], "unban_round_id" = item[17]))
			qdel(query_unban_search_bans)
		else
			bancount = unsent.len
			var/first = bansperpage * page + 1
			if(first <= unsent.len)
				rows = unsent.Copy(first, min(unsent.len, first + bansperpage - 1) + 1)
			unsent = list()
		if(bancount > bansperpage)
			output += "<b>Page: </b>"
			var/pagecount = 1
			var/list/pagelist = list()
			while(bancount > 0)
				pagelist += "<a href='?_src_=holder;[HrefToken()];unbanpagecount=[pagecount - 1];unbankey=[player_key];unbanadminkey=[admin_key];unbanip=[player_ip];unbancid=[player_cid]'>[pagecount - 1 == page ? "<b>\[[pagecount]\]</b>" : "\[[pagecount]\]"]</a>"
				bancount -= bansperpage
				pagecount++
			output += pagelist.Join(" | ")
		for(var/list/row in unsent + rows)
			output += ban_row_html(row, page, player_key, admin_key, player_ip, player_cid)
		output += "</div>"
	unban_panel.set_content(jointext(output, ""))
	unban_panel.open()

//A ban kept on this server, in the shape of an unban panel row
/datum/admins/proc/ban_row(datum/ban_record/B)
	return list("id" = B.id, "bantime" = B.bantime, "round_id" = B.round_id, "role" = B.role, "expiration_time" = B.expiration_text(), "duration" = B.duration_minutes(), "expired" = (B.expire_rt && B.expire_rt <= world.realtime), "applies_to_admins" = B.applies_to_admins, "reason" = B.reason, "key" = B.key || B.ckey, "ip" = B.ip, "cid" = B.cid, "admin_key" = B.a_key || B.a_ckey, "edits" = B.edits, "unban_datetime" = B.unbanned_datetime, "unban_key" = B.unbanned_key || B.unbanned_ckey, "unban_round_id" = B.unbanned_round_id, "local" = B.is_local())

/datum/admins/proc/ban_row_html(list/row, page, search_key, search_admin_key, search_ip, search_cid)
	var/ban_id = row["id"]
	var/role = row["role"]
	var/duration = row["duration"]
	if(isnum(duration))
		duration = num2text(duration, 12) //it goes through an href, where 1.6e+07 would lose its +
	//who to tell about the unban, then the search to show again afterwards
	var/unban_href = "<a href='?_src_=holder;[HrefToken()];unbanid=[ban_id];unbankey=[row["key"]];unbanip=[row["ip"]];unbancid=[row["cid"]];unbanrole=[role];unbanpage=[page];unbansearchkey=[search_key];unbansearchadminkey=[search_admin_key];unbansearchip=[search_ip];unbansearchcid=[search_cid]'>Unban</a>"
	var/target = ban_target_string(row["key"], row["ip"], row["cid"])
	. = list("<div class='banbox'><div class='header [row["unban_datetime"] ? "unbanned" : "banned"]'><b>[target]</b>[row["applies_to_admins"] ? " <b>ADMIN</b>" : ""] banned by <b>[row["admin_key"]]</b> from <b>[role]</b> on <b>[row["bantime"]]</b> during round <b>#[row["round_id"]]</b>.<br>")
	if(row["local"] && CONFIG_GET(flag/sql_enabled))
		. += "<i>Made while the database was out of reach: enforced on this server, and not in the database yet.</i><br>"
	if(!row["expiration_time"])
		. += "<b>Permanent ban</b>."
	else
		. += "Duration of <b>[DisplayTimeText(text2num(duration) MINUTES)]</b>, <b>[row["expired"] ? "expired" : "expires"]</b> on <b>[row["expiration_time"]]</b>."
	if(row["unban_datetime"])
		. += "<br>Unbanned by <b>[row["unban_key"]]</b> on <b>[row["unban_datetime"]]</b> during round <b>#[row["unban_round_id"]]</b>."
	. += "</div><div class='container'><div class='reason'>[row["reason"]]</div><div class='edit'>"
	if(!row["expired"] && !row["unban_datetime"])
		. += "<a href='?_src_=holder;[HrefToken()];editbanid=[ban_id];editbankey=[row["key"]];editbanip=[row["ip"]];editbancid=[row["cid"]];editbanrole=[role];editbanduration=[duration];editbanadmins=[row["applies_to_admins"]];editbanreason=[url_encode(row["reason"])];editbanpage=[page];editbanadminkey=[row["admin_key"]]'>Edit</a><br>[unban_href]"
	if(row["edits"])
		. += "<br><a href='?_src_=holder;[HrefToken()];unbanlog=[ban_id]'>Edit log</a>"
	. += "</div></div></div>"
	return jointext(., "")

/datum/admins/proc/unban(ban_id, player_key, player_ip, player_cid, role, page, search_key, search_admin_key, search_ip, search_cid)
	if(!check_rights(R_BAN))
		return
	var/target = ban_target_string(player_key, player_ip, player_cid)
	if(alert(usr, "Please confirm unban of [target] from [role].", "Unban confirmation", "Yes", "No") == "No")
		return
	var/kn = key_name(usr)
	var/kna = key_name_admin(usr)
	var/result = SSbans.lift(ban_id, usr.client.ckey, usr.client.key, usr.client.address, usr.client.computer_id)
	if(!result)
		return
	if(result == "queued")
		to_chat(usr, "<span class='danger'>The database couldn't be reached. The ban is lifted on this server, and in the database when the database is back.</span>", confidential=TRUE)
	log_admin_private("[kn] has unbanned [target] from [role].")
	message_admins("[kna] has unbanned [target] from [role].")
	var/client/C = GLOB.directory[ckey(player_key)]
	if(C)
		build_ban_cache(C)
		to_chat(C, "<span class='boldannounce'>[usr.client.key] has removed a ban from [role] for your key.</span>", confidential=TRUE)
	for(var/client/i in GLOB.clients - C)
		if((player_ip && i.address == player_ip) || (player_cid && i.computer_id == player_cid))
			build_ban_cache(i)
			to_chat(i, "<span class='boldannounce'>[usr.client.key] has removed a ban from [role] for your IP or CID.</span>", confidential=TRUE)
	unban_panel(search_key, search_admin_key, search_ip, search_cid, page)

/datum/admins/proc/edit_ban(ban_id, player_key, ip_check, player_ip, cid_check, player_cid, use_last_connection, applies_to_admins, duration, interval, reason, mirror_edit, old_key, old_ip, old_cid, old_applies, page, admin_key, list/changes)
	if(!check_rights(R_BAN))
		return
	if(!SSbans.get(ban_id) && !text2num(ban_id))
		return
	var/player_ckey = ckey(player_key)
	if(player_ckey)
		var/list/found = ban_lookup_player(player_key, player_ip, player_cid, use_last_connection, ip_check, cid_check, "edit")
		if(!found)
			return
		player_key = found[1]
		player_ip = found[2]
		player_cid = found[3]
	if(applies_to_admins && (applies_to_admins != old_applies) && over_admin_ban_limit())
		return
	duration = text2num(duration)
	if(!(interval in BAN_INTERVALS))
		interval = "MINUTE"
	var/kn = key_name(usr)
	var/kna = key_name_admin(usr)
	var/list/changes_text= list()
	var/list/changes_keys = list()
	for(var/i in changes)
		changes_text += "[i]: [changes[i]]"
		changes_keys += i
	var/list/op = list("id" = "[ban_id]", "mirror" = text2num(mirror_edit), "old_ckey" = ckey(old_key), "old_ip" = old_ip, "old_cid" = old_cid, "amount" = duration, "unit" = duration ? interval : null, "applies_to_admins" = applies_to_admins, "reason" = reason, "ckey" = player_ckey, "key" = player_key, "ip" = player_ip, "cid" = player_cid, "edit_text" = "[usr.client.key] edited the following [jointext(changes_text, ", ")]<hr>")
	//a mirrored edit matches on the ban time, which the copy has, unless the ban was made elsewhere after it was last refreshed
	if(op["mirror"] && !SSbans.get(ban_id) && CONFIG_GET(flag/sql_enabled) && SSdbcore.Connect())
		var/datum/DBQuery/query_edit_ban_get_bantime = SSdbcore.NewQuery("SELECT bantime FROM [format_table_name("ban")] WHERE id = [text2num(ban_id)]")
		if(!query_edit_ban_get_bantime.warn_execute())
			qdel(query_edit_ban_get_bantime)
			return
		if(query_edit_ban_get_bantime.NextRow())
			op["bantime"] = query_edit_ban_get_bantime.item[1]
		qdel(query_edit_ban_get_bantime)
	var/result = SSbans.edit(op)
	if(!result)
		return
	if(result == "queued")
		to_chat(usr, "<span class='danger'>The database couldn't be reached. The ban is changed on this server, and in the database when the database is back.</span>", confidential=TRUE)
	var/changes_keys_text = jointext(changes_keys, ", ")
	log_admin_private("[kn] has edited the [changes_keys_text] of a ban for [old_key ? "[old_key]" : "[old_ip]-[old_cid]"].") //if a ban doesn't have a key it must have an ip and/or a cid to have reached this point normally
	message_admins("[kna] has edited the [changes_keys_text] of a ban for [old_key ? "[old_key]" : "[old_ip]-[old_cid]"].")
	if(changes["Applies to admins"])
		send2irc("BAN ALERT","[kn] has edited a ban for [old_key ? "[old_key]" : "[old_ip]-[old_cid]"] to [applies_to_admins ? "" : "not "]affect admins")
	var/client/C = GLOB.directory[ckey(old_key)]
	if(C)
		build_ban_cache(C)
		to_chat(C, "<span class='boldannounce'>[usr.client.key] has edited the [changes_keys_text] of a ban for your key.</span>", confidential=TRUE)
	for(var/client/i in GLOB.clients - C)
		if((old_ip && i.address == old_ip) || (old_cid && i.computer_id == old_cid))
			build_ban_cache(i)
			to_chat(i, "<span class='boldannounce'>[usr.client.key] has edited the [changes_keys_text] of a ban for your IP or CID.</span>", confidential=TRUE)
	unban_panel(player_key, null, null, null, page)

/datum/admins/proc/ban_log(ban_id)
	if(!check_rights(R_BAN))
		return
	var/edits
	var/datum/ban_record/B = SSbans.get(ban_id)
	if(B && (B.is_local() || !CONFIG_GET(flag/sql_enabled) || !SSdbcore.Connect()))
		edits = B.edits
	else
		var/db_id = text2num(ban_id)
		if(!db_id)
			return
		if(!SSdbcore.Connect())
			to_chat(usr, "<span class='danger'>Failed to establish database connection.</span>", confidential=TRUE)
			return
		var/datum/DBQuery/query_get_ban_edits = SSdbcore.NewQuery("SELECT edits FROM [format_table_name("ban")] WHERE id = [db_id]")
		if(!query_get_ban_edits.warn_execute())
			qdel(query_get_ban_edits)
			return
		if(query_get_ban_edits.NextRow())
			edits = query_get_ban_edits.item[1]
		qdel(query_get_ban_edits)
	if(edits)
		var/datum/browser/edit_log = new(usr, "baneditlog", "Ban edit log")
		edit_log.set_content(edits)
		edit_log.open()

/datum/admins/proc/ban_target_string(player_key, player_ip, player_cid)
	. = list()
	if(player_key)
		. += player_key
	else
		if(player_ip)
			. += player_ip
		else
			. += "NULL"
		if(player_cid)
			. += player_cid
		else
			. += "NULL"
	. = jointext(., "/")
