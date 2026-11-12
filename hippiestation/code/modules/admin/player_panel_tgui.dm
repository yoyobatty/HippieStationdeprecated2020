// hippie -- the admin player options panel (Show Player Panel; the hub's, tickets' and name menus' "PP") in tgui
// (interfaces/AdminPlayerPanel.js). Laid out in sections: who it is, the quick links, moderation and mutes, movement, transformation
// and the rest. Every button is the link the old page had, sent with the admin token to the admin holder's own Topic() (or the VV and
// PM links to theirs), so each action's rights checks and logs are the old ones. The panel only takes a link it showed that admin.

/datum/admins
	/// Player panels open, by the target mob's REF
	var/list/player_panels

/datum/admins/show_player_panel(mob/M in GLOB.mob_list)
	set category = "Admin"
	set name = "Show Player Panel"
	set desc = "Edit player (respawn, ban, heal, etc)"
	if(!check_rights())
		return
	if(!M)
		to_chat(usr, "<span class='warning'>You seem to be selecting a mob that doesn't exist anymore.</span>", confidential = TRUE)
		return
	log_admin("[key_name(usr)] checked the individual player panel for [key_name(M)][isobserver(usr) ? "" : " while in game"].")
	LAZYINITLIST(player_panels)
	var/datum/admin_player_panel/P = player_panels[REF(M)]
	if(!P || QDELETED(P))
		P = new(src, M)
		player_panels[REF(M)] = P
	P.ui_interact(usr)
	SStgui.update_uis(P)

/datum/admin_player_panel
	var/datum/admins/holder
	var/datum/weakref/target_ref
	var/target_ref_text
	/// The links last shown, by ckey
	var/list/shown = list()

/datum/admin_player_panel/New(datum/admins/H, mob/M)
	holder = H
	target_ref = WEAKREF(M)
	target_ref_text = REF(M)

/datum/admin_player_panel/Destroy()
	SStgui.close_uis(src)
	if(holder)
		LAZYREMOVE(holder.player_panels, target_ref_text)
	holder = null
	return ..()

/datum/admin_player_panel/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, datum/tgui/master_ui = null, datum/ui_state/state = GLOB.always_state)
	var/mob/M = target_ref?.resolve()
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "admin_player_panel", "Options for [M ? (M.key || M.name) : "?"]", 640, 720, master_ui, state)
		ui.open()

/datum/admin_player_panel/ui_status(mob/user, datum/ui_state/state)
	if(!user.client?.holder || user.client.holder != holder || !check_rights_for(user.client, R_ADMIN))
		return UI_CLOSE
	return UI_INTERACTIVE

/datum/admin_player_panel/ui_close(mob/user)
	if(!QDELETED(src)) // Destroy() closing the window lands here too
		qdel(src)

/// One button: "holder" links go to the admin holder's Topic(), "vv" opens View Variables, "pm" an admin PM
/datum/admin_player_panel/proc/pp_link(label, params, kind = "holder", list/extra)
	var/list/L = list("label" = label, "params" = params, "kind" = kind)
	if(extra)
		L += extra
	return L

/datum/admin_player_panel/ui_data(mob/user)
	var/mob/M = target_ref?.resolve()
	. = list()
	if(!M)
		.["gone"] = TRUE
		return
	var/ref = REF(M)
	.["name"] = M.name
	.["real_name"] = M.real_name
	.["key"] = M.key
	.["type"] = "[M.type]"
	.["newplayer"] = isnewplayer(M)
	.["dead"] = M.stat == DEAD
	.["job"] = M.mind?.assigned_role
	.["special_role"] = M.mind?.special_role
	var/list/sections = list()

	// Who it is
	var/list/who = list()
	if(M.client)
		var/client/C = M.client
		.["client"] = "[C]"
		.["rank"] = C.holder ? "[C.holder.rank]" : "Player"
		who += list(pp_link(.["rank"], "editrights=[(GLOB.admin_datums[C.ckey] || GLOB.deadmins[C.ckey]) ? "rank" : "add"];key=[M.key]", extra = list("icon" = "user-shield")))
		if(CONFIG_GET(flag/use_exp_tracking))
			who += list(pp_link("Playtime: [C.get_exp_living()]", "getplaytimewindow=[ref]", extra = list("icon" = "clock")))
		.["first_seen"] = C.player_join_date
		.["account_date"] = C.account_join_date
		.["country"] = C.country
		.["related"] = !!(C.related_accounts_cid || C.related_accounts_ip)
		who += list(pp_link("Related by CID", "showrelatedacc=cid;client=[REF(C)]", extra = list("icon" = "fingerprint")))
		who += list(pp_link("Related by IP", "showrelatedacc=ip;client=[REF(C)]", extra = list("icon" = "network-wired")))
		.["byond"] = C.byond_version ? "[C.byond_version].[C.byond_build ? C.byond_build : "xxx"]" : "Unknown"
		.["antag_rep"] = SSpersistence.antag_rep[M.ckey] || 0
		.["rep_links"] = list(pp_link("+", "modantagrep=add;mob=[ref]"), pp_link("-", "modantagrep=subtract;mob=[ref]"), \
			pp_link("Set", "modantagrep=set;mob=[ref]"), pp_link("Zero", "modantagrep=zero;mob=[ref]"))
	if(!isnewplayer(M))
		who += list(pp_link("Heal", "revive=[ref]", extra = list("icon" = "heart")))
	sections += list(list("name" = "Player", "links" = who))

	// Quick links
	var/list/quick = list(pp_link("VV", "Vars=[ref]", "vv", list("icon" = "code")))
	if(M.mind)
		quick += list(pp_link("Traitor panel", "traitor=[ref]", extra = list("icon" = "user-secret")))
	else
		quick += list(pp_link("Init mind", "initmind=[ref]", extra = list("icon" = "brain")))
	if(iscyborg(M))
		quick += list(pp_link("Borg panel", "borgpanel=[ref]", extra = list("icon" = "robot")))
	if(M.ckey)
		quick += list(pp_link("PM", "[M.ckey]", "pm", list("icon" = "comment")))
	quick += list(pp_link("Subtle message", "subtlemessage=[ref]", extra = list("icon" = "comment-dots")))
	if(ishuman(M) && M.mind)
		quick += list(pp_link("Headset message", "HeadsetMessage=[ref]", extra = list("icon" = "headset")))
	quick += list(pp_link("Narrate to", "narrateto=[ref]", extra = list("icon" = "scroll")))
	quick += list(pp_link("Follow", "adminplayerobservefollow=[ref]", extra = list("icon" = "eye")))
	quick += list(pp_link("Logs", "individuallog=[ref];log_src=[M.client ? LOGSRC_CLIENT : LOGSRC_MOB]", extra = list("icon" = "list")))
	quick += list(pp_link("Search logs", "searchlogs=[M.ckey || M.real_name || M.name]", extra = list("icon" = "search")))
	if(M.ckey)
		quick += list(pp_link("Profile", "playerprofile=[M.ckey]", extra = list("icon" = "id-card")))
	quick += list(pp_link("Language menu", "languagemenu=[ref]", extra = list("icon" = "language")))
	sections += list(list("name" = "Quick", "links" = quick))

	// Moderation
	var/list/mod = list(pp_link("Kick", "boot2=[ref]", extra = list("icon" = "door-open", "color" = "average")))
	if(M.client)
		mod += list(pp_link("Ban", "newbankey=[M.key];newbanip=[M.client.address];newbancid=[M.client.computer_id]", extra = list("icon" = "gavel", "color" = "bad")))
	else
		mod += list(pp_link("Ban", "newbankey=[M.key]", extra = list("icon" = "gavel", "color" = "bad")))
	mod += list(pp_link("Notes, messages, watchlist", "showmessageckey=[M.ckey]", extra = list("icon" = "sticky-note")))
	if(M.client)
		mod += list(pp_link("Prison", "sendtoprison=[ref]", extra = list("icon" = "dungeon")))
		mod += list(pp_link("Send back to lobby", "sendbacktolobby=[ref]", extra = list("icon" = "undo")))
	sections += list(list("name" = "Moderation", "links" = mod))

	// Mutes
	if(M.client)
		var/muted = M.client.prefs.muted
		var/list/mutes = list()
		for(var/list/kind in list(list("IC", MUTE_IC), list("OOC", MUTE_OOC), list("Pray", MUTE_PRAY), list("Adminhelp", MUTE_ADMINHELP), \
			list("Mentorhelp", MUTE_MENTOR), list("Deadchat", MUTE_DEADCHAT)))
			mutes += list(pp_link(kind[1], "mute=[M.ckey];mute_type=[kind[2]]", extra = list("on" = !!(muted & kind[2]))))
		mutes += list(pp_link("Toggle all", "mute=[M.ckey];mute_type=[MUTE_ALL]", extra = list("icon" = "volume-mute")))
		sections += list(list("name" = "Mute", "links" = mutes, "style" = "mutes"))

	// Movement
	sections += list(list("name" = "Movement", "links" = list(pp_link("Jump to", "jumpto=[ref]", extra = list("icon" = "location-arrow")), \
		pp_link("Get", "getmob=[ref]", extra = list("icon" = "magnet")), pp_link("Send to", "sendmob=[ref]", extra = list("icon" = "paper-plane")))))

	// Transformation
	if(M.client && !isnewplayer(M))
		var/list/transform = list()
		transform += list(ishuman(M) ? pp_link("Human", null, extra = list("current" = TRUE)) : pp_link("Humanize", "humanone=[ref]"))
		transform += list(ismonkey(M) ? pp_link("Monkeyized", null, extra = list("current" = TRUE)) : pp_link("Monkeyize", "monkeyone=[ref]"))
		transform += list(iscorgi(M) ? pp_link("Corgized", null, extra = list("current" = TRUE)) : pp_link("Corgize", "corgione=[ref]"))
		if(isAI(M))
			transform += list(pp_link("Is an AI", null, extra = list("current" = TRUE)))
		else if(ishuman(M))
			transform += list(pp_link("Make AI", "makeai=[ref]"), pp_link("Make robot", "makerobot=[ref]"), pp_link("Make alien", "makealien=[ref]"), \
				pp_link("Make slime", "makeslime=[ref]"), pp_link("Make blob", "makeblob=[ref]"))
		transform += list(pp_link(isanimal(M) ? "Re-animalize" : "Animalize", "makeanimal=[ref]"))
		sections += list(list("name" = "Transformation", "links" = transform))
		var/list/simple = list()
		for(var/list/kind in list(list("Observer", "observer"), list("Alien drone", "drone"), list("Alien hunter", "hunter"), list("Alien sentinel", "sentinel"), \
			list("Alien praetorian", "praetorian"), list("Alien queen", "queen"), list("Alien larva", "larva"), list("Human", "human"), list("Baby slime", "slime"), \
			list("Adult slime", "adultslime"), list("Monkey", "monkey"), list("Cyborg", "robot"), list("Cat", "cat"), list("Runtime", "runtime"), list("Corgi", "corgi"), \
			list("Ian", "ian"), list("Crab", "crab"), list("Coffee", "coffee"), list("Juggernaut", "constructarmored"), list("Artificer", "constructbuilder"), \
			list("Wraith", "constructwraith"), list("Shade", "shade")))
			simple += list(pp_link(kind[1], "simplemake=[kind[2]];mob=[ref]"))
		sections += list(list("name" = "Rudimentary transformation", "links" = simple, "note" = "Only makes the new mob type and copies things over; MMIs and the like aren't carried. Prefer the transformations above."))

	// The rest
	if(M.client)
		sections += list(list("name" = "Other", "links" = list(pp_link("Forcesay", "forcespeech=[ref]"), pp_link("Thunderdome 1", "tdome1=[ref]"), \
			pp_link("Thunderdome 2", "tdome2=[ref]"), pp_link("Thunderdome admin", "tdomeadmin=[ref]"), pp_link("Thunderdome observer", "tdomeobserve=[ref]"))))
		// HippiePPoptions()
		sections += list(list("name" = "Hippie", "links" = list(pp_link("Make mentor", "makementor=[M.ckey]"), pp_link("Remove mentor", "removementor=[M.ckey]"), \
			pp_link("Make donator", "makedonator=[M.ckey]"), pp_link("Remove donator", "removedonator=[M.ckey]"))))

	.["sections"] = sections
	var/list/links = list()
	for(var/list/section in sections)
		for(var/list/L in section["links"])
			if(L["params"])
				links += "[L["kind"]]|[L["params"]]"
	for(var/list/L in .["rep_links"])
		links += "[L["kind"]]|[L["params"]]"
	shown[user.ckey] = links

/datum/admin_player_panel/ui_act(action, list/params)
	if(..())
		return
	if(action != "link")
		return
	var/kind = "[params["kind"]]"
	var/wanted = "[params["params"]]"
	if(!("[kind]|[wanted]" in shown[usr.ckey]))
		return
	var/client/C = usr.client
	var/mob/M = target_ref?.resolve()
	switch(kind)
		if("vv")
			if(M)
				C.debug_variables(M)
		if("pm")
			C.cmd_admin_pm(wanted, null)
		if("holder")
			var/list/href_list = params2list(wanted)
			href_list["admin_token"] = RawHrefToken()
			C.holder.Topic(list2params(href_list), href_list)
	return TRUE
