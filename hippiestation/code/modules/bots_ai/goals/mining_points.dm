// Mining points: what a Shaft Miner is paid in, and what it does with them (goals/mining.dm is the digging).
//
//  - the voucher every miner starts with goes to the equipment vendor for a kit (mining/machine_vending.dm, RedeemVoucher()):
//    the shelter capsule and webbing, which a miner would otherwise have to find in a locker.
//  - the redemption machine keeps the points for the ore it's smelted until somebody puts an ID in and presses Claim: the ID
//    out of its slot and into the machine, the button, Eject, and the card back on (ore_redemption ui_act()). Whoever claims
//    gets the lot, as with players.
//  - the vendor takes the card the same way and sells by the points on it. A miner buys the scanner that reads the whole
//    screen first (the locker's reads four tiles), then a first-aid kit for the bites.
//
// The miners dug all shift and never went near either screen: the points sat in the machine and the vouchers in their bags.

/// Points sitting in the redemption machine that are worth the walk round to its screen.
#define BOT_MINER_CLAIM_AT 100
/// After a try at either machine that came to nothing.
#define BOT_MINER_POINTS_REST (5 MINUTES)

/// What a miner spends points on, first to last. It buys the first one it hasn't got and can pay for.
GLOBAL_LIST_INIT(bot_miner_shopping, list(
	/obj/item/t_scanner/adv_mining_scanner,
	/obj/item/storage/firstaid/brute,
))

/datum/bot_brain
	var/mining_points_blocked_until = 0

/// Whether it's carrying one of these already. The locker's scanner is a kind of the advanced one to the game, and isn't one.
/datum/bot_brain/proc/has_mining_gear(path)
	for(var/obj/item/I in owner.GetAllContents(path))
		if(path == /obj/item/t_scanner/adv_mining_scanner && istype(I, /obj/item/t_scanner/adv_mining_scanner/lesser))
			continue
		return TRUE
	return FALSE

/// The nearest equipment vendor that's working, with nobody's card in it, that it can walk to.
/datum/bot_brain/proc/find_mining_vendor()
	var/obj/machinery/mineral/equipment_vendor/best
	var/best_dist
	for(var/obj/machinery/mineral/equipment_vendor/V as anything in bot_instances_of(/obj/machinery/mineral/equipment_vendor))
		if(QDELETED(V) || V.z != owner.z || (V.stat & (BROKEN|NOPOWER)) || V.panel_open || V.inserted_id)
			continue
		if(gym_run && get_area(V) != get_area(owner))
			continue
		var/dist = get_dist(owner, V)
		if(best && dist >= best_dist)
			continue
		if(can_walk_lawfully_to(V))
			best = V
			best_dist = dist
	return best

/// What this miner would buy next with the points on its card, as the vendor's own entry for it, or null.
/datum/bot_brain/proc/next_mining_purchase(obj/machinery/mineral/equipment_vendor/V, obj/item/card/id/card)
	for(var/path in GLOB.bot_miner_shopping)
		if(has_mining_gear(path))
			continue
		for(var/datum/data/mining_equipment/prize as anything in V.prize_list)
			if(prize.equipment_path == path)
				return prize.cost <= card.mining_points ? prize : null //saving up for it: not the next thing down the list instead
	return null

/// Between trips, on the station: the voucher, the points in the machine, and something to spend them on. TRUE if it's off to do one.
/datum/bot_brain/proc/try_mining_points()
	if(world.time < mining_points_blocked_until)
		return FALSE
	var/obj/item/card/id/card = owner.get_idcard(FALSE)
	if(!card)
		return FALSE
	var/obj/item/mining_voucher/voucher = find_carried_tool(/obj/item/mining_voucher)
	var/obj/machinery/mineral/equipment_vendor/V = (voucher || card.mining_points) ? find_mining_vendor() : null
	if(voucher && V && assign_goal(new /datum/bot_goal/redeem_mining_voucher(V)))
		return TRUE
	var/obj/machinery/mineral/ore_redemption/O = find_orm()
	if(O && O.points >= BOT_MINER_CLAIM_AT && !O.inserted_id && assign_goal(new /datum/bot_goal/claim_mining_points(O)))
		return TRUE
	if(V && next_mining_purchase(V, card) && assign_goal(new /datum/bot_goal/buy_mining_gear(V)))
		return TRUE
	return FALSE

// ---------------------------------------------------------------------------------------------
// The voucher
// ---------------------------------------------------------------------------------------------

/datum/bot_goal/redeem_mining_voucher
	lawful = TRUE
	doing = "cashing in my mining voucher"

/datum/bot_goal/redeem_mining_voucher/New(obj/machinery/mineral/equipment_vendor/V)
	. = ..()
	target = V

/datum/bot_goal/redeem_mining_voucher/resolve_target(datum/bot_brain/bot)
	if(QDELETED(target) || !bot.find_carried_tool(/obj/item/mining_voucher))
		target = null

/datum/bot_goal/redeem_mining_voucher/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/mining/S = new
	S.steps = list(new /datum/bot_step/move_to(), new /datum/bot_step/redeem_mining_voucher())
	return list(S)

/datum/bot_goal/redeem_mining_voucher/on_success(datum/bot_brain/bot)
	bot.continue_mining_round()

/datum/bot_goal/redeem_mining_voucher/on_give_up(datum/bot_brain/bot)
	bot.mining_points_blocked_until = world.time + BOT_MINER_POINTS_REST

/// The voucher on the vendor, and the kit taken off the floor in front of it. The list the vendor asks a player to pick from
/// (RedeemVoucher()) is answered here: the capsule and webbing.
/datum/bot_step/redeem_mining_voucher/execute(datum/bot_brain/bot)
	var/obj/machinery/mineral/equipment_vendor/V = bot.current_goal?.target
	var/obj/item/mining_voucher/voucher = bot.find_carried_tool(/obj/item/mining_voucher)
	if(QDELETED(V) || !voucher || !bot.owner.Adjacent(V) || (V.stat & (BROKEN|NOPOWER)))
		return GOAL_STEP_FAIL
	if(!bot.ready_in_hand(voucher))
		return GOAL_STEP_FAIL
	bot.human_pause(V)
	if(QDELETED(V) || QDELETED(voucher) || !bot.owner.Adjacent(V) || voucher.loc != bot.owner)
		return GOAL_STEP_FAIL
	bot.telemetry_ui_action(V, "redeem voucher: Survival Capsule and Explorer's Webbing")
	var/obj/item/storage/belt/mining/vendor/kit = new(V.loc)
	SSblackbox.record_feedback("tally", "mining_voucher_redeemed", 1, "Survival Capsule and Explorer's Webbing")
	qdel(voucher)
	bot_log(bot, "cashed the mining voucher in for [kit]")
	bot_tally("mining vouchers redeemed")
	bot.note_seen(kit) //bot_knowledge.dm: it's just watched it drop
	if(!bot.try_pickup_target(kit, TRUE))
		return GOAL_STEP_FAIL
	// On the belt if there's nothing there: it comes with a shelter capsule in it
	if(!bot.owner.belt && (kit in bot.owner.held_items))
		bot.owner.equip_to_slot_if_possible(kit, ITEM_SLOT_BELT, FALSE, TRUE, TRUE)
	return GOAL_STEP_SUCCESS

// ---------------------------------------------------------------------------------------------
// Claiming
// ---------------------------------------------------------------------------------------------

/datum/bot_goal/claim_mining_points
	lawful = TRUE
	exclusive = TRUE
	doing = "claiming my mining points"

/datum/bot_goal/claim_mining_points/New(obj/machinery/mineral/ore_redemption/O)
	. = ..()
	target = O

/datum/bot_goal/claim_mining_points/resolve_target(datum/bot_brain/bot)
	var/obj/machinery/mineral/ore_redemption/O = target
	if(QDELETED(O) || (O.stat & (BROKEN|NOPOWER)) || O.inserted_id || !bot.owner.get_idcard(FALSE))
		target = null

/datum/bot_goal/claim_mining_points/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/mining/S = new
	S.steps = list(new /datum/bot_step/move_to(), new /datum/bot_step/claim_mining_points())
	return list(S)

/datum/bot_goal/claim_mining_points/on_success(datum/bot_brain/bot)
	bot.continue_mining_round()

/datum/bot_goal/claim_mining_points/on_give_up(datum/bot_brain/bot)
	bot.mining_points_blocked_until = world.time + BOT_MINER_POINTS_REST
	bot.take_card_back(target)

/// Its own card, left in a machine's slot by a step that didn't finish: out and back on. Without it no door opens.
/datum/bot_brain/proc/take_card_back(obj/machinery/mineral/M)
	var/obj/machinery/mineral/ore_redemption/O = M
	var/obj/machinery/mineral/equipment_vendor/V = M
	var/obj/item/card/id/card
	if(istype(O) && O.inserted_id?.registered_name == owner.real_name)
		card = O.inserted_id
		O.inserted_id = null
	else if(istype(V) && V.inserted_id?.registered_name == owner.real_name)
		card = V.inserted_id
		V.inserted_id = null
	if(!card)
		return
	if(!owner.put_in_hands(card))
		card.forceMove(owner.drop_location())
		return
	wear_card(card) //bot_hopping.dm

/// The card in, Claim, Eject, and the card back on: three clicks at the machine's screen.
/datum/bot_step/claim_mining_points/execute(datum/bot_brain/bot)
	var/obj/machinery/mineral/ore_redemption/O = bot.current_goal?.target
	if(QDELETED(O) || !bot.owner.Adjacent(O) || (O.stat & (BROKEN|NOPOWER)) || O.inserted_id)
		return GOAL_STEP_FAIL
	var/obj/item/card/id/card = bot.card_in_hand() //bot_hopping.dm
	if(!card)
		return GOAL_STEP_FAIL
	bot.human_pause(O)
	if(QDELETED(O) || QDELETED(card) || !bot.owner.Adjacent(O) || O.inserted_id || !(card in bot.owner.held_items))
		bot.wear_card(card)
		return GOAL_STEP_FAIL
	bot.telemetry_ui_action(O, "Insert")
	if(!bot.owner.transferItemToLoc(card, O))
		bot.wear_card(card)
		return GOAL_STEP_FAIL
	O.inserted_id = card
	bot.human_pause(O)
	var/claimed = 0
	if(!QDELETED(O) && O.inserted_id == card)
		bot.telemetry_ui_action(O, "Claim")
		claimed = O.points
		card.mining_points += O.points
		O.points = 0
		bot.human_pause(O)
	bot.telemetry_ui_action(O, "Eject")
	bot.take_card_back(O)
	if(bot.owner.get_idcard(FALSE) != card)
		bot_log(bot, "lost hold of my card at [O]")
		return GOAL_STEP_FAIL
	bot_log(bot, "claimed [claimed] mining points - [card.mining_points] on the card")
	bot_tally("mining points claims")
	return claimed ? GOAL_STEP_SUCCESS : GOAL_STEP_FAIL

// ---------------------------------------------------------------------------------------------
// Spending
// ---------------------------------------------------------------------------------------------

/datum/bot_goal/buy_mining_gear
	lawful = TRUE
	exclusive = TRUE
	doing = "spending my mining points"

/datum/bot_goal/buy_mining_gear/New(obj/machinery/mineral/equipment_vendor/V)
	. = ..()
	target = V

/datum/bot_goal/buy_mining_gear/resolve_target(datum/bot_brain/bot)
	var/obj/machinery/mineral/equipment_vendor/V = target
	var/obj/item/card/id/card = bot.owner.get_idcard(FALSE)
	if(QDELETED(V) || (V.stat & (BROKEN|NOPOWER)) || V.inserted_id || !card || !bot.next_mining_purchase(V, card))
		target = null

/datum/bot_goal/buy_mining_gear/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/mining/S = new
	S.steps = list(new /datum/bot_step/move_to(), new /datum/bot_step/buy_mining_gear())
	return list(S)

/datum/bot_goal/buy_mining_gear/on_success(datum/bot_brain/bot)
	bot.continue_mining_round()

/datum/bot_goal/buy_mining_gear/on_give_up(datum/bot_brain/bot)
	bot.mining_points_blocked_until = world.time + BOT_MINER_POINTS_REST
	bot.take_card_back(target)

/// The card in, the purchase, Eject, the card back on, and what it bought picked up from in front of the vendor
/// (equipment_vendor Topic(): the price off the card, and the thing made on the vendor's own tile).
/datum/bot_step/buy_mining_gear/execute(datum/bot_brain/bot)
	var/obj/machinery/mineral/equipment_vendor/V = bot.current_goal?.target
	if(QDELETED(V) || !bot.owner.Adjacent(V) || (V.stat & (BROKEN|NOPOWER)) || V.inserted_id)
		return GOAL_STEP_FAIL
	var/obj/item/card/id/card = bot.card_in_hand()
	if(!card)
		return GOAL_STEP_FAIL
	bot.human_pause(V)
	if(QDELETED(V) || QDELETED(card) || !bot.owner.Adjacent(V) || V.inserted_id || !(card in bot.owner.held_items))
		bot.wear_card(card)
		return GOAL_STEP_FAIL
	bot.telemetry_ui_action(V, "insert")
	if(!bot.owner.transferItemToLoc(card, V))
		bot.wear_card(card)
		return GOAL_STEP_FAIL
	V.inserted_id = card
	bot.human_pause(V)
	var/obj/item/bought
	var/datum/data/mining_equipment/prize = (!QDELETED(V) && V.inserted_id == card) ? bot.next_mining_purchase(V, card) : null
	if(prize)
		bot.telemetry_ui_action(V, "purchase [prize.equipment_name]")
		card.mining_points -= prize.cost
		bought = new prize.equipment_path(V.loc)
		SSblackbox.record_feedback("nested tally", "mining_equipment_bought", 1, list("[V.type]", "[prize.equipment_path]"))
		bot.human_pause(V)
	bot.telemetry_ui_action(V, "eject")
	bot.take_card_back(V)
	if(bot.owner.get_idcard(FALSE) != card)
		bot_log(bot, "lost hold of my card at [V]")
		return GOAL_STEP_FAIL
	if(!bought)
		return GOAL_STEP_FAIL
	bot_log(bot, "bought [bought] for [prize.cost] points - [card.mining_points] left")
	bot_tally("mining gear bought")
	bot.note_seen(bought)
	return bot.try_pickup_target(bought, TRUE) ? GOAL_STEP_SUCCESS : GOAL_STEP_FAIL

#undef BOT_MINER_CLAIM_AT
#undef BOT_MINER_POINTS_REST
