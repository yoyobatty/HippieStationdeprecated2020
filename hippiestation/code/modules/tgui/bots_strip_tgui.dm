// hippie -- bots' control panels and the corgi's, parrot's and alien's strip menus, off their old HTML windows. Each bot type's panel
// (interfaces/BotPanel.js) is written out here: its sprite and status up top, then its settings as switches, steppers and choices.
// Every one of them is the link the old page had, sent to the bot's own Topic(), and the window only takes a link it showed that
// person, so the locks, access, emag and pAI rules stay the bots' own. The animals use the human strip menu (strip_menu route).

// ---------------------------------------------------------------------------------------------
// Bots
// ---------------------------------------------------------------------------------------------

/mob/living/simple_animal/bot
	/// What the panel last showed each viewer: ckey -> list of link params
	var/list/panel_shown

/mob/living/simple_animal/bot/show_controls(mob/M)
	users |= M
	ui_interact(M)
	SStgui.update_uis(src)

// The MULE has its own window (mulebot_tgui.dm)
/mob/living/simple_animal/bot/mulebot/show_controls(mob/M)
	ui_interact(M)

/mob/living/simple_animal/bot/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, datum/tgui/master_ui = null, datum/ui_state/state = GLOB.always_state)
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "bot_panel", name, 420, 620, master_ui, state)
		ui.open()

/mob/living/simple_animal/bot/ui_status(mob/user, datum/ui_state/state)
	return topic_denied(user) ? UI_CLOSE : UI_INTERACTIVE

/mob/living/simple_animal/bot/ui_close(mob/user)
	users -= user

/// A setting of the panel. kind: "toggle" (value), "choice" (value, options: list of list(label, params)), "stepper" (value, steps:
/// list of list(label, params)), "button" (params), "info" (value)
/proc/bot_setting(label, kind, value, params, list/extra)
	var/list/S = list("label" = label, "kind" = kind, "value" = value, "params" = params)
	if(extra)
		S += extra
	return S

/// What can be changed, by type: the old get_controls() lines, nothing more
/mob/living/simple_animal/bot/proc/bot_panel_settings(mob/user)
	return list()

/mob/living/simple_animal/bot/proc/bot_panel_can_behave(mob/user)
	return !locked || issilicon(user) || IsAdminGhost(user)

/mob/living/simple_animal/bot/ui_data(mob/user)
	. = list()
	.["name"] = name
	.["model"] = model
	.["kind"] = bot_panel_kind()
	.["sprite"] = bot_panel_sprite(user)
	.["on"] = on
	.["mode"] = bot_mode_for_ui(src)
	.["locked"] = locked
	.["open"] = open
	.["emagged"] = emagged == 2
	.["hacked"] = hacked
	.["silicon"] = issilicon(user) || IsAdminGhost(user)
	.["can_behave"] = bot_panel_can_behave(user)
	var/list/links = list("power=1")
	// Network: the safety lock for silicons, the remote radio for anyone with the controls unlocked (hack())
	if(issilicon(user) || IsAdminGhost(user))
		.["safety"] = emagged ? "danger" : "engaged"
		links += "operation=hack"
	else if(!locked)
		.["remote"] = !remote_disabled
		links += "operation=remote"
	// The personality card (showpai())
	if((!locked || issilicon(user) || IsAdminGhost(user)) && (paicard || allow_pai))
		if(paicard)
			.["pai"] = client ? "active" : "inactive"
			links += "operation=ejectpai"
		else
			.["pai"] = (!allow_pai || key) ? "unavailable" : "none"
	var/list/settings = bot_panel_can_behave(user) ? bot_panel_settings(user) : list()
	for(var/list/S in settings)
		if(S["params"])
			links += S["params"]
		for(var/list/option in S["options"] + S["steps"])
			links += option["params"]
	.["settings"] = settings
	.["extra"] = bot_panel_extra(user)
	for(var/list/extra in .["extra"])
		if(extra["params"])
			links += extra["params"]
	LAZYINITLIST(panel_shown)
	panel_shown[user.ckey || REF(user)] = links

/// Things loaded in the bot (a beaker, tiles), shown whatever the lock, as the old pages did
/mob/living/simple_animal/bot/proc/bot_panel_extra(mob/user)
	return list()

/mob/living/simple_animal/bot/proc/bot_panel_kind()
	return "generic"

/// The bot's own sprite, sent to the viewer once per icon and state
/mob/living/simple_animal/bot/proc/bot_panel_sprite(mob/user)
	if(!user?.client || !isfile(icon))
		return null
	var/static/list/made = list()
	var/known_as = "[icon]|[icon_state]"
	var/asset_name = made[known_as]
	if(!asset_name)
		var/icon/picture = icon(icon, icon_state, SOUTH, 1)
		asset_name = "[generate_asset_name(picture)].png"
		register_asset(asset_name, picture)
		made[known_as] = asset_name
	send_asset(user.client, asset_name)
	return asset_name

/mob/living/simple_animal/bot/ui_act(action, list/params)
	if(..())
		return
	if(action != "topic")
		return
	var/link = "[params["params"]]"
	var/list/links = LAZYACCESS(panel_shown, usr.ckey || REF(usr))
	if(!(link in links))
		return
	Topic(null, params2list(link))
	return TRUE

// Securitrons and ED-209s

/mob/living/simple_animal/bot/secbot/bot_panel_kind()
	return "security"

/mob/living/simple_animal/bot/secbot/bot_panel_settings(mob/user)
	return list(
		bot_setting("Arrest people without ID", "toggle", idcheck, "operation=idcheck"),
		bot_setting("Arrest for unauthorized weapons", "toggle", weaponscheck, "operation=weaponscheck"),
		bot_setting("Arrest for warrants", "toggle", check_records, "operation=ignorerec"),
		bot_setting("On arrest", "choice", arrest_type ? "Detain" : "Arrest", null, list("options" = list(
			list("label" = "Arrest", "params" = arrest_type ? "operation=switchmode" : null),
			list("label" = "Detain", "params" = arrest_type ? null : "operation=switchmode")))),
		bot_setting("Report arrests on the radio", "toggle", declare_arrests, "operation=declarearrests"),
		bot_setting("Patrol", "toggle", auto_patrol, "operation=patrol"),
	)

/mob/living/simple_animal/bot/ed209/bot_panel_kind()
	return lasercolor ? "lasertag" : "security"

/mob/living/simple_animal/bot/ed209/bot_panel_settings(mob/user)
	if(lasercolor)
		return list()
	return list(
		bot_setting("Arrest people without ID", "toggle", idcheck, "operation=idcheck"),
		bot_setting("Arrest for unauthorized weapons", "toggle", weaponscheck, "operation=weaponscheck"),
		bot_setting("Arrest for warrants", "toggle", check_records, "operation=ignorerec"),
		bot_setting("On arrest", "choice", arrest_type ? "Detain" : "Arrest", null, list("options" = list(
			list("label" = "Arrest", "params" = arrest_type ? "operation=switchmode" : null),
			list("label" = "Detain", "params" = arrest_type ? null : "operation=switchmode")))),
		bot_setting("Report arrests on the radio", "toggle", declare_arrests, "operation=declarearrests"),
		bot_setting("Patrol", "toggle", auto_patrol, "operation=patrol"),
	)

// Cleanbots

/mob/living/simple_animal/bot/cleanbot/bot_panel_kind()
	return "janitor"

/mob/living/simple_animal/bot/cleanbot/bot_panel_settings(mob/user)
	return list(
		bot_setting("Clean blood", "toggle", blood, "operation=blood"),
		bot_setting("Clean trash", "toggle", trash, "operation=trash"),
		bot_setting("Clean graffiti", "toggle", drawn, "operation=drawn"),
		bot_setting("Exterminate pests", "toggle", pests, "operation=pests"),
		bot_setting("Patrol", "toggle", auto_patrol, "operation=patrol"),
	)

// Floorbots

/mob/living/simple_animal/bot/floorbot/bot_panel_kind()
	return "engineering"

/mob/living/simple_animal/bot/floorbot/bot_panel_extra(mob/user)
	if(specialtiles)
		return list(list("label" = "Special tiles", "value" = "[specialtiles] / [maxtiles]", "button" = "Eject", "params" = "operation=eject"))
	return list(list("label" = "Special tiles", "value" = "None loaded"))

/mob/living/simple_animal/bot/floorbot/bot_panel_settings(mob/user)
	var/list/dirs = list()
	for(var/name in list("north", "east", "south", "west"))
		var/d = text2dir(name)
		dirs += list(list("label" = capitalize(name), "params" = targetdirection == d ? null : "linemode=[name]"))
	dirs += list(list("label" = "Off", "params" = targetdirection ? "linemode=disable" : null))
	return list(
		bot_setting("Tile new hull plating", "toggle", autotile, "operation=autotile"),
		bot_setting("Place floor tiles", "toggle", placetiles, "operation=place"),
		bot_setting("Replace tiles with the special ones", "toggle", replacetiles, "operation=replace"),
		bot_setting("Repair damaged floors", "toggle", fixfloors, "operation=fix"),
		bot_setting("Traction magnets", "toggle", anchored, "operation=anchor"),
		bot_setting("Patrol", "toggle", auto_patrol, "operation=patrol"),
		bot_setting("Lay a line", "choice", targetdirection ? capitalize(dir2text(targetdirection)) : "Off", null, list("options" = dirs)),
	)

// The old "Line Mode" link asked for the direction in a prompt: the window's buttons say which
/mob/living/simple_animal/bot/floorbot/Topic(href, href_list)
	var/line = href_list["linemode"]
	if(line && line != "1")
		if(topic_denied(usr) || !(bot_core.allowed(usr) || !locked || issilicon(usr) || IsAdminGhost(usr)))
			return TRUE
		switch(line)
			if("north")
				targetdirection = NORTH
			if("south")
				targetdirection = SOUTH
			if("east")
				targetdirection = EAST
			if("west")
				targetdirection = WEST
			if("disable")
				targetdirection = null
		update_controls()
		return TRUE
	return ..()

// Medibots

/mob/living/simple_animal/bot/medbot/bot_panel_kind()
	return "medical"

/mob/living/simple_animal/bot/medbot/bot_panel_extra(mob/user)
	if(reagent_glass)
		return list(list("label" = "Beaker", "value" = "[reagent_glass.reagents.total_volume] / [reagent_glass.reagents.maximum_volume] u", "button" = "Eject", "params" = "eject=1"))
	return list(list("label" = "Beaker", "value" = "None loaded"))

/mob/living/simple_animal/bot/medbot/bot_panel_settings(mob/user)
	return list(
		bot_setting("Heal below health", "stepper", heal_threshold, null, list("steps" = list(
			list("label" = "-10", "params" = "adj_threshold=-10"), list("label" = "-5", "params" = "adj_threshold=-5"),
			list("label" = "+5", "params" = "adj_threshold=5"), list("label" = "+10", "params" = "adj_threshold=10")), "min" = 5, "max" = 75)),
		bot_setting("Injection", "stepper", injection_amount, null, list("steps" = list(
			list("label" = "-5", "params" = "adj_inject=-5"), list("label" = "+5", "params" = "adj_inject=5")), "min" = 5, "max" = 15, "unit" = "u")),
		bot_setting("Medicine from", "choice", use_beaker ? "Beaker" : "Synthesizer", null, list("options" = list(
			list("label" = "Synthesizer", "params" = use_beaker ? "use_beaker=1" : null),
			list("label" = "Beaker", "params" = use_beaker ? null : "use_beaker=1")))),
		bot_setting("Treat viral infections", "toggle", treat_virus, "virus=1"),
		bot_setting("Speaker", "toggle", !shut_up, "togglevoice=1"),
		bot_setting("Critical patient alerts", "toggle", declare_crit, "critalerts=1"),
		bot_setting("Patrol", "toggle", auto_patrol, "operation=patrol"),
		bot_setting("Stay put", "toggle", stationary_mode, "stationary=1"),
	)

// Firebots

/mob/living/simple_animal/bot/firebot/bot_panel_kind()
	return "fire"

/mob/living/simple_animal/bot/firebot/bot_panel_settings(mob/user)
	return list(
		bot_setting("Put out fires", "toggle", extinguish_fires, "operation=extinguish_fires"),
		bot_setting("Put out people", "toggle", extinguish_people, "operation=extinguish_people"),
		bot_setting("Patrol", "toggle", auto_patrol, "operation=patrol"),
		bot_setting("Stay put", "toggle", stationary_mode, "operation=stationary_mode"),
	)

// Honkbots

/mob/living/simple_animal/bot/honkbot/bot_panel_kind()
	return "clown"

/mob/living/simple_animal/bot/honkbot/bot_panel_settings(mob/user)
	return list(bot_setting("Patrol", "toggle", auto_patrol, "operation=patrol"))

// ---------------------------------------------------------------------------------------------
// The corgi's, parrot's and alien's inventories, in the human strip menu
// ---------------------------------------------------------------------------------------------

/// A slot line for the strip menu (strip_menu_tgui.dm's shape), slot by name
/proc/animal_strip_row(mob/user, label, slot, obj/item/I)
	var/list/row = list("label" = label, "slot" = slot, "hand" = 0)
	if(I && !(I.item_flags & ABSTRACT))
		row["item"] = I.name
		row["icon"] = strip_menu_icon(I, user)
	return row

/mob/living/simple_animal/pet/dog/corgi/show_inv(mob/user)
	if(!user.canUseTopic(src, BE_CLOSE, FALSE, NO_TK))
		return
	user.set_machine(src)
	ui_interact(user)
	SStgui.update_uis(src)

/mob/living/simple_animal/parrot/show_inv(mob/user)
	user.set_machine(src)
	ui_interact(user)
	SStgui.update_uis(src)

/mob/living/simple_animal/pet/dog/corgi/ui_interact(mob/user, ui_key = "strip", datum/tgui/ui = null, force_open = FALSE, datum/tgui/master_ui = null, datum/ui_state/state = GLOB.strip_state)
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "strip_menu", name, 420, 260, master_ui, state)
		ui.open()

/mob/living/simple_animal/parrot/ui_interact(mob/user, ui_key = "strip", datum/tgui/ui = null, force_open = FALSE, datum/tgui/master_ui = null, datum/ui_state/state = GLOB.strip_state)
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "strip_menu", name, 420, 200, master_ui, state)
		ui.open()

/mob/living/simple_animal/pet/dog/corgi/ui_data(mob/user)
	var/obj/item/held = user.get_active_held_item()
	return list("rows" = list(animal_strip_row(user, "Head", "head", inventory_head), animal_strip_row(user, "Back", "back", inventory_back), \
		animal_strip_row(user, "Collar", "collar", pcollar)), "holding" = (held && !(held.item_flags & ABSTRACT)) ? held.name : null)

/mob/living/simple_animal/parrot/ui_data(mob/user)
	var/obj/item/held = user.get_active_held_item()
	return list("rows" = list(animal_strip_row(user, "Headset", "ears", ears)), "holding" = (held && !(held.item_flags & ABSTRACT)) ? held.name : null)

// A click takes off what's there or puts on what's in hand, as the old link did
/mob/living/simple_animal/pet/dog/corgi/ui_act(action, list/params)
	if(..())
		return
	var/slot = params["slot"]
	if(action != "item" || !(slot in list("head", "back", "collar")))
		return
	var/obj/item/there = slot == "head" ? inventory_head : slot == "back" ? inventory_back : pcollar
	Topic(null, list("[there ? "remove_inv" : "add_inv"]" = slot))
	return TRUE

/mob/living/simple_animal/parrot/ui_act(action, list/params)
	if(..())
		return
	if(action != "item" || params["slot"] != "ears")
		return
	Topic(null, list("[ears ? "remove_inv" : "add_inv"]" = "ears"))
	return TRUE

// The alien is a carbon: carbon's strip window, with its hands, pouches and cuffs
/mob/living/carbon/alien/humanoid/show_inv(mob/user)
	if(user?.client)
		ui_interact(user)

/mob/living/carbon/alien/humanoid/strip_menu_rows(mob/user)
	var/list/rows = list()
	for(var/i in 1 to held_items.len)
		var/list/hand_row = strip_menu_slot(user, capitalize(get_held_index_name(i)), ITEM_SLOT_HANDS, get_item_for_held_index(i))
		hand_row["hand"] = i
		rows += list(hand_row)
	rows += list(list("label" = "Pouches", "slot" = "pouches", "hand" = 0, "item" = "Empty them", "gap" = TRUE))
	strip_menu_cuffs(user, rows)
	return rows

/mob/living/carbon/alien/humanoid/ui_act(action, list/params)
	if(action == "item" && params["slot"] == "pouches")
		if(!usr.canUseTopic(src, BE_CLOSE, NO_DEXTERY))
			return
		Topic(null, list("pouches" = "1"))
		return TRUE
	return ..()
