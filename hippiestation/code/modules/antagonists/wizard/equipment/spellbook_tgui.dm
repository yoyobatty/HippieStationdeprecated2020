// The spellbook in tgui (interfaces/Spellbook.js): the same entries, points and tabs as the old page. Learning, refunding and
// turning the page still go through the book's Topic(), which bot wizards call directly (bots_ai/goals/wizard.dm); it ends by
// calling attack_self(), which now brings the window up to date.

/obj/item/spellbook/attack_self(mob/user)
	if(!owner)
		to_chat(user, "<span class='notice'>You bind the spellbook to yourself.</span>")
		owner = user
		return
	if(user != owner)
		to_chat(user, "<span class='warning'>The [name] does not recognize you as its owner and refuses to open!</span>")
		return
	user.set_machine(src)
	ui_interact(user)

/obj/item/spellbook/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, datum/tgui/master_ui = null, datum/ui_state/state = GLOB.default_state)
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "spellbook", name, 720, 640, master_ui, state)
		ui.open()

/obj/item/spellbook/ui_data(mob/user)
	var/list/data = list()
	data["points"] = uses
	data["tab"] = tab
	data["owner"] = "[owner]"
	var/list/tabs = list()
	for(var/category in categories)
		tabs += list(list("name" = category, "header" = replacetext(GetCategoryHeader(category), "<BR>", " ")))
	data["categories"] = tabs
	var/list/spells_known = list()
	if(user?.mind)
		for(var/obj/effect/proc_holder/spell/known in user.mind.spell_list)
			spells_known[initial(known.name)] = known
	var/list/out = list()
	for(var/i in 1 to length(entries))
		var/datum/spellbook_entry/E = entries[i]
		var/list/entry = list(
			"index" = i,
			"name" = E.name,
			"category" = E.category,
			"cost" = E.cost,
			"buy_word" = E.buy_word,
			"limit" = E.limit,
			"can_buy" = ishuman(user) ? E.CanBuy(user, src) : FALSE,
			"can_refund" = ishuman(user) ? E.CanRefund(user, src) : FALSE,
		)
		if(istype(E, /datum/spellbook_entry/item))
			entry["kind"] = "item"
			entry["desc"] = E.desc
			if(E.surplus >= 0)
				entry["left"] = E.surplus
		else if(istype(E, /datum/spellbook_entry/summon))
			var/datum/spellbook_entry/summon/R = E
			entry["kind"] = "ritual"
			entry["desc"] = E.desc
			entry["active"] = R.active
		else if(E.spell_type)
			if(!E.S)
				E.S = new E.spell_type()
			var/obj/effect/proc_holder/spell/S = E.S
			entry["kind"] = "spell"
			entry["name"] = initial(S.name)
			entry["desc"] = "[S.desc][E.desc]"
			if(S.charge_type == "recharge")
				entry["cooldown"] = S.charge_max / 10
			entry["garb"] = S.clothes_req ? TRUE : FALSE
			entry["staff"] = S.staff_req ? TRUE : FALSE //hippie: some spells need a staff
			entry["level_max"] = S.level_max
			var/obj/effect/proc_holder/spell/known = spells_known[initial(S.name)]
			if(known)
				entry["known"] = TRUE
				entry["level"] = known.spell_level
				entry["known_name"] = known.name
				if(known.charge_type == "recharge")
					entry["cooldown"] = known.charge_max / 10
		out += list(entry)
	data["entries"] = out
	return data

/obj/item/spellbook/ui_act(action, list/params)
	if(..())
		return
	switch(action)
		if("buy")
			Topic(null, list("buy" = "[text2num(params["index"])]"))
			return TRUE
		if("refund")
			Topic(null, list("refund" = "[text2num(params["index"])]"))
			return TRUE
		if("page")
			if(params["tab"] in categories)
				tab = params["tab"]
			return TRUE
