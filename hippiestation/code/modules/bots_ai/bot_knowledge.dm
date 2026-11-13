// What a bot knows of where things are (the user's rulings, 2026-11-09, the bot world model): what every crewmember knows, what it
// has seen itself, and (later) what it's been told on the radio. Before this, bots found any item anywhere through
// bot_instances_of(), wherever it had got to, as if they could see through walls.
//
// Common knowledge is the station as mapped: an item still on the tile the map put it on (on the floor there, or still in the locker
// or toolbox it came in) is known to everybody, as a player knows Tool Storage has toolboxes. Anything else a bot knows only if it
// has seen it there: a glance round every few seconds (keep_an_eye_out()), and a look inside a locker or box it opens. A thing moved
// since isn't known any more: nobody follows something they can't see.
//
// Gym arenas count what a scenario has laid out by the time the bot arrives as mapped, so the scenarios keep their setups.
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

/// For a lookup in its own workplace: what it knows of, or anything in the room it's stood in, which it can look round. A bartender
/// in a bar wider than its screen went to the Booze-O-Mat for glasses with empties at the far end of the bar (mix_drink gave up 86 ->
/// 200 times in twelve shifts on knows_of() alone).
/datum/bot_brain/proc/knows_of_in_room(obj/item/I)
	return knows_of(I) || get_area(I) == get_area(owner)

/// Something of `type` inside `container` this bot knows is there, or null
/datum/bot_brain/proc/knows_of_inside(atom/container, type)
	for(var/obj/item/I in container)
		if(istype(I, type) && knows_of(I))
			return I
	return null

/// It saw I, or was told it's on T (tell_where_seen())
/datum/bot_brain/proc/note_seen(obj/item/I, turf/T)
	T = T || get_turf(I)
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
	var/list/contraband_types = GLOB.bot_contraband
	for(var/obj/item/I in view(BOT_SIGHT_RANGE, owner))
		// Still where the map put it: known to everybody, and nothing for note_seen() to do. Asked here, as that's most of what's in
		// sight and it was a proc call for each. Anything else is noted as before, in the same order.
		var/turf/T = get_turf(I)
		if(T && I.bot_mapped_turf != T)
			note_seen(I, T)
		if(contraband_types[I.type] && isturf(I.loc))
			loose_contraband = WEAKREF(I) //a traitor's kit lying about: kept by the kinds that would (pocket_loose_contraband(), bot_playstyles.dm)

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

/// The gym: what the arena has in it when the bot arrives is the arena's "map". At the spawn, not the first goal: a duty scenario's
/// issue_goal() doesn't call its parent, and nothing else overrides spawn_bot().
/datum/bot_scenario/spawn_bot()
	if(arena_area)
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

/// Kinds the game files under a type that nobody would take for one. A bottle of water is a beaker to the game, and every drinks
/// machine sells them: chemists with no beaker went and bought one, 56 times in 12 shifts, found it full of water, and gave the
/// brew up.
GLOBAL_LIST_INIT(bot_kinds_in_name_only, list(
	/obj/item/reagent_containers/glass/beaker = list(/obj/item/reagent_containers/glass/beaker/waterbottle),
	// The Warden went to the armory for "something heavier" with three nanosuits loose and came back with a practice laser (2026-11-10)
	/obj/item/gun/energy/laser = list(/obj/item/gun/energy/laser/practice, /obj/item/gun/energy/laser/bluetag, /obj/item/gun/energy/laser/redtag),
))

/// Something of `type` it's carrying that counts as one (bot_counts_as()): a practice laser isn't a laser
/datum/bot_brain/proc/carries_real(type)
	for(var/obj/item/I in owner.GetAllContents())
		if(istype(I, type) && bot_counts_as(I.type, type))
			return I
	return null

/// Whether something of this path is what anybody asking for a `type` means
/proc/bot_counts_as(path, type)
	for(var/not_one in GLOB.bot_kinds_in_name_only[type])
		if(ispath(path, not_one))
			return FALSE
	return TRUE

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
			if(!known && ispath(path, type) && bot_counts_as(path, type))
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

// ---------------------------------------------------------------------------------------------
// Asking around
// ---------------------------------------------------------------------------------------------
// Nothing it knows of to get: now and then it asks on the radio, and a bot that's seen one says where, as players tell each other.
// Players ask too ("anyone seen a crowbar?"): a bot that knows of one, kept or seen, or a machine that sells them, tells them.

/// Before it asks after the same thing again
#define BOT_ASK_WHERE_REST (20 MINUTES)
/// Between anybody's asks, station-wide, so the common channel isn't all "anyone seen a..."
#define BOT_ASK_WHERE_QUIET (3 MINUTES)

GLOBAL_VAR_INIT(bot_last_where_ask, 0)
/// "[REF(asker)] [item type]" -> until when that question has had its answer
GLOBAL_LIST_EMPTY(bot_where_answered)

/datum/bot_brain
	/// item type -> when it may ask after one again
	var/list/asked_where

/datum/bot_brain/proc/has_headset()
	return istype(owner?.ears, /obj/item/radio/headset)

/// "a crowbar", "an emergency toolbox", "any insulated gloves"
/proc/bot_some(what)
	var/static/regex/plural = regex("(gloves|cuffs|cutters|zipties|restraints|goggles|glasses)$")
	if(plural.Find(what))
		return "any [what]"
	return (lowertext(copytext(what, 1, 2)) in list("a", "e", "i", "o", "u")) ? "an [what]" : "a [what]"

/// Where a fetch finds nothing it knows of: "anyone seen a crowbar?" on the radio. A bot that's seen one says where in a few seconds.
/datum/bot_brain/proc/ask_where(item_type)
	if(GLOB.bot_knowledge_off || QDELETED(owner) || owner.stat != CONSCIOUS || !has_headset() || gone_loud())
		return FALSE
	if(LAZYACCESS(asked_where, item_type) > world.time)
		return FALSE
	if(!gym_run && world.time < GLOB.bot_last_where_ask + BOT_ASK_WHERE_QUIET)
		return FALSE
	LAZYSET(asked_where, item_type, world.time + BOT_ASK_WHERE_REST)
	if(!gym_run) //arenas run side by side: one arena's ask doesn't quieten another's
		GLOB.bot_last_where_ask = world.time
	var/obj/item/kind = item_type
	var/what = bot_some(initial(kind.name))
	var/question = ";" + pick("Anyone seen [what] about?", "Has anybody got [what] going spare?", "Where can I get [what]?")
	say_after_typing(question)
	bot_log(src, "asked on the radio after [item_type] (bot_knowledge.dm)")
	bot_tally("asked where something is")
	for(var/datum/bot_brain/B as anything in shuffle(GLOB.bot_brains.Copy()))
		if(B == src || QDELETED(B.owner) || B.owner.stat != CONSCIOUS || B.owner.z != owner.z || !B.has_headset() || B.gym_run != gym_run || B.gone_loud())
			continue
		var/list/seen = B.where_seen(item_type)
		if(seen)
			addtimer(CALLBACK(B, PROC_REF(tell_where_seen), src, seen[1], seen[2]), bot_typing_time(question) + rand(2, 6) SECONDS) //once it's been asked
			break
	return TRUE

/// The last thing of `type` it saw lying about and still knows of (knows_of()), and where: list(item, turf), or null. Answering with
/// whatever it had ever seen, 235 of 244 asks in twelve shifts got an answer, and three bots could use one: the thing had moved on.
/datum/bot_brain/proc/where_seen(type)
	for(var/i in length(seen_items) to 1 step -1)
		var/datum/weakref/W = seen_items[i]
		var/obj/item/I = W?.resolve() //an entry can go null under it
		if(istype(I, type) && knows_of(I) && !ismob(bot_outermost_holder(I)))
			return list(I, seen_items[W])
	return null

/// The answer to somebody's ask_where(): said on the radio, and the asker knows it from then on
/datum/bot_brain/proc/tell_where_seen(datum/bot_brain/asker, obj/item/I, turf/T)
	if(QDELETED(owner) || owner.stat != CONSCIOUS || QDELETED(asker) || QDELETED(I) || !T)
		return
	var/where = get_area_name(T, TRUE)
	var/answer = ";" + pick("Saw one in [where] a while back.", "There was one in [where].", "Try [where], I saw one there.")
	say_after_typing(answer)
	addtimer(CALLBACK(asker, PROC_REF(told_where), I, T), bot_typing_time(answer) + 1 SECONDS) //once it's been said

/datum/bot_brain/proc/told_where(obj/item/I, turf/T)
	if(QDELETED(owner) || owner.stat != CONSCIOUS || QDELETED(I))
		return
	note_seen(I, T)
	bot_log(src, "told there's [I] in [get_area_name(T, TRUE)] (bot_knowledge.dm)")
	if(state != BOT_STATE_WANDER || current_goal || !knows_of(I))
		return //busy, or it's moved since: what it was told is no use now, and it can't know that till it gets there
	var/datum/bot_goal/acquire_item_type/G = new
	G.item_type = I.type
	G.lawful = TRUE
	if(assign_goal(G))
		say_after_typing(";" + pick("Thanks.", "Cheers.", "Ta, on my way."))

/// Words that start a question about where to get something
GLOBAL_LIST_INIT(bot_where_to_get_words, list("anyone seen", "anybody seen", "has anyone seen", "where can i get", "where can i find", "where do i get",
	"where do i find", "where's a", "wheres a", "where is a", "anyone got a", "anyone got an", "anybody got a", "does anyone have", "anyone have a"))

/// The item a question names, or null: the tools people borrow (bot_tool_words, bot_chatter.dm) and a few more
/proc/bot_item_asked_after(lower_msg)
	var/static/list/words
	if(!words)
		words = GLOB.bot_tool_words.Copy()
		words["flash"] = /obj/item/assembly/flash/handheld
		words["first aid kit"] = /obj/item/storage/firstaid
		words["first-aid kit"] = /obj/item/storage/firstaid
		words["medkit"] = /obj/item/storage/firstaid
		words["handcuffs"] = /obj/item/restraints/handcuffs
		words["cuffs"] = /obj/item/restraints/handcuffs
		words["gas mask"] = /obj/item/clothing/mask/gas
		words["toolbelt"] = /obj/item/storage/belt/utility
		words["tool belt"] = /obj/item/storage/belt/utility
		words["toolbox"] = /obj/item/storage/toolbox
		words["oxygen tank"] = /obj/item/tank/internals/oxygen
		words["jetpack"] = /obj/item/tank/jetpack
		words["fire axe"] = /obj/item/twohanded/fireaxe
	for(var/word in words)
		if(bot_text_word_at(lower_msg, word))
			return words[word]
	return null

/// "Anyone seen a crowbar?" from a player: where it knows of one, nearest them, or a machine that sells them. One bot answers.
/datum/bot_brain/proc/answer_where_to_get(mob/living/talker, lower_msg, radio_freq)
	if(GLOB.bot_knowledge_off || !bot_text_has_any(lower_msg, GLOB.bot_where_to_get_words))
		return FALSE
	var/item_type = bot_item_asked_after(lower_msg)
	if(!item_type)
		return FALSE
	var/key = "[REF(talker)] [item_type]"
	if(GLOB.bot_where_answered[key] > world.time)
		return TRUE //somebody's told them
	var/turf/near = get_turf(talker)
	if(!near)
		return FALSE
	var/atom/best
	var/best_dist
	for(var/obj/item/I as anything in bot_instances_of(item_type))
		var/atom/movable/holder = bot_outermost_holder(I)
		if(QDELETED(I) || ismob(holder) || holder.z != near.z || !knows_of(I))
			continue
		var/dist = get_dist(near, holder)
		if(!best || dist < best_dist)
			best = I
			best_dist = dist
	for(var/obj/machinery/vending/V as anything in bot_instances_of(/obj/machinery/vending))
		if(QDELETED(V) || V.z != near.z || istype(V, /obj/machinery/vending/custom) || !bot_vendor_product(V, item_type))
			continue
		var/dist = get_dist(near, V) + BOT_VEND_BOTHER
		if(!best || dist < best_dist)
			best = V
			best_dist = dist
	if(!best)
		return FALSE //nothing it knows of: somebody else may
	GLOB.bot_where_answered[key] = world.time + 30 SECONDS
	var/where = get_area_name(best, TRUE)
	var/answer = istype(best, /obj/machinery/vending) ? "[best] in [where] sells them." : pick("There's one in [where].", "Try [where].", "[where] had one, last I saw.")
	say_after_typing(bot_radio_prefix(radio_freq) + answer)
	return TRUE

#undef BOT_ASK_WHERE_REST
#undef BOT_ASK_WHERE_QUIET
#undef BOT_SOLD_OUT_MEMORY
#undef BOT_VEND_BOTHER
#undef BOT_SEEN_ITEMS_MAX
