// Disposals (the user's ask, 2026-11-09: "have bots be aware of and know how to use disposals, flushing unwanted items or stunned
// players, or even themselves if they need an emergency escape from a room").
//
//  - Where a bin goes. Anybody who's played a while knows a bin sends you to the disposal room, so bots know it too (the map is
//    theirs to know, bot_knowledge.dm): bot_disposal_landing() follows the pipes from a bin to where they come out, both ways at a
//    junction, and a bin is only one to get into when every way out of it ends on a floor (not space, not a mass driver, not an
//    emagged recycler, not a break in the pipe).
//  - Out by the bin. Shut in somewhere and still shut in after a few minutes of asking to be let out, or hurt and running from
//    somebody with a bin right there and them not between, a bot climbs in and waits for the flush. A player can't reach the
//    handle from inside (the window is notcontained_state), so it's the bin's own flush, up to a minute; then the ride, and on
//    from wherever it lands.
//  - Somebody into the bin. A traitor with a body on its hands and nobody looking, or a greytider who's knocked somebody flat,
//    drags them to the nearest bin, stuffs them in and pulls the handle. Anybody stuffed in who can still move climbs out
//    (mind_being_held(), bot_reflexes.dm); in the pipes there's nothing to do but wait.

/// How long it's been shut in, asking to be let out, before it tries the bin.
#define BOT_SHUT_IN_BIN_AFTER (3 MINUTES)
/// The longest it waits in a bin for the flush before it climbs back out.
#define BOT_BIN_RIDE_WAIT (90 SECONDS)
/// Before it thinks of a bin again when there wasn't one, or it didn't work out.
#define BOT_BIN_ESCAPE_REST (5 MINUTES)
/// How long a bin's way out is good for once worked out: the pipes are the map's, and seldom change.
#define BOT_DISPOSAL_ROUTE_KEEP (10 MINUTES)
/// How long after a fight a greytider still thinks of putting who it beat in the bin.
#define BOT_BIN_PRANK_TIME (30 SECONDS)

/obj/machinery/disposal/bin
	/// Where somebody flushed from here comes out (bot_disposal_landing()): null for nowhere to stand.
	var/turf/bot_landing
	/// When that was worked out, 0 for never.
	var/bot_landing_when = 0

/// Where somebody flushed from this bin comes out, or null if any way out of it is somewhere nobody should be.
/proc/bot_disposal_landing(obj/machinery/disposal/bin/B)
	if(B.bot_landing_when && world.time < B.bot_landing_when + BOT_DISPOSAL_ROUTE_KEEP)
		return B.bot_landing
	B.bot_landing = bot_trace_disposals(B)
	B.bot_landing_when = max(world.time, 1)
	return B.bot_landing

/// Follows the pipes from a bin the way a person in it goes (sorting junctions by the bin's own tag, both ways at a plain one), to
/// every end. The turf of the first end if all of them land somewhere to stand, null if any doesn't.
/proc/bot_trace_disposals(obj/machinery/disposal/bin/B)
	var/obj/structure/disposalpipe/trunk/start = B.trunk
	if(!istype(start) || (B.stat & BROKEN))
		return null
	var/static/obj/structure/disposalholder/probe
	if(QDELETED(probe))
		probe = new
	probe.destinationTag = 1 //a bin's (newHolderDestination())
	probe.tomail = FALSE
	probe.hasmob = TRUE
	var/list/ways = list(list(start, start.dir))
	var/list/seen = list()
	var/turf/landing
	var/steps = 0
	while(length(ways))
		if(++steps > 4000)
			return null
		var/list/way = ways[length(ways)]
		ways.len--
		var/obj/structure/disposalpipe/from = way[1]
		var/going = way[2]
		var/key = "[REF(from)] [going]"
		if(seen[key])
			continue
		seen[key] = TRUE
		if(!(going in GLOB.cardinals))
			return null //up or down a deck: somewhere else entirely
		var/turf/next_turf = get_step(from, going)
		var/obj/structure/disposalpipe/next
		var/flipped = turn(going, 180)
		for(var/obj/structure/disposalpipe/P in next_turf)
			if(P.dpdir & flipped)
				next = P
				break
		if(!next)
			return null //a break in the pipe: out through the floor, wherever that is
		if(istype(next, /obj/structure/disposalpipe/trunk))
			var/turf/out = bot_disposal_outlet_landing(next)
			if(!out)
				return null
			landing = landing || out
			continue
		var/onward
		var/obj/structure/disposalpipe/junction/J = next
		if(istype(J))
			onward = flipped == J.dir ? (J.dpdir & ~J.dir) : J.dir //from the main way, either of the others
		else
			probe.dir = going
			onward = next.nextdir(probe)
		for(var/d in GLOB.cardinals)
			if(onward & d)
				ways += list(list(next, d))
	return landing

/// Where a trunk at the end of the line puts somebody: on the floor in front of an outlet (thrown up to its eject range), or by
/// another bin. Null if any of that is somewhere nobody should land.
/proc/bot_disposal_outlet_landing(obj/structure/disposalpipe/trunk/end)
	var/obj/machinery/disposal/other_bin = end.linked
	if(istype(other_bin))
		var/turf/by_bin = get_turf(other_bin)
		return bot_disposal_safe_floor(by_bin) ? by_bin : null
	var/obj/structure/disposaloutlet/O = end.linked
	if(!istype(O))
		return null //nothing on the trunk: out through the floor
	var/turf/at = get_turf(O)
	if(!bot_disposal_safe_floor(at))
		return null
	var/turf/thrown_to = at
	for(var/i in 1 to O.eject_range)
		var/turf/next = get_step(thrown_to, O.dir)
		if(!next || next.density)
			break
		if(!bot_disposal_safe_floor(next))
			return null
		thrown_to = next
	return at

/proc/bot_disposal_safe_floor(turf/T)
	if(!isopenturf(T) || isspaceturf(T) || islava(T) || ischasm(T) || istype(T, /turf/open/openspace))
		return FALSE
	if(locate(/obj/machinery/mass_driver) in T)
		return FALSE
	var/obj/machinery/recycler/R = locate() in T
	return !R || !(R.obj_flags & EMAGGED)

// ---------------------------------------------------------------------------------------------
// Out by the bin
// ---------------------------------------------------------------------------------------------

/datum/bot_brain
	/// When it was first found shut in, this time round (0 when it isn't).
	var/shut_in_since = 0
	/// The bin it climbed into on purpose: it stays in there for the flush (what_holds_me()).
	var/obj/machinery/disposal/bin/riding_bin
	var/next_bin_escape = 0

/// A bin within `range` that lands somewhere else: with somewhere beside it in `region` if it's shut in, and further from
/// `away_from` than from the bot if it's running. The nearest.
/datum/bot_brain/proc/bin_to_escape_by(range, list/region, atom/away_from)
	var/obj/machinery/disposal/bin/best
	var/best_dist
	for(var/obj/machinery/disposal/bin/B as anything in bot_instances_of(/obj/machinery/disposal/bin))
		if(QDELETED(B) || B.z != owner.z || (B.stat & BROKEN) || B.panel_open || !B.trunk)
			continue
		var/dist = get_dist(owner, B)
		if(dist > range || (best && dist >= best_dist))
			continue
		if(away_from && get_dist(away_from, B) <= dist)
			continue
		if(locate(/mob/living) in B)
			continue
		var/turf/landing = bot_disposal_landing(B)
		if(!landing || get_dist(landing, owner) < 4 || (region && region[landing]))
			continue
		if(region && !bot_beside_in(B, region))
			continue
		best = B
		best_dist = dist
	return best

/proc/bot_beside_in(atom/A, list/region)
	for(var/d in GLOB.alldirs)
		if(region[get_step(A, d)])
			return TRUE
	return FALSE

/datum/bot_brain/maybe_ask_to_be_let_out()
	. = ..()
	try_bin_out_of_shut_in()

/// Shut in, still, after asking a while: out by the bin, if there's one in here that goes somewhere.
/datum/bot_brain/proc/try_bin_out_of_shut_in()
	if((gym_scripted && !gym_asks_out) || riding_bin || owner.stat != CONSCIOUS || !isturf(owner.loc))
		return FALSE
	if(state == BOT_STATE_COMBAT || state == BOT_STATE_ARREST || istype(current_goal, /datum/bot_goal/flush_self))
		return FALSE
	if(owner.handcuffed || owner.bot_life_sentence || is_in_active_cell(owner) || (!is_station_level(owner.z) && !gym_run))
		shut_in_since = 0
		return FALSE //there on purpose, as far as anybody else is concerned
	if(!is_shut_in() || !shut_in_region)
		shut_in_since = 0
		return FALSE
	if(!shut_in_since)
		shut_in_since = world.time
	if(world.time < shut_in_since + BOT_SHUT_IN_BIN_AFTER || world.time < next_bin_escape)
		return FALSE
	var/obj/machinery/disposal/bin/B = bin_to_escape_by(20, shut_in_region)
	if(!B)
		next_bin_escape = world.time + BOT_BIN_ESCAPE_REST
		return FALSE
	drop_goals("getting out by [B]")
	return assign_goal(new /datum/bot_goal/flush_self(B, "shut in [get_area_name(owner, TRUE)]"))

/// Running from somebody with a bin right there, and them not between: into it, a player's way out of a corridor fight it's losing.
/datum/bot_brain/try_run_for_it()
	var/mob/living/from = attacker
	. = ..()
	if(!. || QDELETED(from) || riding_bin || world.time < next_bin_escape || !isturf(owner.loc) || get_dist(owner, from) > 3)
		return
	var/obj/machinery/disposal/bin/B = bin_to_escape_by(2, null, from)
	if(!B)
		return
	if(!prob(30 + 50 * competence))
		next_bin_escape = world.time + 1 MINUTES
		return
	drop_goals("into [B], away from [from]")
	assign_goal(new /datum/bot_goal/flush_self(B, "running from [from]"))

/// In a bin it got into to be flushed it stays put, and in the pipes there's nothing to press.
/datum/bot_brain/what_holds_me()
	. = ..()
	if(!. || . != owner.loc)
		return
	if(istype(owner.loc, /obj/structure/disposalholder))
		return null
	if(owner.loc == riding_bin && istype(current_goal, /datum/bot_goal/flush_self))
		return null

/datum/bot_brain/proc/riding_disposals()
	return istype(owner.loc, /obj/structure/disposalholder) || (riding_bin && owner.loc == riding_bin)

/// In a bin it climbed into, or the pipes, it breathes the bin's air for the minute it's in there: nothing to put a mask on for, or to
/// climb out and look for. Two of twelve shifts' riders read the bin as no air, went looking for some and climbed out.
/datum/bot_brain/mind_air_supply()
	if(riding_disposals())
		return
	return ..()

/datum/bot_goal/flush_self
	lawful = TRUE
	exclusive = TRUE
	never_rests = TRUE
	/// A way out, and as often as not out of somewhere with no air: a Head of Security shut in a Chemistry with the air gone out of it
	/// turned down the bin beside it 14 times as "somewhere I can't breathe", the room it was stood in.
	braves_bad_air = TRUE
	doing = "getting out by the disposal bin"
	var/obj/machinery/disposal/bin/bin
	var/why

/datum/bot_goal/flush_self/New(obj/machinery/disposal/bin/B, reason)
	. = ..()
	bin = B
	why = reason

/datum/bot_goal/flush_self/resolve_target(datum/bot_brain/bot)
	target = (QDELETED(bin) || (bin.stat & BROKEN)) ? null : bin

/datum/bot_goal/flush_self/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/flush_self/S = new
	S.steps = list(new /datum/bot_step/move_to(), new /datum/bot_step/paced/ride_disposals())
	return list(S)

/datum/bot_strategy/flush_self/is_feasible(datum/bot_brain/bot)
	return bot.current_goal?.target && !QDELETED(bot.current_goal.target)

/datum/bot_goal/flush_self/on_success(datum/bot_brain/bot)
	bot.riding_bin = null
	bot.shut_in_since = 0
	bot_tally("got out by the bin")

/datum/bot_goal/flush_self/on_give_up(datum/bot_brain/bot)
	bot.riding_bin = null
	bot.next_bin_escape = world.time + BOT_BIN_ESCAPE_REST

/// Into the bin, the flush, the pipes, and out on a floor somewhere else.
/datum/bot_step/paced/ride_disposals
	max_clicks = 3
	var/obj/machinery/disposal/bin/bin
	var/climbing_since = 0
	var/in_since = 0

/datum/bot_step/paced/ride_disposals/start(datum/bot_brain/bot)
	var/datum/bot_goal/flush_self/G = bot.current_goal
	bin = istype(G) ? G.bin : null
	climbing_since = 0
	in_since = 0
	return !QDELETED(bin) && bot.owner.Adjacent(bin)

/datum/bot_step/paced/ride_disposals/do_click(datum/bot_brain/bot)
	var/mob/living/carbon/human/me = bot.owner
	if(istype(me.loc, /obj/structure/disposalholder))
		wait_for = 1 SECONDS
		return TRUE
	if(!QDELETED(bin) && me.loc == bin)
		if(!in_since)
			in_since = world.time
			bot_log(bot, "in [bin], waiting for it to flush")
		if(world.time > in_since + BOT_BIN_RIDE_WAIT)
			bot_log(bot, "[bin] never flushed: climbing back out")
			bot.riding_bin = null
			INVOKE_ASYNC(bin, TYPE_PROC_REF(/atom, relaymove), me, NORTH)
			return FALSE
		wait_for = 1 SECONDS
		return TRUE
	if(in_since)
		return FALSE //out of it: finish() says where
	if(climbing_since)
		if(world.time > climbing_since + 5 SECONDS)
			return FALSE //it never got in
		wait_for = 5
		return TRUE
	if(QDELETED(bin) || !me.Adjacent(bin) || (locate(/mob/living) in bin) || !isturf(me.loc))
		return FALSE
	var/datum/bot_goal/flush_self/G = bot.current_goal
	climbing_since = world.time
	bot.riding_bin = bin
	bot.stop_pursuit()
	me.face_atom(bin)
	bot.telemetry_event("climb_in", list("what" = "[bin]", "why" = "[G?.why]"))
	var/turf/landing = bin.bot_landing
	bot_log(bot, "climbing into [bin] ([G?.why]): it comes out at [landing ? get_area_name(landing, TRUE) : "?"]")
	INVOKE_ASYNC(bin, TYPE_PROC_REF(/obj/machinery/disposal, stuff_mob_in), me, me)
	wait_for = 5
	return TRUE

/datum/bot_step/paced/ride_disposals/finish(datum/bot_brain/bot)
	bot.riding_bin = null
	var/turf/here = get_turf(bot.owner)
	if(in_since && isturf(bot.owner.loc) && !QDELETED(bin) && get_dist(here, bin) > 2)
		bot_log(bot, "out of the disposals in [get_area_name(here, TRUE)]")
		bot.telemetry_event("flushed_out", list("where" = get_area_name(here, TRUE)))
		return GOAL_STEP_SUCCESS
	return GOAL_STEP_FAIL

// ---------------------------------------------------------------------------------------------
// Somebody into the bin
// ---------------------------------------------------------------------------------------------

/datum/bot_brain
	/// Who it beat last, as a weakref, and when: a greytider may yet put them in the bin.
	var/datum/weakref/beaten_foe
	var/beaten_foe_at = 0
	/// A body it's made, as a weakref: a traitor gets it out of sight.
	var/datum/weakref/body_to_hide

/datum/bot_brain/after_the_fight(mob/living/foe)
	. = ..()
	if(ishuman(foe) && foe.stat != DEAD)
		beaten_foe = WEAKREF(foe)
		beaten_foe_at = world.time

/datum/bot_goal/traitor_kill/on_success(datum/bot_brain/bot)
	. = ..()
	var/mob/living/V = victim()
	if(V && V.stat == DEAD)
		bot.body_to_hide = WEAKREF(V)

/datum/bot_brain/proc/is_bot_traitor()
	return !!owner.mind?.has_antag_datum(/datum/antagonist/traitor)

/// Whoever it would put in a bin just now, if anybody: a body it made, as a traitor with nobody looking, or as a greytider,
/// somebody it's just beaten who's still on the floor.
/datum/bot_brain/proc/someone_to_bin()
	if(is_bot_traitor())
		var/mob/living/carbon/human/body = body_to_hide?.resolve()
		if(!istype(body) || body.stat != DEAD || !isturf(body.loc) || get_dist(body, owner) > 10 || body.z != owner.z)
			body_to_hide = null
		else if(!watched_by_anyone()) //goals/traitor.dm
			return body
	if(greytider && world.time < beaten_foe_at + BOT_BIN_PRANK_TIME)
		var/mob/living/carbon/human/H = beaten_foe?.resolve()
		if(istype(H) && H.stat != DEAD && isturf(H.loc) && get_dist(H, owner) <= 6 && H.z == owner.z && !H.buckled && H.incapacitated() && !bot_is_officer(H))
			return H
	return null

/// The bin to put them in: the nearest it can walk to, within ten tiles of them. Somebody alive only goes in one that lands
/// somewhere (a prank, not a murder); a body can go anywhere.
/datum/bot_brain/proc/bin_for(mob/living/victim)
	var/obj/machinery/disposal/bin/best
	var/best_dist
	for(var/obj/machinery/disposal/bin/B as anything in bot_instances_of(/obj/machinery/disposal/bin))
		if(QDELETED(B) || B.z != victim.z || (B.stat & BROKEN) || B.panel_open || !B.trunk || (locate(/mob/living) in B))
			continue
		var/dist = get_dist(victim, B)
		if(dist > 10 || (best && dist >= best_dist))
			continue
		if(gym_run && get_area(B) != get_area(owner))
			continue
		if(victim.stat != DEAD && !bot_disposal_landing(B))
			continue
		if(!gym_run && !can_walk_lawfully_to(B))
			continue
		best = B
		best_dist = dist
	return best

/// Somebody flat out, into the bin.
/datum/bot_duty/stuff_in_bin
	name = "putting somebody in the disposals"
	tier = BOT_DUTY_URGENT
	priority = 4
	interval_min = 5 SECONDS
	interval_max = 10 SECONDS

/datum/bot_duty/stuff_in_bin/try_start(datum/bot_brain/bot)
	if(!bot.greytider && !bot.body_to_hide)
		return FALSE
	var/mob/living/carbon/human/victim = bot.someone_to_bin()
	if(!victim)
		return FALSE
	var/obj/machinery/disposal/bin/B = bot.bin_for(victim)
	if(!B)
		bot.beaten_foe = null
		return FALSE
	bot.beaten_foe = null
	return bot.assign_goal(new /datum/bot_goal/stuff_in_bin(victim, B))

/datum/bot_goal/stuff_in_bin
	exclusive = TRUE
	doing = "putting somebody in the disposals"
	var/obj/machinery/disposal/bin/bin

/datum/bot_goal/stuff_in_bin/New(mob/living/victim, obj/machinery/disposal/bin/B)
	. = ..()
	target = victim
	bin = B

/datum/bot_goal/stuff_in_bin/resolve_target(datum/bot_brain/bot)
	var/mob/living/victim = target
	if(QDELETED(victim) || QDELETED(bin) || !isturf(victim.loc) || victim.buckled || (victim.stat != DEAD && !victim.incapacitated()))
		target = null

/datum/bot_goal/stuff_in_bin/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/stuff_in_bin/S = new
	var/datum/bot_step/move_to/to_bin = new
	to_bin.step_target = bin
	S.steps = list(new /datum/bot_step/move_to(), new /datum/bot_step/take_hold_of_body(), to_bin, new /datum/bot_step/paced/stuff_in_bin())
	return list(S)

/datum/bot_strategy/stuff_in_bin/is_feasible(datum/bot_brain/bot)
	return bot.current_goal?.target && !QDELETED(bot.current_goal.target)

/datum/bot_goal/stuff_in_bin/on_give_up(datum/bot_brain/bot)
	bot.owner.stop_pulling()

/datum/bot_goal/stuff_in_bin/on_success(datum/bot_brain/bot)
	bot_tally("put somebody in the disposals")
	if(bot.body_to_hide?.resolve() == target)
		bot.body_to_hide = null

/// Beside the bin with them in tow: in they go, and the handle down.
/datum/bot_step/paced/stuff_in_bin
	max_clicks = 4
	var/stuffing_since = 0

/datum/bot_step/paced/stuff_in_bin/start(datum/bot_brain/bot)
	stuffing_since = 0
	var/datum/bot_goal/stuff_in_bin/G = bot.current_goal
	var/mob/living/victim = G?.target
	return istype(G) && !QDELETED(victim) && !QDELETED(G.bin) && bot.owner.Adjacent(G.bin)

/datum/bot_step/paced/stuff_in_bin/do_click(datum/bot_brain/bot)
	var/datum/bot_goal/stuff_in_bin/G = bot.current_goal
	var/mob/living/victim = G?.target
	var/obj/machinery/disposal/bin/B = G?.bin
	if(QDELETED(victim) || QDELETED(B))
		return FALSE
	if(victim.loc == B)
		if(!B.flush)
			bot.owner.face_atom(B)
			B.flush = TRUE //the handle, as the window's "handle-1" does
			B.update_icon()
			bot_log(bot, "pulled [B]'s handle with [victim] in it")
			bot.telemetry_event("binned", list("who" = "[victim]", "dead" = victim.stat == DEAD))
			if(bot.greytider && victim.stat != DEAD && prob(60))
				bot_say(bot.owner, pick("Special delivery!", "Bye!", "Off to the dump with you.", "Enjoy the ride!"))
		return FALSE //done
	if(stuffing_since)
		if(world.time > stuffing_since + 4 SECONDS)
			return FALSE //it didn't take
		wait_for = 5
		return TRUE
	if(!bot.owner.Adjacent(B) || !bot.owner.Adjacent(victim) || !isturf(victim.loc))
		return FALSE
	stuffing_since = world.time
	bot.owner.face_atom(B)
	bot.owner.stop_pulling()
	bot.telemetry_event("drag_onto", list("what" = "[victim]", "onto" = "[B]"))
	bot_log(bot, "putting [victim] in [B]")
	INVOKE_ASYNC(B, TYPE_PROC_REF(/obj/machinery/disposal, stuff_mob_in), victim, bot.owner)
	wait_for = 5
	return TRUE

/datum/bot_step/paced/stuff_in_bin/finish(datum/bot_brain/bot)
	var/datum/bot_goal/stuff_in_bin/G = bot.current_goal
	var/mob/living/victim = G?.target
	return (!QDELETED(victim) && !QDELETED(G.bin) && victim.loc == G.bin) ? GOAL_STEP_SUCCESS : GOAL_STEP_FAIL

#undef BOT_SHUT_IN_BIN_AFTER
#undef BOT_BIN_RIDE_WAIT
#undef BOT_BIN_ESCAPE_REST
#undef BOT_DISPOSAL_ROUTE_KEEP
#undef BOT_BIN_PRANK_TIME
