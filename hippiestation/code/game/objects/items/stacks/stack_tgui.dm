// hippie -- what using a stack in hand opens (metal, glass, rods, wood, cloth, tiles...) in tgui (tgui-next interfaces/
// StackCrafting.js): every recipe with what it costs and makes, in its groups, with a search, and the amounts the old window offered.
// Making something goes through the stack's own Topic(), so its checks are the old window's: the stack in the active hand, enough of
// it, room on the floor, the time it takes. The window shuts once the stack's out of hand, or used up: the old one stayed open, and
// its links went on to whatever took the used-up stack's reference next (the user's sheets of metal, 2026-11-04, pointed at a spark).
// Bots still make things with Topic() (bots_ai goals/repair_damage.dm).

/obj/item/stack/interact(mob/user, sublist)
	ui_interact(user)

/obj/item/stack/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, datum/tgui/master_ui = null, datum/ui_state/state = GLOB.hands_state)
	if(!recipes || get_amount() <= 0)
		return
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "stack_crafting", name, 420, 560, master_ui, state)
		ui.open()

/// A stack's recipes for the window: each made, a group of them (the old window's sub-lists), or a spacer between.
/obj/item/stack/proc/stack_recipe_entries(list/recipe_list, depth = 0)
	. = list()
	for(var/i in 1 to length(recipe_list))
		var/E = recipe_list[i]
		if(isnull(E))
			. += list(list("kind" = "spacer"))
		else if(istype(E, /datum/stack_recipe_list))
			var/datum/stack_recipe_list/L = E
			if(!depth) // Topic() only goes one group deep
				. += list(list("kind" = "group", "index" = i, "title" = L.title, "recipes" = stack_recipe_entries(L.recipes, depth + 1)))
		else if(istype(E, /datum/stack_recipe))
			var/datum/stack_recipe/R = E
			. += list(list(
				"kind" = "recipe",
				"index" = i,
				"title" = R.title,
				"req" = R.req_amount,
				"res" = R.res_amount,
				"max_res" = R.max_res_amount,
				"time" = R.time,
			))

/obj/item/stack/ui_static_data(mob/user)
	. = list()
	.["recipes"] = stack_recipe_entries(recipes)

/obj/item/stack/ui_data(mob/user)
	. = list()
	.["amount"] = get_amount()
	.["singular"] = singular_name || "piece"
	.["name"] = name

/obj/item/stack/ui_act(action, list/params)
	if(..())
		return
	if(action == "make")
		var/list/href = list("make" = "[text2num(params["index"])]", "multiplier" = "[max(1, round(text2num(params["multiplier"])))]")
		if(params["group"])
			href["sublist"] = "[text2num(params["group"])]"
		Topic(null, href)
		return TRUE
