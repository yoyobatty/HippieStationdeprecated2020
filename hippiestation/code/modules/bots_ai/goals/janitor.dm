// Janitor: keeps the station clean the way a player janitor does it - a mop in one hand and a bucket of
// water in the other, working outwards from wherever it is. Blood, vomit and oil before plain dirt; dead
// light tubes swapped with the light replacer; galoshes from the JaniDrobe first, so it doesn't go over
// on its own wet floor (without them it walks while it mops).
//
// The mechanics, all the player's own clicks:
//  - mop on bucket wets it 5u a click (bucket/attackby()); the bucket fills 20u a click at a water tank
//    or sink (the botanist's fill_bucket goal, goals/tend_hydroponics.dm)
//  - mop on a floor tile is a 1.5s do_after and clears every cleanable on it, for 1u of water
//    (mop/afterattack() -> clean())
//  - light replacer on a dead fixture swaps the tube (light/attackby() -> ReplaceLight())
//
// One thing peculiar to this server: a mop carrying 4u or more leaves a puddle of its own water behind
// (hippie chemistry turns it into a "chemicals" decal, reagents.dm handle_state_change()). That isn't a
// mess - bot_is_mess() doesn't count a puddle of plain water or cleaner.

#define BOT_JANITOR_REACH 60
/// Tiles mopped in one stop before looking up again.
#define BOT_MOP_TILES_PER_STOP 8

/datum/bot_brain
	/// Turf (a mess on it) or light fixture -> world.time before it's worth another try.
	var/list/janitor_blocked
	/// When to next think about the JaniDrobe.
	var/janitor_wardrobe_retry = 0
	/// Tiles this janitor has mopped clean, for the Bot Shift report.
	var/tiles_mopped = 0
	var/lights_replaced = 0

/datum/bot_brain/proc/is_janitor_job()
	return owner.mind?.assigned_role == "Janitor"

/datum/bot_brain/proc/janitor_in_reach(atom/A)
	if(!A || QDELETED(A) || A.z != owner.z || get_dist(owner, A) > BOT_JANITOR_REACH)
		return FALSE
	return !gym_run || get_area(A) == get_area(owner) //a Bot Gym bot only sees to its own arena

/datum/bot_brain/proc/has_noslip_shoes()
	var/obj/item/clothing/shoes/S = owner.shoes
	return istype(S) && (S.clothing_flags & NOSLIP)

// ---------------------------------------------------------------------------------------------
// What needs doing
// ---------------------------------------------------------------------------------------------

/// Whether a cleanable is something to mop up, rather than the water a mop left behind.
/proc/bot_is_mess(obj/effect/decal/cleanable/C)
	if(QDELETED(C) || !isopenturf(C.loc))
		return FALSE
	if(istype(C, /obj/effect/decal/cleanable/chempile))
		for(var/datum/reagent/R in C.reagents?.reagent_list)
			if(!istype(R, /datum/reagent/water) && !istype(R, /datum/reagent/space_cleaner))
				return TRUE
		return FALSE
	return TRUE

/// 3 for what nobody wants to walk through, 1 for the dirt that's always there, 2 for the rest.
/proc/bot_mess_priority(obj/effect/decal/cleanable/C)
	if(istype(C, /obj/effect/decal/cleanable/blood) || istype(C, /obj/effect/decal/cleanable/xenoblood) || istype(C, /obj/effect/decal/cleanable/vomit) \
		|| istype(C, /obj/effect/decal/cleanable/oil) || istype(C, /obj/effect/decal/cleanable/robot_debris) || istype(C, /obj/effect/decal/cleanable/chempile) \
		|| istype(C, /obj/effect/decal/cleanable/insectguts) || istype(C, /obj/effect/decal/cleanable/greenglow))
		return 3
	if(istype(C, /obj/effect/decal/cleanable/dirt) || istype(C, /obj/effect/decal/cleanable/cobweb))
		return 1
	return 2

/datum/bot_brain/proc/turf_has_mess(turf/T)
	for(var/obj/effect/decal/cleanable/C in T)
		if(bot_is_mess(C))
			return TRUE
	return FALSE

/// The mess to see to next: the worst first, the nearest among equals. Plain dirt in the maintenance tunnels is left
/// where it is - nobody mops maintenance.
/datum/bot_brain/proc/pick_mess()
	var/obj/effect/decal/cleanable/best
	var/best_score
	for(var/obj/effect/decal/cleanable/C as anything in bot_instances_of(/obj/effect/decal/cleanable))
		if(!bot_is_mess(C) || !janitor_in_reach(C))
			continue
		var/turf/T = C.loc
		var/area/A = T.loc
		if(LAZYACCESS(janitor_blocked, T) > world.time || LAZYACCESS(janitor_blocked, A) > world.time || taken_by_another(C))
			continue
		var/priority = bot_mess_priority(C)
		if(priority == 1 && !gym_run && findtext(A.name, "Maintenance"))
			continue
		var/score = priority * 40 - get_dist(owner, T)
		// Somebody asked for the janitor over there (bot_requests.dm): that one first.
		if(janitor_called_to && world.time < janitor_called_until && get_dist(T, janitor_called_to) <= 7)
			score += 400
		if(!best || score > best_score)
			best = C
			best_score = score
	return best

/// A light fixture with a dead, broken or missing tube that the replacer can do something about.
/datum/bot_brain/proc/pick_dead_light()
	var/obj/item/lightreplacer/replacer = find_carried_tool(/obj/item/lightreplacer)
	if(!replacer || replacer.uses <= 0)
		return null
	var/list/dead = list() //fixture -> how far off
	for(var/obj/machinery/light/L as anything in bot_instances_of(/obj/machinery/light))
		if(L.status == LIGHT_OK || !janitor_in_reach(L) || LAZYACCESS(janitor_blocked, L) > world.time || LAZYACCESS(janitor_blocked, get_area(L)) > world.time || taken_by_another(L))
			continue
		dead[L] = get_dist(owner, L)
	// The nearest there's a way to. A dark room behind a door this ID doesn't open is somebody else's to see to:
	// the nearest dead tube as the crow flies used to be in the Toxins lab or out on the AI satellite, every time.
	var/tries = 0
	while(length(dead) && tries++ < 4)
		var/obj/machinery/light/nearest
		for(var/obj/machinery/light/L as anything in dead)
			if(!nearest || dead[L] < dead[nearest])
				nearest = L
		dead -= nearest
		if(can_walk_lawfully_to(nearest))
			return nearest
		LAZYSET(janitor_blocked, get_area(nearest), world.time + 10 MINUTES)
	return null

/// What this janitor still wants out of the JaniDrobe, as product types.
/datum/bot_brain/proc/janitor_wardrobe_wants()
	. = list()
	if(!has_noslip_shoes() && !find_carried_tool(/obj/item/clothing/shoes/galoshes))
		. += /obj/item/clothing/shoes/galoshes
	if(!find_carried_tool(/obj/item/lightreplacer))
		. += /obj/item/lightreplacer

/datum/bot_brain/proc/find_janidrobe(list/wanted)
	var/obj/machinery/vending/best
	var/best_dist
	for(var/obj/machinery/vending/wardrobe/jani_wardrobe/V as anything in bot_instances_of(/obj/machinery/vending/wardrobe/jani_wardrobe))
		if(!janitor_in_reach(V) || V.panel_open || (V.stat & (BROKEN|NOPOWER)) || !length(vendor_stock(V, wanted)))
			continue
		var/dist = get_dist(owner, V)
		if(!best || dist < best_dist)
			best = V
			best_dist = dist
	return best

/// Water for the bucket: a tank or a sink, further afield than the botanist's version looks - the janitor's own tank
/// is back in the closet, wherever on the station the bucket ran dry.
/datum/bot_brain/proc/find_janitor_water()
	var/atom/best
	var/best_dist
	for(var/obj/structure/reagent_dispensers/watertank/T as anything in bot_instances_of(/obj/structure/reagent_dispensers/watertank))
		if(!janitor_in_reach(T) || T.reagents?.get_reagent_amount(/datum/reagent/water) < 20 || LAZYACCESS(janitor_blocked, T) > world.time)
			continue
		var/dist = get_dist(owner, T)
		if(!best || dist < best_dist)
			best = T
			best_dist = dist
	for(var/obj/structure/sink/S as anything in bot_instances_of(/obj/structure/sink))
		if(!janitor_in_reach(S) || S.dispensedreagent != /datum/reagent/water || LAZYACCESS(janitor_blocked, S) > world.time)
			continue
		var/dist = get_dist(owner, S)
		if(!best || dist < best_dist)
			best = S
			best_dist = dist
	return best

// ---------------------------------------------------------------------------------------------
// The round
// ---------------------------------------------------------------------------------------------

/datum/bot_duty/janitor
	name = "janitor's rounds"
	jobs = list("Janitor")
	interval_min = 40
	interval_max = 100

/datum/bot_duty/janitor/try_start(datum/bot_brain/bot)
	if(bot.state == BOT_STATE_GOAL && bot.current_goal)
		return FALSE //a chained continuation arriving after something else took the goal slot
	// Kit first: galoshes and the light replacer, once.
	if(world.time >= bot.janitor_wardrobe_retry)
		bot.janitor_wardrobe_retry = world.time + 5 MINUTES
		var/list/wanted = bot.janitor_wardrobe_wants()
		if(length(wanted) && bot.find_janidrobe(wanted) && bot.assign_goal(new /datum/bot_goal/janitor_wardrobe()))
			return TRUE
	// No mop to be had (there is one on the whole station, and two janitors): no mopping, until one turns up.
	var/can_mop = bot.find_carried_tool(/obj/item/mop) || bot.find_loose_item(/obj/item/mop)
	var/obj/effect/decal/cleanable/mess = can_mop ? bot.pick_mess() : null
	var/obj/machinery/light/dead_light = bot.pick_dead_light()
	// Something foul on the floor comes before a dead light; a dead light before everyday dirt.
	if(mess && (!dead_light || bot_mess_priority(mess) >= 3) && bot.assign_goal(new /datum/bot_goal/mop_mess(mess)))
		return TRUE
	if(dead_light && bot.assign_goal(new /datum/bot_goal/replace_light(dead_light)))
		return TRUE
	if(mess && bot.assign_goal(new /datum/bot_goal/mop_mess(mess)))
		return TRUE
	// Nothing to do: the mop and bucket go away rather than being carried about on a stroll.
	for(var/obj/item/I in bot.owner.held_items)
		if(istype(I, /obj/item/mop) || istype(I, /obj/item/reagent_containers/glass/bucket) || istype(I, /obj/item/lightreplacer))
			bot.put_away(I, allow_equip = FALSE)
	return FALSE

/// Straight on to the next thing, the way someone in the middle of their rounds does - a slacker less reliably.
/datum/bot_brain/proc/continue_janitor_round()
	if(prob((1 - diligence) * 40))
		return
	var/datum/bot_duty/janitor/duty = bot_duty_of(/datum/bot_duty/janitor)
	continue_goal_chain(CALLBACK(duty, TYPE_PROC_REF(/datum/bot_duty, try_start), src))

// ---------------------------------------------------------------------------------------------
// Mopping
// ---------------------------------------------------------------------------------------------

/datum/bot_goal/mop_mess
	lawful = TRUE
	exclusive = TRUE
	doing = "mopping the floor"
	/// The tile the mess is on - the decal itself is gone the moment it's mopped.
	var/turf/spot

/datum/bot_goal/mop_mess/New(obj/effect/decal/cleanable/mess)
	. = ..()
	target = mess
	spot = get_turf(mess)

/datum/bot_goal/mop_mess/resolve_target(datum/bot_brain/bot)
	if(QDELETED(target))
		target = null
		return
	careful = !bot.has_noslip_shoes() //no galoshes: it walks, or it's flat on its back on the first wet tile

/datum/bot_goal/mop_mess/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/janitor/S = new
	S.steps = list(new /datum/bot_step/prepare_to_mop(), new /datum/bot_step/move_to(), new /datum/bot_step/paced/mop_floor())
	return list(S)

/datum/bot_goal/mop_mess/on_success(datum/bot_brain/bot)
	bot.continue_janitor_round()

/datum/bot_goal/mop_mess/on_give_up(datum/bot_brain/bot)
	if(!spot)
		return
	LAZYSET(bot.janitor_blocked, spot, world.time + 5 MINUTES)
	// Never got near it: somewhere this janitor's ID doesn't open (medbay, the bridge). The whole room is left for
	// a while, rather than walking to its door once for every stain inside.
	if(get_dist(bot.owner, spot) > 2 && !bot.gym_run)
		LAZYSET(bot.janitor_blocked, get_area(spot), world.time + 10 MINUTES)

/datum/bot_strategy/janitor
	max_attempts = 2 //a fumbled click gets a second go before the spot is written off for five minutes

/datum/bot_strategy/janitor/is_feasible(datum/bot_brain/bot)
	return bot.current_goal?.target && !QDELETED(bot.current_goal.target)

/// A mop, a bucket, water in the bucket and the mop wet - each fetched or done in turn, one try apiece.
/datum/bot_step/prepare_to_mop
	var/list/tried

/datum/bot_step/prepare_to_mop/execute(datum/bot_brain/bot)
	LAZYINITLIST(tried)
	var/obj/item/mop/mop = bot.find_carried_tool(/obj/item/mop)
	if(!mop)
		return fetch(bot, "mop", /obj/item/mop)
	if(mop.reagents.total_volume >= 1)
		return GOAL_STEP_SUCCESS
	var/obj/item/reagent_containers/glass/bucket/bucket = bot.find_carried_tool(/obj/item/reagent_containers/glass/bucket)
	if(!bucket)
		return fetch(bot, "bucket", /obj/item/reagent_containers/glass/bucket)
	if(bucket.reagents.total_volume < 5)
		if("water" in tried)
			bot_log(bot, "no water for the mop bucket")
			return GOAL_STEP_FAIL
		tried += "water"
		if(bot.suspend_goal_for(new /datum/bot_goal/fill_bucket/janitor()))
			return GOAL_STEP_PENDING
		return GOAL_STEP_FAIL
	return bot.wet_mop(mop, bucket) ? GOAL_STEP_SUCCESS : GOAL_STEP_FAIL

/datum/bot_step/prepare_to_mop/proc/fetch(datum/bot_brain/bot, key, item_type)
	if(key in tried)
		bot_log(bot, "nowhere to get a [key]")
		return GOAL_STEP_FAIL
	tried += key
	if(bot.suspend_goal_for(new /datum/bot_goal/take_item(item_type))) //goals/take_item.dm - into a hand, never onto the head
		return GOAL_STEP_PENDING
	return GOAL_STEP_FAIL

/// The bucket in the off hand and the mop dunked in it until it's full - 5u a dunk, 15u to the mop.
/datum/bot_brain/proc/wet_mop(obj/item/mop/mop, obj/item/reagent_containers/glass/bucket/bucket)
	if(!(bucket in owner.held_items) && !ready_in_hand(bucket))
		return FALSE
	for(var/dunk in 1 to 3)
		if(mop.reagents.holder_full() || bucket.reagents.total_volume < 1)
			break
		if(!use_item_on(mop, bucket))
			return FALSE
	return mop.reagents.total_volume >= 1

/// The botanist's bucket-filling errand, from the janitor's water (find_janitor_water()).
/datum/bot_goal/fill_bucket/janitor
	lawful = TRUE
	doing = "filling the mop bucket"

/datum/bot_goal/fill_bucket/janitor/resolve_target(datum/bot_brain/bot)
	target = bot.find_janitor_water()

/// A tap behind a door that doesn't open for a janitor: not that one again for a while.
/datum/bot_goal/fill_bucket/janitor/on_give_up(datum/bot_brain/bot)
	if(target)
		LAZYSET(bot.janitor_blocked, target, world.time + 10 MINUTES)

/// Mops the tile it came for and whatever else is dirty within arm's reach, re-wetting the mop from the bucket as
/// it goes: one tile a stroke, a stroke every second and a half.
/datum/bot_step/paced/mop_floor
	max_clicks = 30
	var/turf/spot
	var/mopped = 0

/datum/bot_step/paced/mop_floor/start(datum/bot_brain/bot)
	var/datum/bot_goal/mop_mess/G = bot.current_goal
	spot = istype(G) ? G.spot : null
	mopped = 0
	return spot && get_dist(bot.owner, spot) <= 1

/datum/bot_step/paced/mop_floor/do_click(datum/bot_brain/bot)
	var/obj/item/mop/mop = bot.find_carried_tool(/obj/item/mop)
	if(!mop)
		return FALSE
	if(!spot || !bot.turf_has_mess(spot))
		if(spot)
			mopped++
			bot.tiles_mopped++
		spot = null
		if(mopped >= BOT_MOP_TILES_PER_STOP)
			return FALSE
		// Anything else dirty that can be reached from here without taking a step.
		for(var/turf/open/T in range(1, bot.owner))
			if(bot.turf_has_mess(T) && bot.owner.Adjacent(T) && !(LAZYACCESS(bot.janitor_blocked, T) > world.time))
				spot = T
				break
		if(!spot)
			return FALSE
	if(mop.reagents.total_volume < 1)
		var/obj/item/reagent_containers/glass/bucket/bucket = bot.find_carried_tool(/obj/item/reagent_containers/glass/bucket)
		if(!bucket || bucket.reagents.total_volume < 1)
			return FALSE //dry: the next round goes for water
		return bot.wet_mop(mop, bucket)
	if(!bot.ready_in_hand(mop))
		return FALSE
	bot_log(bot, "mopping [spot] ([get_area_name(spot)])")
	var/before = mop.reagents.total_volume
	bot.use_item_on(mop, spot) //mop/afterattack(): a 1.5s do_after, then clean()
	if(mop.reagents.total_volume >= before)
		LAZYSET(bot.janitor_blocked, spot, world.time + 2 MINUTES) //the stroke never landed (jostled, or the tile's out of reach after all)
		spot = null
	return TRUE

/datum/bot_step/paced/mop_floor/finish(datum/bot_brain/bot)
	spot = null
	return mopped ? GOAL_STEP_SUCCESS : GOAL_STEP_FAIL

// ---------------------------------------------------------------------------------------------
// Lights
// ---------------------------------------------------------------------------------------------

/datum/bot_goal/replace_light
	lawful = TRUE
	exclusive = TRUE
	doing = "changing a light tube"

/datum/bot_goal/replace_light/New(obj/machinery/light/fixture)
	. = ..()
	target = fixture

/datum/bot_goal/replace_light/resolve_target(datum/bot_brain/bot)
	if(QDELETED(target))
		target = null

/datum/bot_goal/replace_light/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/janitor/S = new
	S.steps = list(new /datum/bot_step/move_to(), new /datum/bot_step/replace_light())
	return list(S)

/datum/bot_goal/replace_light/on_success(datum/bot_brain/bot)
	bot.continue_janitor_round()

/datum/bot_goal/replace_light/on_give_up(datum/bot_brain/bot)
	if(target)
		LAZYSET(bot.janitor_blocked, target, world.time + 5 MINUTES)

/datum/bot_step/replace_light/execute(datum/bot_brain/bot)
	var/obj/machinery/light/fixture = bot.current_goal?.target
	var/obj/item/lightreplacer/replacer = bot.find_carried_tool(/obj/item/lightreplacer)
	if(!istype(fixture) || QDELETED(fixture) || !replacer)
		return GOAL_STEP_FAIL
	if(fixture.status == LIGHT_OK)
		return GOAL_STEP_SUCCESS //someone got there first
	bot_log(bot, "replacing the [fixture.fitting] in [get_area_name(fixture)]")
	if(!bot.use_item_on(replacer, fixture) || fixture.status != LIGHT_OK)
		return GOAL_STEP_FAIL
	bot.lights_replaced++
	return GOAL_STEP_SUCCESS

// ---------------------------------------------------------------------------------------------
// The JaniDrobe
// ---------------------------------------------------------------------------------------------

/datum/bot_goal/janitor_wardrobe
	lawful = TRUE
	doing = "getting my gear"

/datum/bot_goal/janitor_wardrobe/resolve_target(datum/bot_brain/bot)
	target = bot.find_janidrobe(bot.janitor_wardrobe_wants())

/datum/bot_goal/janitor_wardrobe/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/janitor/S = new
	S.steps = list(new /datum/bot_step/move_to(), new /datum/bot_step/paced/vend_products(bot.janitor_wardrobe_wants()), new /datum/bot_step/wear_galoshes())
	return list(S)

/datum/bot_goal/janitor_wardrobe/on_success(datum/bot_brain/bot)
	bot.continue_janitor_round()

/// Galoshes on, the shoes they replace into the bag.
/datum/bot_step/wear_galoshes/execute(datum/bot_brain/bot)
	var/obj/item/clothing/shoes/galoshes/G = bot.find_carried_tool(/obj/item/clothing/shoes/galoshes)
	if(G && !bot.has_noslip_shoes())
		bot.wear(G, ITEM_SLOT_FEET)
	return GOAL_STEP_SUCCESS

#undef BOT_JANITOR_REACH
#undef BOT_MOP_TILES_PER_STOP
