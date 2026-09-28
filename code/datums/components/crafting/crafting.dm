/datum/component/personal_crafting/Initialize()
	if(!ismob(parent))
		return COMPONENT_INCOMPATIBLE
	RegisterSignal(parent, COMSIG_MOB_CLIENT_LOGIN, PROC_REF(create_mob_button))

/datum/component/personal_crafting/proc/create_mob_button(mob/user, client/CL)
	var/datum/hud/H = user.hud_used
	var/obj/screen/craft/C = new()
	C.icon = H.ui_style
	H.static_inventory += C
	CL.screen += C
	RegisterSignal(C, COMSIG_CLICK, PROC_REF(component_ui_interact))

#define CRAFTING_MODE 0
#define COOKING_MODE 1
/// Upper bound on "Craft all" repeats, in case a recipe somehow never runs out of parts
#define MAX_MASS_CRAFT 50

/datum/component/personal_crafting
	var/busy
	/// CRAFTING_MODE or COOKING_MODE, which half of the recipe list the menu shows
	var/mode = CRAFTING_MODE
	var/datum/action/innate/crafting/button
	var/display_craftable_only = FALSE
	var/display_compact = FALSE




/*	This is what procs do:
	get_environment - gets a list of things accessable for crafting by user
	get_surroundings - takes a list of things and makes a list of key-types to values-amounts of said type in the list
	check_contents - takes a recipe and a key-type list and checks if said recipe can be done with available stuff
	check_tools - takes recipe, a key-type list, and a user and checks if there are enough tools to do the stuff, checks bugs one level deep
	construct_item - takes a recipe and a user, call all the checking procs, calls do_after, checks all the things again, calls del_reqs, creates result, calls CheckParts of said result with argument being list returned by deel_reqs
	del_reqs - takes recipe and a user, loops over the recipes reqs var and tries to find everything in the list make by get_environment and delete it/add to parts list, then returns the said list
*/



/**
  * Check that the contents of the recipe meet the requirements.
  *
  * user: The /mob that initated the crafting.
  * R: The /datum/crafting_recipe being attempted.
  * contents: List of items to search for R's reqs.
  */
/datum/component/personal_crafting/proc/check_contents(mob/user, datum/crafting_recipe/R, list/contents)
	var/list/item_instances = contents["instances"]
	contents = contents["other"]

	var/list/requirements_list = list()

	// Process all requirements
	for(var/requirement_path in R.reqs)
		// Check we have the appropriate amount available in the contents list
		var/needed_amount = R.reqs[requirement_path]
		for(var/content_item_path in contents)
			// Right path and not blacklisted
			if(!ispath(content_item_path, requirement_path) || R.blacklist.Find(content_item_path))
				continue

			needed_amount -= contents[content_item_path]
			if(needed_amount <= 0)
				break

		if(needed_amount > 0)
			return FALSE

		// Store the instances of what we will use for R.check_requirements() for requirement_path
		var/list/instances_list = list()
		for(var/instance_path in item_instances)
			if(ispath(instance_path, requirement_path))
				instances_list += item_instances[instance_path]

		requirements_list[requirement_path] = instances_list

	for(var/requirement_path in R.chem_catalysts)
		if(contents[requirement_path] < R.chem_catalysts[requirement_path])
			return FALSE

	return R.check_requirements(user, requirements_list)

/datum/component/personal_crafting/proc/get_environment(mob/user, list/blacklist = null)
	. = list()
	for(var/obj/item/I in user.held_items)
		. += I
	if(!isturf(user.loc))
		return
	var/list/L = block(get_step(user, SOUTHWEST), get_step(user, NORTHEAST))
	for(var/A in L)
		var/turf/T = A
		if(T.Adjacent(user))
			for(var/B in T)
				var/atom/movable/AM = B
				if(AM.flags_1 & HOLOGRAM_1)
					continue
				. += AM
	for(var/slot in list(ITEM_SLOT_RPOCKET, ITEM_SLOT_LPOCKET))
		. += user.get_item_by_slot(slot)
	if(blacklist)
		for(var/obj/B in .)
			if(blacklist.Find(B.type))
				. -= B

/datum/component/personal_crafting/proc/get_surroundings(mob/user)
	. = list()
	.["tool_behaviour"] = list()
	.["other"] = list()
	.["instances"] = list()
	for(var/obj/item/I in get_environment(user))
		if(I.flags_1 & HOLOGRAM_1)
			continue
		if(.["instances"][I.type])
			.["instances"][I.type] += I
		else
			.["instances"][I.type] = list(I)
		if(istype(I, /obj/item/stack))
			var/obj/item/stack/S = I
			.["other"][I.type] += S.amount
		else if(I.tool_behaviour)
			.["tool_behaviour"] += I.tool_behaviour
			.["other"][I.type] += 1
		else
			if(istype(I, /obj/item/reagent_containers))
				var/obj/item/reagent_containers/RC = I
				if(RC.is_drainable())
					for(var/datum/reagent/A in RC.reagents.reagent_list)
						.["other"][A.type] += A.volume
			.["other"][I.type] += 1

/datum/component/personal_crafting/proc/check_tools(mob/user, datum/crafting_recipe/R, list/contents)
	if(!R.tools.len)
		return TRUE
	var/list/possible_tools = list()
	var/list/present_qualities = list()
	present_qualities |= contents["tool_behaviour"]
	for(var/obj/item/I in user.contents)
		if(istype(I, /obj/item/storage))
			for(var/obj/item/SI in I.contents)
				possible_tools += SI.type
				if(SI.tool_behaviour)
					present_qualities.Add(SI.tool_behaviour)

		possible_tools += I.type

		if(I.tool_behaviour)
			present_qualities.Add(I.tool_behaviour)

	possible_tools |= contents["other"]

	main_loop:
		for(var/A in R.tools)
			if(A in present_qualities)
				continue
			else
				for(var/I in possible_tools)
					if(ispath(I, A))
						continue main_loop
			return FALSE
	return TRUE

/datum/component/personal_crafting/proc/construct_item(mob/user, datum/crafting_recipe/R)
	var/list/contents = get_surroundings(user)
	var/send_feedback = 1
	if(check_contents(user, R, contents))
		if(check_tools(user, R, contents))
			if(do_after(user, R.time, target = user))
				contents = get_surroundings(user)
				if(!check_contents(user, R, contents))
					return ", missing component."
				if(!check_tools(user, R, contents))
					return ", missing tool."
				var/list/parts = del_reqs(R, user)
				var/atom/movable/I = new R.result (get_turf(user.loc))
				I.CheckParts(parts, R)
				if(isitem(I))
					user.put_in_hands(I)
				if(send_feedback)
					SSblackbox.record_feedback("tally", "object_crafted", 1, I.type)
				return 0
			return "."
		return ", missing tool."
	return ", missing component."


/*Del reqs works like this:

	Loop over reqs var of the recipe
	Set var amt to the value current cycle req is pointing to, its amount of type we need to delete
	Get var/surroundings list of things accessable to crafting by get_environment()
	Check the type of the current cycle req
		If its reagent then do a while loop, inside it try to locate() reagent containers, inside such containers try to locate needed reagent, if there isnt remove thing from surroundings
			If there is enough reagent in the search result then delete the needed amount, create the same type of reagent with the same data var and put it into deletion list
			If there isnt enough take all of that reagent from the container, put into deletion list, substract the amt var by the volume of reagent, remove the container from surroundings list and keep searching
			While doing above stuff check deletion list if it already has such reagnet, if yes merge instead of adding second one
		If its stack check if it has enough amount
			If yes create new stack with the needed amount and put in into deletion list, substract taken amount from the stack
			If no put all of the stack in the deletion list, substract its amount from amt and keep searching
			While doing above stuff check deletion list if it already has such stack type, if yes try to merge them instead of adding new one
		If its anything else just locate() in in the list in a while loop, each find --s the amt var and puts the found stuff in deletion loop

	Then do a loop over parts var of the recipe
		Do similar stuff to what we have done above, but now in deletion list, until the parts conditions are satisfied keep taking from the deletion list and putting it into parts list for return

	After its done loop over deletion list and delete all the shit that wasnt taken by parts loop

	del_reqs return the list of parts resulting object will receive as argument of CheckParts proc, on the atom level it will add them all to the contents, on all other levels it calls ..() and does whatever is needed afterwards but from contents list already
*/

/datum/component/personal_crafting/proc/del_reqs(datum/crafting_recipe/R, mob/user)
	var/list/surroundings
	var/list/Deletion = list()
	. = list()
	var/data
	var/amt
	main_loop:
		for(var/A in R.reqs)
			amt = R.reqs[A]
			surroundings = get_environment(user, R.blacklist)
			surroundings -= Deletion
			if(ispath(A, /datum/reagent))
				var/datum/reagent/RG = new A
				var/datum/reagent/RGNT
				while(amt > 0)
					var/obj/item/reagent_containers/RC = locate() in surroundings
					RG = RC.reagents.get_reagent(A)
					if(RG)
						if(!locate(RG.type) in Deletion)
							Deletion += new RG.type()
						if(RG.volume > amt)
							RG.volume -= amt
							data = RG.data
							RC.reagents.conditional_update(RC)
							RG = locate(RG.type) in Deletion
							RG.volume = amt
							RG.data += data
							continue main_loop
						else
							surroundings -= RC
							amt -= RG.volume
							RC.reagents.reagent_list -= RG
							RC.reagents.conditional_update(RC)
							RGNT = locate(RG.type) in Deletion
							RGNT.volume += RG.volume
							RGNT.data += RG.data
							qdel(RG)
						RC.on_reagent_change()
					else
						surroundings -= RC
			else if(ispath(A, /obj/item/stack))
				var/obj/item/stack/S
				var/obj/item/stack/SD
				while(amt > 0)
					S = locate(A) in surroundings
					if(S.amount >= amt)
						if(!locate(S.type) in Deletion)
							SD = new S.type()
							Deletion += SD
						S.use(amt)
						SD = locate(S.type) in Deletion
						SD.amount += amt
						continue main_loop
					else
						amt -= S.amount
						if(!locate(S.type) in Deletion)
							Deletion += S
						else
							data = S.amount
							S = locate(S.type) in Deletion
							S.add(data)
						surroundings -= S
			else
				var/atom/movable/I
				while(amt > 0)
					I = locate(A) in surroundings
					Deletion += I
					surroundings -= I
					amt--
	var/list/partlist = list(R.parts.len)
	for(var/M in R.parts)
		partlist[M] = R.parts[M]
	for(var/A in R.parts)
		if(istype(A, /datum/reagent))
			var/datum/reagent/RG = locate(A) in Deletion
			if(RG.volume > partlist[A])
				RG.volume = partlist[A]
			. += RG
			Deletion -= RG
			continue
		else if(istype(A, /obj/item/stack))
			var/obj/item/stack/ST = locate(A) in Deletion
			if(ST.amount > partlist[A])
				ST.amount = partlist[A]
			. += ST
			Deletion -= ST
			continue
		else
			while(partlist[A] > 0)
				var/atom/movable/AM = locate(A) in Deletion
				. += AM
				Deletion -= AM
				partlist[A] -= 1
	while(Deletion.len)
		var/DL = Deletion[Deletion.len]
		Deletion.Cut(Deletion.len)
		qdel(DL)

/datum/component/personal_crafting/proc/component_ui_interact(obj/screen/craft/image, location, control, params, user)
	if(user == parent)
		ui_interact(user)

/datum/component/personal_crafting/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, datum/tgui/master_ui = null, datum/ui_state/state = GLOB.not_incapacitated_turf_state)
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		var/datum/asset/assets = get_asset_datum(/datum/asset/spritesheet/crafting)
		assets.send(user)
		ui = new(user, src, ui_key, "personal_crafting", "Crafting Menu", 800, 720, master_ui, state)
		ui.open()

/datum/component/personal_crafting/ui_base_html(html)
	var/datum/asset/spritesheet/assets = get_asset_datum(/datum/asset/spritesheet/crafting)
	. = replacetext(html, "<!--customheadhtml-->", assets.css_tag())

/// Recipes this user can see in the current mode: everything always available, plus what their mind has learned
/datum/component/personal_crafting/proc/get_visible_recipes(mob/user)
	init_crafting_ui_data()
	. = list()
	var/list/learned = user?.mind?.learned_recipes
	for(var/rec in GLOB.crafting_ui_recipes[mode + 1])
		var/datum/crafting_recipe/R = rec
		if(R.always_availible || (learned && (R.type in learned)))
			. += R

/datum/component/personal_crafting/proc/can_see_recipe(mob/user, datum/crafting_recipe/R)
	if(!istype(R) || !GLOB.crafting_ui_recipe_data[R])
		return FALSE
	return R.always_availible || (R.type in user?.mind?.learned_recipes)

/datum/component/personal_crafting/ui_data(mob/user)
	var/list/data = list()
	data["busy"] = busy
	data["mode"] = mode
	data["display_craftable_only"] = display_craftable_only
	data["display_compact"] = display_compact

	var/list/surroundings = get_surroundings(user)
	var/list/craftability = list()
	for(var/rec in get_visible_recipes(user))
		var/datum/crafting_recipe/R = rec
		if(check_contents(user, R, surroundings) && check_tools(user, R, surroundings))
			craftability["[REF(R)]"] = TRUE

	data["craftability"] = craftability
	return data

/datum/component/personal_crafting/ui_static_data(mob/user)
	var/list/data = list()

	var/list/recipes = list()
	var/list/categories = list()
	for(var/rec in get_visible_recipes(user))
		var/list/recipe_data = GLOB.crafting_ui_recipe_data[rec]
		recipes += list(recipe_data)
		categories |= recipe_data["category"]
	data["recipes"] = recipes
	data["categories"] = sortList(categories)

	if(!GLOB.crafting_ui_atom_data)
		var/datum/asset/spritesheet/assets = get_asset_datum(/datum/asset/spritesheet/crafting)
		var/list/atom_data = list()
		for(var/path in GLOB.crafting_ui_atoms)
			atom_data += list(crafting_ui_atom_data(path, assets))
		GLOB.crafting_ui_atom_data = atom_data
	data["atom_data"] = GLOB.crafting_ui_atom_data

	if(mode == COOKING_MODE)
		data["foodtypes"] = crafting_foodtype_names(ALL)
		if(ishuman(user))
			var/mob/living/carbon/human/H = user
			data["diet"] = list(
				"liked_food" = crafting_foodtype_names(H.dna.species.liked_food),
				"disliked_food" = crafting_foodtype_names(H.dna.species.disliked_food),
				"toxic_food" = crafting_foodtype_names(H.dna.species.toxic_food),
			)
	return data

/datum/component/personal_crafting/ui_act(action, params)
	if(..())
		return
	switch(action)
		if("make", "make_mass")
			if(busy)
				return
			var/mob/user = usr
			var/datum/crafting_recipe/TR = locate(params["recipe"]) in GLOB.crafting_recipes
			if(!can_see_recipe(user, TR)) //Unlearned recipes stay unlearned, whatever ref the client sends
				return
			busy = TRUE
			ui_interact(user)
			var/crafted = 0
			var/fail_msg
			do
				fail_msg = construct_item(user, TR)
				if(fail_msg)
					break
				crafted++
				on_recipe_crafted(user, TR)
			while(action == "make_mass" && crafted < MAX_MASS_CRAFT)
			if(crafted > 1)
				to_chat(user, "<span class='notice'>You made [TR.name] x[crafted].</span>")
			else if(crafted)
				to_chat(user, "<span class='notice'>[TR.name] constructed.</span>")
			if(fail_msg && (!crafted || fail_msg != ", missing component."))
				to_chat(user, "<span class='warning'>Construction failed[fail_msg]</span>")
			busy = FALSE
			. = TRUE
		if("toggle_recipes")
			display_craftable_only = !display_craftable_only
			. = TRUE
		if("toggle_compact")
			display_compact = !display_compact
			. = TRUE
		if("toggle_mode")
			var/new_mode = text2num(params["mode"])
			if(new_mode != CRAFTING_MODE && new_mode != COOKING_MODE)
				return
			mode = new_mode
			update_static_data(usr)
			. = TRUE

/// Side effects of finishing a recipe, run once per crafted item
/datum/component/personal_crafting/proc/on_recipe_crafted(mob/user, datum/crafting_recipe/TR)
	if(!user.mind)
		return
	//*************************
	//***Curator magic stuff***
	//*************************

	if(istype(TR, /datum/crafting_recipe/tier1/obelisk))
		user.mind.teach_crafting_recipe(/datum/crafting_recipe/tier1/upgradescroll) //Gives the curator a few recipes upon building the first obelisk. Like unlocks.
		user.mind.teach_crafting_recipe(/datum/crafting_recipe/tier1/sord)
		user.mind.teach_crafting_recipe(/datum/crafting_recipe/tier1/magicsoap)
		user.mind.teach_crafting_recipe(/datum/crafting_recipe/tier1/immortalitytalisman)
		user.mind.teach_crafting_recipe(/datum/crafting_recipe/tier1/d100)
		user.mind.teach_crafting_recipe(/datum/crafting_recipe/tier1/doorwand)
		user.mind.teach_crafting_recipe(/datum/crafting_recipe/tier1/lazarusinjector)
		user.mind.teach_crafting_recipe(/datum/crafting_recipe/tier2/obelisk)

	else if(istype(TR, /datum/crafting_recipe/tier2/obelisk))
		user.mind.teach_crafting_recipe(/datum/crafting_recipe/tier2/telecrystal)
		user.mind.teach_crafting_recipe(/datum/crafting_recipe/tier2/shittyrevivewand)
		user.mind.teach_crafting_recipe(/datum/crafting_recipe/tier2/shittysafetywand)
		user.mind.teach_crafting_recipe(/datum/crafting_recipe/tier2/monstercube)
		user.mind.teach_crafting_recipe(/datum/crafting_recipe/tier2/soulshard)
		user.mind.teach_crafting_recipe(/datum/crafting_recipe/tier2/spectralblade)
		user.mind.teach_crafting_recipe(/datum/crafting_recipe/tier2/lighteater)
		user.mind.teach_crafting_recipe(/datum/crafting_recipe/tier3/obelisk)

	else if(istype(TR, /datum/crafting_recipe/tier3/obelisk))
		user.mind.teach_crafting_recipe(/datum/crafting_recipe/tier3/oneusedieoffate)
		user.mind.teach_crafting_recipe(/datum/crafting_recipe/tier3/nullrod)
		user.mind.teach_crafting_recipe(/datum/crafting_recipe/tier3/portalgun)
		user.mind.teach_crafting_recipe(/datum/crafting_recipe/tier3/gravitygun)

	else
		return

	//The unlocks above add recipes to the menu, so resend the recipe list
	update_static_data(user)

//*************************
//*** Crafting menu data ***
//*************************

/// Every atom or reagent path the crafting menu shows (results, ingredients, tools, catalysts). A path's index is its UI id.
GLOBAL_LIST_EMPTY(crafting_ui_atoms)
/// Two lists of valid recipes, index 1 for CRAFTING_MODE and 2 for COOKING_MODE
GLOBAL_LIST_EMPTY(crafting_ui_recipes)
/// recipe datum -> the static UI data for it, which is the same for every user
GLOBAL_LIST_EMPTY(crafting_ui_recipe_data)
/// Name and icon for each entry of crafting_ui_atoms, built the first time a menu opens
GLOBAL_VAR(crafting_ui_atom_data)

/// Builds the crafting menu globals the first time anything asks for them
/proc/init_crafting_ui_data()
	if(length(GLOB.crafting_ui_recipes))
		return
	GLOB.crafting_ui_recipes = list(list(), list())
	for(var/rec in GLOB.crafting_recipes)
		var/datum/crafting_recipe/R = rec
		if(!R.name || !R.result) //Abstract parents
			continue
		GLOB.crafting_ui_atoms |= R.result
		for(var/path in R.reqs)
			GLOB.crafting_ui_atoms |= path
		for(var/path in R.chem_catalysts)
			GLOB.crafting_ui_atoms |= path
		for(var/tool in R.tools)
			if(ispath(tool))
				GLOB.crafting_ui_atoms |= tool
	for(var/rec in GLOB.crafting_recipes)
		var/datum/crafting_recipe/R = rec
		if(!R.name || !R.result)
			continue
		var/list/recipe_data = build_crafting_ui_recipe(R)
		GLOB.crafting_ui_recipe_data[R] = recipe_data
		var/list/mode_recipes = GLOB.crafting_ui_recipes[recipe_data["cooking"] ? COOKING_MODE + 1 : CRAFTING_MODE + 1]
		mode_recipes += R

/proc/build_crafting_ui_recipe(datum/crafting_recipe/R)
	var/list/data = list()
	data["ref"] = "[REF(R)]"
	data["name"] = R.name
	data["id"] = GLOB.crafting_ui_atoms.Find(R.result)
	data["time"] = R.time / 10
	data["learned"] = !R.always_availible

	var/atom/result = R.result
	data["desc"] = initial(result.desc)

	// Food recipes were split into a category and a subcategory, the menu only has categories
	var/static/list/food_categories = list(CAT_BREAD, CAT_BURGER, CAT_CAKE, CAT_EGG, CAT_MEAT, CAT_MISCFOOD, CAT_PASTRY, CAT_PIE, CAT_PIZZA, CAT_SALAD, CAT_SANDWICH, CAT_SOUP, CAT_SPAGHETTI)
	var/category = R.category
	if(category == CAT_FOOD)
		category = R.subcategory || CAT_MISCFOOD
	var/cooking = (category in food_categories)
	if(!cooking)
		switch(category)
			if(CAT_WEAPONRY)
				category = R.subcategory || CAT_WEAPON
			if(CAT_MAGIC)
				if(R.subcategory)
					category = "[CAT_MAGIC] ([R.subcategory])"
			if(CAT_LEARNED)
				category = "Learned"
			if(CAT_NONE)
				category = CAT_MISC
	data["category"] = category
	data["cooking"] = cooking

	if(cooking && ispath(R.result, /obj/item/reagent_containers/food))
		var/obj/item/reagent_containers/food/F = R.result
		data["foodtypes"] = crafting_foodtype_names(initial(F.foodtype))

	var/list/reqs = list()
	for(var/path in R.reqs)
		reqs["[GLOB.crafting_ui_atoms.Find(path)]"] = R.reqs[path]
	data["reqs"] = reqs

	var/list/catalysts = list()
	for(var/path in R.chem_catalysts)
		catalysts["[GLOB.crafting_ui_atoms.Find(path)]"] = R.chem_catalysts[path]
	data["chem_catalysts"] = catalysts

	var/list/tool_behaviors = list()
	var/list/tool_paths = list()
	for(var/tool in R.tools)
		if(ispath(tool))
			tool_paths += GLOB.crafting_ui_atoms.Find(tool)
		else
			tool_behaviors += tool
	data["tool_behaviors"] = tool_behaviors
	data["tool_paths"] = tool_paths
	return data

/proc/crafting_ui_atom_data(path, datum/asset/spritesheet/assets)
	var/list/data = list()
	if(ispath(path, /datum/reagent))
		var/datum/reagent/reagent = path
		data["name"] = initial(reagent.name)
		data["is_reagent"] = TRUE
	else
		var/atom/A = path
		data["name"] = initial(A.name)
		var/sprite = "a[GLOB.crafting_ui_atoms.Find(path)]"
		data["icon"] = assets.icon_class_name(sprite)
		data["icon_size"] = assets.icon_size_id(sprite)
	return data

/// Converts a food flags bitfield into the flags' display names
/proc/crafting_foodtype_names(foodflags)
	var/static/list/foodtype_names = list(
		"Meat" = MEAT,
		"Vegetables" = VEGETABLES,
		"Raw" = RAW,
		"Junk Food" = JUNKFOOD,
		"Grain" = GRAIN,
		"Fruit" = FRUIT,
		"Dairy" = DAIRY,
		"Fried" = FRIED,
		"Alcohol" = ALCOHOL,
		"Sugar" = SUGAR,
		"Gross" = GROSS,
		"Toxic" = TOXIC,
		"Pineapple" = PINEAPPLE,
		"Cloth" = CLOTH,
	)
	. = list()
	for(var/foodtype in foodtype_names)
		if(foodflags & foodtype_names[foodtype])
			. += foodtype

#undef CRAFTING_MODE
#undef COOKING_MODE
#undef MAX_MASS_CRAFT

//Mind helpers

/datum/mind/proc/teach_crafting_recipe(R)
	if(!learned_recipes)
		learned_recipes = list()
	learned_recipes |= R
