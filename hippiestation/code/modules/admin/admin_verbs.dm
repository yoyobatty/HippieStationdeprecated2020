/client/add_admin_verbs()
	. = ..()
	if (holder)
		var/rights = holder.rank.rights
		if(rights & R_SOUND)
			if(CONFIG_GET(flag/enable_tts))
				verbs += /client/proc/play_tts
		if(rights & R_ADMIN)
			verbs += GLOB.admin_verbs_economy

/client/remove_admin_verbs()
	. = ..()
	verbs.Remove(/client/proc/play_tts)
	verbs.Remove(GLOB.admin_verbs_economy)

/// Economy and research admin verbs (hippiestation/code/modules/admin/verbs/economy_verbs.dm)
GLOBAL_LIST_INIT(admin_verbs_economy, list(/client/proc/cmd_admin_give_money, /client/proc/cmd_admin_adjust_budget, /client/proc/cmd_admin_give_research_points))
