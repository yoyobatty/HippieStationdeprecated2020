#define IRC_STATUS_THROTTLE 5

/datum/tgs_chat_command/validated/ircstatus // hippie -- linked admins only (hippiestation/code/modules/discord/chat_admin_check.dm)
	name = "status"
	help_text = "Gets the admincount, playercount, gamemode, and true game mode of the server"
	admin_only = TRUE
	required_rights = R_ADMIN // hippie
	var/last_irc_status = 0

/datum/tgs_chat_command/validated/ircstatus/Validated_Run(datum/tgs_chat_user/sender, params) // hippie
	var/rtod = REALTIMEOFDAY
	if(rtod - last_irc_status < IRC_STATUS_THROTTLE)
		return new /datum/tgs_message_content("Asked too recently, try again in a few seconds.") // hippie -- TGS DMAPI 7: null logs an error
	last_irc_status = rtod
	var/list/adm = get_admin_counts()
	var/list/allmins = adm["total"]
	var/status = "Admins: [allmins.len] (Active: [english_list(adm["present"])] AFK: [english_list(adm["afk"])] Stealth: [english_list(adm["stealth"])] Skipped: [english_list(adm["noflags"])]). "
	status += "Players: [GLOB.clients.len] (Active: [get_active_player_count(0,1,0)]). Mode: [SSticker.mode ? SSticker.mode.name : "Not started"]."
	return new /datum/tgs_message_content(status) // hippie -- TGS DMAPI 7 message datum

/datum/tgs_chat_command/irccheck
	name = "check"
	help_text = "Gets the playercount, gamemode, and address of the server"
	var/last_irc_check = 0

/datum/tgs_chat_command/irccheck/Run(datum/tgs_chat_user/sender, params)
	var/rtod = REALTIMEOFDAY
	if(rtod - last_irc_check < IRC_STATUS_THROTTLE)
		return new /datum/tgs_message_content("Asked too recently, try again in a few seconds.") // hippie -- TGS DMAPI 7: null logs an error
	last_irc_check = rtod
	var/server = CONFIG_GET(string/server)
	return new /datum/tgs_message_content("[GLOB.round_id ? "Round #[GLOB.round_id]: " : ""][GLOB.clients.len] players on [SSmapping.config.map_name], Mode: [GLOB.master_mode]; Round [SSticker.HasRoundStarted() ? (SSticker.IsRoundInProgress() ? "Active" : "Finishing") : "Starting"] -- [server ? server : "[world.internet_address]:[world.port]"]") // hippie -- TGS DMAPI 7 message datum

/datum/tgs_chat_command/validated/ahelp // hippie -- linked admins only
	name = "ahelp"
	help_text = "<ckey|ticket #> <message|ticket <close|resolve|icissue|reject|reopen <ticket #>|list>>"
	admin_only = TRUE
	required_rights = R_ADMIN // hippie

/datum/tgs_chat_command/validated/ahelp/Validated_Run(datum/tgs_chat_user/sender, params) // hippie
	var/list/all_params = splittext(params, " ")
	if(all_params.len < 2)
		return new /datum/tgs_message_content("Insufficient parameters") // hippie -- TGS DMAPI 7 message datum
	var/target = all_params[1]
	all_params.Cut(1, 2)
	var/id = text2num(target)
	if(id != null)
		var/datum/admin_help/AH = GLOB.ahelp_tickets.TicketByID(id)
		if(AH)
			target = AH.initiator_ckey
		else
			return new /datum/tgs_message_content("Ticket #[id] not found!") // hippie -- TGS DMAPI 7 message datum
	var/res = IrcPm(target, all_params.Join(" "), sender.friendly_name)
	return new /datum/tgs_message_content(res) // hippie -- TGS DMAPI 7: always answer (null logs an error)

/datum/tgs_chat_command/validated/namecheck // hippie -- linked admins only
	name = "namecheck"
	help_text = "Returns info on the specified target"
	admin_only = TRUE
	required_rights = R_ADMIN // hippie

/datum/tgs_chat_command/validated/namecheck/Validated_Run(datum/tgs_chat_user/sender, params) // hippie
	params = trim(params)
	if(!params)
		return new /datum/tgs_message_content("Insufficient parameters") // hippie -- TGS DMAPI 7 message datum
	log_admin("Chat Name Check: [sender.friendly_name] on [params]")
	message_admins("Name checking [params] from [sender.friendly_name]")
	return new /datum/tgs_message_content(keywords_lookup(params, 1)) // hippie -- TGS DMAPI 7 message datum

/datum/tgs_chat_command/validated/adminwho // hippie -- linked admins only (any rank)
	name = "adminwho"
	help_text = "Lists administrators currently on the server"
	admin_only = TRUE

/datum/tgs_chat_command/validated/adminwho/Validated_Run(datum/tgs_chat_user/sender, params) // hippie
	return new /datum/tgs_message_content(ircadminwho()) // hippie -- TGS DMAPI 7 message datum

GLOBAL_LIST(round_end_notifiees)

/datum/tgs_chat_command/endnotify
	name = "endnotify"
	help_text = "Pings the invoker when the round ends"
	admin_only = TRUE

/datum/tgs_chat_command/endnotify/Run(datum/tgs_chat_user/sender, params)
	if(!SSticker.IsRoundInProgress() && SSticker.HasRoundStarted())
		return new /datum/tgs_message_content("[sender.mention], the round has already ended!") // hippie -- TGS DMAPI 7 message datum
	LAZYINITLIST(GLOB.round_end_notifiees)
	GLOB.round_end_notifiees[sender.mention] = TRUE
	return new /datum/tgs_message_content("I will notify [sender.mention] when the round ends.") // hippie -- TGS DMAPI 7 message datum

/datum/tgs_chat_command/validated/sdql // hippie -- linked admins with +DEBUG only
	name = "sdql"
	help_text = "Runs an SDQL query"
	admin_only = TRUE
	required_rights = R_DEBUG // hippie

/datum/tgs_chat_command/validated/sdql/Validated_Run(datum/tgs_chat_user/sender, params) // hippie
	if(GLOB.AdminProcCaller)
		return new /datum/tgs_message_content("Unable to run query, another admin proc call is in progress. Try again later.") // hippie -- TGS DMAPI 7 message datum
	GLOB.AdminProcCaller = "CHAT_[sender.friendly_name]"	//_ won't show up in ckeys so it'll never match with a real admin
	var/list/results = world.SDQL2_query(params, GLOB.AdminProcCaller, GLOB.AdminProcCaller)
	GLOB.AdminProcCaller = null
	if(!results)
		return new /datum/tgs_message_content("Query produced no output") // hippie -- TGS DMAPI 7 message datum
	var/list/text_res = results.Copy(1, 3)
	var/list/refs = results.len > 3 ? results.Copy(4) : null
	return new /datum/tgs_message_content("[text_res.Join("\n")][refs ? "\nRefs: [refs.Join(" ")]" : ""]") // hippie -- TGS DMAPI 7 message datum
	
/datum/tgs_chat_command/reload_admins
	name = "reload_admins"
	help_text = "Forces the server to reload admins."
	admin_only = TRUE

/datum/tgs_chat_command/reload_admins/Run(datum/tgs_chat_user/sender, params)
	ReloadAsync()
	log_admin("[sender.friendly_name] reloaded admins via chat command.")
	return new /datum/tgs_message_content("Admins reloaded.") // hippie -- TGS DMAPI 7 message datum

/datum/tgs_chat_command/reload_admins/proc/ReloadAsync()
	set waitfor = FALSE
	load_admins()
