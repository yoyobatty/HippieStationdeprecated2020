/client/add_admin_verbs()
	. = ..()
	if (holder)
		var/rights = holder.rank.rights
		if(rights & R_SOUND)
			if(CONFIG_GET(flag/enable_tts))
				verbs += /client/proc/play_tts
		if(rights & R_ADMIN)
			verbs += GLOB.admin_verbs_economy
			verbs += /client/proc/cmd_search_logs // log_search.dm
			verbs += /client/proc/cmd_admin_find // admin_find.dm
			verbs += /client/proc/cmd_admin_notes // ban_window.dm
			verbs += /client/proc/cmd_tickets // tickets.dm
			verbs += /client/proc/cmd_admin_alerts // admin_alerts.dm
			verbs += /client/proc/cmd_player_profile // player_profile.dm

/client/remove_admin_verbs()
	. = ..()
	verbs.Remove(/client/proc/play_tts)
	verbs.Remove(GLOB.admin_verbs_economy)
	verbs.Remove(/client/proc/cmd_search_logs)
	verbs.Remove(/client/proc/cmd_admin_find)
	verbs.Remove(/client/proc/cmd_admin_notes)
	verbs.Remove(/client/proc/cmd_tickets)
	verbs.Remove(/client/proc/cmd_admin_alerts)
	verbs.Remove(/client/proc/cmd_player_profile)

/// Economy and research admin verbs (hippiestation/code/modules/admin/verbs/economy_verbs.dm)
GLOBAL_LIST_INIT(admin_verbs_economy, list(/client/proc/cmd_admin_give_money, /client/proc/cmd_admin_adjust_budget, /client/proc/cmd_admin_give_research_points))
