// Department samples, the second research piece (the first is experiments.dm). Science keeps a board of open requests for
// things only the other departments make or find: a crop bred to a potency, ore or sheets, a trophy off Lavaland, an organ
// or blood, a reagent, a tank of gas, a dish. Hand one in at R&D (put it in the destructive analyzer, Hand in on the
// console) or ship it through Cargo, and it pays research points; shipped, Cargo gets a fee too. Partial loads count
// towards the ones that want a number of something. A filled request is replaced a little later and an unfilled one after
// half an hour, and each new one is called out on its department's radio. Shown on the R&D console's Samples tab and the
// experiment scanner (tgui-next RdConsole.js, Experiments.js). The user left research's design to me, 2026-11-06.

#define SAMPLE_BOARD_SIZE 5
/// The board opens this long into the round
#define SAMPLE_OPEN_DELAY (3 MINUTES)
/// A filled request's replacement comes this much later
#define SAMPLE_REFILL_DELAY (2 MINUTES)
/// An unfilled request is swapped for another after this
#define SAMPLE_LIFETIME (30 MINUTES)
/// What Cargo gets for shipping one
#define SAMPLE_SHIPPING_FEE 250
/// Filled ones the windows list
#define SAMPLE_HISTORY 6

GLOBAL_DATUM_INIT(sample_board, /datum/sample_board, new)

/// "a" or "an", by the first letter
/proc/sample_article(text)
	return (lowertext(copytext(text, 1, 2)) in list("a", "e", "i", "o", "u")) ? "an" : "a"

// The requests

/datum/sample_request
	var/kind = "sample"
	/// Who it's for, as the windows say it
	var/department = "Station"
	/// Where it's called out
	var/channel = RADIO_CHANNEL_SCIENCE
	var/name = "a sample"
	var/reward = 3000
	/// How many of it (sheets, units, moles), and how many are in
	var/needed = 1
	var/got = 0
	var/unit = ""
	var/opened_at = 0
	var/closed_at = 0
	/// "R&D" or "Cargo"; null while open, "expired" if it ran out
	var/filled_via
	var/filled_by

/// Picks what this one wants
/datum/sample_request/proc/setup()
	return

/// How much of what's still wanted the thing would give: 0 if it's no good
/datum/sample_request/proc/amount_in(obj/O)
	return 0

/// Uses up that much of it
/datum/sample_request/proc/take(obj/O, amount)
	qdel(O)

/datum/sample_request/proc/left()
	return max(0, needed - got)

/// For whole things: one, if it's the thing
/datum/sample_request/proc/one_if(matches)
	return (matches && left()) ? 1 : 0

/// For stacks: what the stack has, up to what's still wanted
/datum/sample_request/proc/from_stack(obj/item/stack/S)
	return min(S.amount, left())

/datum/sample_request/proc/take_stack(obj/item/stack/S, amount)
	S.use(amount)

// Botany: a crop of one kind bred to a potency

/datum/sample_request/botany
	kind = "botany"
	department = "Botany"
	channel = RADIO_CHANNEL_SERVICE
	var/seed_type
	var/potency

/datum/sample_request/botany/setup()
	// Seeds the vendor sells, whose crop is food (and one there is: garlic's had none)
	var/list/seeds = list()
	for(var/path in list(/obj/item/seeds/tomato, /obj/item/seeds/wheat, /obj/item/seeds/potato, /obj/item/seeds/carrot, /obj/item/seeds/apple,
		/obj/item/seeds/corn, /obj/item/seeds/chili, /obj/item/seeds/cabbage, /obj/item/seeds/eggplant, /obj/item/seeds/grape,
		/obj/item/seeds/watermelon, /obj/item/seeds/soya, /obj/item/seeds/pumpkin, /obj/item/seeds/banana, /obj/item/seeds/berry,
		/obj/item/seeds/cocoapod, /obj/item/seeds/lemon, /obj/item/seeds/orange, /obj/item/seeds/sugarcane, /obj/item/seeds/cherry,
		/obj/item/seeds/onion, /obj/item/seeds/pineapple, /obj/item/seeds/garlic))
		var/obj/item/seeds/candidate = path
		if(ispath(initial(candidate.product), /obj/item/reagent_containers/food/snacks/grown))
			seeds += path
	seed_type = pick(seeds)
	potency = pick(40, 50, 60)
	reward = 2500 + (potency - 40) * 100
	var/obj/item/seeds/S = seed_type
	var/obj/crop = initial(S.product)
	var/crop_name = initial(crop.name)
	name = "[sample_article(crop_name)] [crop_name] of potency [potency]+"

/datum/sample_request/botany/amount_in(obj/O)
	var/obj/item/reagent_containers/food/snacks/grown/G = O
	return one_if(istype(G) && G.seed && G.seed.type == seed_type && G.seed.potency >= potency)

// Kitchen: a dish

/datum/sample_request/kitchen
	kind = "kitchen"
	department = "Kitchen"
	channel = RADIO_CHANNEL_SERVICE
	reward = 2500
	var/dish

/datum/sample_request/kitchen/setup()
	// Whole ones: a pizza, cake or loaf, not a slice
	var/list/dishes = list(
		/obj/item/reagent_containers/food/snacks/burger/plain = "a burger",
		/obj/item/reagent_containers/food/snacks/pizza/margherita = "a whole pizza margherita",
		/obj/item/reagent_containers/food/snacks/store/cake/plain = "a whole vanilla cake",
		/obj/item/reagent_containers/food/snacks/pie/cream = "a banana cream pie",
		/obj/item/reagent_containers/food/snacks/soup/tomato = "a bowl of tomato soup",
		/obj/item/reagent_containers/food/snacks/store/bread/plain = "a loaf of bread",
		/obj/item/reagent_containers/food/snacks/spaghetti/pastatomato = "a plate of spaghetti",
		/obj/item/reagent_containers/food/snacks/salad/validsalad = "a valid salad",
		/obj/item/reagent_containers/food/snacks/pancakes = "a pancake",
		/obj/item/reagent_containers/food/snacks/burrito = "a burrito",
		/obj/item/reagent_containers/food/snacks/soup/meatball = "a bowl of meatball soup")
	dish = pick(dishes)
	name = dishes[dish]

/datum/sample_request/kitchen/amount_in(obj/O)
	return one_if(O.type == dish)

// Mining: so many sheets or ore of a material

/datum/sample_request/mining
	kind = "mining"
	department = "Mining"
	channel = RADIO_CHANNEL_SUPPLY
	var/sheet_type
	var/ore_type

/datum/sample_request/mining/setup()
	var/list/choice = pick(
		list("uranium", /obj/item/stack/sheet/mineral/uranium, /obj/item/stack/ore/uranium, 10, 4000),
		list("diamond", /obj/item/stack/sheet/mineral/diamond, /obj/item/stack/ore/diamond, 5, 5000),
		list("gold", /obj/item/stack/sheet/mineral/gold, /obj/item/stack/ore/gold, 10, 3500),
		list("silver", /obj/item/stack/sheet/mineral/silver, /obj/item/stack/ore/silver, 10, 3500),
		list("titanium", /obj/item/stack/sheet/mineral/titanium, /obj/item/stack/ore/titanium, 10, 4000),
		list("plasma", /obj/item/stack/sheet/mineral/plasma, /obj/item/stack/ore/plasma, 20, 3000),
		list("bluespace crystal", /obj/item/stack/sheet/bluespace_crystal, /obj/item/stack/ore/bluespace_crystal, 3, 6000))
	sheet_type = choice[2]
	ore_type = choice[3]
	needed = choice[4]
	reward = choice[5]
	name = "[needed] [choice[1]], sheets or ore"

/datum/sample_request/mining/amount_in(obj/O)
	if(istype(O, sheet_type) || istype(O, ore_type))
		return from_stack(O)
	return 0

/datum/sample_request/mining/take(obj/O, amount)
	take_stack(O, amount)

// Lavaland: something off its fauna

/datum/sample_request/lavaland
	kind = "lavaland"
	department = "Lavaland" // miners, but told apart from the ore on the board
	channel = RADIO_CHANNEL_SUPPLY
	var/want

/datum/sample_request/lavaland/setup()
	var/list/choice = pick(
		list("goliath hide plates", /obj/item/stack/sheet/animalhide/goliath_hide, 3, 4500),
		list("watcher sinew", /obj/item/stack/sheet/sinew, 3, 4000),
		list("bones", /obj/item/stack/sheet/bone, 5, 3500),
		list("a legion's regenerative core", /obj/item/organ/regenerative_core, 1, 5000))
	want = choice[2]
	needed = choice[3]
	reward = choice[4]
	name = needed > 1 ? "[needed] [choice[1]]" : choice[1]

/datum/sample_request/lavaland/amount_in(obj/O)
	if(!istype(O, want))
		return 0
	return istype(O, /obj/item/stack) ? from_stack(O) : one_if(TRUE)

/datum/sample_request/lavaland/take(obj/O, amount)
	if(istype(O, /obj/item/stack))
		take_stack(O, amount)
	else
		qdel(O)

// Medical: an organ, or blood of a type

/datum/sample_request/medical
	kind = "medical"
	department = "Medical"
	channel = RADIO_CHANNEL_MEDICAL
	var/organ_slot
	var/blood_type

/datum/sample_request/medical/setup()
	if(prob(35))
		blood_type = pick("A+", "A-", "B+", "B-", "AB+", "AB-", "O+", "O-")
		needed = 50
		unit = "u"
		reward = 2500
		name = "50u of [blood_type] blood"
		return
	var/list/choice = pick(
		list(ORGAN_SLOT_HEART, "a heart"),
		list(ORGAN_SLOT_LUNGS, "a pair of lungs"),
		list(ORGAN_SLOT_LIVER, "a liver"),
		list(ORGAN_SLOT_STOMACH, "a stomach"),
		list(ORGAN_SLOT_EYES, "a pair of eyes"),
		list(ORGAN_SLOT_TONGUE, "a tongue"),
		list(ORGAN_SLOT_APPENDIX, "an appendix"))
	organ_slot = choice[1]
	name = choice[2]
	reward = 3000

/datum/sample_request/medical/amount_in(obj/O)
	if(blood_type)
		if(!istype(O, /obj/item/reagent_containers) || istype(O, /obj/item/reagent_containers/food) || !O.reagents)
			return 0
		var/datum/reagent/blood/B = locate() in O.reagents.reagent_list
		if(!B || !B.data || B.data["blood_type"] != blood_type)
			return 0
		return min(round(B.volume), left())
	var/obj/item/organ/organ = O
	return one_if(istype(organ) && !istype(organ, /obj/item/organ/alien) && organ.slot == organ_slot && organ.status == ORGAN_ORGANIC)

/datum/sample_request/medical/take(obj/O, amount)
	if(blood_type)
		O.reagents.remove_reagent(/datum/reagent/blood, amount)
	else
		qdel(O)

// Chemistry: so many units of a medicine

/datum/sample_request/chemistry
	kind = "chemistry"
	department = "Chemistry"
	channel = RADIO_CHANNEL_MEDICAL
	needed = 30
	unit = "u"
	var/reagent

/datum/sample_request/chemistry/setup()
	var/list/choice = pick(
		list(/datum/reagent/medicine/bicaridine, 3000), list(/datum/reagent/medicine/kelotane, 3000),
		list(/datum/reagent/medicine/charcoal, 3000), list(/datum/reagent/medicine/salglu_solution, 3000),
		list(/datum/reagent/medicine/epinephrine, 3000), list(/datum/reagent/medicine/salbutamol, 4000),
		list(/datum/reagent/medicine/mannitol, 4000), list(/datum/reagent/medicine/oxandrolone, 4000),
		list(/datum/reagent/medicine/pen_acid, 4000), list(/datum/reagent/medicine/perfluorodecalin, 4000),
		list(/datum/reagent/medicine/cryoxadone, 4500))
	reagent = choice[1]
	reward = choice[2]
	var/datum/reagent/R = reagent
	name = "30u of [initial(R.name)]"

/datum/sample_request/chemistry/amount_in(obj/O)
	if(!istype(O, /obj/item/reagent_containers) || istype(O, /obj/item/reagent_containers/food) || !O.reagents)
		return 0
	return min(round(O.reagents.get_reagent_amount(reagent)), left())

/datum/sample_request/chemistry/take(obj/O, amount)
	O.reagents.remove_reagent(reagent, amount)

// Atmospherics: moles of a gas, in a tank or a canister

/datum/sample_request/atmos
	kind = "atmos"
	department = "Atmospherics"
	channel = RADIO_CHANNEL_ENGINEERING
	unit = " mol"
	var/gas

/datum/sample_request/atmos/setup()
	// The common ones twice: a canister's worth from storage is likelier than one that has to be made
	var/list/choice = pick(
		list(/datum/gas/nitrous_oxide, 20, 3000), list(/datum/gas/nitrous_oxide, 20, 3000),
		list(/datum/gas/carbon_dioxide, 20, 3000), list(/datum/gas/carbon_dioxide, 20, 3000),
		list(/datum/gas/plasma, 20, 3000), list(/datum/gas/plasma, 20, 3000),
		list(/datum/gas/bz, 5, 5000), list(/datum/gas/tritium, 5, 6000), list(/datum/gas/pluoxium, 5, 6000))
	gas = choice[1]
	needed = choice[2]
	reward = choice[3]
	var/gas_name = GAS_META[META_GAS_NAME][gas]
	if(gas_name != uppertext(gas_name)) // "Plasma" mid-sentence is "plasma"; "BZ" stays
		gas_name = lowertext(gas_name)
	name = "[needed] mol of [gas_name], in a tank or canister"

/datum/sample_request/atmos/proc/air_of(obj/O)
	if(istype(O, /obj/item/tank))
		var/obj/item/tank/T = O
		return T.air_contents
	if(istype(O, /obj/machinery/portable_atmospherics))
		var/obj/machinery/portable_atmospherics/P = O
		return P.air_contents

/datum/sample_request/atmos/amount_in(obj/O)
	var/datum/gas_mixture/air = air_of(O)
	if(!air)
		return 0
	return min(round(air.moles[gas] || 0), left())

/datum/sample_request/atmos/take(obj/O, amount)
	var/datum/gas_mixture/air = air_of(O)
	air.moles[gas] = max(0, air.moles[gas] - amount)
	air.garbage_collect()

// The board

/datum/sample_board
	var/list/requests = list()
	/// Filled and expired ones, newest first
	var/list/history = list()
	var/opened = FALSE
	/// world.time it opens at, once the round's started
	var/opens_at = 0
	/// world.times new requests are due at
	var/list/refills = list()
	var/points_paid = 0
	var/filled_count = 0
	var/next_check = 0

/// The round's started: the board opens a little later
/datum/sample_board/proc/round_started()
	opens_at = world.time + SAMPLE_OPEN_DELAY
	addtimer(CALLBACK(src, PROC_REF(open)), SAMPLE_OPEN_DELAY)
	put_export_first()

/// Cargo's exports are tried in order and the first that takes a thing sells it: a sample ahead of the sheet or canister price
/datum/sample_board/proc/put_export_first()
	if(!GLOB.exports_list.len)
		setupExports()
	for(var/datum/export/science_sample/E in GLOB.exports_list)
		GLOB.exports_list -= E
		GLOB.exports_list.Insert(1, E)
		return

/datum/sample_board/proc/open(quiet = FALSE)
	if(opened)
		return
	opened = TRUE
	put_export_first()
	while(requests.len < SAMPLE_BOARD_SIZE)
		if(!new_request(quiet))
			break
	START_PROCESSING(SSprocessing, src)

/// A new request of a kind that isn't on the board; called out on its department's radio
/datum/sample_board/proc/new_request(quiet = FALSE, kind_path)
	if(!kind_path)
		var/list/kinds = subtypesof(/datum/sample_request)
		for(var/datum/sample_request/R in requests)
			kinds -= R.type
		if(!kinds.len)
			return null
		kind_path = pick(kinds)
	var/datum/sample_request/R = new kind_path
	R.setup()
	R.opened_at = world.time
	requests += R
	if(!quiet)
		radio_say("Science wants [R.name] for [R.reward] research points. Hand it in at R&D or ship it through Cargo.", R.channel)
	return R

/datum/sample_board/proc/radio_say(message, channel)
	for(var/obj/machinery/announcement_system/A in GLOB.announcement_systems)
		if(A.is_operational() && A.radio)
			A.radio.talk_into(A, message, channel)
			return TRUE
	return FALSE

/datum/sample_board/process()
	if(world.time < next_check)
		return
	next_check = world.time + 10 SECONDS
	for(var/datum/sample_request/R in requests.Copy())
		if(world.time - R.opened_at >= SAMPLE_LIFETIME)
			close(R, "expired")
			new_request()
	for(var/due in refills.Copy())
		if(world.time >= due)
			refills -= due
			if(requests.len < SAMPLE_BOARD_SIZE)
				new_request()

/// The open request a thing would count towards, if any
/datum/sample_board/proc/request_for(obj/O)
	if(!O || (O.flags_1 & HOLOGRAM_1))
		return null
	for(var/datum/sample_request/R in requests)
		if(R.amount_in(O) > 0)
			return R

/// Counts a thing towards its request, using up what's wanted of it. Returns the request, or null if it didn't count.
/datum/sample_board/proc/hand_in(obj/O, mob/user, via)
	var/datum/sample_request/R = request_for(O)
	if(!R)
		return null
	var/amount = R.amount_in(O)
	R.take(O, amount)
	R.got += amount
	log_game("Sample [R.name]: [amount] in via [via][user ? " by [key_name(user)]" : ""] ([R.got]/[R.needed])")
	if(R.got >= R.needed)
		R.filled_by = user ? user.name : null
		close(R, via)
		var/datum/techweb/web = SSresearch.science_tech
		web?.add_point_type(TECHWEB_POINT_TYPE_GENERIC, R.reward)
		points_paid += R.reward
		filled_count++
		radio_say("Sample in: [R.name], [R.reward] research points.", RADIO_CHANNEL_SCIENCE)
		refills += world.time + SAMPLE_REFILL_DELAY
	return R

/datum/sample_board/proc/close(datum/sample_request/R, via)
	requests -= R
	R.filled_via = via
	R.closed_at = world.time
	history.Insert(1, R)
	if(history.len > SAMPLE_HISTORY)
		history.Cut(SAMPLE_HISTORY + 1)

/// The board as the windows show it
/datum/sample_board/proc/board_data()
	var/list/open_list = list()
	for(var/datum/sample_request/R in requests)
		open_list += list(list(
			"kind" = R.kind,
			"department" = R.department,
			"name" = R.name,
			"reward" = R.reward,
			"got" = R.got,
			"needed" = R.needed,
			"unit" = R.unit,
			"minutes_left" = max(0, round((SAMPLE_LIFETIME - (world.time - R.opened_at)) / (1 MINUTES))),
		))
	var/list/done = list()
	for(var/datum/sample_request/R in history)
		done += list(list(
			"kind" = R.kind,
			"name" = R.name,
			"reward" = R.reward,
			"via" = R.filled_via,
			"by" = R.filled_by,
			"minutes_ago" = round((world.time - R.closed_at) / (1 MINUTES)),
		))
	return list(
		"open" = opened,
		"opens_in" = (!opened && opens_at) ? max(0, round((opens_at - world.time) / (1 MINUTES))) : null,
		"requests" = open_list,
		"history" = done,
		"points_paid" = points_paid,
		"filled_count" = filled_count,
	)

/datum/controller/subsystem/research/Initialize(start_timeofday)
	. = ..()
	SSticker.OnRoundstart(CALLBACK(GLOB.sample_board, TYPE_PROC_REF(/datum/sample_board, round_started)))

// Shipped through Cargo

/datum/export/science_sample
	cost = SAMPLE_SHIPPING_FEE
	k_elasticity = 0
	unit_name = "research sample"
	export_types = list(/obj/item, /obj/machinery/portable_atmospherics)

/datum/export/science_sample/applies_to(obj/O, allowed_categories = NONE, apply_elastic = TRUE)
	if((allowed_categories & export_category) != export_category)
		return FALSE
	return !!GLOB.sample_board.request_for(O)

/datum/export/science_sample/get_cost(obj/O, allowed_categories = NONE, apply_elastic = TRUE)
	return cost

/// The fee, plus what the rest of a stack (more than the request wanted) would have sold for, then the sample handed in
/datum/export/science_sample/sell_object(obj/O, datum/export_report/report, dry_run = TRUE, allowed_categories = EXPORT_CARGO, apply_elastic = TRUE)
	var/datum/sample_request/R = GLOB.sample_board.request_for(O)
	if(!R)
		return FALSE
	var/value = cost
	if(istype(O, /obj/item/stack))
		var/obj/item/stack/S = O
		var/excess = S.amount - R.amount_in(O)
		if(excess > 0)
			for(var/datum/export/E in GLOB.exports_list)
				if(E != src && E.applies_to(O, allowed_categories, apply_elastic))
					value += round(E.get_cost(O, allowed_categories, apply_elastic) * excess / S.amount)
					break
	report.total_value[src] += value
	report.total_amount[src] += 1
	if(!dry_run)
		GLOB.sample_board.hand_in(O, null, "Cargo")
	return TRUE

// Handed in at R&D

/obj/machinery/computer/rdconsole/proc/hand_in_sample(mob/user)
	var/obj/machinery/rnd/destructive_analyzer/A = linked_destroy
	if(!A || A.busy || !A.loaded_item)
		return FALSE
	var/obj/item/I = A.loaded_item
	var/datum/sample_request/R = GLOB.sample_board.hand_in(I, user, "R&D")
	if(!R)
		return FALSE
	if(QDELETED(I) || I.loc != A)
		A.loaded_item = null
	flick("d_analyzer_process", A)
	A.update_icon()
	playsound(A, 'sound/machines/ping.ogg', 30, TRUE)
	if(R.filled_via)
		say("Sample request filled: [R.name]. [R.reward] research points.")
	else
		say("Sample counted: [R.got]/[R.needed][R.unit] of [R.name].")
	return TRUE

/// What's in the analyzer would count towards a request
/obj/machinery/computer/rdconsole/proc/analyzer_sample_data(obj/item/I)
	var/datum/sample_request/R = GLOB.sample_board.request_for(I)
	if(!R)
		return null
	return list("name" = R.name, "reward" = R.reward, "gives" = R.amount_in(I), "got" = R.got, "needed" = R.needed, "unit" = R.unit)

// The experiment scanner says when a thing's wanted

/obj/item/experi_scanner/afterattack(atom/target, mob/user, proximity_flag, click_parameters)
	. = ..()
	if(!isobj(target) || (!proximity_flag && get_dist(user, target) > 1))
		return
	var/datum/sample_request/R = GLOB.sample_board.request_for(target)
	if(R)
		to_chat(user, "<span class='notice'>Science's sample board wants [R.name] ([R.reward] points): hand [target] in at R&D or ship it through Cargo.</span>")

#undef SAMPLE_BOARD_SIZE
#undef SAMPLE_OPEN_DELAY
#undef SAMPLE_REFILL_DELAY
#undef SAMPLE_LIFETIME
#undef SAMPLE_SHIPPING_FEE
#undef SAMPLE_HISTORY
