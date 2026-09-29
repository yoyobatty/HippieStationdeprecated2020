// RPED tier readout: a machine's parts are listed grouped, each with its tier, plus the machine's average tier and how
// many of the parts the RPED in your hand could upgrade. The RPED's own examine sums up what it's carrying by tier.

/// The colour a part tier is shown in: grey, green, blue, purple, then orange for anything past tier 4
/proc/part_tier_color(tier)
	switch(tier)
		if(-INFINITY to 1)
			return "#9e9e9e"
		if(2)
			return "#43a047"
		if(3)
			return "#1e88e5"
		if(4)
			return "#9c3fd6"
	return "#ef8a17"

/// What to show after a part's name: its tier for stock parts, its capacity for cells, nothing for anything else
/proc/part_tier_suffix(obj/item/part)
	if(istype(part, /obj/item/stock_parts/cell))
		var/obj/item/stock_parts/cell/cell = part
		return " ([DisplayEnergy(cell.maxcharge)])"
	if(istype(part, /obj/item/stock_parts))
		var/obj/item/stock_parts/stock_part = part
		return " &mdash; <font color='[part_tier_color(stock_part.rating)]'><b>tier [stock_part.rating]</b></font>"
	return ""

/// Whether a part counts towards the tier average: stock parts do, cells don't (their rating is a capacity score)
/proc/part_has_tier(obj/item/part)
	return istype(part, /obj/item/stock_parts) && !istype(part, /obj/item/stock_parts/cell)

/obj/machinery/display_parts(mob/user)
	. = list("<span class='notice'>It contains the following parts:</span>")
	var/list/amounts = list()
	var/list/examples = list()
	for(var/obj/item/part in component_parts)
		var/obj/item/stack/stack = part
		amounts[part.type] += istype(stack) ? stack.get_amount() : 1
		if(!examples[part.type])
			examples[part.type] = part
	for(var/path in amounts)
		var/obj/item/part = examples[path]
		var/amount = amounts[path]
		. += "<span class='notice'>[icon2html(part, user)] [amount > 1 ? "[amount]&times; " : ""][part.name][part_tier_suffix(part)]</span>"
	var/summary = part_tier_summary(user)
	if(summary)
		. += summary
	. = jointext(., "\n")

/// The machine's average part tier, its weakest part, and how many parts the RPED the user holds could upgrade
/obj/machinery/proc/part_tier_summary(mob/user)
	var/tier_total = 0
	var/tier_count = 0
	var/obj/item/stock_parts/weakest
	for(var/obj/item/stock_parts/part in component_parts)
		if(!part_has_tier(part))
			continue
		tier_total += part.rating
		tier_count++
		if(!weakest || part.rating < weakest.rating)
			weakest = part
	if(!tier_count)
		return
	var/average = round(tier_total / tier_count, 0.1)
	. = "<span class='notice'>Average part tier: <font color='[part_tier_color(round(average))]'><b>[average]</b></font>"
	if(weakest.rating < average)
		. += " (weakest: [weakest.name], tier [weakest.rating])"
	. += ".</span>"
	var/obj/item/storage/part_replacer/rped = user?.is_holding_item_of_type(/obj/item/storage/part_replacer)
	if(!rped)
		return
	var/upgrades = rped_upgrade_count(rped)
	if(!upgrades)
		. += "\n<span class='notice'>[rped] has nothing better for it.</span>"
	else if(panel_open || rped.works_from_distance)
		. += "\n<span class='notice'>[rped] can upgrade <b>[upgrades]</b> of its parts.</span>"
	else
		. += "\n<span class='notice'>[rped] could upgrade <b>[upgrades]</b> of its parts: open the maintenance panel to install them.</span>"

/// How many of this machine's parts exchange_parts() would swap for better ones out of the RPED, each RPED part used once
/obj/machinery/proc/rped_upgrade_count(obj/item/storage/part_replacer/rped)
	var/obj/item/circuitboard/machine/board = locate() in component_parts
	if(!board)
		return 0
	var/list/obj/item/spares = rped.contents.Copy()
	for(var/obj/item/part in component_parts)
		var/wanted
		for(var/path in board.req_components)
			if(istype(part, path))
				wanted = path
				break
		if(!wanted || istype(part, /obj/item/stack))
			continue
		for(var/obj/item/spare as anything in spares)
			if(istype(spare, wanted) && spare.get_part_rating() > part.get_part_rating())
				spares -= spare
				.++
				break

/obj/item/storage/part_replacer/examine(mob/user)
	. = ..()
	var/list/by_tier = list()
	var/list/amounts = list()
	var/list/examples = list()
	for(var/obj/item/part in contents)
		amounts[part.type]++
		if(!examples[part.type])
			examples[part.type] = part
		if(part_has_tier(part))
			var/obj/item/stock_parts/stock_part = part
			by_tier["[stock_part.rating]"]++
	if(!length(amounts))
		. += "<span class='notice'>It's empty.</span>"
		return
	if(length(by_tier))
		var/list/tier_counts = list()
		for(var/tier in sortList(by_tier))
			tier_counts += "<font color='[part_tier_color(text2num(tier))]'>[by_tier[tier]]&times; tier [tier]</font>"
		. += "<span class='notice'>It holds [jointext(tier_counts, ", ")].</span>"
	var/list/lines = list()
	for(var/path in amounts)
		var/obj/item/part = examples[path]
		lines += "[amounts[path]]&times; [part.name][part_tier_suffix(part)]"
	. += "<span class='notice'>[jointext(lines, "\n")]</span>"
