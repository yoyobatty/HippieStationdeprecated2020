// The MULE's window picks its destination and home from the beacons and takes its ID typed in the window (tgui-next Mule.js),
// where the old one asked in pop-ups. The pop-ups stay for anything else that sends these without a value (the PDA).

/mob/living/simple_animal/bot/mulebot/ui_data(mob/user)
	. = ..()
	.["id"] = id
	.["home"] = home_destination
	.["beacons"] = sortList(GLOB.deliverybeacontags.Copy())

/mob/living/simple_animal/bot/mulebot/ui_act(action, params, datum/tgui/ui, datum/ui_state/state)
	if(isnull(params["value"]) || !(action in list("destination", "sethome", "setid")))
		return ..()
	if(!ui || ui.status != UI_INTERACTIVE || (locked && !usr.has_unlimited_silicon_privilege))
		return
	var/value = params["value"]
	switch(action)
		if("destination")
			if(value in GLOB.deliverybeacontags)
				set_destination(value)
		if("sethome")
			if(value in GLOB.deliverybeacontags)
				home_destination = value
		if("setid")
			value = trim(html_encode(value), MAX_NAME_LEN)
			if(value)
				set_id(value)
	return TRUE
