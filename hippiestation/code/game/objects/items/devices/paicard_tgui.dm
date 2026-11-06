// The pAI card moved off its old HTML window (tgui-next PaiCard.js). Buttons run the card's own Topic(); the additional
// directive and the wipe's confirmation, pop-ups there, come from the window with the same checks.

/obj/item/paicard/attack_self(mob/user)
	if(!in_range(src, user))
		return
	user.set_machine(src)
	ui_interact(user)

/obj/item/paicard/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, \
							datum/tgui/master_ui = null, datum/ui_state/state = GLOB.default_state)
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "pai_card", "Personal AI Device", 440, 440, master_ui, state)
		ui.open()

/obj/item/paicard/ui_data(mob/user)
	var/list/data = list()
	if(!pai)
		data["pai"] = null
		return data
	var/is_master = FALSE
	if(ishuman(user))
		var/mob/living/carbon/human/H = user
		is_master = H.real_name == pai.master || H.dna.unique_enzymes == pai.master_dna
	data["pai"] = list(
		"name" = pai.name,
		"master" = pai.master,
		"has_master" = !!(pai.master_dna && pai.master),
		"zeroth" = pai.laws.zeroth,
		"supplied" = pai.laws.supplied,
		"radio" = !!pai.radio,
		"transmit" = pai.can_transmit,
		"receive" = pai.can_receive,
		"holo" = pai.canholo,
		"is_master" = is_master,
	)
	return data

/obj/item/paicard/ui_act(action, list/params)
	if(..())
		return
	var/static/list/hrefs = list("request" = "request", "setdna" = "setdna", "transmit" = "toggle_transmit", \
		"receive" = "toggle_receive", "holo" = "toggle_holo")
	if(hrefs[action])
		Topic(null, list("[hrefs[action]]" = "1"))
		return TRUE
	if(!pai || loc != usr || usr.stat) // as the old Topic
		return
	switch(action)
		if("setlaws")
			var/newlaws = trim(copytext(sanitize(params["laws"]), 1, MAX_MESSAGE_LEN))
			if(newlaws)
				pai.add_supplied_law(0, newlaws)
			return TRUE
		if("wipe")
			// Confirmed in the window, where the old Topic asked with a pop-up
			to_chat(pai, "<span class='warning'>You feel yourself slipping away from reality.</span>")
			to_chat(pai, "<span class='danger'>Byte by byte you lose your sense of self.</span>")
			to_chat(pai, "<span class='userdanger'>Your mental faculties leave you.</span>")
			to_chat(pai, "<span class='rose'>oblivion... </span>")
			qdel(pai)
			return TRUE
