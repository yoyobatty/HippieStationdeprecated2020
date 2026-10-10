// Orders: asking the bartender for a drink, or cargo for supplies, and getting it.
//
// Both are calls like any other (bot_requests.dm) - heard, acknowledged on the channel they came over, and then
// done by the ordinary rounds, which look at what's been asked for before what they'd have made anyway:
//
//  - "can I get a gin and tonic?" at the bar (or over the radio): the bartender says it's coming, mixes that next
//    and says so when it's on the bar. Anything it can't make - "a beer, please" - gets whatever it would have
//    mixed next
//  - "cargo, can we get some metal?": whoever's on the supply console says they'll order it, and the next order
//    that goes in is that crate (goals/cargo.dm), budget allowing

/// Words that make a sentence an order.
GLOBAL_LIST_INIT(bot_order_words, list("can i get", "could i get", "can i have", "could i have", "can we get", "could we get", "can you get",
	"i'll have", "ill have", "i will have", "i'd like", "id like", "give me", "gimme", "get me", "please", "pls", "plz", "order", "need"))

/// Other things people call the drinks on the menu.
GLOBAL_LIST_INIT(bot_drink_aliases, list(
	"g&t" = /datum/bot_drink/gin_tonic, "gin tonic" = /datum/bot_drink/gin_tonic, "gin & tonic" = /datum/bot_drink/gin_tonic,
	"rum & coke" = /datum/bot_drink/rum_coke, "rum and cola" = /datum/bot_drink/rum_coke, "cuba libre" = /datum/bot_drink/rum_coke,
	"whiskey and cola" = /datum/bot_drink/whiskey_cola, "whiskey coke" = /datum/bot_drink/whiskey_cola, "whiskey and coke" = /datum/bot_drink/whiskey_cola,
	"vodka orange" = /datum/bot_drink/screwdriver, "vodka and orange" = /datum/bot_drink/screwdriver,
))

/// The drink on the bar's menu that a line names, if it names one.
/proc/bot_drink_named(lower_msg)
	for(var/datum/bot_drink/D as anything in GLOB.bot_bar_menu)
		if(findtext(lower_msg, D.name))
			return D
	for(var/alias in GLOB.bot_drink_aliases)
		if(findtext(lower_msg, alias))
			return locate(GLOB.bot_drink_aliases[alias]) in GLOB.bot_bar_menu
	return null

/datum/bot_request_kind/bar_order
	name = "bar order"
	jobs = list("Bartender")
	role_words = list("bartender", "barkeep", "barman", "barmaid")
	ack_lines = list("Coming right up.", "One moment.", "Sure thing.", "Coming up.")
	doing = "mixing an order"
	walks_there = FALSE
	needs_place = FALSE

/datum/bot_request_kind/bar_order/matches(lower_msg, named, turf/near)
	if(!bot_text_has_any(lower_msg, GLOB.bot_order_words))
		return FALSE
	return bot_drink_named(lower_msg) || bot_text_has_any(lower_msg, role_words + list("a drink", "something to drink", "a beer", "a pint", "a cocktail"))

/datum/bot_request_kind/bar_order/read_details(datum/bot_request/R, lower_msg)
	R.detail = bot_drink_named(lower_msg)

/datum/bot_request_kind/bar_order/attend(datum/bot_brain/bot, datum/bot_request/R)
	LAZYADD(bot.bar_orders, R)
	if(bot.state == BOT_STATE_WANDER)
		bot.continue_bar_round()

/datum/bot_brain
	/// Drinks people have asked for and not had yet, as the calls they came in (bot_request.detail is the drink).
	var/list/bar_orders

/// The next order worth mixing: asked for in the last few minutes, by somebody who's still about.
/datum/bot_brain/proc/next_bar_order()
	while(length(bar_orders))
		var/datum/bot_request/R = bar_orders[1]
		var/mob/living/who = R.caller_ref?.resolve()
		if(world.time <= R.made + 6 MINUTES && who && who.stat != DEAD)
			return R
		bar_orders -= R
	return null

/// What cargo calls each of the crates it can be asked for.
GLOBAL_LIST_INIT(bot_cargo_order_words, list(
	"metal" = /datum/supply_pack/materials/metal50, "steel" = /datum/supply_pack/materials/metal50,
	"glass" = /datum/supply_pack/materials/glass50,
	"tools" = /datum/supply_pack/engineering/tools, "toolbox" = /datum/supply_pack/engineering/tools, "toolboxes" = /datum/supply_pack/engineering/tools,
	"internals" = /datum/supply_pack/emergency/internals, "oxygen" = /datum/supply_pack/emergency/internals, "air tanks" = /datum/supply_pack/emergency/internals,
	"janitor" = /datum/supply_pack/service/janitor, "cleaning" = /datum/supply_pack/service/janitor, "mop" = /datum/supply_pack/service/janitor, "mops" = /datum/supply_pack/service/janitor,
	"food" = /datum/supply_pack/organic/food,
	"medical" = /datum/supply_pack/medical/supplies, "medkits" = /datum/supply_pack/medical/supplies, "first aid" = /datum/supply_pack/medical/supplies, "medicine" = /datum/supply_pack/medical/supplies,
))
/// Crates somebody has asked cargo for, not ordered yet: the calls they came in (bot_request.detail is the pack type).
GLOBAL_LIST_EMPTY(bot_cargo_requests)

/proc/bot_supply_pack_named(lower_msg)
	var/asked
	for(var/word in GLOB.bot_cargo_order_words)
		if(bot_text_has_any(lower_msg, list(word)) && (!asked || length(word) > length(asked)))
			asked = word
	return asked ? GLOB.bot_cargo_order_words[asked] : null

/datum/bot_request_kind/cargo_order
	name = "supply order"
	jobs = list("Quartermaster", "Cargo Technician")
	role_words = list("cargo", "quartermaster", "qm", "supply")
	ack_lines = list("Sure, I'll put the order in.", "On it - ordering now.", "Can do, give it a few minutes.", "I'll get that ordered.")
	doing = "seeing to an order somebody asked for"
	walks_there = FALSE
	needs_place = FALSE

/datum/bot_request_kind/cargo_order/matches(lower_msg, named, turf/near)
	return bot_text_has_any(lower_msg, role_words) && bot_text_has_any(lower_msg, GLOB.bot_order_words) && bot_supply_pack_named(lower_msg)

/datum/bot_request_kind/cargo_order/read_details(datum/bot_request/R, lower_msg)
	R.detail = bot_supply_pack_named(lower_msg)

/datum/bot_request_kind/cargo_order/attend(datum/bot_brain/bot, datum/bot_request/R)
	GLOB.bot_cargo_requests |= R
	if(bot.state == BOT_STATE_WANDER)
		bot.continue_cargo_round()

/// The next crate somebody asked for that the budget covers, as the call it came in.
/proc/bot_next_cargo_request()
	var/datum/bank_account/budget = SSeconomy.get_dep_account(ACCOUNT_CAR)
	for(var/datum/bot_request/R as anything in GLOB.bot_cargo_requests)
		var/datum/supply_pack/P = SSshuttle.supply_packs[R.detail]
		if(world.time > R.made + 10 MINUTES || !P)
			GLOB.bot_cargo_requests -= R
			continue
		if(budget && P.cost <= budget.account_balance)
			return R
	return null
