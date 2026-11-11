/*
 * The stat panel: tg's HTML stat browser (tgstation master ceb0ca2410d4b2bbade05f61a661ebdd684c0e79) in place of BYOND's own
 * info control, which called every mob's Stat() about five times a second for every player whatever was on it. Here the
 * Status, MC, Tickets and tile tabs are sent by SSstatpanels at their own pace, verbs when they change.
 *
 * The page is html/statbrowser.html with its script and styles put inside it at server start, so it fetches nothing: on 516 a
 * file a page asks for while it's still arriving can go unanswered for good (see the chat's loader in browserOutput.html).
 */

/// The page, built once: html/statbrowser.html with statbrowser.css and statbrowser.js inside it
GLOBAL_VAR(stat_panel_page)

/proc/stat_panel_page()
	if(!GLOB.stat_panel_page)
		var/page = file2text('html/statbrowser.html')
		page = replacetext(page, "/*STATBROWSER_CSS*/", file2text('html/statbrowser.css'))
		page = replacetext(page, "/*STATBROWSER_JS*/", file2text('html/statbrowser.js'))
		GLOB.stat_panel_page = page
	return GLOB.stat_panel_page

/datum/stat_panel
	var/client/owner
	/// The page has said it's up
	var/ready = FALSE
	/// What was sent before it was
	var/list/waiting
	/// The tab the player has open
	var/tab = "Status"
	/// Whether the page has the admin tabs
	var/admin_tabs = FALSE
	/// Whether the page has an alt-clicked tile's tab
	var/turf_shown = FALSE
	/// The verbs last sent, to tell when they change
	var/list/sent_verbs
	/// What was last sent of these, to send again only when it changes
	var/sent_spells
	var/sent_extra
	/// Things the page lists that it may click, ref -> TRUE, each list made afresh with what it's for: the tile's contents,
	/// spells and abilities, and the admin tabs' ticket and query links
	var/list/clickable_turf = list()
	var/list/clickable_spells = list()
	var/list/clickable_admin = list()
	/// When it was last loaded, for the retry
	var/loaded_at = 0
	/// The subsystem (type, as text) whose row is open on the MC tab: its history goes with each update
	var/mc_detail

/datum/stat_panel/New(client/C)
	owner = C

/datum/stat_panel/proc/initialize()
	ready = FALSE
	waiting = list()
	admin_tabs = FALSE
	turf_shown = FALSE
	sent_verbs = null
	sent_spells = null
	sent_extra = null
	mc_detail = null
	loaded_at = world.time
	owner << browse(stat_panel_page(), "window=statbrowser")

/datum/stat_panel/proc/is_ready()
	return ready

/// One message to the page: a type its script subscribes to, and anything json can carry
/datum/stat_panel/proc/send_message(type, payload)
	var/message = url_encode(url_encode(json_encode(list("type" = type, "payload" = payload)))) // twice: UTF-8 comes through
	if(!ready)
		if(length(waiting) < 50)
			waiting += message
		return
	owner << output(message, "statbrowser:byondMessage")

/datum/stat_panel/proc/on_ready()
	ready = TRUE
	for(var/message in waiting)
		owner << output(message, "statbrowser:byondMessage")
	waiting = null
	send_message("set_theme", owner.dark_theme ? "dark" : "light")
	if(owner.prefs?.last_stat_tab)
		send_message("restore_tab", owner.prefs.last_stat_tab)
	owner.init_verbs()
	SSstatpanels.immediate_send_stat_data(owner)

/// From the page: ?_src_=statpanel&type=...&payload=json
/datum/stat_panel/proc/on_message(type, list/payload)
	switch(type)
		if("ready")
			on_ready()
		if("Update-Verbs")
			owner.init_verbs()
		if("Set-Tab")
			if(istext(payload?["tab"]))
				tab = copytext(payload["tab"], 1, 100)
				SSstatpanels.immediate_send_stat_data(owner)
				if(payload["picked"]) // the player clicked it: kept across rounds (game_menu.dm)
					owner.remember_stat_tab(tab)
		if("MC-Detail") // a row opened or closed on the MC tab
			if(owner.holder)
				mc_detail = istext(payload?["type"]) && length(payload["type"]) ? copytext(payload["type"], 1, 200) : null
				if(tab == "MC")
					SSstatpanels.set_MC_tab(owner)

/// A click on something the page lists, as if on the map. Only what it was sent for this player.
/datum/stat_panel/proc/item_click(atom/target, list/href_list)
	if(!istype(target))
		return
	var/ref = REF(target)
	if(!clickable_turf[ref] && !clickable_spells[ref] && !clickable_admin[ref])
		return
	var/list/params = list()
	switch(href_list["statpanel_item_click"])
		if("left")
			params["left"] = "1"
		if("right")
			params["right"] = "1"
		if("middle")
			params["middle"] = "1"
		else
			return
	if(href_list["statpanel_item_shiftclick"])
		params["shift"] = "1"
	if(href_list["statpanel_item_ctrlclick"])
		params["ctrl"] = "1"
	if(href_list["statpanel_item_altclick"])
		params["alt"] = "1"
	owner.Click(target, target.loc, null, list2params(params))

/// The alt-clicked tile's tab, opened now
/datum/stat_panel/proc/show_turf(turf/T)
	turf_shown = TRUE
	send_message("create_listedturf", T.name)
	tab = T.name
	SSstatpanels.set_turf_tab(owner)

/client
	var/datum/stat_panel/stat_panel

/// Every verb this player has, by tab, to the page
/client/proc/init_verbs()
	if(!stat_panel)
		return
	var/list/procs = stat_panel_verbs()
	stat_panel.sent_verbs = procs
	var/list/verblist = list()
	var/list/panel_tabs = list()
	for(var/procpath/verb_to_init as anything in procs)
		panel_tabs |= verb_to_init.category
		verblist[++verblist.len] = list(verb_to_init.category, verb_to_init.name)
	stat_panel.send_message("init_verbs", list("panel_tabs" = panel_tabs, "verblist" = verblist))

/// The verbs the panel shows, the way the old panel found them: the client's, the mob's and those of what the mob holds
/client/proc/stat_panel_verbs()
	var/list/all = verbs.Copy()
	if(mob)
		all += mob.verbs
		for(var/atom/movable/thing as anything in mob.contents)
			all += thing.verbs
	. = list()
	for(var/procpath/verb_to_init as anything in all)
		if(!verb_to_init || verb_to_init.hidden || !istext(verb_to_init.category) || !length(verb_to_init.category))
			continue
		. += verb_to_init

/client/verb/fix_stat_panel()
	set name = "Fix-Stat-Panel"
	set hidden = TRUE
	if(!stat_panel)
		return
	if(!stat_panel.is_ready() && world.time - stat_panel.loaded_at > 5 SECONDS)
		stat_panel.initialize()
		return
	init_verbs()

/client/verb/reload_stat_panel()
	set name = "Reload Stat Panel"
	set category = "OOC"
	set desc = "Loads the status and verbs panel again, if it's stuck or blank"
	stat_panel?.initialize()

/// Starts the panel at login, and loads it again if it hasn't said it's up in 10 s
/client/proc/start_stat_panel()
	stat_panel = new(src)
	stat_panel.initialize()
	addtimer(CALLBACK(src, PROC_REF(check_stat_panel_loaded), 1), 10 SECONDS)

/client/proc/check_stat_panel_loaded(attempt)
	if(!stat_panel || stat_panel.is_ready())
		return
	if(attempt >= 3)
		to_chat(src, "<span class='userdanger'>The stat panel didn't load. Use Reload Stat Panel in the OOC tab, or <a href='?_src_=statpanel;type=reload'>click here</a>.</span>")
		return
	stat_panel.initialize()
	addtimer(CALLBACK(src, PROC_REF(check_stat_panel_loaded), attempt + 1), 10 SECONDS)

/// Topic() for ?_src_=statpanel (the page's messages) and for a click on something the page lists
/client/proc/stat_panel_topic(list/href_list, hsrc)
	if(!stat_panel)
		return FALSE
	if(href_list["_src_"] == "statpanel")
		if(href_list["type"] == "reload")
			stat_panel.initialize()
			return TRUE
		var/list/payload
		if(href_list["payload"])
			try
				payload = json_decode(href_list["payload"])
			catch
				return TRUE
		stat_panel.on_message(href_list["type"], payload)
		return TRUE
	if(href_list["statpanel_item_click"] && hsrc)
		stat_panel.item_click(hsrc, href_list)
		return TRUE
	return FALSE

/// What a mob shows under the round's lines in the Status tab: text, "Label: value" for two columns, "" for a gap
/mob/proc/get_status_tab_items()
	return list()

/// Text tabs some gear adds (SpiderOS, Crynet Nanosuit): tab name -> its lines, as Status's
/mob/proc/get_stat_panel_extra_tabs()
	return null

/// Spells and abilities for the panel, each list(panel, charge text, name, ref)
/mob/proc/get_stat_panel_spells(list/clickables)
	. = list()
	if(mind)
		add_spells_to_stat_panel(mind.spell_list, ., clickables)
	add_spells_to_stat_panel(mob_spell_list, ., clickables)

/mob/proc/add_spells_to_stat_panel(list/spells, list/out, list/clickables)
	for(var/obj/effect/proc_holder/spell/S in spells)
		if(!S.can_be_cast_by(src))
			continue
		var/charge
		switch(S.charge_type)
			if("recharge")
				charge = "[S.charge_counter/10.0]/[S.charge_max/10]"
			if("charges")
				charge = "[S.charge_counter]/[S.charge_max]"
			if("holdervar")
				charge = "[S.holder_var_type] [S.holder_var_amount]"
		out[++out.len] = list("[S.panel]", charge, S.name, REF(S))
		clickables[REF(S)] = TRUE

/mob/living/get_stat_panel_spells(list/clickables)
	var/list/out = ..()
	for(var/obj/effect/proc_holder/A in abilities)
		out[++out.len] = list("[A.panel]", A.get_panel_text(), A.name, REF(A))
		clickables[REF(A)] = TRUE
	return out
