// Throwing check (tools/throw_check/run_throw_check.sh): glide and flight put back, a steady and an unsteady thrower's aim, strength,
// the toss and catch, what's never tossed, a caught beaker not splashing, a running throw's hit, rebounds off a wall, and a blast throwing
// a pile. Headless on Runtime Station. Lines to data/throw_check.txt, PASS/FAIL each, with the numbers.
/datum/controller/master/Initialize(delay, init_sss, tgs_prime)
	if("throw-check" in world.params)
		sleep_offline_after_initializations = FALSE
		INVOKE_ASYNC(GLOBAL_PROC, GLOBAL_PROC_REF(run_throw_check))
	return ..()

GLOBAL_LIST_EMPTY(throw_check_lines)
GLOBAL_VAR_INIT(throw_check_fails, 0)

/proc/tc_note(ok, text)
	GLOB.throw_check_lines += "[ok ? "PASS" : "FAIL"] [text]"
	if(!ok)
		GLOB.throw_check_fails++

/proc/tc_line(text)
	GLOB.throw_check_lines += "     [text]"

/// A floor tile with `lane` clear floor tiles east of it, and a wall right after them if `wall`
/proc/tc_lane(lane, wall = FALSE, list/not_near)
	for(var/turf/open/floor/T in GLOB.station_turfs)
		var/clear = TRUE
		for(var/dx in 0 to lane)
			var/turf/along = locate(T.x + dx, T.y, T.z)
			if(!istype(along, /turf/open/floor) || along.density || !along.has_gravity() || (locate(/obj/structure) in along) || (locate(/obj/machinery) in along) || (locate(/mob) in along))
				clear = FALSE
				break
			for(var/turf/N as anything in not_near)
				if(get_dist(N, along) < 4)
					clear = FALSE
					break
			if(!clear)
				break
		if(!clear)
			continue
		var/turf/after = locate(T.x + lane + 1, T.y, T.z)
		if(wall && !iswallturf(after))
			continue
		return T

/proc/tc_human(turf/T, dir = SOUTH)
	var/mob/living/carbon/human/H = new(T)
	H.setDir(dir)
	return H

/// Waits for a thrown thing to come down, and a moment after
/proc/tc_landed(atom/movable/AM)
	var/deadline = world.time + 5 SECONDS
	while(!QDELETED(AM) && AM.throwing && world.time < deadline)
		sleep(world.tick_lag)
	sleep(2)

/// H throws I at target with this intent, and waits for it to land
/proc/tc_throw(mob/living/carbon/human/H, obj/item/I, atom/target, intent = INTENT_HARM)
	H.a_intent = intent
	H.put_in_active_hand(I)
	H.throw_item(target)
	tc_landed(I)

/// A thrower at `start` facing east and somebody at `finish` facing them, both fresh and standing
/proc/tc_pair(turf/start, turf/finish)
	return list(tc_human(start, EAST), tc_human(finish, WEST))

/proc/tc_clear(list/things)
	for(var/datum/D as anything in things)
		if(!QDELETED(D))
			qdel(D)

/proc/run_throw_check()
	sleep(5 SECONDS)
	GLOB.master_mode = "extended"
	SSticker.start_immediately = TRUE
	var/round_deadline = world.time + 3 MINUTES
	while(SSticker.current_state < GAME_STATE_PLAYING && world.time < round_deadline)
		sleep(1 SECONDS)
	sleep(5 SECONDS)
	var/turf/lane = tc_lane(10)
	var/list/main_lane = list()
	for(var/dx in 0 to 10)
		main_lane += locate(lane.x + dx, lane.y, lane.z)
	var/turf/wall_lane = tc_lane(6, TRUE, main_lane)
	if(!lane || !wall_lane)
		tc_note(FALSE, "no clear lane found ([lane], [wall_lane])")
		tc_finish()
		return
	GLOB.throw_check_lines += "lane [AREACOORD(lane)], wall lane [AREACOORD(wall_lane)], tick_lag [world.tick_lag]"
	var/turf/east7 = locate(lane.x + 7, lane.y, lane.z)
	var/turf/east4 = locate(lane.x + 4, lane.y, lane.z)
	var/turf/east10 = locate(lane.x + 10, lane.y, lane.z)

	// 1 Glide, arc and look put back
	var/mob/living/carbon/human/thrower = tc_human(lane, EAST)
	var/obj/item/wrench/W = new(lane)
	var/old_glide = W.glide_size
	var/old_layer = W.layer
	thrower.a_intent = INTENT_HARM
	thrower.put_in_active_hand(W)
	thrower.throw_item(east7)
	sleep(world.tick_lag)
	var/flying_glide = W.glide_size
	var/flying_layer = W.layer
	tc_landed(W)
	tc_note(flying_glide == throw_glide_size(W.throw_speed) && flying_glide > old_glide && flying_layer == ABOVE_MOB_LAYER, "a wrench (speed [W.throw_speed]) glides [flying_glide] px a tick in the air (was [old_glide] the whole way), drawn over people")
	var/matrix/M = W.transform
	tc_note(W.glide_size == old_glide && W.layer == old_layer && W.pixel_z == 0 && M.a == 1 && M.b == 0 && M.d == 0 && M.e == 1, "landed at [W.x - lane.x] tiles: glide [W.glide_size], layer [W.layer], pixel_z [W.pixel_z], upright")
	GLOB.throw_realism = FALSE
	thrower.put_in_active_hand(W)
	thrower.throw_item(east7)
	sleep(world.tick_lag)
	var/off_glide = W.glide_size
	tc_landed(W)
	GLOB.throw_realism = TRUE
	tc_note(off_glide == old_glide, "with throw-realism off it glides [off_glide], as before")
	tc_clear(list(thrower, W))

	// 2 Aim: steady, drunk, blind, at 7 tiles
	for(var/state in list("sober", "drunk", "dizzy", "blind", "worn out", "hurt arm"))
		var/mob/living/carbon/human/H = tc_human(lane, EAST)
		switch(state)
			if("drunk")
				H.drunkenness = 80
			if("dizzy")
				H.dizziness = 40
			if("blind")
				H.eye_blind = 100
			if("worn out")
				H.adjustStaminaLoss(80)
			if("hurt arm")
				var/obj/item/bodypart/BP = H.hand_bodyparts[H.active_hand_index]
				BP.receive_damage(BP.max_damage * 0.6)
		var/on_mark = 0
		var/total_off = 0
		var/total_reach = 0
		var/n = 12
		for(var/i in 1 to n)
			var/obj/item/wrench/T = new(lane)
			if(state == "worn out")
				H.setStaminaLoss(80) //it wears off as it goes
			tc_throw(H, T, east7)
			var/off = get_dist(T, east7)
			total_off += off
			total_reach += T.x - lane.x
			if(!off)
				on_mark++
			qdel(T)
		var/wobble = round(H.throw_wobble(), 0.01)
		var/strength = round(H.throw_strength(), 0.01)
		tc_line("[state]: wobble [wobble], strength [strength]; [on_mark] of [n] on the mark, [round(total_off / n, 0.1)] tiles off on average, reached [round(total_reach / n, 0.1)] tiles east")
		switch(state)
			if("sober")
				tc_note(on_mark == n, "a sober thrower hits the mark every time ([on_mark] of [n])")
			if("drunk", "dizzy", "blind")
				tc_note(on_mark < n && total_off > 0, "[state]: it wanders ([on_mark] of [n] on the mark)")
			if("worn out", "hurt arm")
				tc_note(total_reach / n < 7, "[state]: it falls short (reached [round(total_reach / n, 0.1)] of 7)")
		qdel(H)

	// 3 Strength: a hulk at 10 tiles with a 7-tile throw
	var/mob/living/carbon/human/hulk = tc_human(lane, EAST)
	hulk.dna.add_mutation(HULK)
	var/obj/item/wrench/HW = new(lane)
	tc_throw(hulk, HW, east10)
	tc_note(HW.x - lane.x > 7, "a hulk throws a wrench [HW.x - lane.x] tiles (a 7-tile throw)")
	tc_clear(list(hulk, HW))

	// 4 The toss: caught facing, at the feet facing away, a hit on harm intent; everybody fresh each time, standing
	var/list/pair = tc_pair(lane, east4)
	var/obj/item/wrench/TW = new(lane)
	var/mob/living/carbon/human/friend = pair[2]
	var/health = friend.health
	tc_throw(pair[1], TW, friend, INTENT_HELP)
	tc_note(TW.loc == friend && friend.health == health, "a wrench tossed on help intent to somebody facing: caught ([TW.loc == friend ? "in hand" : "at [TW.x - lane.x] tiles"]), health [health] -> [friend.health]")
	tc_note(TW.layer == ABOVE_HUD_LAYER && TW.pixel_z == 0, "caught, it's drawn in the hand (layer [TW.layer], pixel_z [TW.pixel_z])")
	tc_clear(pair + TW)

	pair = tc_pair(lane, east4)
	friend = pair[2]
	friend.setDir(EAST)
	TW = new(lane)
	tc_throw(pair[1], TW, friend, INTENT_HELP)
	tc_note(TW.loc == get_turf(friend) && friend.health == health, "tossed to somebody facing away: at their feet ([TW.x - lane.x] tiles), health [friend.health]")
	tc_clear(pair + TW)

	pair = tc_pair(lane, east4)
	friend = pair[2]
	TW = new(lane)
	tc_throw(pair[1], TW, friend, INTENT_HARM)
	tc_note(TW.loc != friend && friend.health < health, "thrown on harm intent: not caught, health [health] -> [friend.health]")
	tc_clear(pair + TW)

	pair = tc_pair(lane, east4)
	friend = pair[2]
	var/obj/item/crowbar/C1 = new(east4)
	var/obj/item/crowbar/C2 = new(east4)
	friend.put_in_hands(C1)
	friend.put_in_hands(C2)
	TW = new(lane)
	tc_throw(pair[1], TW, friend, INTENT_HELP)
	tc_note(TW.loc == get_turf(friend) && friend.health == health, "tossed to somebody with full hands: at their feet, health [friend.health]")
	tc_clear(pair + list(C1, C2, TW))

	var/caught = 0
	for(var/i in 1 to 20)
		pair = tc_pair(lane, east4)
		friend = pair[2]
		friend.drunkenness = 100
		var/obj/item/wrench/D = new(lane)
		tc_throw(pair[1], D, friend, INTENT_HELP)
		if(D.loc == friend)
			caught++
		tc_clear(pair + D)
	tc_note(caught > 0 && caught < 20, "a very drunk catcher catches [caught] of 20")

	// 4b A pacifist can toss a wrench (it can't hurt), but not throw it
	pair = tc_pair(lane, east4)
	var/mob/living/carbon/human/dove = pair[1]
	friend = pair[2]
	ADD_TRAIT(dove, TRAIT_PACIFISM, "throw_check")
	TW = new(lane)
	tc_throw(dove, TW, friend, INTENT_HELP)
	var/tossed_to = TW.loc == friend
	qdel(TW)
	TW = new(lane)
	tc_throw(dove, TW, friend, INTENT_HARM)
	tc_note(tossed_to && get_dist(TW, dove) == 0 && friend.health == health, "a pacifist tosses a wrench ([tossed_to ? "caught" : "not caught"]), and on harm intent sets it down ([get_dist(TW, dove)] tiles away)")
	tc_clear(pair + TW)

	// 5 Never tossed: a cream pie and a bola on help intent do what they do
	pair = tc_pair(lane, east4)
	friend = pair[2]
	var/obj/item/reagent_containers/food/snacks/pie/cream/pie = new(lane)
	tc_throw(pair[1], pie, friend, INTENT_HELP)
	tc_note(QDELETED(pie) && friend.creamed, "a cream pie on help intent isn't caught ([QDELETED(pie) ? "it splatted" : "at [pie.x - lane.x] tiles"], [friend.creamed ? "creamed" : "clean"])")
	tc_clear(pair + pie)
	pair = tc_pair(lane, east4)
	friend = pair[2]
	var/obj/item/restraints/legcuffs/bola/bola = new(lane)
	tc_throw(pair[1], bola, friend, INTENT_HELP)
	tc_note(friend.legcuffed, "a bola on help intent still wraps their legs ([friend.legcuffed ? "legcuffed" : "free"])")
	tc_clear(pair + bola)

	// 6 A caught beaker doesn't splash the catcher
	pair = tc_pair(lane, east4)
	friend = pair[2]
	var/obj/item/reagent_containers/glass/beaker/B = new(lane)
	B.reagents.add_reagent(/datum/reagent/water, 50)
	friend.throw_mode_on()
	tc_throw(pair[1], B, friend, INTENT_HARM)
	tc_note(B.loc == friend && B.reagents.total_volume == 50, "a beaker of water caught in throw mode: [B.loc == friend ? "caught" : "not caught"], [B.reagents.total_volume] of 50 units left")
	tc_clear(pair + B)

	// 7 A faster throw hits harder: a toolbox at its own speed and half again
	var/list/hits = list()
	for(var/speed_mult in list(1, 1.5))
		pair = tc_pair(lane, east4)
		friend = pair[2]
		var/obj/item/storage/toolbox/mechanical/TB = new(lane)
		var/before = friend.getBruteLoss()
		TB.throw_at(friend, 7, TB.throw_speed * speed_mult, pair[1])
		tc_landed(TB)
		hits += friend.getBruteLoss() - before
		tc_clear(pair + TB)
	tc_note(hits[2] > hits[1] && hits[1] > 0, "a toolbox (throwforce 12) at its own speed hit for [hits[1]], at 1.5 times for [hits[2]]")

	// 8 Rebounds off a wall
	var/turf/before_wall = locate(wall_lane.x + 6, wall_lane.y, wall_lane.z)
	var/turf/wall = locate(wall_lane.x + 7, wall_lane.y, wall_lane.z)
	var/at_wall = 0
	var/bounced = 0
	var/elsewhere = list()
	for(var/i in 1 to 30)
		var/mob/living/carbon/human/pitcher = tc_human(wall_lane, EAST)
		var/obj/item/wrench/R = new(wall_lane)
		tc_throw(pitcher, R, wall)
		if(R.loc == before_wall)
			at_wall++
		else if(get_dist(R, before_wall) == 1 && R.y == before_wall.y)
			bounced++
		else
			elsewhere += "[R.x - wall_lane.x],[R.y - wall_lane.y]"
		tc_clear(list(pitcher, R))
	tc_note(bounced > 5 && at_wall > 5, "30 wrenches thrown at a wall: [at_wall] dropped at it, [bounced] rebounded a tile[length(elsewhere) ? ", elsewhere [jointext(elsewhere, " ")]" : ""]")

	// 8b Thrown again mid-air (a blast catching it): still put back as it was
	var/mob/living/carbon/human/twice = tc_human(lane, EAST)
	var/obj/item/wrench/TW2 = new(lane)
	var/old_layer2 = TW2.layer
	var/old_glide2 = TW2.glide_size
	TW2.throw_at(east7, 7, 2, twice)
	sleep(world.tick_lag * 2)
	TW2.throw_at(locate(lane.x + 3, lane.y, lane.z), 7, 3, twice)
	var/deadline2 = world.time + 5 SECONDS
	while(length(SSthrowing.processing) && (TW2 in SSthrowing.processing) && world.time < deadline2)
		sleep(world.tick_lag)
	sleep(3)
	tc_note(TW2.layer == old_layer2 && TW2.glide_size == old_glide2 && TW2.pixel_z == 0, "thrown again mid-air: layer [TW2.layer] (was [old_layer2]), glide [TW2.glide_size] (was [old_glide2]), pixel_z [TW2.pixel_z]")
	tc_clear(list(twice, TW2))

	// 8c A bowling ball rolls: no arc, drawn as it was
	var/mob/living/carbon/human/bowler = tc_human(lane, EAST)
	var/obj/item/bowling/ball = new(lane)
	var/ball_layer = ball.layer
	ball.throw_at(east7, 7, 2, bowler)
	sleep(world.tick_lag)
	var/ball_air_layer = ball.layer
	tc_landed(ball)
	tc_note(ball_air_layer == ball_layer && ball.layer == ball_layer, "a bowling ball rolls rather than flies (layer [ball_air_layer] in the air, [ball.layer] after)")
	tc_clear(list(bowler, ball))

	// 8d What starting a throw costs: 200 wrenches thrown from one tile, realism on and off
	for(var/on in list(FALSE, TRUE))
		GLOB.throw_realism = on
		var/list/batch = list()
		for(var/i in 1 to 200)
			batch += new /obj/item/wrench(lane)
		var/started = TICK_USAGE_REAL
		for(var/obj/item/wrench/BW as anything in batch)
			BW.throw_at(east7, 7, 2, null, quickstart = FALSE)
		var/took = TICK_DELTA_TO_MS(TICK_USAGE_REAL - started)
		tc_line("starting 200 throws with realism [on ? "on" : "off"]: [round(took, 0.01)] ms ([round(took * 1000 / 200, 0.1)] us a throw)")
		var/deadline3 = world.time + 10 SECONDS
		while(length(SSthrowing.processing) && world.time < deadline3)
			sleep(world.tick_lag)
		tc_clear(batch)
	GLOB.throw_realism = TRUE

	// 9 A thrown person: glide put back, nothing left on them
	var/mob/living/carbon/human/flung = tc_human(lane, EAST)
	var/flung_glide = flung.glide_size
	flung.throw_at(east7, 7, 2)
	tc_landed(flung)
	tc_note(flung.glide_size == flung_glide && flung.pixel_z == 0, "a person thrown 7 tiles: glide [flung_glide] -> [flung.glide_size], pixel_z [flung.pixel_z]")
	qdel(flung)

	// 10 A pile: 300 things on a tile a blast throws about, realism on, then off
	for(var/on in list(TRUE, FALSE))
		GLOB.throw_realism = on
		var/turf/pile = lane
		for(var/i in 1 to 300)
			new /obj/item/wrench(pile)
		var/started = REALTIMEOFDAY
		var/busy = 0
		var/cost_before = SSthrowing.cost
		explosion(locate(pile.x - 1, pile.y, pile.z), 0, 0, 3, 0, adminlog = FALSE, silent = TRUE)
		var/deadline = world.time + 20 SECONDS
		while(world.time < deadline)
			sleep(world.tick_lag)
			if(!length(SSthrowing.processing) && !SSexplosions.is_exploding())
				break
			busy++
		var/left_up = 0
		var/turned = 0
		for(var/obj/item/wrench/P in range(12, pile))
			if(P.layer == ABOVE_MOB_LAYER || P.pixel_z)
				left_up++
			var/matrix/PM = P.transform
			if(PM.b || PM.d)
				turned++
			qdel(P)
		tc_line("pile with realism [on ? "on" : "off"]: settled after [busy] ticks, [(REALTIMEOFDAY - started) / 10] s real; SSthrowing [round(SSthrowing.cost, 0.01)] ms last fire (was [round(cost_before, 0.01)])")
		tc_note(!left_up && !turned, "pile with realism [on ? "on" : "off"]: none left in the air ([left_up]) or turned ([turned])")
		sleep(2 SECONDS)
	GLOB.throw_realism = TRUE
	tc_finish()

/proc/tc_finish()
	var/list/out = GLOB.throw_check_lines.Copy()
	out += "[GLOB.throw_check_fails ? "FAILED [GLOB.throw_check_fails]" : "ALL PASSED"]"
	text2file(jointext(out, "\n"), "data/throw_check.txt")
