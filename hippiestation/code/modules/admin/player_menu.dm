// Every name is a link (the user's ruling, 2026-11-07, making the admin tools easier to get around): a player's name in any admin
// window (Tickets, Alerts, Player Profile, Search Logs, Find, Bans) opens the same small menu: Profile, PP, VV, FLW, PM, SM,
// Logs, Jump. The page (tgui-next common/PlayerLink.js) sends "player_menu" with what was picked and who: a ckey, a ref to the
// mob or thing, or both; each window's ui_act hands it here.

/// What the menu needs to know about someone, for a window's data
/proc/player_link(atom/movable/thing, player_ckey, name)
	var/mob/M = ismob(thing) ? thing : null
	return list(
		"ckey" = M?.ckey || player_ckey,
		"ref" = thing ? REF(thing) : null,
		"mob" = !!M,
		"name" = name || (M ? (M.real_name || M.name) : thing?.name) || player_ckey,
	)

/// A pick from a name's menu. TRUE if it was one (the window needn't redraw).
/proc/player_menu_act(mob/user, list/params)
	var/client/C = user?.client
	if(!C?.holder || !check_rights_for(C, R_ADMIN))
		return TRUE
	var/player_ckey = ckey(params["ckey"])
	var/atom/movable/thing
	if(params["ref"])
		thing = locate(params["ref"])
		if(!ismovable(thing))
			thing = null
	var/mob/M = ismob(thing) ? thing : (player_ckey ? mob_of_ckey(player_ckey) : null)
	if(!player_ckey && M?.ckey)
		player_ckey = M.ckey
	var/atom/movable/target = thing || M
	switch(params["what"])
		if("profile")
			if(player_ckey)
				C.open_player_profile(player_ckey)
		if("pp")
			if(M)
				C.holder.show_player_panel(M)
		if("vv")
			if(target)
				C.debug_variables(target)
		if("flw")
			if(target && (isobserver(user) || C.admin_ghost()))
				var/mob/dead/observer/ghost = C.mob
				ghost.ManualFollow(target)
		if("pm")
			var/client/them = GLOB.directory[player_ckey]
			if(them)
				C.cmd_admin_pm(them, null)
			else
				to_chat(C, "<span class='warning'>[player_ckey] isn't connected.</span>", confidential = TRUE)
		if("sm")
			if(M)
				C.cmd_admin_subtle_message(M)
		if("logs")
			C.open_log_search(player_ckey || target?.name)
		if("jmp")
			var/turf/T = get_turf(target)
			if(T)
				C.jumptocoord(T.x, T.y, T.z)
	if(!target && (params["what"] in list("pp", "vv", "flw", "sm", "jmp")))
		to_chat(C, "<span class='warning'>[player_ckey || "They"] [player_ckey ? "has" : "have"] no body in the round.</span>", confidential = TRUE)
	return TRUE
