// What a bot knows of where things are (the user's rulings, 2026-11-09, the bot world model): what every crewmember knows, what it
// has seen itself, and (later) what it's been told on the radio. Before this, bots found any item anywhere through
// bot_instances_of(), wherever it had got to, as if they could see through walls.
//
// Common knowledge is the station as mapped: an item still on the tile the map put it on (on the floor there, or still in the locker
// or toolbox it came in) is known to everybody, as a player knows Tool Storage has toolboxes. Anything else a bot knows only if it
// has seen it there: a glance round every few seconds (keep_an_eye_out()), and a look inside a locker or box it opens. A thing moved
// since isn't known any more: nobody follows something they can't see.
//
// Gym arenas count what a scenario has laid out by the time it hands the bot its goal as mapped, so the scenarios keep their setups.
// Goals ask through knows_of() and knows_of_inside(); converted so far: acquire_item_type.dm, acquire_tool.dm. Those two also know what
// the vending machines sell (vendors_selling()), as anybody on the crew does.

/// Seen things a bot keeps track of at most (oldest go first)
#define BOT_SEEN_ITEMS_MAX 400

/obj/item
	/// The tile the map put it on: common knowledge while it's still there (in whatever it came in, or not)
	var/tmp/turf/bot_mapped_turf

/obj/item/Initialize(mapload)
	. = ..()
	if(mapload)
		bot_mapped_turf = get_turf(src)

/proc/bot_note_mapped(obj/item/I)
	I.bot_mapped_turf = get_turf(I)

/datum/bot_brain
	/// weakref of a thing it saw -> the tile it saw it on
	var/list/seen_items
	var/next_item_glance = 0

/// World param bot-knowledge=off: every bot knows where everything is, as before 2026-11-09 (for comparisons)
GLOBAL_VAR_INIT(bot_knowledge_off, world.params["bot-knowledge"] == "off")

/// Whether this bot knows where I is: where the map left it, or where it saw it, and still there
/datum/bot_brain/proc/knows_of(obj/item/I)
	if(GLOB.bot_knowledge_off)
		return TRUE
	var/turf/T = get_turf(I)
	if(!T)
		return FALSE
	if(I.bot_mapped_turf == T)
		return TRUE
	var/datum/weakref/W = I.weak_reference
	return W && LAZYACCESS(seen_items, W) == T

/// Something of `type` inside `container` this bot knows is there, or null
/datum/bot_brain/proc/knows_of_inside(atom/container, type)
	for(var/obj/item/I in container)
		if(istype(I, type) && knows_of(I))
			return I
	return null

/datum/bot_brain/proc/note_seen(obj/item/I)
	var/turf/T = get_turf(I)
	if(!T || I.bot_mapped_turf == T)
		return // known to everybody already
	LAZYINITLIST(seen_items)
	var/datum/weakref/W = WEAKREF(I)
	seen_items -= W // to the end: the oldest go first
	seen_items[W] = T
	if(length(seen_items) > BOT_SEEN_ITEMS_MAX)
		seen_items.Cut(1, length(seen_items) - BOT_SEEN_ITEMS_MAX + 1)

/// A look at what's lying about in sight. At most once a second: from keep_an_eye_out(), and before choosing what to fetch.
/datum/bot_brain/proc/glance_at_items()
	if(world.time < next_item_glance || !isturf(owner?.loc))
		return
	next_item_glance = world.time + 1 SECONDS
	for(var/obj/item/I in view(BOT_SIGHT_RANGE, owner))
		note_seen(I)

/// What's inside something it has opened or is going through
/datum/bot_brain/proc/look_inside(atom/container)
	for(var/obj/item/I in container)
		note_seen(I)

/datum/bot_brain/keep_an_eye_out()
	glance_at_items()
	return ..()

/// Opening a locker or crate shows what's in it (it all comes out onto the floor, which the next glance sees too)
/obj/structure/closet/open(mob/living/user)
	var/mob/living/carbon/human/H = user
	if(istype(H) && H.bot_brain)
		H.bot_brain.look_inside(src)
	return ..()

/// The gym: what the arena has in it when the bot gets its goal is the arena's "map"
/datum/bot_scenario/issue_goal()
	if(!goal_attempts && arena_area)
		for(var/turf/T in arena_area)
			for(var/obj/item/I in T.GetAllContents())
				bot_note_mapped(I)
	return ..()

/// On a fetch for one tool in particular (acquire_tool's needed_tool_type) that it still has no way to provide
/datum/bot_brain/proc/needs_specific_tool_still()
	var/datum/bot_goal/acquire_tool/AT = current_goal
	return istype(AT) && AT.needed_tool_type && !can_eventually_provide_tool(AT.needed_tool_type)

// ---------------------------------------------------------------------------------------------
// What everybody knows about the station: what the vending machines sell
// ---------------------------------------------------------------------------------------------
// Anybody after a screwdriver knows the YouTool sells them. What the machine has left is this round's business: that a bot finds out at the
// machine, and remembers for a while.

/// How long it remembers a machine that couldn't give it something (sold out, or it couldn't pay)
#define BOT_SOLD_OUT_MEMORY (20 MINUTES)
/// Buying something takes a moment more than picking it up: counted as this many more tiles of walk
#define BOT_VEND_BOTHER 5

/// "[vendor type] [item type]" -> what a machine of that kind sells of that item type, or FALSE. Going by the machine's own list, which is
/// the same for every one of a kind.
GLOBAL_LIST_EMPTY(bot_vendor_sells)

/datum/bot_brain
	/// "[REF(vendor)] [item type]" -> until when it remembers that machine couldn't give it one
	var/list/sold_out_seen

/// What V sells of `type` (that type itself before a kind of it), going by what's on its front, or null
/proc/bot_vendor_product(obj/machinery/vending/V, type)
	var/key = "[V.type] [type]"
	var/known = GLOB.bot_vendor_sells[key]
	if(isnull(known))
		known = FALSE
		for(var/path in V.products)
			if(path == type)
				known = path
				break
			if(!known && ispath(path, type))
				known = path
		GLOB.bot_vendor_sells[key] = known
	return known || null

/// Machines it knows sell `type`, that weren't out of it when it last tried: each -> how far off, with the bother of buying on top
/datum/bot_brain/proc/vendors_selling(type)
	. = list()
	var/turf/here = get_turf(owner)
	if(!here)
		return
	for(var/obj/machinery/vending/V as anything in bot_instances_of(/obj/machinery/vending))
		if(QDELETED(V) || V.z != here.z || istype(V, /obj/machinery/vending/custom) || (V.stat & (BROKEN|NOPOWER)) || V.panel_open)
			continue
		var/product = bot_vendor_product(V, type)
		if(!product || on_a_shuttle_without_me(V) || !can_afford_from(V, product))
			continue
		if(gym_run && get_area(V) != get_area(owner)) //a Bot Gym bot only uses its own arena's things
			continue
		if(LAZYACCESS(sold_out_seen, "[REF(V)] [type]") > world.time)
			continue
		.[V] = get_dist(owner, V) + BOT_VEND_BOTHER

/// Whether its card would pay for `product` at V: what's in its own account it knows, as anybody does. The price as vend_from() works it out.
/datum/bot_brain/proc/can_afford_from(obj/machinery/vending/V, product)
	if(!V.onstation)
		return TRUE
	var/obj/item/card/id/C = owner.get_idcard(TRUE)
	var/datum/bank_account/account = C?.registered_account
	if(!account)
		return FALSE
	if(account.account_job && account.account_job.paycheck_department == V.payment_department)
		return TRUE
	var/price = V.default_price
	for(var/datum/data/vending_product/R as anything in V.product_records)
		if(R.product_path == product)
			price = R.custom_price || V.default_price
			break
	return account.account_balance >= price

/datum/bot_strategy/buy_item/New(item_type)
	. = ..()
	steps = list(new /datum/bot_step/move_to(), new /datum/bot_step/buy_item(item_type))

/datum/bot_strategy/buy_item/is_feasible(datum/bot_brain/bot)
	return TRUE

/// At the machine: buy one (vend_from(), goals/tend_hydroponics.dm) and take it out of the tray
/datum/bot_step/buy_item
	var/item_type

/datum/bot_step/buy_item/New(item_type)
	src.item_type = item_type

/datum/bot_step/buy_item/execute(datum/bot_brain/bot)
	var/obj/machinery/vending/V = bot.current_goal?.target
	if(!istype(V) || !bot.owner.Adjacent(V))
		return GOAL_STEP_FAIL
	var/product = bot_vendor_product(V, item_type)
	var/obj/item/bought = product && bot.vend_from(V, product)
	if(!bought)
		bot.human_pause(V) //a look down the list for it
		LAZYSET(bot.sold_out_seen, "[REF(V)] [item_type]", world.time + BOT_SOLD_OUT_MEMORY)
		var/left = 0
		for(var/datum/data/vending_product/R as anything in bot.vendor_stock(V, list(product)))
			left += R.amount
		var/obj/item/card/id/C = bot.owner.get_idcard(TRUE)
		var/datum/bank_account/account = C?.registered_account
		bot_log(bot, "[V] had no [item_type] for me ([left] left; [account ? "[account.account_balance] cr" : (C ? "no account" : "no card")]) (bot_knowledge.dm)")
		return GOAL_STEP_FAIL
	return bot.try_pickup_target(bought, TRUE) ? GOAL_STEP_SUCCESS : GOAL_STEP_FAIL

#undef BOT_SOLD_OUT_MEMORY
#undef BOT_VEND_BOTHER
#undef BOT_SEEN_ITEMS_MAX
