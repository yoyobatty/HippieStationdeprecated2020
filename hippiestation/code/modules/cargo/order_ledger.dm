// Order ledger: shipped orders already pile up in SSshuttle.orderhistory, but nothing ever showed them. This records who put
// each order on the shuttle, what it actually cost, whose account paid and when it shipped, and shows the lot on the cargo
// console's History tab and on the quartermaster's PDA cartridge. Express console orders go in it too.

/// How many shipped orders the cargo console lists, newest first
#define ORDER_LEDGER_CONSOLE_ROWS 50

/datum/supply_order
	/// Who put the order on the shuttle: the orderer at a full cargo console, or whoever approved their request
	var/approved_by
	/// Credits actually charged when it shipped (private orders carry cargo's handling fee on top of the pack's cost)
	var/charged
	/// Whose account paid: "Cargo budget", or the holder of the private or departmental card it was charged to
	var/paid_by
	/// How it arrived: the supply shuttle or an express pod
	var/delivery
	/// Station time it shipped at
	var/shipped_at

/datum/supply_order/proc/record_shipment(paid_by, charged, delivery, approved_by)
	src.paid_by = paid_by
	src.charged = round(charged)
	src.delivery = delivery
	if(approved_by)
		src.approved_by = approved_by
	shipped_at = station_time_timestamp("hh:mm")

/datum/supply_order/proc/ledger_entry()
	return list(
		"id" = id,
		"object" = pack.name,
		"cost" = charged,
		"orderer" = orderer,
		"orderer_rank" = orderer_rank,
		"reason" = reason,
		"paid_by" = paid_by,
		"approved_by" = approved_by,
		"delivery" = delivery,
		"shipped_at" = shipped_at
	)

/// The newest shipped orders first, as ledger entries
/proc/cargo_order_ledger(count)
	. = list()
	var/list/history = SSshuttle.orderhistory
	for(var/i in length(history) to max(1, length(history) - count + 1) step -1)
		var/datum/supply_order/order = history[i]
		. += list(order.ledger_entry())

/// "Name (Assignment)" of whoever is working a cargo console, for the ledger
/proc/cargo_ledger_signature(mob/user)
	if(ishuman(user))
		var/mob/living/carbon/human/H = user
		return "[H.get_authentification_name()] ([H.get_assignment(hand_first = TRUE)])"
	if(issilicon(user))
		return "[user.real_name] (Silicon)"
	return "[user]"

/obj/machinery/computer/cargo/ui_act(action, params, datum/tgui/ui)
	var/list/queued_before = SSshuttle.shoppinglist.Copy()
	. = ..()
	// Anything this console put on the shuttle - a direct order, an approved request, a self-paid order - is signed for by whoever did it
	for(var/datum/supply_order/order as anything in SSshuttle.shoppinglist - queued_before)
		if(!order.approved_by)
			order.approved_by = cargo_ledger_signature(usr)

/obj/machinery/computer/cargo/ui_data()
	. = ..()
	if(!requestonly)
		.["history"] = cargo_order_ledger(ORDER_LEDGER_CONSOLE_ROWS)

#undef ORDER_LEDGER_CONSOLE_ROWS
