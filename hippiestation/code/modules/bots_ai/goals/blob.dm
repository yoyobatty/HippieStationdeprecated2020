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
/// Emitters out against a blob at once.
#define BOT_BLOB_EMITTERS 3
/// Clear tiles between an emitter and the blob it's shooting at.
#define BOT_BLOB_EMITTER_GAP_MIN 5
#define BOT_BLOB_EMITTER_GAP_MAX 10
/// None of the blob this near a spot an emitter is set down on, but along its line.
#define BOT_BLOB_EMITTER_CLEAR 4
/// The blob this near an emitter, round its side, and the engineer minding it drags it back.
#define BOT_BLOB_EMITTER_TOO_CLOSE 2
/// How far along its line an emitter does any good.
#define BOT_BLOB_EMITTER_REACH 20

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
		next_dispatch = world.time + 2 MINUTES
		bot_dispatch_security(get_turf(owner.blob_core), "the blob") //goals/security_tactics.dm
		send_volunteers()
		var/emitters = 0
		for(var/obj/machinery/power/emitter/E as anything in bot_instances_of(/obj/machinery/power/emitter))
			if(E.type == /obj/machinery/power/emitter && E.active && E.z == owner.blob_core.z)
				emitters++
		log_game("BOT BLOB: [length(owner.blobs_legit)] tiles, [round(owner.blob_points)] points, core [round(owner.blob_core.obj_integrity)]/[owner.blob_core.max_integrity], [emitters] emitters on it")
	if(build())
		return
	if(owner.blob_points >= BLOB_SPREAD_COST)
		var/turf/T = next_spread()
		if(T)
			owner.forceMove(T) //the overmind's eye goes where it clicks
			owner.expand_blob(T)

/// "Everybody grab a welder and kill the blob": the braver half of the crew, Security with them, up to twelve a wave every two minutes. Anybody without a
/// gun or a welder fetches a welder on the way (arm_for_blob). Engineers take emitters out to it first, nerve or no nerve: that's done from well
/// back. Medical stays to patch them up.
/datum/bot_blob/proc/send_volunteers()
	var/sent = 0
	var/emitters_sent = 0
	var/emitters_out = 0
	for(var/datum/bot_brain/B as anything in GLOB.bot_brains)
		if(istype(B.current_goal, /datum/bot_goal/blob_emitter) || istype(B.suspended_goal, /datum/bot_goal/blob_emitter))
			emitters_out++
	var/list/why_not = list()
	var/list/engineers_first = list()
	var/list/the_rest = list()
	for(var/datum/bot_brain/B as anything in shuffle(GLOB.bot_brains.Copy()))
		if(B.work_role() in GLOB.engineering_positions)
			engineers_first += B
		else
			the_rest += B
	for(var/datum/bot_brain/B as anything in engineers_first + the_rest) //the wave used to fill up before an engineer came round
		if(sent >= 12)
			break
		var/mob/living/carbon/human/H = B.owner
		if(QDELETED(H) || H.stat != CONSCIOUS || H.z != owner.blob_core.z)
			why_not["down or away"]++
			continue
		var/engineer = (B.work_role() in GLOB.engineering_positions)
		if(B.gone_loud() || (B.work_role() in GLOB.medical_positions) || (B.nerve < 0.5 && !B.is_security_job() && !engineer))
			why_not["not the sort"]++
			continue
		var/on_the_blob = istype(B.current_goal, /datum/bot_goal/approach_blob) || istype(B.current_goal, /datum/bot_goal/fight_blob)
		if(H.health < H.maxHealth * 0.7 || (on_the_blob && !(engineer && emitters_out < BOT_BLOB_EMITTERS)) \
			|| istype(B.current_goal, /datum/bot_goal/blob_emitter) || istype(B.suspended_goal, /datum/bot_goal/blob_emitter) \
			|| istype(B.current_goal, /datum/bot_goal/open_blast_door) || istype(B.suspended_goal, /datum/bot_goal/open_blast_door))
			why_not["hurt or on it already"]++
			continue
		if(B.state == BOT_STATE_GOAL) //the day's work waits: only the idle went, one or two a wave, most of the crew being in the middle of something
			B.drop_goals("everybody to the blob")
		if(B.state != BOT_STATE_WANDER)
			why_not["fighting or arresting"]++
			continue
		if(engineer && emitters_out < BOT_BLOB_EMITTERS && B.assign_goal(new /datum/bot_goal/blob_emitter()))
			sent++
			emitters_sent++
			emitters_out++
			continue
		if(B.nerve < 0.5 && !B.is_security_job())
			why_not["no emitter for them"]++
			continue
		if(B.assign_goal(new /datum/bot_goal/approach_blob(owner.blob_core)))
			sent++
		else
			why_not["no way there"]++
	var/list/reasons = list()
	for(var/reason in why_not)
		reasons += "[why_not[reason]] [reason]"
	log_game("BOT BLOB: [sent] of the crew went to fight it, [emitters_sent] with emitters; not: [jointext(reasons, ", ")]")

/// To the blob's edge, on its own side of it and as far towards the core as that goes: open floor beside a blob. From there it cuts its
/// way in (hit_blob). It used to make for the open floor nearest the core within ten tiles: once the blob had grown past that nobody was
/// sent anywhere (one volunteer went in the last ten minutes of a round), and the nearest free floor was usually a room the blob had
/// closed round, with no way to it at all.
/datum/bot_goal/approach_blob
	doing = "going to fight the blob"
	/// REF() of the core, not the core: the crew kill it, and a goal still holding it was a hard delete
	var/core_ref

/datum/bot_goal/approach_blob/New(obj/structure/blob/core/C)
	. = ..()
	core_ref = REF(C)

/datum/bot_goal/approach_blob/resolve_target(datum/bot_brain/bot)
	target = null
	var/obj/structure/blob/core/core = locate(core_ref)
	if(!istype(core))
		return
	var/mob/camera/blob/overmind = core.overmind
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
				if(is_blocked_turf(T, TRUE) || bot_in_emitter_fire(T))
					continue
				best_score = score
				target = T

/datum/bot_goal/approach_blob/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/fight_blob/S = new
	S.steps = list(new /datum/bot_step/ready_welder/arm_for_blob(), new /datum/bot_step/move_to())
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

/// Off the blob's edge. It reaches out at whoever stands by it, once a second, and that's how the crew died: all 40 in each of three
/// 40-minute shifts, 68 of them in the blob, with its core never touched. A player steps back. Somebody fighting it does that between
/// blows (hit_blob); anybody else gets well away. TRUE if that's what it's doing now.
/datum/bot_brain/proc/dodge_blob()
	var/turf/here = get_turf(owner)
	if(!here || owner.buckled || istype(current_goal, /datum/bot_goal/fight_blob))
		return FALSE
	var/obj/structure/blob/near = locate() in orange(1, here)
	if(!near)
		return FALSE
	var/turf/away = bot_blob_free_step(here)
	if(away)
		owner.Move(away, get_dir(here, away))
	if(istype(current_goal, /datum/bot_goal/blob_emitter) || istype(suspended_goal, /datum/bot_goal/blob_emitter))
		return FALSE //the step back, and on with the emitter
	if(armed_against_blob() && (state == BOT_STATE_GOAL || state == BOT_STATE_WANDER))
		// the step back, then the fight: sent to it, or come across it with something to hit it with
		if(state == BOT_STATE_GOAL)
			drop_goals("the blob's here")
		if(fight_the_blob())
			return TRUE
	if(!istype(current_goal, /datum/bot_goal/run_from))
		bot_tally("backed off the blob")
		run_from(near, "the blob's right there")
	return TRUE

/// Something that does a blob harm: a gun with a killing shot, a welder with fuel in, or something really heavy in hand. A blob takes
/// half of a blow and the whole of a burn, and what the fighters were swinging at it was a seclite, a cap, a multitool and a crowbar:
/// 40-odd tiles a shift against its 400.
/datum/bot_brain/proc/armed_against_blob()
	if(blob_gun())
		return TRUE
	var/obj/item/weldingtool/W = find_carried_tool(/obj/item/weldingtool)
	if(W && W.get_fuel() > 0)
		return TRUE
	var/obj/item/I = owner.get_active_held_item()
	return I && I.force >= 15

/// A gun it's carrying that can kill: a laser, an energy gun, something with bullets in. Not a disabler or a taser.
/datum/bot_brain/proc/blob_gun()
	for(var/obj/item/gun/G in owner.GetAllContents())
		if(!G.can_shoot())
			continue
		if(istype(G, /obj/item/gun/ballistic) || istype(G, /obj/item/gun/energy/laser) || istype(G, /obj/item/gun/energy/e_gun))
			return G
	return null

/// A welder with fuel in: from the nearest toolbox or locker if it hasn't got one, filled at a tank if it's dry.
/datum/bot_step/ready_welder
	var/fetched = FALSE
	var/filled = FALSE

/datum/bot_step/ready_welder/proc/ready(datum/bot_brain/bot)
	var/obj/item/weldingtool/W = bot.find_carried_tool(/obj/item/weldingtool)
	return W && W.get_fuel() >= 5

/datum/bot_step/ready_welder/execute(datum/bot_brain/bot)
	if(ready(bot))
		return GOAL_STEP_SUCCESS
	var/obj/item/weldingtool/W = bot.find_carried_tool(/obj/item/weldingtool)
	if(W && !filled)
		filled = TRUE
		bot_log(bot, "filling [W] for the blob")
		return bot.suspend_goal_for(new /datum/bot_goal/acquire_fuel()) ? GOAL_STEP_PENDING : GOAL_STEP_FAIL
	if(!W && !fetched)
		fetched = TRUE
		bot_log(bot, "getting a welder for the blob")
		return bot.suspend_goal_for(new /datum/bot_goal/acquire_tool(/obj/item/weldingtool)) ? GOAL_STEP_PENDING : GOAL_STEP_FAIL
	return GOAL_STEP_FAIL

/// What a volunteer without a gun or a welder goes and gets first: a welder. There's one in every toolbox, and nothing an ordinary
/// crewman can carry does a blob more harm.
/datum/bot_step/ready_welder/arm_for_blob

/datum/bot_step/ready_welder/arm_for_blob/ready(datum/bot_brain/bot)
	return bot.armed_against_blob()

/// A step off the blob's edge: to a tile with no blob by it if there is one, otherwise the one furthest from what's there.
/proc/bot_blob_free_step(turf/here)
	var/turf/best
	var/best_near
	for(var/d in GLOB.alldirs)
		var/turf/T = get_step(here, d)
		if(!T || T.density || isspaceturf(T) || is_blocked_turf(T, TRUE) || (locate(/obj/structure/blob) in T))
			continue
		var/near = 0
		for(var/obj/structure/blob/B in orange(1, T))
			near++
		if(isnull(best_near) || near < best_near)
			best = T
			best_near = near
	return best

/// The nearest bit of blob in sight, for anybody who'd fight it: Security, and anybody with something to hit it with.
/datum/bot_brain/proc/fight_the_blob()
	if(!length(GLOB.bot_blobs) || gone_loud() || owner.incapacitated() || owner.health < owner.maxHealth * 0.6)
		return FALSE
	if(!armed_against_blob())
		return FALSE
	// What a player goes for: the core, which ends it, then the nodes and factories that keep it growing, then whatever's nearest.
	var/obj/structure/blob/best
	var/best_score
	for(var/obj/structure/blob/B in view(BOT_SIGHT_RANGE, owner))
		var/obj/structure/blob/core/core = B.overmind?.blob_core
		// The way in: whatever in sight is nearest the core, as well as near. Chopping at the nearest edge did nothing, the blob grows it
		// straight back; hit_blob() cuts through what's in between.
		var/score = core ? get_dist(B, core) + get_dist(owner, B) / 2 : get_dist(owner, B)
		if(bot_in_emitter_fire(get_turf(B))) //an emitter has that one, and whoever went for it would be stood in its line
			score += 20
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

/// From range with a gun if it has one, else walk up and hit it, until it's gone or it isn't getting anywhere. Never stood at its edge:
/// it reaches out at whoever's there once a second. A gun keeps a tile between, a club or a welder hits and steps back.
/datum/bot_step/paced/hit_blob
	max_clicks = 40
	/// Swung at it last click: this one's the step back
	var/swung = FALSE

/datum/bot_step/paced/hit_blob/do_click(datum/bot_brain/bot)
	var/obj/structure/blob/B = bot.current_goal?.target
	if(QDELETED(B) || bot.owner.incapacitated() || bot.owner.health < bot.owner.maxHealth * 0.5)
		return FALSE
	var/turf/here = get_turf(bot.owner)
	if(bot_in_emitter_fire(here)) //out of an emitter's line before anything
		for(var/d in GLOB.alldirs)
			var/turf/T = get_step(here, d)
			if(T && !T.density && !is_blocked_turf(T, TRUE) && !(locate(/obj/structure/blob) in T) && !bot_in_emitter_fire(T) && bot.owner.Move(T, d))
				wait_for = 3
				clicks++
				return TRUE
	var/at_the_edge = !!(locate(/obj/structure/blob) in orange(1, here))
	if(swung && at_the_edge)
		swung = FALSE
		var/turf/back = bot_blob_free_step(here)
		if(back)
			bot.owner.Move(back, get_dir(here, back))
		wait_for = 4
		clicks++
		return TRUE
	swung = FALSE
	var/obj/item/gun/G = bot.ready_lethal_gun() //goals/security_tactics.dm: a disabler's beam does nothing to it, and that's what an officer drew first
	if(!G)
		var/obj/item/gun/ballistic/shooter = bot.find_carried_tool(/obj/item/gun/ballistic)
		if(shooter?.can_shoot())
			G = shooter
	if(G && G.can_shoot() && at_the_edge) //a tile back, then shoot
		var/turf/back = bot_blob_free_step(here)
		if(back && bot.owner.Move(back, get_dir(here, back)))
			wait_for = 3
			clicks++
			return TRUE
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
			if(!next || bot_in_emitter_fire(next) || !bot.owner.Move(next, get_dir(bot.owner, next)))
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
	swung = TRUE
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


// ---------------------------------------------------------------------------------------------
// Emitters on the blob
// ---------------------------------------------------------------------------------------------
//
// What engineers do about a blob: a spare emitter out of Secure Storage, dragged over, set down a good way back with its line running
// into the blob, turned to face it, wrenched, welded and switched on. A shot is thirty burn, which a blob takes whole: one kills a
// plain blob, five a shield, every two to ten seconds, with nobody standing at the edge. The blob takes an emitter the moment it grows
// on to it, and it grows every way at once while the beam only keeps it off the one, so the emitter goes a long way back with none of
// the blob to its sides, on a cable that has power, and the engineer stays by it, out of its line, and drags it back when the blob
// comes round the side, the power goes, or there's nothing left in front of it.

/// "x,y,z" -> when a spot an emitter couldn't be set down on is worth trying again
/datum/bot_brain/var/list/blob_spots_failed

/datum/bot_goal/blob_emitter
	lawful = TRUE
	exclusive = TRUE
	doing = "setting an emitter on the blob"
	/// REF() of the emitter to take if it still can: the one this engineer has out already
	var/prefer_ref
	var/turf/spot
	var/aim
	/// Why the engineer is moving it again, or null
	var/again
	/// Times it's gone back for the emitter after letting go of it on the way
	var/regrabs = 0

/datum/bot_goal/blob_emitter/New(obj/machinery/power/emitter/E)
	. = ..()
	if(E)
		prefer_ref = REF(E)

/datum/bot_goal/blob_emitter/resolve_target(datum/bot_brain/bot)
	target = null
	if(!length(GLOB.blob_cores))
		return
	var/obj/machinery/power/emitter/E = bot.spare_emitter_for_blob(prefer_ref)
	var/list/where = E ? bot.blob_emitter_spot(E) : null
	if(!where)
		return
	spot = where[1]
	aim = where[2]
	target = E

/datum/bot_goal/blob_emitter/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/fight_blob/S = new
	S.steps = list(new /datum/bot_step/ensure_wrench(), new /datum/bot_step/ready_welder(), new /datum/bot_step/open_emitter_storage(), new /datum/bot_step/move_to(), new /datum/bot_step/free_emitter(), \
		new /datum/bot_step/move_to/ahead_of_emitter(), new /datum/bot_step/sm_take_hold(), new /datum/bot_step/move_to/emitter_spot(), new /datum/bot_step/set_down_emitter(), \
		new /datum/bot_step/paced/aim_emitter(), new /datum/bot_step/secure_emitter(), new /datum/bot_step/paced/mind_emitter())
	return list(S)

/datum/bot_goal/blob_emitter/on_success(datum/bot_brain/bot)
	if(again && !QDELETED(target))
		bot.continue_goal_chain(CALLBACK(bot, TYPE_PROC_REF(/datum/bot_brain, set_emitter_on_blob), target), loud_too = TRUE)

/datum/bot_goal/blob_emitter/on_give_up(datum/bot_brain/bot)
	if(bot.owner.pulling == target)
		bot.owner.stop_pulling()
	if(QDELETED(target))
		return
	if(get_dist(bot.owner, target) > 1) //never got to it
		LAZYSET(bot.failed_engine_parts, target, world.time + rand(1200, 2400))
	else if(spot)
		LAZYSET(bot.blob_spots_failed, "[spot.x],[spot.y],[spot.z]", world.time + 5 MINUTES)

/datum/bot_brain/proc/set_emitter_on_blob(obj/machinery/power/emitter/E)
	return assign_goal(new /datum/bot_goal/blob_emitter(E))

/// An emitter nobody's using that an engineer could take to the blob: a spare out of storage, or one already out against it and switched
/// off. Never the engine's own (the /anchored ones at the crystal and the tesla) or the prototype turret. The nearest one this engineer can
/// get at: the spares are kept behind Secure Storage's blast doors, whose button is in the Chief Engineer's office on most maps. With
/// only those left and no way to open them, it asks over the radio (bot_ask_for_storage()).
/datum/bot_brain/proc/spare_emitter_for_blob(prefer_ref)
	var/obj/machinery/power/emitter/E = prefer_ref ? locate(prefer_ref) : null
	if(istype(E) && spare_emitter(E, TRUE))
		return E
	var/turf/here = get_turf(owner)
	var/list/by_dist = list()
	for(var/obj/machinery/power/emitter/candidate as anything in bot_instances_of(/obj/machinery/power/emitter))
		if(spare_emitter(candidate))
			by_dist[candidate] = get_dist(here, candidate)
	var/list/gates_tried = list() //REF(blast door) -> whether this engineer can open it
	var/obj/machinery/door/poddoor/shut_gate
	while(length(by_dist))
		E = null
		for(var/obj/machinery/power/emitter/candidate as anything in by_dist)
			if(!E || by_dist[candidate] < by_dist[E])
				E = candidate
		by_dist -= E
		var/obj/machinery/door/poddoor/gate = bot_emitter_gate(E)
		if(!gate)
			return E
		var/key = REF(gate)
		if(isnull(gates_tried[key]))
			gates_tried[key] = !!blast_door_button_for(gate)
		if(gates_tried[key])
			return E
		shut_gate = shut_gate || gate
	if(shut_gate)
		bot_ask_for_storage(shut_gate, src)
	return null

/datum/bot_brain/proc/spare_emitter(obj/machinery/power/emitter/E, mine = FALSE)
	if(QDELETED(E) || E.type != /obj/machinery/power/emitter || E.z != owner.z || !isturf(E.loc) || (E.stat & BROKEN) || E.locked)
		return FALSE
	if(E.active && !mine)
		return FALSE
	return !is_failed_engine_part(E) && !taken_by_another(E) && bot_emitter_has_free_side(E)

/// Somewhere to stand beside it and take hold. Secure Storage packs them in with the field generators: on Box only the front one has a
/// free side, and an engineer sent for the nearest got as far as the doors with no way to it. Taking the front one out frees the next.
/proc/bot_emitter_has_free_side(obj/machinery/power/emitter/E)
	for(var/d in GLOB.cardinals)
		var/turf/T = get_step(E, d)
		if(T && !T.density && !isspaceturf(T) && !is_blocked_turf(T, TRUE))
			return TRUE
	return FALSE

/// TRUE if an emitter's beam goes on through T: not a wall, and nothing there a beam stops at. Glass, grilles and tables let it by.
/proc/bot_beam_passes(turf/T)
	if(!T || T.density)
		return FALSE
	for(var/obj/O in T)
		if(O.density && !istype(O, /obj/structure/blob) && !istype(O, /obj/structure/window) && !istype(O, /obj/structure/grille) && !istype(O, /obj/structure/table))
			return FALSE
	return TRUE

/// What an emitter at T facing `aim` would shoot at: the blob along its line, the core and the nodes most. 0 if none of it is in reach.
/proc/bot_emitter_line_worth(turf/T, aim)
	. = 0
	for(var/i in 1 to BOT_BLOB_EMITTER_REACH)
		T = get_step(T, aim)
		if(!bot_beam_passes(T))
			return
		var/obj/structure/blob/B = locate() in T
		if(istype(B, /obj/structure/blob/core))
			. += 25
		else if(istype(B, /obj/structure/blob/node) || istype(B, /obj/structure/blob/factory))
			. += 8
		else if(B)
			. += istype(B, /obj/structure/blob/resource) ? 4 : 1

/// TRUE if T is in front of an emitter that's on: anywhere along its line, walls or no. Nobody who knows what one is stands there.
/proc/bot_in_emitter_fire(turf/T)
	if(!T)
		return FALSE
	for(var/obj/machinery/power/emitter/E as anything in bot_instances_of(/obj/machinery/power/emitter))
		if(E.active && !QDELETED(E) && E.z == T.z && (E.x == T.x || E.y == T.y) && get_dist(E, T) <= BOT_BLOB_EMITTER_REACH && get_dir(E, T) == E.dir)
			return TRUE
	return FALSE

/// TRUE if there's a cable on T an emitter would join (what get_cable_node() picks, without its update_icon(): this asks it of a lot of
/// floor) and there's power on it.
/proc/bot_live_cable(turf/T)
	var/bridged = locate(/obj/structure/cable_bridge) in T
	for(var/obj/structure/cable/C in T)
		if(C.cable_layer == CABLE_LAYER_2 || bridged)
			return C.powernet?.avail >= 1000
	return FALSE

/// Where T would still do for an emitter facing `aim`: nothing in the way, a live cable, none of the blob near but for its line, which
/// still has some in it.
/proc/bot_emitter_spot_holds(turf/T, aim)
	if(!T || is_blocked_turf(T, TRUE) || (locate(/obj/structure/blob) in orange(BOT_BLOB_EMITTER_CLEAR, T)) || !bot_live_cable(T))
		return FALSE
	return bot_emitter_line_worth(T, aim) > 0

/// Where an emitter goes against the blob, and which way it faces: floor with a live cable under it, a long clear run out from the blob's
/// edge, none of the blob near it but for what's in front, room beside it to work, and out of any other emitter's line. The most blob in
/// its line wins, the core or a node in it most of all; then the shortest haul. list(turf, dir), or null.
/datum/bot_brain/proc/blob_emitter_spot(obj/machinery/power/emitter/E)
	var/turf/from = get_turf(E)
	var/list/scores = list()
	var/list/spots = list()
	for(var/obj/structure/blob/core/core as anything in GLOB.blob_cores)
		if(QDELETED(core) || core.z != from.z || !core.overmind)
			continue
		for(var/obj/structure/blob/B as anything in core.overmind.blobs_legit)
			if(QDELETED(B) || B.z != from.z)
				continue
			for(var/d in GLOB.cardinals)
				var/turf/T = get_turf(B)
				for(var/gap in 1 to BOT_BLOB_EMITTER_GAP_MAX)
					T = get_step(T, d)
					if(!bot_beam_passes(T) || (locate(/obj/structure/blob) in T))
						break
					if(gap < BOT_BLOB_EMITTER_GAP_MIN)
						continue
					var/aim = turn(d, 180)
					var/key = "[T.x],[T.y],[aim]"
					if(spots[key] || !isfloorturf(T) || is_blocked_turf(T, TRUE) || (locate(/obj/machinery/door) in T) || !bot_live_cable(T))
						continue
					spots[key] = list(T, aim)
					scores[key] = bot_emitter_line_worth(T, aim) * 4 - get_dist(from, T) / 5
			CHECK_TICK
	var/list/why_not = list()
	var/walks_checked = 0
	for(var/tries in 1 to 40)
		var/best_key
		for(var/key in scores)
			if(!best_key || scores[key] > scores[best_key])
				best_key = key
		if(!best_key)
			break
		var/list/where = spots[best_key]
		scores -= best_key
		var/turf/T = where[1]
		if(LAZYACCESS(blob_spots_failed, "[T.x],[T.y],[T.z]") > world.time)
			why_not["tried"]++
		else if(locate(/obj/structure/blob) in orange(BOT_BLOB_EMITTER_CLEAR, T))
			why_not["blob near"]++
		else if(bot_in_emitter_fire(T))
			why_not["in a line of fire"]++
		else if(bot_emitter_room_beside(T, where[2]) < 2)
			why_not["no room"]++
		else if(++walks_checked > 3)
			break
		else if(!can_walk_lawfully_to(T)) //maintenance behind a door this engineer's ID doesn't open
			why_not["no way there"]++
			LAZYSET(blob_spots_failed, "[T.x],[T.y],[T.z]", world.time + 5 MINUTES)
		else
			return where
	var/list/reasons = list()
	for(var/reason in why_not)
		reasons += "[why_not[reason]] [reason]"
	bot_log_verbose(src, "no spot for an emitter on the blob: [length(spots)] looked at[length(reasons) ? ", [jointext(reasons, ", ")]" : ""]")
	return null

/// Open floor round T to stand on and work from, not counting the tile in front of an emitter there.
/proc/bot_emitter_room_beside(turf/T, aim)
	. = 0
	var/turf/muzzle = get_step(T, aim)
	for(var/turf/open/N in orange(1, T))
		if(N != muzzle && !isspaceturf(N) && !is_blocked_turf(N, TRUE) && !(locate(/obj/structure/blob) in N))
			.++

/// The shut blast door an emitter is kept behind, or null if there's a way to it without one: a few dozen tiles of floor round it, walled
/// in, with a blast door in the walls. Airlocks count as a way through; whether they open for whoever's going is for the route planner.
/proc/bot_emitter_gate(obj/machinery/power/emitter/E)
	var/turf/start = get_turf(E)
	if(!start)
		return null
	var/list/seen = list()
	seen[start] = TRUE
	var/list/queue = list(start)
	var/at = 1
	var/obj/machinery/door/poddoor/gate
	while(at <= length(queue))
		var/turf/T = queue[at++]
		for(var/d in GLOB.cardinals)
			var/turf/next = get_step(T, d)
			if(!next || seen[next])
				continue
			seen[next] = TRUE
			if(next.density || (locate(/obj/structure/window) in next) || (locate(/obj/structure/grille) in next))
				continue
			var/obj/machinery/door/poddoor/P = locate() in next
			if(P?.density)
				gate = gate || P
				continue
			queue += next
			if(length(queue) > 60)
				return null
	return gate

/// A button for that blast door this bot may press and can walk to by doors its own ID opens.
/datum/bot_brain/proc/blast_door_button_for(obj/machinery/door/poddoor/gate)
	if(!gate.id)
		return null
	for(var/obj/machinery/button/door/B as anything in bot_buttons_for_door_id(gate.id))
		if(QDELETED(B) || B.z != gate.z || B.normaldoorcontrol || B.panel_open || (B.stat & (NOPOWER|BROKEN)) || !B.allowed(owner))
			continue
		if(can_walk_lawfully_to(B))
			return B
	return null

/// Blast door id -> when it's worth asking for it to be opened again
GLOBAL_LIST_EMPTY(bot_storage_asked)

/// An engineer after an emitter behind a blast door they can't open asks over the radio, and whoever can opens it: the Chief Engineer,
/// whose office the button is in on most maps, or else the Captain or the Head of Personnel.
/proc/bot_ask_for_storage(obj/machinery/door/poddoor/gate, datum/bot_brain/asker)
	var/key = "[gate.id]"
	if(GLOB.bot_storage_asked[key] > world.time)
		return
	GLOB.bot_storage_asked[key] = world.time + 2 MINUTES
	for(var/datum/bot_brain/B as anything in GLOB.bot_brains)
		if(istype(B.current_goal, /datum/bot_goal/open_blast_door) || istype(B.suspended_goal, /datum/bot_goal/open_blast_door))
			return //somebody's on their way to it
	var/what = lowertext(gate.name)
	bot_say(asker.owner, ":e [pick("Can somebody open [what]? We need the emitters for the blob.", "Need [what] open for the emitters, the blob's spreading.", "Who can get [what] open? I want an emitter on the blob.")]")
	var/checked = 0
	for(var/job in list("Chief Engineer", "Captain", "Head of Personnel"))
		for(var/datum/bot_brain/B as anything in GLOB.bot_brains)
			if(B == asker || B.work_role() != job || QDELETED(B.owner) || B.owner.stat != CONSCIOUS || B.owner.z != gate.z || B.gone_loud())
				continue
			if(++checked > 4)
				return
			var/obj/machinery/button/door/button = B.blast_door_button_for(gate)
			if(!button)
				continue
			if(B.state == BOT_STATE_GOAL)
				B.drop_goals("opening [what] for the emitters")
			if(B.state == BOT_STATE_WANDER && B.assign_goal(new /datum/bot_goal/open_blast_door(button, gate)))
				addtimer(CALLBACK(GLOBAL_PROC, GLOBAL_PROC_REF(bot_say), B.owner, ":e [pick("On it, opening [what].", "Opening [what] now.", "Give me a minute, I'll get it open.")]"), rand(2 SECONDS, 5 SECONDS))
				return

/// Over to a blast door's button, and pressed if the door's still shut: Secure Storage, for the emitters in it.
/datum/bot_goal/open_blast_door
	lawful = TRUE
	doing = "opening a blast door"
	/// REF() of the door
	var/gate_ref

/datum/bot_goal/open_blast_door/New(obj/machinery/button/door/B, obj/machinery/door/poddoor/gate)
	. = ..()
	target = B
	gate_ref = REF(gate)

/datum/bot_goal/open_blast_door/resolve_target(datum/bot_brain/bot)
	var/obj/machinery/door/poddoor/gate = locate(gate_ref)
	if(QDELETED(target) || !istype(gate) || !gate.density)
		target = null

/datum/bot_goal/open_blast_door/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/fight_blob/S = new
	S.steps = list(new /datum/bot_step/move_to(), new /datum/bot_step/paced/press_blast_door_button())
	return list(S)

/datum/bot_goal/open_blast_door/on_success(datum/bot_brain/bot)
	for(var/datum/bot_blob/BB as anything in GLOB.bot_blobs)
		BB.next_dispatch = min(BB.next_dispatch, world.time + 5 SECONDS) //the engineers who were waiting on it go now

/// The press, then a moment while the door slides up.
/datum/bot_step/paced/press_blast_door_button
	max_clicks = 8
	var/pressed = FALSE

/datum/bot_step/paced/press_blast_door_button/start(datum/bot_brain/bot)
	pressed = FALSE
	return TRUE

/datum/bot_step/paced/press_blast_door_button/do_click(datum/bot_brain/bot)
	var/datum/bot_goal/open_blast_door/G = bot.current_goal
	var/obj/machinery/door/poddoor/gate = istype(G) ? locate(G.gate_ref) : null
	if(!istype(gate) || !gate.density)
		return FALSE
	if(pressed)
		clicks++
		wait_for = 5
		return TRUE
	var/obj/machinery/button/door/B = G.target
	if(QDELETED(B) || !bot.owner.Adjacent(B))
		return FALSE
	pressed = TRUE
	bot_log(bot, "opening [gate] with [B]")
	bot.press_door_button(B)
	return TRUE

/datum/bot_step/paced/press_blast_door_button/finish(datum/bot_brain/bot)
	var/datum/bot_goal/open_blast_door/G = bot.current_goal
	var/obj/machinery/door/poddoor/gate = istype(G) ? locate(G.gate_ref) : null
	return istype(gate) && !gate.density ? GOAL_STEP_SUCCESS : GOAL_STEP_FAIL

/// Its emitter's storage opened first, if that's shut and this engineer can work the button: a short errand of its own.
/datum/bot_step/open_emitter_storage
	var/tried = FALSE

/datum/bot_step/open_emitter_storage/execute(datum/bot_brain/bot)
	var/obj/machinery/power/emitter/E = bot.current_goal?.target
	if(QDELETED(E))
		return GOAL_STEP_FAIL
	var/obj/machinery/door/poddoor/gate = bot_emitter_gate(E)
	if(!gate)
		return GOAL_STEP_SUCCESS
	if(tried)
		return GOAL_STEP_FAIL
	tried = TRUE
	var/obj/machinery/button/door/B = bot.blast_door_button_for(gate)
	if(!B)
		return GOAL_STEP_FAIL
	return bot.suspend_goal_for(new /datum/bot_goal/open_blast_door(B, gate)) ? GOAL_STEP_PENDING : GOAL_STEP_FAIL

/// Switched off, cut free and unwrenched, if it's set up somewhere already.
/datum/bot_step/free_emitter/execute(datum/bot_brain/bot)
	var/obj/machinery/power/emitter/E = bot.current_goal?.target
	if(QDELETED(E) || !bot.owner.Adjacent(E))
		return GOAL_STEP_FAIL
	if(E.active)
		bot.use_atom(E)
		if(QDELETED(E) || E.active)
			return GOAL_STEP_FAIL
	if(E.state == 2) //EMITTER_WELDED
		var/obj/item/weldingtool/W = bot.blob_welder()
		if(!W)
			return GOAL_STEP_FAIL
		bot.use_item_on(W, E)
		if(W.isOn() && (W in bot.owner.held_items))
			bot.toggle_in_hand(W)
		if(QDELETED(E) || E.state == 2)
			return GOAL_STEP_FAIL
	if(E.anchored)
		var/obj/item/wrench = bot.find_or_transform_tool(/obj/item/wrench)
		if(!wrench)
			return GOAL_STEP_FAIL
		bot.use_item_on(wrench, E)
		if(QDELETED(E) || E.anchored)
			return GOAL_STEP_FAIL
		bot_log(bot, "freed [E] to move it")
	return GOAL_STEP_SUCCESS

/// Round to the side of it the way to the spot goes, before taking hold, so it comes along behind. Stood the wrong side, the walk set
/// off through it: the bot stepped round it, the pull broke, and it went the rest of the way with nothing in tow.
/datum/bot_step/move_to/ahead_of_emitter/execute(datum/bot_brain/bot)
	var/datum/bot_goal/blob_emitter/G = bot.current_goal
	var/obj/machinery/power/emitter/E = G?.target
	if(!istype(G) || QDELETED(E))
		return GOAL_STEP_FAIL
	var/turf/here = get_turf(bot.owner)
	var/turf/at = get_turf(E)
	var/list/path = bot.bot_path_to(G.spot, /turf/proc/Distance_cardinal, /turf/proc/bot_reachable_strict, bot.route_card(), !bot.can_path_through_space())
	var/turf/ahead
	for(var/i in 1 to min(length(path), 6))
		var/turf/T = path[i]
		if(T != here && T != at && get_dist(T, at) <= 1)
			ahead = T
	if(!ahead)
		return GOAL_STEP_SUCCESS //already on the side it goes
	step_target = ahead
	return ..()

/// To the spot, dragging it. If the blob has got near the spot on the way, or its line has emptied, a fresh one from here.
/datum/bot_step/move_to/emitter_spot
	hauling = TRUE

/// Back for it: over to it, round to the side the way goes, and take hold again. Three times, then it's given up.
/datum/bot_step/move_to/emitter_spot/lost_hold(datum/bot_brain/bot)
	var/datum/bot_goal/blob_emitter/G = bot.current_goal
	if(!istype(G) || QDELETED(G.target) || ++G.regrabs > 3)
		return ..()
	bot.current_step_index = bot.current_strategy.steps.Find(src) - 4 //the walk over to it (move_to, free_emitter, ahead_of_emitter, sm_take_hold, this)
	bot.run_current_step()

/datum/bot_step/move_to/emitter_spot/execute(datum/bot_brain/bot)
	var/datum/bot_goal/blob_emitter/G = bot.current_goal
	if(!istype(G) || QDELETED(G.target) || bot.owner.pulling != G.target)
		return GOAL_STEP_FAIL
	if(!bot_emitter_spot_holds(G.spot, G.aim))
		var/list/where = bot.blob_emitter_spot(G.target)
		if(!where)
			return GOAL_STEP_FAIL
		G.spot = where[1]
		G.aim = where[2]
		bot_log(bot, "the blob's moved - a new spot for [G.target] at [bot_coord(G.spot)]")
	step_target = G.spot
	return ..()

/// Standing on the spot with it in tow: a step to the side, and it comes on to the spot. A step to the side and not on in front, where
/// it's about to shoot.
/datum/bot_step/set_down_emitter/execute(datum/bot_brain/bot)
	var/datum/bot_goal/blob_emitter/G = bot.current_goal
	var/mob/living/carbon/human/H = bot.owner
	var/obj/machinery/power/emitter/E = G?.target
	if(!istype(G) || QDELETED(E) || H.pulling != E)
		return GOAL_STEP_FAIL
	var/turf/here = get_turf(H)
	if(here == G.spot)
		var/turf/muzzle = get_step(here, G.aim)
		var/turf/behind = get_turf(E)
		var/stepped = FALSE
		for(var/d in GLOB.alldirs) //the cardinals first
			var/turf/T = get_step(here, d)
			if(!T || T == muzzle || T == behind || isspaceturf(T) || T.density || is_blocked_turf(T, TRUE) || (locate(/obj/structure/blob) in T))
				continue
			if(H.Move(T, d))
				stepped = TRUE
				break
		if(!stepped)
			H.stop_pulling()
			return GOAL_STEP_FAIL
	H.stop_pulling()
	if(QDELETED(E) || get_turf(E) != G.spot)
		bot_log(bot, "[E] didn't end up on [bot_coord(G.spot)]")
		return GOAL_STEP_FAIL
	bot_log(bot, "set [E] down at [bot_coord(G.spot)] to face [dir2text(G.aim)]")
	return GOAL_STEP_SUCCESS

/// Turned to face the blob: an alt-click turns it a quarter clockwise.
/datum/bot_step/paced/aim_emitter
	max_clicks = 8
	var/stepped_round = FALSE

/datum/bot_step/paced/aim_emitter/start(datum/bot_brain/bot)
	stepped_round = FALSE
	return TRUE

/datum/bot_step/paced/aim_emitter/do_click(datum/bot_brain/bot)
	var/datum/bot_goal/blob_emitter/G = bot.current_goal
	var/obj/machinery/power/emitter/E = G?.target
	if(!istype(G) || QDELETED(E) || E.dir == G.aim || E.anchored)
		return FALSE
	if(!bot.owner.Adjacent(E)) //the step off the spot went round a corner from it
		if(stepped_round || !bot.step_beside_emitter(E, G.aim))
			bot_log(bot, "can't get at [E] to turn it")
			return FALSE
		stepped_round = TRUE
		clicks++
		wait_for = 3
		return TRUE
	bot.human_pause(E)
	if(QDELETED(E) || !bot.owner.Adjacent(E))
		return FALSE
	bot.owner.face_atom(E)
	bot.telemetry_clicked(E)
	E.AltClick(bot.owner)
	return TRUE

/// A step on to a tile to the side of or behind an emitter, from next to that tile. Never the one in front of it.
/datum/bot_brain/proc/step_beside_emitter(obj/machinery/power/emitter/E, aim)
	var/turf/here = get_turf(owner)
	var/turf/muzzle = get_step(E, aim)
	for(var/d in GLOB.cardinals)
		var/turf/T = get_step(E, d)
		if(!T || T == muzzle || T.density || is_blocked_turf(T, TRUE) || get_dist(here, T) != 1)
			continue
		if(owner.Move(T, get_dir(here, T)))
			return TRUE
	return FALSE

/datum/bot_step/paced/aim_emitter/finish(datum/bot_brain/bot)
	var/datum/bot_goal/blob_emitter/G = bot.current_goal
	var/obj/machinery/power/emitter/E = G?.target
	return istype(G) && !QDELETED(E) && E.dir == G.aim ? GOAL_STEP_SUCCESS : GOAL_STEP_FAIL

/// Wrenched, welded and switched on.
/datum/bot_step/secure_emitter/execute(datum/bot_brain/bot)
	var/obj/machinery/power/emitter/E = bot.current_goal?.target
	if(QDELETED(E) || !bot.owner.Adjacent(E))
		return GOAL_STEP_FAIL
	if(!E.anchored)
		var/obj/item/wrench = bot.find_or_transform_tool(/obj/item/wrench)
		if(!wrench)
			return GOAL_STEP_FAIL
		bot.use_item_on(wrench, E)
		if(QDELETED(E) || !E.anchored)
			bot_log(bot, "couldn't wrench [E] down")
			return GOAL_STEP_FAIL
	if(E.state != 2) //EMITTER_WELDED
		var/obj/item/weldingtool/W = bot.blob_welder()
		if(!W)
			return GOAL_STEP_FAIL
		bot.use_item_on(W, E)
		if(W.isOn() && (W in bot.owner.held_items))
			bot.toggle_in_hand(W)
		if(QDELETED(E) || E.state != 2)
			bot_log(bot, "couldn't weld [E] down")
			return GOAL_STEP_FAIL
	if(!E.powernet)
		bot_log(bot, "[E] has no cable to run on")
		return GOAL_STEP_FAIL
	if(!E.active)
		bot.use_atom(E)
	if(QDELETED(E) || !E.active)
		bot_log(bot, "couldn't switch [E] on")
		return GOAL_STEP_FAIL
	bot_log(bot, "switched [E] on at the blob")
	bot_tally("emitter on the blob")
	return GOAL_STEP_SUCCESS

/// Beside it, out of its line, looking every two seconds: off and back with it when the blob comes round its side, the power's gone, or
/// there's been nothing in front of it for a while. Left running if this engineer gets hurt, or after eight minutes of it.
/datum/bot_step/paced/mind_emitter
	max_clicks = 240
	var/empty_looks = 0
	var/dark_looks = 0

/datum/bot_step/paced/mind_emitter/start(datum/bot_brain/bot)
	empty_looks = 0
	dark_looks = 0
	return TRUE

/datum/bot_step/paced/mind_emitter/do_click(datum/bot_brain/bot)
	var/datum/bot_goal/blob_emitter/G = bot.current_goal
	var/obj/machinery/power/emitter/E = G?.target
	var/mob/living/carbon/human/H = bot.owner
	if(!istype(G))
		return FALSE
	if(QDELETED(E))
		bot_tally("emitter lost to the blob")
		return FALSE
	if(!E.active || H.incapacitated() || H.health < H.maxHealth * 0.5)
		return FALSE
	var/turf/T = get_turf(E)
	for(var/obj/structure/blob/B in orange(BOT_BLOB_EMITTER_TOO_CLOSE, T))
		if(get_dir(E, B) != E.dir || (B.x != E.x && B.y != E.y))
			G.again = "the blob's come round the side"
			break
	empty_looks = bot_emitter_line_worth(T, E.dir) ? 0 : empty_looks + 1
	dark_looks = E.powered ? 0 : dark_looks + 1
	if(!G.again && empty_looks >= 8)
		G.again = "nothing in front of it"
	if(!G.again && dark_looks >= 5)
		G.again = "no power"
	if(G.again)
		bot_log(bot, "moving [E]: [G.again]")
		bot_tally("emitter moved: [G.again]")
		return FALSE
	clicks++
	wait_for = 2 SECONDS
	if(get_dist(H, E) > 1 || bot_in_emitter_fire(get_turf(H))) //back beside it, out of the line
		for(var/turf/open/N in orange(1, T))
			if(get_dist(H, N) == 1 && !is_blocked_turf(N, TRUE) && !(locate(/obj/structure/blob) in N) && !bot_in_emitter_fire(N))
				H.Move(N, get_dir(H, N))
				break
	return TRUE

/datum/bot_step/paced/mind_emitter/finish(datum/bot_brain/bot)
	return GOAL_STEP_SUCCESS

#undef BOT_BLOB_TICK
#undef BOT_BLOB_RESOURCES
#undef BOT_BLOB_FACTORIES
#undef BOT_BLOB_EMITTERS
#undef BOT_BLOB_EMITTER_GAP_MIN
#undef BOT_BLOB_EMITTER_GAP_MAX
#undef BOT_BLOB_EMITTER_CLEAR
#undef BOT_BLOB_EMITTER_TOO_CLOSE
#undef BOT_BLOB_EMITTER_REACH
