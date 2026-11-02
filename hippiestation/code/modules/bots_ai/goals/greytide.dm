// Greytide. Most assistants, the odd clown and one or two of anybody else are out for trouble when they get the chance
// (bot_brain.greytider, bot_personality.dm): a round where everybody does their job has nothing happening in it.
//
// It goes the way it goes for a player. Something heavy first: a toolbox, or the extinguisher off the wall. Then off to a
// department, in by the front door if it opens and through the window if it doesn't, to smash what's in there and pocket
// what's worth having. The crew sees it (bot_witness.dm), calls it in and comes for it, and it fights them and slips its
// cuffs (bot_reflexes.dm). Now and then one puts a call out on the radio and every tider on the station turns up.
//
// There's a line: it keeps away from the engine, the air and the AI, and it doesn't put a hole in the hull. A griefing
// player has a whole round to answer for; a bot doing that would end every shift the same way.

/// How long after the round starts before anybody starts anything.
#define BOT_TIDE_SETTLE_IN (5 MINUTES)
/// Between one piece of trouble and the next, for one bot.
#define BOT_TIDE_REST (4 MINUTES)
/// The longest it keeps at a spree of smashing.
#define BOT_TIDE_SPREE (100 SECONDS)
/// How long the crew are still after it once it's stopped.
#define BOT_TIDE_HEAT (90 SECONDS)
/// How far from the bot it looks for the next thing to smash.
#define BOT_TIDE_REACH 7

/// Where a tider goes to make trouble, and how much they like it: rooms with something in them, and nothing that ends the round.
GLOBAL_LIST_INIT(bot_mischief_areas, list(
	/area/crew_quarters/bar = 4,
	/area/crew_quarters/cafeteria = 3,
	/area/crew_quarters/kitchen = 2,
	/area/hydroponics = 2,
	/area/library = 2,
	/area/chapel/main = 1,
	/area/medical/medbay/lobby = 3,
	/area/medical/medbay/central = 3,
	/area/medical/chemistry = 3,
	/area/science/research = 3,
	/area/science/lab = 2,
	/area/science/robotics = 2,
	/area/storage/primary = 3,
	/area/storage/tech = 3,
	/area/storage/art = 1,
	/area/quartermaster/office = 3,
	/area/quartermaster/storage = 2,
	/area/crew_quarters/theatre = 2,
	/area/crew_quarters/dorms = 1,
	/area/crew_quarters/heads/hop = 1,
	/area/bridge = 1,
	/area/security/brig = 1,
	/area/hallway/primary/central = 2,
))

/// What's worth a swing, for what it does to the room. The first three are why anybody does this.
GLOBAL_LIST_INIT(bot_tide_targets, typecacheof(list(
	/obj/machinery/vending,
	/obj/machinery/computer,
	/obj/machinery/smartfridge,
	/obj/machinery/chem_dispenser,
	/obj/machinery/chem_master,
	/obj/machinery/autolathe,
	/obj/machinery/rnd/production,
	/obj/machinery/microwave,
	/obj/machinery/newscaster,
	/obj/machinery/light,
	/obj/machinery/camera,
	/obj/machinery/door/window,
	/obj/structure/window,
	/obj/structure/grille,
	/obj/structure/table,
	/obj/structure/rack,
	/obj/structure/displaycase,
	/obj/structure/mirror,
)))

/// What gets pocketed on the way past.
GLOBAL_LIST_INIT(bot_tide_loot, typecacheof(list(
	/obj/item/clothing/gloves/color/yellow,
	/obj/item/storage/toolbox,
	/obj/item/storage/firstaid,
	/obj/item/storage/belt,
	/obj/item/melee,
	/obj/item/gun,
	/obj/item/weldingtool,
	/obj/item/crowbar,
	/obj/item/multitool,
	/obj/item/reagent_containers/glass/beaker,
	/obj/item/reagent_containers/pill,
	/obj/item/stock_parts/cell,
	/obj/item/card/id,
)))

GLOBAL_LIST_INIT(bot_tide_lines, list(
	"Haha, get wrecked!",
	"Whoops!",
	"Oops, did I do that?",
	"This place needed redecorating.",
	"Greytide worldwide!",
	"Nobody saw that.",
	"Come at me, shitcurity!",
))

GLOBAL_LIST_INIT(bot_tide_rally_lines, list(
	"GREYTIDE WORLDWIDE! EVERYONE TO",
	"TIDE'S IN! MEET AT",
	"ASSISTANTS UNITE! BRING TOOLBOXES TO",
	"WE RIOT AT DAWN! BY WHICH I MEAN NOW! GET TO",
))

GLOBAL_LIST_INIT(bot_tide_insults, list(
	"Nice uniform. Did your mum pick it?",
	"What are you looking at?",
	"Hey, gimme your ID.",
	"You look like you need a shove.",
	"You got all access? Give it here.",
	"Move it, buddy.",
))

/datum/bot_brain
	/// When it can next start something.
	var/next_mischief_time = 0
	/// Until when anybody who sees it would know it's up to something.
	var/trouble_until = 0
	/// Where a riot's been called, and until when that's where it means to go.
	var/area/riot_room
	var/riot_until = 0
	/// Things it's smashed, and things it's pocketed, for the Bot Shift report.
	var/things_smashed = 0
	var/things_looted = 0

/// Base of the goals that are trouble, for up_to_no_good() (bot_reflexes.dm).
/datum/bot_goal/tide
	doing = "just looking around"

/datum/bot_goal/tide/on_give_up(datum/bot_brain/bot)
	bot.trouble_until = world.time + BOT_TIDE_HEAT

/datum/bot_goal/tide/on_success(datum/bot_brain/bot)
	bot.trouble_until = world.time + BOT_TIDE_HEAT

/datum/bot_strategy/tide/is_feasible(datum/bot_brain/bot)
	return bot.current_goal?.target && !QDELETED(bot.current_goal.target)

/// Greytiders out and about right now.
/proc/bot_tiders_out()
	. = 0
	for(var/datum/bot_brain/B as anything in GLOB.bot_brains)
		if(B.greytider && B.up_to_no_good())
			.++

/// Whether something can be swung at, by this bot, right now, and what it's worth.
/datum/bot_brain/proc/tide_value(obj/O, obj/item/W)
	if(QDELETED(O) || !is_type_in_typecache(O, GLOB.bot_tide_targets) || (O.resistance_flags & INDESTRUCTIBLE))
		return 0
	var/obj/machinery/M = O
	if(istype(M) && (M.stat & BROKEN))
		return 0
	if(bot_holds_back_space(O) || bot_breach_damage(W, O) <= 0)
		return 0
	if(LAZYACCESS(ineffective_breach_pairs, "[O.type]|[W.type]"))
		return 0
	if(istype(O, /obj/machinery/vending) || istype(O, /obj/machinery/computer) || istype(O, /obj/structure/displaycase) || istype(O, /obj/machinery/chem_dispenser))
		return 10
	if(istype(O, /obj/machinery) || istype(O, /obj/structure/mirror))
		return 6
	return istype(O, /obj/structure/window) ? 5 : 3

/// Whether breaking this would let the vacuum in.
/proc/bot_holds_back_space(obj/O)
	var/turf/T = get_turf(O)
	if(!T)
		return TRUE
	for(var/d in GLOB.alldirs)
		if(isspaceturf(get_step(T, d)))
			return TRUE
	return FALSE

/// The thing to hit things with: the heaviest it has that works as one.
/datum/bot_brain/proc/mischief_weapon()
	var/obj/item/best
	var/best_force = BOT_COMBAT_WEAPON_FORCE - 1
	for(var/atom/source in get_breach_kit())
		var/obj/item/I = source
		if(!istype(I) || !is_carried(I) || QDELETED(I) || istype(I, /obj/item/gun))
			continue
		var/force = bot_weapon_force(I)
		if(force > best_force)
			best = I
			best_force = force
	return best

/datum/bot_duty/greytide
	name = "causing trouble"
	priority = 40
	interval_min = 300
	interval_max = 900

/datum/bot_duty/greytide/applies_to(datum/bot_brain/bot)
	return bot.greytider || bot.gym_run

/datum/bot_duty/greytide/next_look(datum/bot_brain/bot)
	return rand(interval_min, interval_max)

/datum/bot_duty/greytide/try_start(datum/bot_brain/bot)
	if(!bot.greytider || !bot_mischief_allowed() || world.time < bot.next_mischief_time)
		return FALSE
	if(!bot.gym_run && world.time < SSticker.round_start_time + BOT_TIDE_SETTLE_IN)
		return FALSE
	if(bot.owner.handcuffed || bot.is_in_active_cell(bot.owner))
		return FALSE
	if(!bot.gym_run && world.time >= bot.riot_until && bot_tiders_out() >= GLOB.bot_chaos_level * 2)
		return FALSE //no more than a couple at a time, unless it's a riot or a really bad shift
	return bot.plan_mischief()

/proc/bot_mischief_allowed()
	return GLOB.bot_chaos_level >= 1 || GLOB.bot_gym_running

/// Sets it off on something. TRUE if it's now up to no good.
/datum/bot_brain/proc/plan_mischief()
	next_mischief_time = world.time + (BOT_TIDE_REST + rand(0, 3 MINUTES)) / max(GLOB.bot_chaos_level, 1)
	if(!mischief_weapon())
		var/datum/bot_goal/tide/arm_up/kit = new
		if(assign_goal(kit))
			next_mischief_time = world.time //and straight on to using it
			return TRUE
	if(world.time < riot_until)
		return assign_goal(new /datum/bot_goal/tide/smash(riot_room))
	if(!mischief_weapon())
		next_mischief_time = world.time + 1 MINUTES //nothing to swing and nothing to be had: a word on the radio instead, and another look shortly
		mouth_off()
		return FALSE
	var/plan = pickweight(list("smash" = 6, "harass" = 3, "mouth off" = 2))
	if(plan == "mouth off")
		mouth_off()
		next_mischief_time = world.time + 1 MINUTES
		return FALSE
	var/mob/living/carbon/human/mark = plan == "harass" ? find_mark() : null
	if(mark)
		return assign_goal(new /datum/bot_goal/tide/harass(mark))
	return assign_goal(new /datum/bot_goal/tide/smash())

/// Says something on the radio that'll get somebody's back up.
/datum/bot_brain/proc/mouth_off()
	bot_say(owner, ";[pick(GLOB.bot_radio_mouthing)]")

GLOBAL_LIST_INIT(bot_radio_mouthing, list(
	"HoP give me all access or I'm opening every door on this station",
	"Captain is a comdom",
	"who stole my insuls",
	"sec is shitcurity, I did nothing wrong",
	"AI open the armory, I have a very good reason",
	"can someone buckle me to something",
	"why is the janitor looking at me like that",
	"RD let me have the hand tele I'll bring it back",
	"medbay is a meatlocker",
	"is the clown allowed to do that",
	"I swear this is a toolbox for WORK",
	"robust me, cowards",
))

// ---------------------------------------------------------------------------------------------
// Getting something heavy
// ---------------------------------------------------------------------------------------------

/// Goes and gets something to swing: the nearest toolbox, or the extinguisher off the nearest wall.
/datum/bot_goal/tide/arm_up
	lawful = TRUE

/datum/bot_goal/tide/arm_up/resolve_target(datum/bot_brain/bot)
	var/list/sources = list() //source -> how far off
	for(var/obj/item/storage/toolbox/T as anything in bot_instances_of(/obj/item/storage/toolbox))
		if(!QDELETED(T) && isturf(T.loc) && T.z == bot.owner.z)
			sources[T] = get_dist(bot.owner, T)
	for(var/obj/structure/extinguisher_cabinet/C as anything in bot_instances_of(/obj/structure/extinguisher_cabinet))
		if(!QDELETED(C) && C.stored_extinguisher && C.z == bot.owner.z && !C.opened)
			sources[C] = get_dist(bot.owner, C) + 6 //it only just does the job
	var/tries = 0
	while(length(sources) && tries++ < 12)
		var/atom/nearest
		for(var/atom/A as anything in sources)
			if(!nearest || sources[A] < sources[nearest])
				nearest = A
		sources -= nearest
		if(bot.gym_run ? get_area(nearest) == get_area(bot.owner) : bot.can_walk_lawfully_to(nearest))
			target = nearest
			return

/datum/bot_goal/tide/arm_up/get_strategies(datum/bot_brain/bot)
	if(istype(target, /obj/structure/extinguisher_cabinet))
		return list(new /datum/bot_strategy/grab_from_extinguisher_cabinet())
	return list(new /datum/bot_strategy/grab_item())

/datum/bot_goal/tide/arm_up/on_give_up(datum/bot_brain/bot)
	return //nothing's happened that anybody would hold against it

/datum/bot_goal/tide/arm_up/on_success(datum/bot_brain/bot)
	return

// ---------------------------------------------------------------------------------------------
// Smashing
// ---------------------------------------------------------------------------------------------

/// Off to a department, and everything in it that'll break. A way in by whatever door it opens, or the window if none do.
/datum/bot_goal/tide/smash
	var/area/place
	/// What it's going for first: something in the room, or the window that's in the way.
	var/obj/first_target

/datum/bot_goal/tide/smash/New(area/where)
	. = ..()
	place = where

/// All it has in mind is a room. The first thing to break in it decides where it goes.
/datum/bot_goal/tide/smash/resolve_target(datum/bot_brain/bot)
	var/obj/item/W = bot.mischief_weapon()
	if(!W)
		return
	if(bot.gym_run)
		place = get_area(bot.owner)
	if(place)
		target = bot.way_into(place, W)
		return
	var/list/rooms = GLOB.bot_mischief_areas.Copy()
	for(var/tries in 1 to 8)
		if(!length(rooms))
			return
		var/area_type = pickweight(rooms)
		rooms -= area_type
		var/area/A = GLOB.areas_by_type[area_type]
		if(!A || A.z != bot.owner.z)
			continue
		target = bot.way_into(A, W)
		if(target)
			place = A
			return

/// The nearest thing worth breaking in a room this bot can walk up to, or failing that a window into it from a corridor.
/datum/bot_brain/proc/way_into(area/room, obj/item/W)
	var/list/candidates = list() //thing -> how far off
	for(var/obj/O in room)
		if(tide_value(O, W))
			candidates[O] = get_dist(owner, O)
	var/tries = 0
	while(length(candidates) && tries++ < 8)
		var/obj/nearest
		for(var/obj/O as anything in candidates)
			if(!nearest || candidates[O] < candidates[nearest])
				nearest = O
		candidates -= nearest
		if(gym_run || can_walk_lawfully_to(nearest))
			return nearest
	return null

/datum/bot_goal/tide/smash/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/tide/S = new
	S.steps = list(new /datum/bot_step/move_to(), new /datum/bot_step/paced/smash_spree())
	return list(S)

/datum/bot_goal/tide/smash/on_success(datum/bot_brain/bot)
	..()
	bot.get_clear_of_the_scene()

/datum/bot_goal/tide/smash/on_give_up(datum/bot_brain/bot)
	..()
	bot.get_clear_of_the_scene()

/// Done: off somewhere else, before anybody comes. Maintenance, if it can.
/datum/bot_brain/proc/get_clear_of_the_scene()
	var/obj/item/W = mischief_weapon()
	if(W && owner.get_active_held_item() == W)
		put_away(W)

/// One swing a second at the best thing in reach, walking from one to the next, until the time's up or there's nothing left.
/datum/bot_step/paced/smash_spree
	max_clicks = 200
	var/ends_at = 0
	var/obj/mark
	var/announced = FALSE

/datum/bot_step/paced/smash_spree/start(datum/bot_brain/bot)
	ends_at = world.time + BOT_TIDE_SPREE
	mark = null
	announced = FALSE
	return !!bot.mischief_weapon()

/datum/bot_step/paced/smash_spree/do_click(datum/bot_brain/bot)
	var/mob/living/carbon/human/H = bot.owner
	if(world.time > ends_at || H.incapacitated())
		return FALSE
	var/obj/item/W = bot.mischief_weapon()
	if(!W)
		return FALSE
	bot.trouble_until = world.time + BOT_TIDE_HEAT
	if(!announced)
		announced = TRUE
		if(prob(40))
			bot_say(H, pick(GLOB.bot_tide_lines))
	if(prob(25) && bot.pocket_something())
		wait_for = 8
		return TRUE
	if(QDELETED(mark) || !bot.tide_value(mark, W))
		mark = pick_mark(bot, W)
		if(!mark)
			return FALSE
	if(!H.Adjacent(mark))
		if(bot.pursuing_kind != "follow" || bot.pursue_target != mark)
			if(!bot.gym_run && !bot.can_walk_lawfully_to(mark))
				LAZYSET(bot.ineffective_breach_pairs, "[mark.type]|[W.type]", TRUE)
				mark = null
				wait_for = 5
				return TRUE
			bot.pursue(mark, "follow", force = TRUE)
		wait_for = 8
		return TRUE
	bot.stop_pursuit()
	var/integrity_before = mark.obj_integrity
	var/obj/target_now = mark
	bot.use_item_on(W, target_now, TRUE)
	if(QDELETED(target_now) || !bot.tide_value(target_now, W))
		bot.things_smashed++
		bot_log(bot, "smashed [target_now]")
	else if(target_now.obj_integrity >= integrity_before)
		bot_log(bot, "[W] isn't doing anything to [target_now]")
		LAZYSET(bot.ineffective_breach_pairs, "[target_now.type]|[W.type]", TRUE)
	H.changeNext_move(CLICK_CD_MELEE)
	wait_for = CLICK_CD_MELEE
	return TRUE

/datum/bot_step/paced/smash_spree/proc/pick_mark(datum/bot_brain/bot, obj/item/W)
	var/obj/best
	var/best_score = 0
	for(var/obj/O in view(BOT_TIDE_REACH, bot.owner))
		var/value = bot.tide_value(O, W)
		if(!value)
			continue
		var/score = value * 3 - get_dist(bot.owner, O)
		if(!best || score > best_score)
			best = O
			best_score = score
	return best

/datum/bot_step/paced/smash_spree/finish(datum/bot_brain/bot)
	bot.stop_pursuit()
	mark = null
	return bot.things_smashed ? GOAL_STEP_SUCCESS : GOAL_STEP_FAIL

/// Something worth having within reach, on the floor or on a table: into a pocket with it.
/datum/bot_brain/proc/pocket_something()
	for(var/obj/item/I in range(1, owner))
		if(!isturf(I.loc) || I.anchored || !is_type_in_typecache(I, GLOB.bot_tide_loot) || already_carries_matching_tool(I))
			continue
		if(!try_pickup_target(I))
			return FALSE
		things_looted++
		bot_log(src, "pocketed [I]")
		return TRUE
	return FALSE

/// Another tider going at it in front of it: it isn't going to miss out on that.
/datum/bot_brain/proc/join_in_the_smashing(mob/living/carbon/human/vandal)
	if(state != BOT_STATE_WANDER || current_goal || !bot_mischief_allowed())
		return
	var/obj/item/W = mischief_weapon()
	if(W)
		bot_say(owner, pick("Yeah! Smash it!", "Haha, nice!", "Wait up!", "Tide's in!"))
		assign_goal(new /datum/bot_goal/tide/smash(get_area(vandal)))

// ---------------------------------------------------------------------------------------------
// Harassing somebody
// ---------------------------------------------------------------------------------------------

/// Somebody in sight worth bothering: a lone bystander who isn't security.
/datum/bot_brain/proc/find_mark()
	var/mob/living/carbon/human/best
	for(var/mob/living/carbon/human/H in view(7, owner))
		if(H == owner || H.stat != CONSCIOUS || bot_is_officer(H) || H.handcuffed)
			continue
		if(!best || get_dist(owner, H) < get_dist(owner, best))
			best = H
	return best

/datum/bot_goal/tide/harass
	/// How many goes it has at them. Picked when it starts if this is left alone.
	var/shoves = 0

/datum/bot_goal/tide/harass/New(mob/living/carbon/human/mark)
	. = ..()
	target = mark

/datum/bot_goal/tide/harass/resolve_target(datum/bot_brain/bot)
	if(QDELETED(target))
		target = null

/datum/bot_goal/tide/harass/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/tide/S = new
	S.steps = list(new /datum/bot_step/move_to(), new /datum/bot_step/paced/harass())
	return list(S)

/// A few shoves and a word or two. It's for them to take it further.
/datum/bot_step/paced/harass
	max_clicks = 10
	var/turns = 0

/datum/bot_step/paced/harass/start(datum/bot_brain/bot)
	var/datum/bot_goal/tide/harass/G = bot.current_goal
	turns = G?.shoves || rand(2, 5)
	bot.trouble_until = world.time + BOT_TIDE_HEAT
	bot_say(bot.owner, pick(GLOB.bot_tide_insults))
	return TRUE

/datum/bot_step/paced/harass/do_click(datum/bot_brain/bot)
	var/mob/living/carbon/human/mark = bot.current_goal?.target
	if(turns-- <= 0 || QDELETED(mark) || mark.stat != CONSCIOUS || !bot.owner.Adjacent(mark))
		return FALSE
	bot.trouble_until = world.time + BOT_TIDE_HEAT
	bot.human_pause(mark)
	if(QDELETED(mark) || !bot.owner.Adjacent(mark))
		return FALSE
	if(bot.owner.incapacitated()) //pushed over, and it isn't finished: it gets up and goes back to it. Each second down costs it a go.
		wait_for = 10
		return TRUE
	bot.owner.face_atom(mark)
	bot.owner.changeNext_move(CLICK_CD_MELEE)
	bot.owner.a_intent = pick(INTENT_DISARM, INTENT_DISARM, INTENT_GRAB)
	bot.telemetry_clicked(mark)
	bot.owner.UnarmedAttack(mark, TRUE)
	bot.owner.a_intent = INTENT_HELP
	bot.owner.stop_pulling()
	wait_for = rand(10, 25)
	return TRUE

// ---------------------------------------------------------------------------------------------
// The clown's banana
// ---------------------------------------------------------------------------------------------

/// The one in the clown's bag: eaten, and the skin left where somebody will tread on it, just inside a door.
/datum/bot_duty/prank
	name = "pulling a prank"
	jobs = list("Clown")
	interval_min = 1800
	interval_max = 3600

/datum/bot_duty/prank/try_start(datum/bot_brain/bot)
	if(!bot_mischief_allowed())
		return FALSE
	if(!bot.find_carried_tool(/obj/item/grown/bananapeel) && !bot.find_carried_tool(/obj/item/reagent_containers/food/snacks/grown/banana))
		return FALSE
	var/turf/spot = bot.pick_prank_spot()
	return spot ? bot.assign_goal(new /datum/bot_goal/tide/banana_skin(spot)) : FALSE

/// A tile next to a door it can see.
/datum/bot_brain/proc/pick_prank_spot()
	for(var/obj/machinery/door/D in view(7, owner))
		for(var/turf/open/T in get_adjacent_open_turfs(D))
			if(!is_blocked_turf(T, TRUE) && !(locate(/obj/item/grown/bananapeel) in T))
				return T
	return null

/datum/bot_goal/tide/banana_skin/New(turf/spot)
	. = ..()
	target = spot

/datum/bot_goal/tide/banana_skin/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/tide/S = new
	S.steps = list(new /datum/bot_step/paced/eat_the_banana(), new /datum/bot_step/move_to(), new /datum/bot_step/leave_the_skin())
	return list(S)

/// A bite at a time, like any other meal, until there's only the skin left.
/datum/bot_step/paced/eat_the_banana
	max_clicks = 10
	optional = TRUE

/datum/bot_step/paced/eat_the_banana/do_click(datum/bot_brain/bot)
	var/obj/item/reagent_containers/food/snacks/grown/banana/B = bot.find_carried_tool(/obj/item/reagent_containers/food/snacks/grown/banana)
	if(!B || !bot.use_item_on(B, bot.owner))
		return FALSE
	wait_for = 15
	return TRUE

/datum/bot_step/leave_the_skin/execute(datum/bot_brain/bot)
	var/obj/item/grown/bananapeel/peel = bot.find_carried_tool(/obj/item/grown/bananapeel)
	if(!peel || !bot.ready_in_hand(peel))
		return GOAL_STEP_FAIL
	bot.owner.dropItemToGround(peel)
	bot_tally("banana skins left")
	bot_log(bot, "left a banana skin at [bot_coord(get_turf(peel))]")
	if(prob(50))
		bot_say(bot.owner, pick("Honk.", "Oops!", "Watch your step!"))
	return GOAL_STEP_SUCCESS

// ---------------------------------------------------------------------------------------------
// The tide coming in
// ---------------------------------------------------------------------------------------------

/// A tider puts it out on the radio, and every other one on the station drops what it's doing and comes.
/proc/bot_call_riot()
	var/list/tiders = list()
	for(var/datum/bot_brain/B as anything in GLOB.bot_brains)
		if(B.greytider && B.owner.stat == CONSCIOUS && !B.owner.handcuffed && !B.is_in_active_cell(B.owner))
			tiders += B
	if(length(tiders) < 2)
		return FALSE
	var/datum/bot_brain/ringleader = pick(tiders)
	var/area/room
	for(var/tries in 1 to 5)
		room = GLOB.areas_by_type[pickweight(GLOB.bot_mischief_areas)]
		if(room && room.z == ringleader.owner.z)
			break
		room = null
	if(!room)
		return FALSE
	bot_say(ringleader.owner, ";[pick(GLOB.bot_tide_rally_lines)] [uppertext(room.name)]!")
	log_game("BOT CHAOS: [ringleader.owner.real_name] called a riot in [room.name] ([length(tiders)] tiders)")
	for(var/datum/bot_brain/B as anything in tiders)
		B.riot_room = room
		B.riot_until = world.time + 3 MINUTES
		B.next_mischief_time = 0
		if(B.state == BOT_STATE_WANDER && !B.current_goal)
			B.plan_mischief() //the rest see to it when they're done with what's in hand
	return TRUE

#undef BOT_TIDE_SETTLE_IN
#undef BOT_TIDE_REST
#undef BOT_TIDE_SPREE
#undef BOT_TIDE_HEAT
#undef BOT_TIDE_REACH
