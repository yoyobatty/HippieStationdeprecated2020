// The uplink redone as a shop (tgui-next Uplink.js): each item's picture from a sprite sheet built after init, like the
// vending machines', and how many are left of the limited ones.

/// The sprite sheet name of an uplink item: its type without the /datum/uplink_item/ start, slashes as dashes
/proc/uplink_icon_key(type)
	return replacetext(replacetext("[type]", "/datum/uplink_item/", ""), "/", "-")

/datum/asset/spritesheet/uplink
	name = "uplink"
	build_after_init = TRUE

/datum/asset/spritesheet/uplink/register()
	for(var/type in subtypesof(/datum/uplink_item))
		var/datum/uplink_item/U = type
		var/atom/item = initial(U.item)
		if(!ispath(item, /atom))
			continue
		var/icon_file = initial(item.icon)
		var/icon_state = initial(item.icon_state)
		if(!icon_file || !(icon_state in spritesheet_icon_states(icon_file)))
			continue
		// iconforge makes the sheet from these (spritesheet_forge.dm): scaled to 32x32 if bigger, then the item's colour
		var/list/transforms = spritesheet_scale_to_32(icon_file)
		var/c = initial(item.color)
		if(!isnull(c) && c != "#FFFFFF")
			LAZYADD(transforms, list(list("type" = RUSTG_ICONFORGE_BLEND_COLOR, "color" = c, "blend_mode" = ICON_MULTIPLY)))
		Insert(uplink_icon_key(type), icon_file, icon_state, SOUTH, 1, FALSE, transforms)
	return ..()

/datum/component/uplink/ui_base_html(html)
	var/datum/asset/spritesheet/assets = get_asset_datum(/datum/asset/spritesheet/uplink)
	. = replacetext(html, "<!--customheadhtml-->", assets.css_tag())

/datum/component/uplink/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, \
									datum/tgui/master_ui = null, datum/ui_state/state = GLOB.inventory_state)
	active = TRUE
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		var/datum/asset/assets = get_asset_datum(/datum/asset/spritesheet/uplink)
		assets.send(user)
		ui = new(user, src, ui_key, "uplink", name, 760, 640, master_ui, state)
		ui.set_autoupdate(FALSE) // This UI is only ever opened by one person, and never is updated outside of user input.
		ui.set_style("syndicate")
		ui.open()

/datum/component/uplink/ui_data(mob/user)
	. = ..()
	if(!.)
		return
	// How many are left of the items with a limit, by name
	var/list/stock = list()
	for(var/category in uplink_items)
		for(var/item in uplink_items[category])
			var/datum/uplink_item/I = uplink_items[category][item]
			if(I.limited_stock >= 0)
				stock[I.name] = I.limited_stock
	.["stock"] = stock

/datum/component/uplink/ui_static_data(mob/user)
	. = ..()
	var/datum/asset/spritesheet/sheet = get_asset_datum(/datum/asset/spritesheet/uplink)
	for(var/list/category in .["categories"])
		var/list/by_name = uplink_items[category["name"]]
		if(!by_name)
			continue
		for(var/list/item in category["items"])
			var/datum/uplink_item/I = by_name[item["name"]]
			if(!I)
				continue
			var/key = uplink_icon_key(I.type)
			if(sheet.sprites[key])
				item["icon"] = key
			if(I.refundable)
				item["refundable"] = TRUE
