// Botany: a Botanist runs the hydroponics bay the way the tgstation Guide to Hydroponics has a
// player do it - plant seeds from the MegaSeed Servitor, keep every tray watered (bucket filled
// at the water tank), fed (E-Z-Nutrient from the NutriMax), weeded (cultivator) and pest-free
// (pest spray), harvest into a plant bag, run produce through the seed extractor to replant, and
// stock the smartfridge the kitchen shares.
//
// One goal is one visit to one tray: gather whatever that tray needs first (each fetch is its
// own small sub-goal, suspended/resumed like acquire_tool), walk over, then tend it one click at
// a time. Each visit chains into the next like the engineering round does, so the bot works down
// the bay; when every tray is fine it delivers what it harvested, then goes about its day.
//
// Everything is done with the item in hand, clicked on the tray/machine the way a player clicks
// (tray attackby(), vending ui_act("vend"), seed extractor attackby(), smartfridge attackby()).

#define BOT_TRAY_WEED_LIMIT 3 //uproot at this many weeds - 5+ starts hurting the plant (hydroponics.dm process())
#define BOT_TRAY_PEST_LIMIT 3 //spray at this many pests - 5+ starts hurting the plant
#define BOT_TRAY_POUR_MARGIN 15 //while at a tray, keep pouring until the water is within this of full
#define BOT_TRAY_TOXIC_LIMIT 30 //flush with water from here - 40+ hurts the plant, and pest spray adds toxin
#define BOT_TRAY_TOXIC_OK 15 //while flushing, keep pouring down to this
#define BOT_BOTANY_SUPPLY_REACH 30 //how far to look for a bucket, vendor, water tank or fridge
#define BOT_BOTANY_BAG_FULL 20 //produce in the bag that sends the bot to the fridge even with trays to tend

/// Crops the kitchen and bar actually use, from the MegaSeed Servitor's stock - what a botanist
/// plants when nobody has asked for anything in particular.
GLOBAL_LIST_INIT(bot_botany_crops, list(
	/obj/item/seeds/wheat,
	/obj/item/seeds/wheat/rice,
	/obj/item/seeds/tomato,
	/obj/item/seeds/potato,
	/obj/item/seeds/carrot,
	/obj/item/seeds/cabbage,
	/obj/item/seeds/corn,
	/obj/item/seeds/onion,
	/obj/item/seeds/chili,
	/obj/item/seeds/eggplant,
	/obj/item/seeds/soya,
	/obj/item/seeds/sugarcane,
	/obj/item/seeds/pumpkin,
	/obj/item/seeds/watermelon,
	/obj/item/seeds/berry,
	/obj/item/seeds/banana,
	/obj/item/seeds/apple,
	/obj/item/seeds/grape,
	/obj/item/seeds/whitebeet,
))

/datum/bot_brain
	var/next_botany_check_time = 0
	/// Tray -> world.time before it's worth another visit (a visit that couldn't fix everything).
	var/list/resting_trays
	/// Supply key ("bucket", "seeds"...) -> world.time before trying to fetch it again.
	var/list/botany_supply_blocked
	/// tray_priority() of what pick_tray_to_tend() last returned.
	var/last_tray_score = 0

/datum/bot_brain/proc/is_botanist_job()
	return owner.mind?.assigned_role == "Botanist"

// ---------------------------------------------------------------------------------------------
// The round
// ---------------------------------------------------------------------------------------------

/datum/bot_brain/proc/try_botany_round()
	if(!is_botanist_job())
		return FALSE
	// Already busy (a chained continuation arriving after something else took the goal slot):
	// don't plan - the project planner reads the world as it is between goals, and mid-splice
	// the seed it needs is sitting inside the DNA manipulator, not in the bag.
	if(state == BOT_STATE_GOAL && current_goal)
		return FALSE
	var/produce = find_produce_fridge() ? carried_produce_count() : 0 //nowhere to take it, nothing to deliver
	if(produce >= BOT_BOTANY_BAG_FULL && assign_goal(new /datum/bot_goal/stock_produce()))
		return TRUE
	var/obj/machinery/hydroponics/H = pick_tray_to_tend()
	// A thirsty, ripe or infested tray comes first; a mad scientist's project fits in around that
	// (goals/botany_projects.dm), before the routine top-ups and replanting.
	if(H && last_tray_score >= 3 && assign_goal(new /datum/bot_goal/tend_tray(H)))
		return TRUE
	if(try_botany_project())
		return TRUE
	if(H && assign_goal(new /datum/bot_goal/tend_tray(H)))
		return TRUE
	// Every tray is fine - take what was harvested to the fridge before doing anything else.
	if(produce && assign_goal(new /datum/bot_goal/stock_produce()))
		return TRUE
	return FALSE

/datum/bot_brain/proc/continue_botany_round()
	continue_goal_chain(CALLBACK(src, PROC_REF(try_botany_round)))

/// The trays this botanist looks after: the hydroponics bay proper, not the public garden's
/// soil plots or the prison's trays. A Bot Gym bot looks after the trays in its own arena.
/datum/bot_brain/proc/is_workplace_tray(obj/machinery/hydroponics/H)
	if(QDELETED(H) || H.z != owner.z || !H.anchored || (H.stat & BROKEN))
		return FALSE
	var/area/A = get_area(H)
	if(gym_run)
		return A == get_area(owner)
	return istype(A, /area/hydroponics) && !istype(A, /area/hydroponics/garden)

/datum/bot_brain/proc/rest_tray(obj/machinery/hydroponics/H, duration)
	LAZYSET(resting_trays, H, world.time + duration)

/datum/bot_brain/proc/is_resting_tray(obj/machinery/hydroponics/H)
	var/until = LAZYACCESS(resting_trays, H)
	return until && world.time < until

/// What a tray needs doing, as a list of keys. Thresholds are where a player would step in -
/// before the plant starts losing health (hydroponics.dm process()), not at the first drop.
/datum/bot_brain/proc/tray_needs(obj/machinery/hydroponics/H)
	. = list()
	var/growing = H.myseed && !H.dead
	var/project = is_project_tray(H) //planted by the project, not the ordinary round
	if(H.dead)
		. += "clear"
		if(!project)
			. += "plant"
	else if(H.harvest)
		. += "harvest"
		if(!project && !H.myseed.get_gene(/datum/plant_gene/trait/repeated_harvest))
			. += "plant" //the plant comes out with the harvest - bring seeds for the empty tray
	else if(!H.myseed && !project)
		. += "plant"
	if(H.weedlevel >= BOT_TRAY_WEED_LIMIT)
		. += "weed"
	if(growing)
		if(H.pestlevel >= BOT_TRAY_PEST_LIMIT)
			. += "pests"
		if(H.waterlevel < H.maxwater * 0.5)
			. += "water"
		if(H.nutrilevel < H.maxnutri * 0.3 || wrong_fertilizer(H))
			. += "feed"
		// Overwatering flushes toxin out (adjustWater() takes a quarter of what's poured off the
		// toxicity, even into a full tray) - the guide's fix, and what pest spray needs after.
		if(H.toxic >= BOT_TRAY_TOXIC_LIMIT)
			. += "flush"

/datum/bot_brain/proc/tray_priority(obj/machinery/hydroponics/H, list/needs)
	. = 0
	if(("harvest" in needs) || ("clear" in needs))
		. = max(., 5)
	if("water" in needs)
		. = max(., H.waterlevel <= 10 ? 6 : 3) //10 or less and the plant is already taking damage
	if(("weed" in needs) || ("pests" in needs))
		. = max(., (H.weedlevel >= 5 || H.pestlevel >= 5) ? 4 : 2)
	if("flush" in needs)
		. = max(., H.toxic >= 40 ? 4 : 2) //40+ is already hurting it
	if("feed" in needs)
		. = max(., 2)
	if("plant" in needs)
		. = max(., 1)

/// The most pressing tray, nearest first among equals.
/datum/bot_brain/proc/pick_tray_to_tend()
	var/obj/machinery/hydroponics/best
	var/best_score = 0
	var/best_dist
	var/seeds_available = can_get_seeds()
	for(var/obj/machinery/hydroponics/H as anything in bot_instances_of(/obj/machinery/hydroponics))
		if(!is_workplace_tray(H) || is_resting_tray(H))
			continue
		var/list/needs = tray_needs(H)
		if(!seeds_available)
			needs -= "plant"
		if(!length(needs))
			continue
		var/score = tray_priority(H, needs)
		var/dist = get_dist(owner, H)
		if(!best || score > best_score || (score == best_score && dist < best_dist))
			best = H
			best_score = score
			best_dist = dist
	last_tray_score = best_score
	return best

// ---------------------------------------------------------------------------------------------
// What the bot is carrying
// ---------------------------------------------------------------------------------------------

/// A carried item of item_type, optionally only one that still has something in it.
/datum/bot_brain/proc/carried_botany_item(item_type, need_reagents = FALSE)
	for(var/obj/item/I in owner.GetAllContents())
		if(!istype(I, item_type))
			continue
		if(need_reagents && !I.reagents?.total_volume)
			continue
		return I
	return null

/datum/bot_brain/proc/carried_plant_bag()
	return carried_botany_item(/obj/item/storage/bag/plants)

/datum/bot_brain/proc/carried_produce()
	. = list()
	var/obj/item/storage/bag/plants/bag = carried_plant_bag()
	if(!bag)
		return
	for(var/obj/item/reagent_containers/food/snacks/grown/G in bag)
		. += G

/// Produce in the bag bound for the kitchen fridge.
/datum/bot_brain/proc/carried_produce_count()
	. = 0
	for(var/obj/item/reagent_containers/food/snacks/grown/G as anything in carried_produce())
		if(is_stockable(G))
			.++

/datum/bot_brain/proc/carried_seeds()
	. = list()
	for(var/obj/item/seeds/S in owner.GetAllContents())
		if(!istype(S, /obj/item/seeds/sample))
			. += S

/// A nutrient bottle worth using: Robust Harvest first (+30% yield, no mutation - what the kitchen
/// wants), then E-Z-Nutrient (a stat mutation every harvest). Never Left 4 Zed: it caps the yield
/// at one (getYield()).
/datum/bot_brain/proc/carried_fertilizer()
	var/obj/item/reagent_containers/glass/bottle/nutrient/fallback
	for(var/obj/item/reagent_containers/glass/bottle/nutrient/N in owner.GetAllContents())
		if(!N.reagents?.total_volume || istype(N, /obj/item/reagent_containers/glass/bottle/nutrient/l4z))
			continue
		if(istype(N, /obj/item/reagent_containers/glass/bottle/nutrient/rh))
			return N
		fallback = N
	return fallback

/// A mutation tray is fed Left 4 Zed - a species roll every harvest (nutrimentMutation()); once
/// it has turned into what the project wanted, Robust Harvest locks it (no more mutation).
/datum/bot_brain/proc/wanted_mutmod(obj/machinery/hydroponics/H)
	var/role = project_tray_role(H)
	if(role == "mutate")
		return 2
	if(role == "grow")
		// A jump in species re-rolls the stats (mutatespecie() -> hardmutate(), yield +-4) and can
		// leave the new plant yielding nothing - locking that in with Robust Harvest would keep it
		// barren for good. E-Z-Nutrient shakes the stats up again every harvest, species and all
		// kept, until it bears.
		return H.myseed.yield <= 0 ? 1 : 0
	return null

/datum/bot_brain/proc/wrong_fertilizer(obj/machinery/hydroponics/H)
	var/want = wanted_mutmod(H)
	return !isnull(want) && H.mutmod != want

/datum/bot_brain/proc/fertilizer_for(obj/machinery/hydroponics/H)
	switch(wanted_mutmod(H))
		if(2)
			return carried_botany_item(/obj/item/reagent_containers/glass/bottle/nutrient/l4z, TRUE)
		if(1)
			return carried_botany_item(/obj/item/reagent_containers/glass/bottle/nutrient/ez, TRUE)
	return carried_fertilizer()

/// The supply key for the fertilizer tray H wants.
/datum/bot_brain/proc/fertilizer_key_for(obj/machinery/hydroponics/H)
	switch(wanted_mutmod(H))
		if(2)
			return "l4z"
		if(1)
			return "ez"
	return "nutrient"

/// Which fertilizer to go and get: Robust Harvest if the NutriMax still has any.
/datum/bot_brain/proc/preferred_fertilizer_type()
	if(find_botany_vendor(/obj/machinery/vending/hydronutrients, list(/obj/item/reagent_containers/glass/bottle/nutrient/rh)))
		return /obj/item/reagent_containers/glass/bottle/nutrient/rh
	return /obj/item/reagent_containers/glass/bottle/nutrient/ez

/datum/bot_brain/proc/is_botany_tool(obj/item/I)
	return istype(I, /obj/item/reagent_containers/glass/bucket) || istype(I, /obj/item/storage/bag/plants) \
		|| istype(I, /obj/item/cultivator) || istype(I, /obj/item/reagent_containers/glass/bottle/nutrient) \
		|| istype(I, /obj/item/reagent_containers/spray/pestspray) || istype(I, /obj/item/seeds) \
		|| istype(I, /obj/item/shovel/spade) || istype(I, /obj/item/reagent_containers/food/snacks/grown)

/// Puts a held item away without ever wearing it - a bucket's slot_flags include the head, and
/// equip_to_appropriate_slot() would happily put it there. Seed packets go in the backpack: the
/// plant bag (usually on the belt, first in put_away()'s order) gets emptied into the fridge.
/datum/bot_brain/proc/put_away_botany(obj/item/I)
	if(istype(I, /obj/item/seeds) && (I in owner.held_items))
		var/obj/item/storage/pack = owner.get_item_by_slot(ITEM_SLOT_BACK)
		if(pack && SEND_SIGNAL(pack, COMSIG_TRY_STORAGE_INSERT, I, owner))
			return TRUE
	return put_away(I, allow_equip = !(I.slot_flags & ITEM_SLOT_HEAD))

/// Draws I into the active hand, putting away whichever other botany tool was in hand first, the
/// way a player swaps the bucket back into the bag before taking out the cultivator.
/datum/bot_brain/proc/botany_ready(obj/item/I)
	for(var/obj/item/held in owner.held_items)
		if(held != I && is_botany_tool(held))
			put_away_botany(held)
	return ready_in_hand(I)

/// Picks a loose item up off the floor/table/vendor tray and puts it in the bag.
/datum/bot_brain/proc/take_botany_item(obj/item/I)
	if(!I || QDELETED(I) || !isturf(I.loc) || get_dist(owner, I) > 1)
		return FALSE
	telemetry_action = "pick up [I]"
	human_pause(I)
	telemetry_action = null
	if(QDELETED(I) || !isturf(I.loc) || get_dist(owner, I) > 1)
		return FALSE
	owner.face_atom(I)
	if(owner.get_active_held_item() && owner.get_inactive_held_item())
		put_away_botany(owner.get_active_held_item())
	if(!owner.put_in_hands(I))
		return FALSE
	bot_log(src, "picked up [I]")
	put_away_botany(I)
	return TRUE

/// The carried seed to plant next: whichever crop the bay has least of, so the kitchen gets a mix.
/datum/bot_brain/proc/pick_seed_to_plant()
	var/list/seeds = list()
	for(var/obj/item/seeds/S as anything in carried_seeds())
		if(is_crop_seed(S))
			seeds += S
	if(!length(seeds))
		return null
	var/list/growing = botany_crop_counts()
	var/obj/item/seeds/best
	var/best_count
	for(var/obj/item/seeds/S as anything in shuffle(seeds))
		var/count = growing[S.plantname] || 0
		if(!best || count < best_count)
			best = S
			best_count = count
	return best

/// A plain packet of a kitchen crop - what the ordinary round plants, stocks and replants.
/// Mutation stock, gene donors and the experiments themselves are the project's business.
/datum/bot_brain/proc/is_crop_seed(obj/item/seeds/S)
	return S && (S.type in GLOB.bot_botany_crops) && !bot_seed_is_experimental(S) && !is_reserved_seed(S)

/// Produce that can go to the kitchen: plain crops, never experiments or weapons.
/datum/bot_brain/proc/is_stockable(obj/item/reagent_containers/food/snacks/grown/G)
	return G.seed && (G.seed.type in GLOB.bot_botany_crops) && !bot_seed_is_experimental(G.seed)

/// plantname -> number of workplace trays growing it.
/datum/bot_brain/proc/botany_crop_counts()
	. = list()
	for(var/obj/machinery/hydroponics/H as anything in bot_instances_of(/obj/machinery/hydroponics))
		if(H.myseed && !H.dead && is_workplace_tray(H))
			.[H.myseed.plantname] = (.[H.myseed.plantname] || 0) + 1

/datum/bot_brain/proc/empty_workplace_trays()
	. = 0
	for(var/obj/machinery/hydroponics/H as anything in bot_instances_of(/obj/machinery/hydroponics))
		if(is_workplace_tray(H) && (!H.myseed || H.dead))
			.++

/datum/bot_brain/proc/can_get_seeds()
	if(pick_seed_to_plant())
		return TRUE
	return !!find_seed_source()

/// Where to get seeds: the seed extractor if there's produce in the bag to put through it,
/// otherwise the MegaSeed Servitor. Each route is blocked separately after it fails.
/datum/bot_brain/proc/find_seed_source()
	if(!is_botany_supply_blocked("seed_extractor"))
		for(var/obj/item/reagent_containers/food/snacks/grown/G in carried_produce())
			if(is_stockable(G))
				var/obj/machinery/seed_extractor/E = find_seed_extractor()
				if(E)
					return E
				break
	if(!is_botany_supply_blocked("seed_vendor"))
		return find_botany_vendor(/obj/machinery/vending/hydroseeds, GLOB.bot_botany_crops)
	return null

// ---------------------------------------------------------------------------------------------
// Finding things in the bay
// ---------------------------------------------------------------------------------------------

/datum/bot_brain/proc/botany_in_reach(atom/A)
	if(!A || QDELETED(A) || A.z != owner.z || get_dist(owner, A) > BOT_BOTANY_SUPPLY_REACH)
		return FALSE
	return !gym_run || get_area(A) == get_area(owner) //a Bot Gym bot only uses its own arena's things

/// Nearest working vendor of vendor_type that has any of product_types in stock.
/datum/bot_brain/proc/find_botany_vendor(vendor_type, list/product_types)
	var/obj/machinery/vending/best
	var/best_dist
	for(var/obj/machinery/vending/V as anything in bot_instances_of(vendor_type))
		if(!botany_in_reach(V) || V.panel_open || (V.stat & (BROKEN|NOPOWER)))
			continue
		if(!length(vendor_stock(V, product_types)))
			continue
		var/dist = get_dist(owner, V)
		if(!best || dist < best_dist)
			best = V
			best_dist = dist
	return best

/// The product records of V that stock any of product_types (exact types).
/datum/bot_brain/proc/vendor_stock(obj/machinery/vending/V, list/product_types)
	. = list()
	for(var/datum/data/vending_product/R in V.extended_inventory ? V.product_records + V.hidden_records : V.product_records)
		if(R.amount > 0 && (R.product_path in product_types))
			. += R

/// A loose one lying around the bay (a bucket on the floor, a cultivator on a table) or the
/// vendor that sells it, whichever is closer - a player grabs the bucket by the water tank
/// rather than walking to a machine for a new one.
/datum/bot_brain/proc/find_botany_supply(item_type)
	var/atom/best
	var/best_dist
	for(var/obj/item/I as anything in bot_instances_of(item_type))
		if(!isturf(I.loc) || I.anchored || !botany_in_reach(I))
			continue
		if(I.reagents && istype(I, /obj/item/reagent_containers/spray) && !I.reagents.total_volume)
			continue //an empty spray bottle is no use
		var/dist = get_dist(owner, I)
		if(!best || dist < best_dist)
			best = I
			best_dist = dist
	var/obj/machinery/vending/V = find_botany_vendor(/obj/machinery/vending/hydronutrients, list(item_type))
	if(V && (!best || get_dist(owner, V) + 2 < best_dist)) //slight preference for the loose one
		best = V
	return best

/datum/bot_brain/proc/find_water_source()
	var/atom/best
	var/best_dist
	for(var/obj/structure/reagent_dispensers/watertank/T as anything in bot_instances_of(/obj/structure/reagent_dispensers/watertank))
		if(!botany_in_reach(T) || T.reagents?.get_reagent_amount(/datum/reagent/water) < 20)
			continue
		var/dist = get_dist(owner, T)
		if(!best || dist < best_dist)
			best = T
			best_dist = dist
	for(var/obj/structure/sink/S as anything in bot_instances_of(/obj/structure/sink))
		if(!botany_in_reach(S) || S.dispensedreagent != /datum/reagent/water)
			continue
		var/dist = get_dist(owner, S)
		if(!best || dist < best_dist)
			best = S
			best_dist = dist
	return best

/// The plain smartfridge shared with the kitchen (not the chemistry/drinks/extract ones).
/datum/bot_brain/proc/find_produce_fridge()
	var/obj/machinery/smartfridge/best
	var/best_dist
	for(var/obj/machinery/smartfridge/F as anything in bot_instances_of(/obj/machinery/smartfridge))
		if(F.type != /obj/machinery/smartfridge || !botany_in_reach(F) || (F.stat & (BROKEN|NOPOWER)))
			continue
		var/dist = get_dist(owner, F)
		if(!best || dist < best_dist)
			best = F
			best_dist = dist
	return best

/datum/bot_brain/proc/find_seed_extractor()
	var/obj/machinery/seed_extractor/best
	var/best_dist
	for(var/obj/machinery/seed_extractor/E as anything in bot_instances_of(/obj/machinery/seed_extractor))
		if(!botany_in_reach(E) || (E.stat & (BROKEN|NOPOWER)))
			continue
		var/dist = get_dist(owner, E)
		if(!best || dist < best_dist)
			best = E
			best_dist = dist
	return best

/datum/bot_brain/proc/is_botany_supply_blocked(key)
	var/until = LAZYACCESS(botany_supply_blocked, key)
	return until && world.time < until

// ---------------------------------------------------------------------------------------------
// Vending, replicating /obj/machinery/vending/ui_act("vend") (_vending.dm) against a real ID
// ---------------------------------------------------------------------------------------------

/// Presses the vend button for product_path. Returns the dispensed item (on the vendor's tile,
/// where a player picks it up from) or null.
/datum/bot_brain/proc/vend_from(obj/machinery/vending/V, product_path)
	if(QDELETED(V) || V.panel_open || (V.stat & (BROKEN|NOPOWER)) || !owner.Adjacent(V))
		return null
	var/list/records = vendor_stock(V, list(product_path))
	if(!length(records))
		return null
	var/datum/data/vending_product/R = records[1]
	telemetry_action = "vend [R.name] from [V]"
	human_pause(V)
	telemetry_action = null
	if(QDELETED(V) || !owner.Adjacent(V) || R.amount <= 0)
		return null
	owner.face_atom(V)
	telemetry_ui_action(V, "vend")
	if(V.onstation)
		var/obj/item/card/id/C = owner.get_idcard(TRUE)
		if(!C || !C.registered_account)
			V.say(C ? "No account found." : "No card found.")
			if(V.icon_deny)
				flick(V.icon_deny, V)
			return null
		var/datum/bank_account/account = C.registered_account
		var/price = R.custom_price || V.default_price
		if(account.account_job && account.account_job.paycheck_department == V.payment_department)
			price = 0 //the botanist's own department's machine
		if(R in V.hidden_records)
			price = R.custom_premium_price || V.extra_price //contraband costs even staff
		if(price && !account.adjust_money(-price))
			V.say("You do not possess the funds to purchase [R.name].")
			if(V.icon_deny)
				flick(V.icon_deny, V)
			return null
		var/datum/bank_account/D = SSeconomy.get_dep_account(V.payment_department)
		D?.adjust_money(price)
	if(V.last_shopper != owner || V.purchase_message_cooldown < world.time)
		V.say("Thank you for shopping with [V]!")
		V.purchase_message_cooldown = world.time + 5 SECONDS
		V.last_shopper = owner
	V.use_power(5)
	if(V.icon_vend)
		flick(V.icon_vend, V)
	var/obj/item/I = new R.product_path(get_turf(V))
	R.amount--
	bot_log(src, "vended [I] from [V]")
	return I

/// Which crops to buy: the ones the bay has least of, a few different kinds per trip.
/datum/bot_brain/proc/choose_crops_to_buy(obj/machinery/vending/V, count)
	. = list()
	var/list/growing = botany_crop_counts()
	var/list/carried = list()
	for(var/obj/item/seeds/S as anything in carried_seeds())
		carried[S.type] = TRUE
	var/list/options = list()
	for(var/datum/data/vending_product/R as anything in shuffle(vendor_stock(V, GLOB.bot_botany_crops)))
		if(carried[R.product_path])
			continue
		var/obj/item/seeds/path = R.product_path
		options[path] = growing[initial(path.plantname)] || 0
	while(length(.) < count && length(options))
		var/pick
		for(var/path in options)
			if(!pick || options[path] < options[pick])
				pick = path
		. += pick
		options -= pick

// ---------------------------------------------------------------------------------------------
// Tending a tray
// ---------------------------------------------------------------------------------------------

/datum/bot_goal/tend_tray

/datum/bot_goal/tend_tray/New(obj/machinery/hydroponics/H)
	. = ..()
	target = H

/datum/bot_goal/tend_tray/resolve_target(datum/bot_brain/bot)
	return //set in New()

/datum/bot_goal/tend_tray/get_strategies(datum/bot_brain/bot)
	return list(new /datum/bot_strategy/tend_tray())

/datum/bot_goal/tend_tray/on_success(datum/bot_brain/bot)
	bot.continue_botany_round()

/datum/bot_goal/tend_tray/on_give_up(datum/bot_brain/bot)
	bot.rest_tray(target, 2 MINUTES)

/datum/bot_strategy/tend_tray/New()
	. = ..()
	steps = list(new /datum/bot_step/prepare_for_tray(), new /datum/bot_step/move_to(), new /datum/bot_step/paced/care_for_tray())

/datum/bot_strategy/tend_tray/is_feasible(datum/bot_brain/bot)
	var/obj/machinery/hydroponics/H = bot.current_goal?.target
	return istype(H) && !QDELETED(H)

/// The supplies to have on hand before walking over to H, in the order to fetch them.
/datum/bot_brain/proc/visit_supplies(obj/machinery/hydroponics/H)
	. = list()
	var/list/needs = tray_needs(H)
	if(("harvest" in needs) && !carried_plant_bag())
		. += "bag"
	if(("weed" in needs) && !carried_botany_item(/obj/item/cultivator))
		. += "cultivator"
	if(("pests" in needs) && !carried_botany_item(/obj/item/reagent_containers/spray/pestspray, TRUE))
		. += "pestspray"
	if(("water" in needs) || ("flush" in needs))
		var/obj/item/reagent_containers/glass/bucket/B = carried_botany_item(/obj/item/reagent_containers/glass/bucket)
		if(!B)
			. += "bucket"
		if(!B || B.reagents.total_volume < 20)
			. += "water"
	if(("feed" in needs) && !fertilizer_for(H))
		. += fertilizer_key_for(H)
	// A ripe crop about to be harvested brings its own seeds (through the extractor) - no need
	// to buy any first.
	if(("plant" in needs) && !pick_seed_to_plant() && !(("harvest" in needs) && find_seed_extractor()))
		. += "seeds"
	var/list/wanted = .
	. = list()
	for(var/key in wanted)
		if(!is_botany_supply_blocked(key))
			. += key

/datum/bot_brain/proc/botany_supply_goal(key)
	switch(key)
		if("bag")
			return new /datum/bot_goal/botany_supply(/obj/item/storage/bag/plants, key)
		if("cultivator")
			return new /datum/bot_goal/botany_supply(/obj/item/cultivator, key)
		if("pestspray")
			return new /datum/bot_goal/botany_supply(/obj/item/reagent_containers/spray/pestspray, key)
		if("bucket")
			return new /datum/bot_goal/botany_supply(/obj/item/reagent_containers/glass/bucket, key)
		if("nutrient")
			return new /datum/bot_goal/botany_supply(preferred_fertilizer_type(), key)
		if("ez")
			return new /datum/bot_goal/botany_supply(/obj/item/reagent_containers/glass/bottle/nutrient/ez, key)
		if("l4z")
			return new /datum/bot_goal/botany_supply(/obj/item/reagent_containers/glass/bottle/nutrient/l4z, key)
		if("spade")
			return new /datum/bot_goal/botany_supply(/obj/item/shovel/spade, key)
		if("water")
			if(carried_botany_item(/obj/item/reagent_containers/glass/bucket))
				return new /datum/bot_goal/fill_bucket()
		if("seeds")
			return new /datum/bot_goal/get_seeds()
	return null

/// Fetches what the tray needs, one sub-goal at a time. Re-run each time a fetch comes back, so
/// it always works from what the bot actually has now; each supply is only tried once per visit.
/datum/bot_step/prepare_for_tray
	var/list/tried

/datum/bot_step/prepare_for_tray/execute(datum/bot_brain/bot)
	var/obj/machinery/hydroponics/H = bot.current_goal?.target
	if(!istype(H) || QDELETED(H))
		return GOAL_STEP_FAIL
	LAZYINITLIST(tried)
	for(var/key in bot.visit_supplies(H))
		if(key in tried)
			continue
		tried += key
		var/datum/bot_goal/G = bot.botany_supply_goal(key)
		if(G && bot.suspend_goal_for(G))
			return GOAL_STEP_PENDING
	tried = null
	return GOAL_STEP_SUCCESS

/// Base for a step made of separate clicks (watering a tray, filling a bucket, buying several
/// packets of seeds): do_click() makes one click and returns TRUE, or FALSE once there's nothing
/// left to do. Clicks come one per timer tick, paced by human_pause(), never all in one instant.
/datum/bot_step/paced
	var/clicks = 0
	var/max_clicks = 12
	/// Set by do_click() to wait this long for something (a shock wearing off) instead of clicking.
	var/wait_for = 0
	/// TRUE if not getting anywhere shouldn't sink the errand (no seeds worth extracting, say).
	var/optional = FALSE

/datum/bot_step/paced/execute(datum/bot_brain/bot)
	clicks = 0
	if(!start(bot))
		return optional ? GOAL_STEP_SUCCESS : GOAL_STEP_FAIL
	return next_click(bot)

/datum/bot_step/paced/proc/start(datum/bot_brain/bot)
	return TRUE

/datum/bot_step/paced/proc/do_click(datum/bot_brain/bot)
	return FALSE

/datum/bot_step/paced/proc/finish(datum/bot_brain/bot)
	return GOAL_STEP_SUCCESS

/datum/bot_step/paced/proc/next_click(datum/bot_brain/bot)
	wait_for = 0
	var/clicked = FALSE
	// A runtime in whatever the click touched (game code included) ends this step as a failure -
	// left uncaught it killed the timer chain and froze the bot mid-goal for good.
	try
		clicked = clicks < max_clicks && do_click(bot)
	catch(var/exception/e)
		bot_log_exception(bot, "[type]/do_click", e)
		clicked = FALSE
	if(clicked)
		if(wait_for)
			addtimer(CALLBACK(src, PROC_REF(continue_clicks), bot), wait_for)
			return GOAL_STEP_PENDING
		clicks++
		addtimer(CALLBACK(src, PROC_REF(continue_clicks), bot), rand(1, 3))
		return GOAL_STEP_PENDING
	. = finish(bot)
	if(optional)
		. = GOAL_STEP_SUCCESS

/datum/bot_step/paced/proc/continue_clicks(datum/bot_brain/bot)
	if(QDELETED(bot) || bot.state != BOT_STATE_GOAL || bot.current_strategy?.steps?[bot.current_step_index] != src)
		return //goal moved on while we were waiting - don't act on stale state
	var/result = next_click(bot)
	if(result != GOAL_STEP_PENDING)
		bot.advance_goal_step(result == GOAL_STEP_SUCCESS)

/// Everything the tray needs, most urgent first, with whatever the bot has on it.
/datum/bot_step/paced/care_for_tray
	max_clicks = 16
	var/obj/machinery/hydroponics/tray
	var/harvested = FALSE
	var/poured_mutagen = FALSE

/datum/bot_step/paced/care_for_tray/start(datum/bot_brain/bot)
	tray = bot.current_goal?.target
	harvested = FALSE
	poured_mutagen = FALSE
	return istype(tray) && !QDELETED(tray) && bot.owner.Adjacent(tray)

/datum/bot_step/paced/care_for_tray/do_click(datum/bot_brain/bot)
	if(QDELETED(tray) || !bot.owner.Adjacent(tray))
		return FALSE
	var/turf/here = get_turf(bot.owner)
	// Picked by hand (no plant bag): gather up what fell at our feet.
	if(harvested && !bot.carried_plant_bag())
		var/obj/item/reagent_containers/food/snacks/grown/G = locate() in here
		if(G)
			return bot.take_botany_item(G)
	var/plant = tray.myseed?.plantname
	if(tray.dead)
		bot_log(bot, "pulling the dead [plant] out of [tray]")
		return bot.use_atom(tray)
	if(tray.harvest && tray.myseed)
		harvested = TRUE
		var/obj/item/storage/bag/plants/bag = bot.carried_plant_bag()
		bot_log(bot, "harvesting the [plant][bag ? "" : " by hand"]")
		return bag ? bot.botany_use(bag, tray) : bot.use_atom(tray)
	var/obj/item/cultivator/C = bot.carried_botany_item(/obj/item/cultivator)
	if(C && tray.weedlevel > 0 && (tray.weedlevel >= BOT_TRAY_WEED_LIMIT || !tray.myseed))
		bot_log(bot, "uprooting the weeds in [tray]")
		return bot.botany_use(C, tray)
	if(!tray.myseed)
		if(bot.is_project_tray(tray))
			return FALSE //the project replants its own trays
		var/obj/item/seeds/S = bot.pick_seed_to_plant()
		if(!S)
			return FALSE
		bot_log(bot, "planting [S.plantname] in [tray]")
		return bot.botany_use(S, tray)
	var/obj/item/reagent_containers/spray/pestspray/P = bot.carried_botany_item(/obj/item/reagent_containers/spray/pestspray, TRUE)
	if(P && tray.pestlevel >= 2)
		bot_log(bot, "spraying the pests on the [plant]")
		return bot.botany_use(P, tray)
	var/obj/item/reagent_containers/glass/bucket/B = bot.carried_botany_item(/obj/item/reagent_containers/glass/bucket, TRUE)
	if(B && tray.waterlevel <= tray.maxwater - BOT_TRAY_POUR_MARGIN)
		bot_log(bot, "watering the [plant] ([tray.waterlevel]/[tray.maxwater])")
		return bot.botany_use(B, tray)
	if(B && tray.toxic >= BOT_TRAY_TOXIC_OK)
		bot_log(bot, "flushing the toxins out of [tray] with water ([tray.toxic]/100)")
		return bot.botany_use(B, tray)
	var/obj/item/reagent_containers/glass/bottle/nutrient/N = bot.fertilizer_for(tray)
	if(N && (tray.nutrilevel <= tray.maxnutri / 2 || bot.wrong_fertilizer(tray)))
		if(bot.wanted_mutmod(tray) == 1 && tray.mutmod != 1)
			bot_log(bot, "the [plant] isn't bearing anything - switching it to [N] to shake its stats up")
		else
			bot_log(bot, "feeding the [plant] with [N] ([tray.nutrilevel]/[tray.maxnutri])")
		return bot.botany_use(N, tray)
	if(!poured_mutagen && bot.project_tray_role(tray) == "mutate")
		var/obj/item/reagent_containers/M = bot.carried_mutagen()
		if(M)
			poured_mutagen = TRUE
			return bot.pour_mutagen(M, tray)
	return FALSE

/datum/bot_step/paced/care_for_tray/finish(datum/bot_brain/bot)
	for(var/obj/item/held in bot.owner.held_items)
		if(bot.is_botany_tool(held))
			bot.put_away_botany(held)
	// Walked over and couldn't do anything at all (nothing to fix it with): don't come straight
	// back to stare at it - other trays first. A visit that got somewhere but not all the way
	// (the bucket ran dry mid-flush, the harvest emptied the tray) is picked up again next round,
	// like a player going to refill the bucket and coming straight back.
	if(!QDELETED(tray) && !clicks && length(bot.tray_needs(tray)))
		bot.rest_tray(tray, 1 MINUTES)
	tray = null
	return GOAL_STEP_SUCCESS

/// Pours mutagen into a mutation tray. 50u at once guarantees a new species on this server (the
/// hippie applyChemicals()), so with that much the bottle is set to pour it all - using it in
/// hand cycles the transfer amount, as a player does.
/datum/bot_brain/proc/pour_mutagen(obj/item/reagent_containers/M, obj/machinery/hydroponics/H)
	var/want = M.reagents.get_reagent_amount(/datum/reagent/toxin/mutagen) >= 50 ? 50 : 5
	if(want in M.possible_transfer_amounts)
		for(var/i in 1 to length(M.possible_transfer_amounts))
			if(M.amount_per_transfer_from_this == want || !toggle_in_hand(M))
				break
	bot_log(src, "pouring [M.amount_per_transfer_from_this]u of [M] into the [H.myseed?.plantname]")
	return botany_use(M, H)

/// A help-intent click on target with a botany tool drawn into the hand.
/datum/bot_brain/proc/botany_use(obj/item/I, atom/target)
	if(!botany_ready(I))
		return FALSE
	return use_tool_on(I, target)

// ---------------------------------------------------------------------------------------------
// Fetching supplies
// ---------------------------------------------------------------------------------------------

/// A plant bag, bucket, cultivator, nutrient bottle or pest spray - picked up if one is lying
/// about the bay, bought from the NutriMax otherwise.
/datum/bot_goal/botany_supply
	var/item_type
	var/key

/datum/bot_goal/botany_supply/New(item_type, key)
	. = ..()
	src.item_type = item_type
	src.key = key

/datum/bot_goal/botany_supply/resolve_target(datum/bot_brain/bot)
	target = bot.find_botany_supply(item_type)

/datum/bot_goal/botany_supply/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/botany_errand/S = new
	if(istype(target, /obj/machinery/vending))
		S.steps = list(new /datum/bot_step/move_to(), new /datum/bot_step/paced/vend_products(list(item_type)))
	else
		S.steps = list(new /datum/bot_step/move_to(), new /datum/bot_step/take_target())
	return list(S)

/datum/bot_goal/botany_supply/on_give_up(datum/bot_brain/bot)
	LAZYSET(bot.botany_supply_blocked, key, world.time + 2 MINUTES)

/datum/bot_strategy/botany_errand/is_feasible(datum/bot_brain/bot)
	return bot.current_goal?.target && !QDELETED(bot.current_goal.target)

/datum/bot_step/take_target/execute(datum/bot_brain/bot)
	return bot.take_botany_item(bot.current_goal?.target) ? GOAL_STEP_SUCCESS : GOAL_STEP_FAIL

/// Buys each of products in turn: press the button, pick the item up off the vendor's tray.
/datum/bot_step/paced/vend_products
	var/list/products
	var/list/pending
	var/obj/item/dispensed
	var/got = 0

/datum/bot_step/paced/vend_products/New(list/products)
	. = ..()
	src.products = products

/datum/bot_step/paced/vend_products/start(datum/bot_brain/bot)
	pending = products.Copy()
	dispensed = null
	got = 0
	return bot.owner.Adjacent(bot.current_goal?.target)

/datum/bot_step/paced/vend_products/do_click(datum/bot_brain/bot)
	if(dispensed)
		var/obj/item/I = dispensed
		dispensed = null
		if(bot.take_botany_item(I))
			got++
		return TRUE
	if(!length(pending))
		return FALSE
	var/path = pending[1]
	pending.Cut(1, 2)
	dispensed = bot.vend_from(bot.current_goal?.target, path)
	return TRUE

/datum/bot_step/paced/vend_products/finish(datum/bot_brain/bot)
	return got ? GOAL_STEP_SUCCESS : GOAL_STEP_FAIL

/// Fills the carried bucket at the nearest water tank or sink.
/datum/bot_goal/fill_bucket

/datum/bot_goal/fill_bucket/resolve_target(datum/bot_brain/bot)
	target = bot.find_water_source()

/datum/bot_goal/fill_bucket/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/botany_errand/S = new
	S.steps = list(new /datum/bot_step/move_to(), new /datum/bot_step/paced/fill_bucket())
	return list(S)

/datum/bot_goal/fill_bucket/on_give_up(datum/bot_brain/bot)
	LAZYSET(bot.botany_supply_blocked, "water", world.time + 1 MINUTES)

/// One click per scoop until the bucket is full - the tank gives amount_per_transfer_from_this
/// a click (glass/afterattack()), a sink the same (sink/attackby()).
/datum/bot_step/paced/fill_bucket
	var/obj/item/reagent_containers/glass/bucket/bucket
	var/last_volume = -1

/datum/bot_step/paced/fill_bucket/start(datum/bot_brain/bot)
	bucket = bot.carried_botany_item(/obj/item/reagent_containers/glass/bucket)
	last_volume = -1
	return bucket && bot.owner.Adjacent(bot.current_goal?.target)

/datum/bot_step/paced/fill_bucket/do_click(datum/bot_brain/bot)
	if(QDELETED(bucket) || bucket.reagents.holder_full())
		return FALSE
	if(bucket.reagents.total_volume == last_volume)
		return FALSE //the last scoop didn't add anything - the tank's dry
	last_volume = bucket.reagents.total_volume
	if(clicks == 0)
		bot_log(bot, "filling [bucket] at [bot.current_goal?.target]")
	return bot.botany_use(bucket, bot.current_goal?.target)

/datum/bot_step/paced/fill_bucket/finish(datum/bot_brain/bot)
	var/ok = !QDELETED(bucket) && bucket.reagents.total_volume >= 20
	bucket = null
	return ok ? GOAL_STEP_SUCCESS : GOAL_STEP_FAIL

/// Seeds to plant: out of the seed extractor if there's produce in the bag to put through it,
/// otherwise a few different packets from the MegaSeed Servitor.
/datum/bot_goal/get_seeds

/datum/bot_goal/get_seeds/resolve_target(datum/bot_brain/bot)
	target = bot.find_seed_source()

/datum/bot_goal/get_seeds/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/botany_errand/S = new
	if(istype(target, /obj/machinery/seed_extractor))
		S.steps = list(new /datum/bot_step/move_to(), new /datum/bot_step/paced/extract_seeds(target, 1))
	else
		var/count = clamp(bot.empty_workplace_trays(), 1, 4)
		S.steps = list(new /datum/bot_step/move_to(), new /datum/bot_step/paced/vend_products(bot.choose_crops_to_buy(target, count)))
	return list(S)

/datum/bot_goal/get_seeds/on_give_up(datum/bot_brain/bot)
	LAZYSET(bot.botany_supply_blocked, istype(target, /obj/machinery/seed_extractor) ? "seed_extractor" : "seed_vendor", world.time + 2 MINUTES)

/// Feeds produce from the bag into the seed extractor, one piece per click, and picks up the
/// seeds it drops on its tile (seedify(), seed_extractor.dm). One piece per crop not already
/// carried as seeds, up to `species` crops.
/datum/bot_step/paced/extract_seeds
	var/obj/machinery/seed_extractor/extractor
	var/species = 1
	/// Only this species (a project's), instead of any kitchen crop.
	var/only_type
	var/list/queue
	var/list/fresh_seeds
	var/got = 0

/datum/bot_step/paced/extract_seeds/New(obj/machinery/seed_extractor/E, species)
	. = ..()
	extractor = E
	src.species = species

/datum/bot_step/paced/extract_seeds/start(datum/bot_brain/bot)
	if(QDELETED(extractor) || !bot.owner.Adjacent(extractor))
		return FALSE
	got = 0
	fresh_seeds = list()
	queue = list()
	var/list/have = list()
	for(var/obj/item/seeds/S as anything in bot.carried_seeds())
		if(!only_type || bot_seed_is_plain(S, only_type))
			have[S.plantname] = TRUE
	for(var/obj/item/reagent_containers/food/snacks/grown/G in bot.carried_produce())
		if(length(queue) >= species)
			break
		if(!G.seed || have[G.seed.plantname])
			continue
		if(only_type ? !bot_seed_is_plain(G.seed, only_type) : !bot.is_stockable(G))
			continue
		have[G.seed.plantname] = TRUE
		queue += G
	return length(queue)

/datum/bot_step/paced/extract_seeds/do_click(datum/bot_brain/bot)
	if(QDELETED(extractor) || !bot.owner.Adjacent(extractor))
		return FALSE
	while(length(fresh_seeds))
		var/obj/item/seeds/S = fresh_seeds[1]
		fresh_seeds.Cut(1, 2)
		if(QDELETED(S) || S.loc != extractor.loc)
			continue
		if(bot.take_botany_item(S))
			got++
		return TRUE
	while(length(queue))
		var/obj/item/reagent_containers/food/snacks/grown/G = queue[1]
		queue.Cut(1, 2)
		if(QDELETED(G) || !(G in bot.carried_produce()))
			continue
		var/list/before = list()
		for(var/obj/item/seeds/S in extractor.loc)
			before += S
		bot_log(bot, "putting [G] through [extractor]")
		if(!bot.botany_use(G, extractor))
			continue
		for(var/obj/item/seeds/S in extractor.loc)
			if(!(S in before))
				fresh_seeds += S
		return TRUE
	return FALSE

/datum/bot_step/paced/extract_seeds/finish(datum/bot_brain/bot)
	queue = null
	fresh_seeds = null
	return got ? GOAL_STEP_SUCCESS : GOAL_STEP_FAIL

// ---------------------------------------------------------------------------------------------
// Delivering the harvest
// ---------------------------------------------------------------------------------------------

/// Empties the plant bag into the smartfridge the kitchen shares - after keeping back seeds of
/// what was harvested at the seed extractor, if the bot has none left to replant with.
/datum/bot_goal/stock_produce
	var/obj/machinery/seed_extractor/extractor

/datum/bot_goal/stock_produce/resolve_target(datum/bot_brain/bot)
	target = bot.find_produce_fridge()
	if(length(bot.carried_seeds()) < 3)
		extractor = bot.find_seed_extractor()

/datum/bot_goal/stock_produce/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/botany_errand/S = new
	S.steps = list()
	if(extractor)
		var/datum/bot_step/move_to/to_extractor = new
		to_extractor.step_target = extractor
		S.steps += to_extractor
		var/datum/bot_step/paced/extract_seeds/extract = new(extractor, 2)
		extract.optional = TRUE
		S.steps += extract
	S.steps += new /datum/bot_step/move_to()
	S.steps += new /datum/bot_step/paced/load_fridge()
	return list(S)

/datum/bot_goal/stock_produce/on_success(datum/bot_brain/bot)
	bot.continue_botany_round()

/datum/bot_goal/stock_produce/on_give_up(datum/bot_brain/bot)
	bot.next_botany_check_time = world.time + 1 MINUTES //nowhere to put it right now

/// Empties the bag into the fridge in one go when it's all kitchen produce. With experiments or
/// project produce in there too (the fridge would take everything), the crops go in by hand.
/datum/bot_step/paced/load_fridge
	max_clicks = 30
	var/before = 0

/datum/bot_step/paced/load_fridge/start(datum/bot_brain/bot)
	before = bot.carried_produce_count()
	var/obj/machinery/smartfridge/F = bot.current_goal?.target
	return istype(F) && bot.carried_plant_bag() && bot.owner.Adjacent(F)

/datum/bot_step/paced/load_fridge/do_click(datum/bot_brain/bot)
	var/obj/machinery/smartfridge/F = bot.current_goal?.target
	var/obj/item/storage/bag/plants/bag = bot.carried_plant_bag()
	if(!bag || !bot.owner.Adjacent(F) || !bot.carried_produce_count())
		return FALSE
	var/mixed = FALSE
	for(var/obj/item/I in bag)
		var/obj/item/reagent_containers/food/snacks/grown/G = I
		if(!istype(G) || !bot.is_stockable(G))
			mixed = TRUE
			break
	if(!mixed)
		if(clicks)
			return FALSE //already emptied it
		bot_log(bot, "stocking [F] with [before] piece\s of produce")
		return bot.botany_use(bag, F)
	for(var/obj/item/reagent_containers/food/snacks/grown/G in bag)
		if(bot.is_stockable(G))
			return bot.botany_use(G, F)
	return FALSE

/datum/bot_step/paced/load_fridge/finish(datum/bot_brain/bot)
	var/obj/item/storage/bag/plants/bag = bot.carried_plant_bag()
	if(bag)
		bot.put_away_botany(bag)
	return (!before || bot.carried_produce_count() < before) ? GOAL_STEP_SUCCESS : GOAL_STEP_FAIL

#undef BOT_TRAY_WEED_LIMIT
#undef BOT_TRAY_PEST_LIMIT
#undef BOT_TRAY_POUR_MARGIN
#undef BOT_TRAY_TOXIC_LIMIT
#undef BOT_TRAY_TOXIC_OK
#undef BOT_BOTANY_SUPPLY_REACH
#undef BOT_BOTANY_BAG_FULL
