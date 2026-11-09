/// hippie -- anything that isn't a sheet or another stack asks before it's melted down. On help intent a wrench, a toolbox with
/// everything in it, or somebody's gun went in without a word. The checks are the ones the autolathe's own attackby() makes before
/// it lets the material container have the item: a screwdriver still opens it, wire tools and a crowbar still work with the panel
/// open, and a design disk still loads.
/obj/machinery/autolathe/attackby(obj/item/O, mob/user, params)
	if(user.a_intent != INTENT_HELP || busy || stat || istype(O, /obj/item/stack) || istype(O, /obj/item/disk/design_disk) || (O.item_flags & ABSTRACT))
		return ..()
	if(O.tool_behaviour == TOOL_SCREWDRIVER || (panel_open && (O.tool_behaviour == TOOL_CROWBAR || is_wire_tool(O))))
		return ..()
	var/datum/component/material_container/materials = GetComponent(/datum/component/material_container)
	if(!materials || !materials.get_item_material_amount(O))
		return ..() // nothing in it the autolathe takes: it says so itself
	if(!user.client) // nobody to ask, and alert() answers its first button for them: kept
		return TRUE
	var/what = materials.describe_materials(O.materials)
	if(tgui_alert(user, "Melt down [O] for [what]?", name, list("Melt it down", "Keep it")) != "Melt it down")
		return TRUE
	if(QDELETED(O) || QDELETED(src) || user.get_active_held_item() != O || !user.canUseTopic(src, BE_CLOSE))
		return TRUE
	return ..()
