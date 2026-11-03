// The blob (bot-blob=1 on a Bot Shift, or bot_spawn_blob()): an overmind with the game's own blob antagonist datum, played the way
// players play it, through the same procs its buttons call:
//
//  - The core somewhere out of the way, in maintenance where the blob starts.
//  - The economy first: resource blobs by the core while the points come in, then factories for spores, nodes to reach further.
//  - Every spare point into spreading: at anybody near the edge first, then outwards, the way that's towards the middle of the station.
//
// The crew fight what they can see of it (fight_the_blob(), below): Security and anybody with something heavy in hand go at the
// nearest blob in sight. Its being there keeps the shuttle from being called (SSshuttle's hostile environment), as it does for players.

#define BOT_BLOB_TICK (1 SECONDS)
/// Resource blobs it keeps, before anything else.
#define BOT_BLOB_RESOURCES 3
#define BOT_BLOB_FACTORIES 2

GLOBAL_LIST_EMPTY(bot_blobs)

/datum/bot_brain/var/next_blob_check = 0

/mob/camera/blob/var/datum/bot_blob/bot_blob

/proc/bot_spawn_blob()
	var/list/starts = list()
	for(var/obj/effect/landmark/L in GLOB.blobstart)
		starts += get_turf(L)
	for(var/turf/T in GLOB.blobstart)
		starts += T
	if(!length(starts))
		return FALSE
	var/turf/T = pick(starts)
	var/mob/camera/blob/B = new(T, 60) //what the overmind starts with anyway
	B.mind_initialize()
	B.mind.add_antag_datum(/datum/antagonist/blob)
	new /datum/bot_blob(B)
	B.place_blob_core(0, TRUE)
	log_game("BOT BLOB: core at [AREACOORD(B.blob_core)]")
	return TRUE

/datum/bot_blob
	var/mob/camera/blob/owner
	var/started_at = 0
	var/next_dispatch = 0

/datum/bot_blob/New(mob/camera/blob/B)
	. = ..()
	owner = B
	B.bot_blob = src
	started_at = world.time
	if(!B.hud_used) //a player's comes with their client: the points and the core's health are written on it every change
		B.hud_used = new B.hud_type(B)
	GLOB.bot_blobs += src
	RegisterSignal(B, COMSIG_PARENT_QDELETING, PROC_REF(lost_overmind))
	think_loop()

/datum/bot_blob/proc/lost_overmind()
	GLOB.bot_blobs -= src
	if(owner)
		owner.bot_blob = null
	owner = null

/datum/bot_blob/proc/think_loop()
	set waitfor = FALSE
	while(!QDELETED(owner))
		try
			think()
		catch(var/exception/e)
			log_runtime("BOT BLOB EXCEPTION: [e] at [e.file]:[e.line]")
		sleep(BOT_BLOB_TICK)

/datum/bot_blob/proc/think()
	if(!owner.placed)
		owner.place_blob_core(0, TRUE)
		return
	if(QDELETED(owner.blob_core))
		return
	if(world.time >= started_at + 3 MINUTES && world.time >= next_dispatch) //the core announces itself at three minutes (core.dm): Security gets sent to it
		next_dispatch = world.time + 3 MINUTES
		bot_dispatch_security(get_turf(owner.blob_core), "the blob") //goals/security_tactics.dm
		send_volunteers()
		log_game("BOT BLOB: [length(owner.blobs_legit)] tiles, [round(owner.blob_points)] points, core [round(owner.blob_core.obj_integrity)]/[owner.blob_core.max_integrity]")
	if(build())
		return
	if(owner.blob_points >= BLOB_SPREAD_COST)
		var/turf/T = next_spread()
		if(T)
			owner.forceMove(T) //the overmind's eye goes where it clicks
			owner.expand_blob(T)

/// "Everybody grab something and kill the blob": the braver half of the armed crew go to it with Security, up to six at a time.
/datum/bot_blob/proc/send_volunteers()
	var/sent = 0
	for(var/datum/bot_brain/B as anything in shuffle(GLOB.bot_brains.Copy()))
		if(sent >= 6)
			break
		var/mob/living/carbon/human/H = B.owner
		if(QDELETED(H) || H.stat != CONSCIOUS || H.z != owner.blob_core.z || B.gone_loud() || B.is_security_job() || B.nerve < 0.5 || !(B.has_a_weapon() || B.find_carried_tool(/obj/item/weldingtool)))
			continue
		if(B.state != BOT_STATE_WANDER || H.health < H.maxHealth * 0.7)
			continue
		if(B.assign_goal(new /datum/bot_goal/approach_blob(owner.blob_core)))
			sent++
	if(sent)
		log_game("BOT BLOB: [sent] of the crew went to fight it")

/// To the blob's edge, on its own side of it and as far towards the core as that goes: open floor beside a blob. From there it cuts its
/// way in (hit_blob). It used to make for the open floor nearest the core within ten tiles: once the blob had grown past that nobody was
/// sent anywhere (one volunteer went in the last ten minutes of a round), and the nearest free floor was usually a room the blob had
/// closed round, with no way to it at all.
/datum/bot_goal/approach_blob
	doing = "going to fight the blob"
	var/obj/structure/blob/core/core

/datum/bot_goal/approach_blob/New(obj/structure/blob/core/C)
	. = ..()
	core = C

/datum/bot_goal/approach_blob/resolve_target(datum/bot_brain/bot)
	target = null
	var/mob/camera/blob/overmind = core?.overmind
	if(QDELETED(core) || !overmind)
		return
	var/turf/here = get_turf(bot.owner)
	var/best_score
	for(var/obj/structure/blob/B as anything in overmind.blobs_legit)
		if(QDELETED(B) || B.z != here.z)
			continue
		for(var/d in GLOB.cardinals)
			var/turf/open/T = get_step(B, d)
			if(!istype(T) || T.density || (locate(/obj/structure/blob) in T))
				continue
			// Its own distance counts double: the blob's outside edge is on its side, and a pocket the blob has closed round is
			// further in from there.
			var/score = get_dist(here, T) * 2 + get_dist(T, core)
			if(isnull(best_score) || score < best_score)
				if(is_blocked_turf(T, TRUE))
					continue
				best_score = score
				target = T

/datum/bot_goal/approach_blob/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/fight_blob/S = new
	S.steps = list(new /datum/bot_step/move_to())
	return list(S)

/// What its points go on before spreading: the economy, then spores, then reach.
/datum/bot_blob/proc/build()
	var/resources = 0
	var/factories = 0
	var/nodes = 0
	for(var/obj/structure/blob/B as anything in owner.blobs_legit)
		if(istype(B, /obj/structure/blob/resource))
			resources++
		else if(istype(B, /obj/structure/blob/factory))
			factories++
		else if(istype(B, /obj/structure/blob/node))
			nodes++
	if(resources < BOT_BLOB_RESOURCES + nodes && owner.blob_points >= 40)
		return place_special(40, /obj/structure/blob/resource, 4, TRUE)
	if(factories < BOT_BLOB_FACTORIES + nodes && owner.blob_points >= 60)
		return place_special(60, /obj/structure/blob/factory, 7, TRUE)
	if(length(owner.blobs_legit) > 40 * (nodes + 1) && owner.blob_points >= 50)
		return place_special(50, /obj/structure/blob/node, 5, FALSE)
	return FALSE

/// A normal blob it can turn into that: by the core or a node if it needs one, and not next to another of the same.
/datum/bot_blob/proc/place_special(price, path, near_equals, needs_node)
	var/list/candidates = list()
	for(var/obj/structure/blob/normal/B in owner.blobs_legit)
		if(needs_node && !(locate(/obj/structure/blob/node) in orange(3, B)) && !(locate(/obj/structure/blob/core) in orange(4, B)))
			continue
		var/clash = FALSE
		for(var/obj/structure/blob/L in orange(near_equals, B))
			if(L.type == path)
				clash = TRUE
				break
		if(!clash)
			candidates += B
	if(!length(candidates))
		return FALSE
	var/obj/structure/blob/spot = pick(candidates)
	owner.forceMove(get_turf(spot))
	return !!owner.createSpecial(price, path, near_equals, needs_node, get_turf(spot))

/// Where to spread to: somebody alive by the edge first, otherwise open floor off the edge, the way that's nearest the middle.
/datum/bot_blob/proc/next_spread()
	var/list/edge = list()
	for(var/i in 1 to 40) //a sample of the edge is plenty to choose from
		var/obj/structure/blob/B = pick(owner.blobs_legit)
		if(QDELETED(B))
			continue
		for(var/d in GLOB.cardinals)
			var/turf/T = get_step(B, d)
			if(!T || isspaceturf(T) || T.density || (locate(/obj/structure/blob) in T))
				continue
			for(var/mob/living/L in T)
				if(L.stat != DEAD && !(ROLE_BLOB in L.faction))
					return T //somebody right at the edge
			edge |= T
	if(!length(edge))
		return null
	var/turf/middle = locate(world.maxx / 2, world.maxy / 2, owner.z)
	var/turf/best
	for(var/turf/T as anything in edge)
		if(!best || get_dist(T, middle) < get_dist(best, middle) || prob(20))
			best = T
	return best

// ---------------------------------------------------------------------------------------------
// The crew's side
// ---------------------------------------------------------------------------------------------

/// The nearest bit of blob in sight, for anybody who'd fight it: Security, and anybody with something to hit it with.
/datum/bot_brain/proc/fight_the_blob()
	if(!length(GLOB.bot_blobs) || gone_loud() || owner.incapacitated() || owner.health < owner.maxHealth * 0.6)
		return FALSE
	var/armed = is_security_job() || find_carried_tool(/obj/item/gun) || (nerve >= 0.4 && (has_a_weapon() || find_carried_tool(/obj/item/weldingtool))) //bot_playstyles.dm: something heavy to hand
	if(!armed)
		return FALSE
	// What a player goes for: the core, which ends it, then the nodes and factories that keep it growing, then whatever's nearest.
	var/obj/structure/blob/best
	var/best_score
	for(var/obj/structure/blob/B in view(BOT_SIGHT_RANGE, owner))
		var/obj/structure/blob/core/core = B.overmind?.blob_core
		// The way in: whatever in sight is nearest the core, as well as near. Chopping at the nearest edge did nothing, the blob grows it
		// straight back; hit_blob() cuts through what's in between.
		var/score = core ? get_dist(B, core) + get_dist(owner, B) / 2 : get_dist(owner, B)
		if(istype(B, /obj/structure/blob/core))
			score -= 30
		else if(istype(B, /obj/structure/blob/node) || istype(B, /obj/structure/blob/factory))
			score -= 12
		else if(istype(B, /obj/structure/blob/resource))
			score -= 6
		if(!best || score < best_score)
			best = B
			best_score = score
	if(!best)
		return FALSE
	return assign_goal(new /datum/bot_goal/fight_blob(best))

/datum/bot_goal/fight_blob
	doing = "fighting the blob"
	var/obj/structure/blob/blob

/datum/bot_goal/fight_blob/New(obj/structure/blob/B)
	. = ..()
	blob = B

/datum/bot_goal/fight_blob/resolve_target(datum/bot_brain/bot)
	target = QDELETED(blob) ? null : blob

/datum/bot_goal/fight_blob/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/fight_blob/S = new
	S.steps = list(new /datum/bot_step/paced/hit_blob())
	return list(S)

/datum/bot_strategy/fight_blob/is_feasible(datum/bot_brain/bot)
	return bot.current_goal?.target && !QDELETED(bot.current_goal.target)

/// From range with a gun if it has one, else walk up and hit it, until it's gone or it isn't getting anywhere.
/datum/bot_step/paced/hit_blob
	max_clicks = 30

/datum/bot_step/paced/hit_blob/do_click(datum/bot_brain/bot)
	var/obj/structure/blob/B = bot.current_goal?.target
	if(QDELETED(B) || bot.owner.incapacitated() || bot.owner.health < bot.owner.maxHealth * 0.5)
		return FALSE
	var/obj/item/gun/G = bot.ready_lethal_gun() //goals/security_tactics.dm: a disabler's beam does nothing to it, and that's what an officer drew first
	if(!G)
		var/obj/item/gun/ballistic/shooter = bot.find_carried_tool(/obj/item/gun/ballistic)
		if(shooter?.can_shoot())
			G = shooter
	if(G && G.can_shoot() && get_dist(bot.owner, B) > 1 && bot.ready_in_hand(G))
		bot.owner.face_atom(B)
		bot.owner.a_intent = INTENT_HARM
		INVOKE_ASYNC(G, TYPE_PROC_REF(/obj/item/gun, afterattack), B, bot.owner, FALSE, null)
		wait_for = max(CLICK_CD_RANGE, G.fire_delay)
		return TRUE
	if(!bot.owner.Adjacent(B))
		var/turf/next = get_step_towards(bot.owner, B)
		var/obj/structure/blob/in_the_way = next && (locate(/obj/structure/blob) in next)
		if(in_the_way)
			B = in_the_way //cutting a way through to the core: it used to stop at the first blob between, and the core was never reached
		else
			if(!next || !bot.owner.Move(next, get_dir(bot.owner, next)))
				return FALSE
			wait_for = 3
			return TRUE
	var/obj/item/weapon = bot.blob_welder()
	if(!weapon)
		bot.reach_for_weapon() //bot_fighting.dm: the best thing it's got, in hand
		weapon = bot.owner.get_active_held_item()
	bot.owner.face_atom(B)
	bot.owner.a_intent = INTENT_HARM
	if(weapon)
		bot.use_item_on(weapon, B, harm = TRUE)
	else
		bot.owner.UnarmedAttack(B)
	bot.owner.changeNext_move(CLICK_CD_MELEE)
	wait_for = CLICK_CD_MELEE
	return TRUE

/datum/bot_step/paced/hit_blob/finish(datum/bot_brain/bot)
	var/obj/item/weldingtool/W = bot.find_carried_tool(/obj/item/weldingtool)
	if(W?.isOn() && (W in bot.owner.held_items))
		bot.toggle_in_hand(W) //not left burning in its hand to set the next plasma leak off
	return GOAL_STEP_SUCCESS

/// A lit welder, if it's carrying one with fuel in. A blob takes the whole of a burn and only half a club's blow (a shield blob a
/// quarter): a rod did two and a half to the shields round the core, a lit welder fifteen.
/datum/bot_brain/proc/blob_welder()
	var/obj/item/weldingtool/W = find_carried_tool(/obj/item/weldingtool)
	if(!W || W.get_fuel() <= 0 || !ready_in_hand(W))
		return null
	if(!W.isOn())
		toggle_in_hand(W)
	return W.isOn() ? W : null

#undef BOT_BLOB_TICK
#undef BOT_BLOB_RESOURCES
#undef BOT_BLOB_FACTORIES
