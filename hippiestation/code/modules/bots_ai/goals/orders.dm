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

/// A person's ask, or a console's, that the budget hasn't covered yet: nothing else is ordered before it while Cargo saves up
/// (pick_supply_pack(), goals/cargo.dm). Not for anything far past a budget, or one ask would stop Cargo for good.
GLOBAL_DATUM(bot_cargo_saving_for, /datum/bot_request)

#define BOT_CARGO_SAVE_UP_TO 5000

/// What Cargo's budget has to spend once what's already on order is paid for. Orders are charged when the shuttle brings them in,
/// and the balance alone said "on it" to the silver somebody asked for at Science's console with three crates still to be paid for:
/// they were, and the silver never was.
/proc/bot_cargo_spendable(datum/bank_account/budget)
	if(!budget)
		return 0
	. = budget.account_balance
	for(var/datum/supply_order/SO as anything in SSshuttle.shoppinglist)
		if(!SO.paying_account)
			. -= SO.pack.cost

/// Whether an ask came from a person or a console, not a bot's own errand
/proc/bot_cargo_request_for_people(datum/bot_request/R)
	var/mob/living/carbon/human/asker = R.caller_ref?.resolve()
	return !!(R.station_request || !istype(asker) || !asker.bot_brain) //a TRUE or FALSE: it's compared with one

/// The next crate somebody asked for that the budget covers, as the call it came in: people's asks first. The user's silver at
/// Science's console sat behind a toolbox crate, a bot's medical supplies and the rest of the budget in three shifts of six.
/proc/bot_next_cargo_request()
	var/datum/bank_account/budget = SSeconomy.get_dep_account(ACCOUNT_CAR)
	GLOB.bot_cargo_saving_for = null
	for(var/pass in 1 to 2)
		var/datum/bot_request/found = bot_next_cargo_request_of(budget, pass == 1)
		if(found)
			return found
		if(GLOB.bot_cargo_saving_for)
			return null
	return null

/proc/bot_next_cargo_request_of(datum/bank_account/budget, people)
	for(var/datum/bot_request/R as anything in GLOB.bot_cargo_requests.Copy())
		var/datum/supply_pack/P = SSshuttle.supply_packs[R.detail]
		// Somebody's own ask, or a console's, waits for the budget half an hour: the user's silver (2000 credits) at Science's console
		// was "on it" in three shifts out of six and quietly dropped at ten minutes. A bot's own asks come round again anyway.
		var/mob/living/carbon/human/asker = R.caller_ref?.resolve()
		var/keep = (R.station_request || !istype(asker) || !asker.bot_brain) ? 30 MINUTES : 10 MINUTES
		if(world.time > R.made + keep || !P)
			GLOB.bot_cargo_requests -= R
			continue
		if(bot_cargo_request_for_people(R) != people)
			continue
		if(budget && P.cost <= bot_cargo_spendable(budget))
			return R
		if(people && !GLOB.bot_cargo_saving_for && P.cost <= BOT_CARGO_SAVE_UP_TO)
			GLOB.bot_cargo_saving_for = R
	return null

#undef BOT_CARGO_SAVE_UP_TO
