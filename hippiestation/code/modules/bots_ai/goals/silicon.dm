// The AI and cyborgs. Everything else in this folder is written for a human body, with hands and a backpack, so silicons get a small brain of
// their own. There's one AI and a couple of cyborgs on a crew big enough to have them (BOT_CREW_SILICONS).
//
// The AI can't go anywhere, and what it's for is everything it can do from the core:
//  - Doors. Somebody shut in who says so, or anybody who says "AI, open this", gets the nearest door opened.
//  - Cameras. Whoever Security wants, if a camera can see them, gets called out with where they are, which is what Security's hunts run on.
//  - Sensors. Somebody dead turns up on the crew monitor, and Medical gets told where.
//  - Asked for its laws, it states them.
//
// A cyborg goes about the station with whatever its module gives it, the same click a player's would be (ClickOn(), with the tool active):
// a medical cyborg sees to anybody hurt, a janitor cyborg mops, an engineering cyborg repairs what's been broken, and a security cyborg stops
// anybody wanted. Between jobs it goes to wherever the crew are.

/// Between looks at what wants doing.
#define BOT_SILICON_TICK (2 SECONDS)
#define BOT_BORG_STEP 2
/// Between calling the same person out over the cameras.
#define BOT_AI_CALLOUT_GAP (45 SECONDS)
/// Tiles a cyborg will look for work in.
#define BOT_BORG_SIGHT 7
/// What a cyborg will walk across the station for, in its own trade.
#define BOT_BORG_RANGE 40
/// Damage worth a medical cyborg's time.
#define BOT_BORG_HURT 25

GLOBAL_LIST_EMPTY(bot_silicons)
/// The order a crew gets its cyborgs in.
GLOBAL_LIST_INIT(bot_borg_modules, list(/obj/item/robot_module/medical, /obj/item/robot_module/engineering, /obj/item/robot_module/janitor, /obj/item/robot_module/security))

/mob/living/silicon/var/datum/bot_silicon/bot_silicon

/mob/living/silicon/Hear(message, atom/movable/speaker, datum/language/message_language, raw_message, radio_freq, list/spans, message_mode)
	. = ..()
	if(bot_silicon && raw_message)
		bot_silicon.heard(speaker, lowertext(raw_message), radio_freq)

/// One AI first, then cyborgs, each out of a body that's made for it and handed over by the game's own procs.
/proc/bot_spawn_silicons(count)
	var/made = 0
	if(count > 0 && !length(GLOB.ai_list))
		var/mob/living/silicon/ai/A = bot_make_silicon("AI")
		if(A)
			new /datum/bot_silicon/ai(A)
			made++
	for(var/path in GLOB.bot_borg_modules)
		if(made >= count)
			break
		var/mob/living/silicon/robot/R = bot_make_silicon("Cyborg")
		if(R)
			var/datum/bot_silicon/borg/B = new(R)
			var/obj/item/robot_module/M = R.module.transform_to(path) //picks a skin for it, renames it, and plays the animation on its own
			B.note(M ? "a [M.name] cyborg" : "no module: [path] wouldn't take")
			made++
	return made

/proc/bot_make_silicon(rank)
	var/turf/T
	for(var/obj/effect/landmark/start/cyborg/L in GLOB.landmarks_list)
		T = get_turf(L)
		break
	if(!T)
		T = get_turf(pick(SSjob.latejoin_trackers))
	var/mob/living/carbon/human/H = new(T)
	H.mind_initialize()
	H.mind.assigned_role = rank
	H.mind.special_role = null
	if(rank == "AI")
		return H.AIize(TRUE)
	return H.Robotize(FALSE, TRUE)

/datum/bot_silicon
	var/mob/living/silicon/owner
	/// Requests read this off whoever's taken them.
	var/next_tick = 0

/datum/bot_silicon/New(mob/living/silicon/S)
	. = ..()
	owner = S
	S.bot_silicon = src
	GLOB.bot_silicons += src
	RegisterSignal(S, COMSIG_PARENT_QDELETING, PROC_REF(lost_body))
	think_loop()

/datum/bot_silicon/proc/lost_body()
	GLOB.bot_silicons -= src
	if(owner)
		owner.bot_silicon = null
	owner = null

/datum/bot_silicon/proc/think_loop()
	set waitfor = FALSE
	while(!QDELETED(owner))
		if(owner.stat == CONSCIOUS)
			try
				think()
			catch(var/exception/e)
				log_runtime("BOT SILICON EXCEPTION ([owner]): [e] at [e.file]:[e.line]")
		sleep(next_look())

/datum/bot_silicon/proc/next_look()
	return BOT_SILICON_TICK

/datum/bot_silicon/proc/think()
	return

/datum/bot_silicon/proc/heard(atom/movable/speaker, lower_msg, radio_freq)
	return

/// A line in game.log, the same as a bot's. Silicons have no telemetry: this is all there is to read them by.
/datum/bot_silicon/proc/note(text)
	log_game("BOT SILICON: [owner]: [text]")

/datum/bot_silicon/proc/say_it(line)
	if(!QDELETED(owner) && owner.stat == CONSCIOUS)
		owner.say(line)

// ---------------------------------------------------------------------------------------------
// The AI
// ---------------------------------------------------------------------------------------------

/datum/bot_silicon/ai
	/// Weakref -> when it can next call this person out.
	var/list/called_out
	/// Weakrefs of the bodies it's told Medical about.
	var/list/bodies_reported
	var/greeted = FALSE
	var/next_law_recital = 0

/datum/bot_silicon/ai/think()
	if(!greeted)
		greeted = TRUE
		say_it(pick("Good morning, crew. Station systems nominal.", "All systems online. Call if you need a door.", "AI online. Have a safe shift."))
	open_doors_for_those_shut_in()
	watch_the_cameras()
	read_the_crew_monitor()

/// The nearest door to somebody that's shut, if the AI can work it.
/datum/bot_silicon/ai/proc/door_near(atom/A)
	var/obj/machinery/door/airlock/best
	var/best_dist
	for(var/obj/machinery/door/airlock/D in range(2, get_turf(A)))
		if(!D.density || !D.canAIControl(owner))
			continue
		var/dist = get_dist(A, D)
		if(!best || dist < best_dist)
			best = D
			best_dist = dist
	return best

/datum/bot_silicon/ai/proc/open_door(obj/machinery/door/airlock/D)
	if(D.locked)
		D.unbolt()
	return D.open()

/datum/bot_silicon/ai/proc/open_doors_for_those_shut_in()
	for(var/datum/bot_request/R as anything in GLOB.bot_requests)
		if(!istype(R.kind, /datum/bot_request_kind/let_out) || !R.still_open())
			continue
		var/mob/living/asker = R.caller_ref?.resolve()
		if(!asker || asker.stat == DEAD || !GLOB.cameranet.checkTurfVis(get_turf(asker)))
			continue
		var/obj/machinery/door/airlock/D = door_near(asker)
		if(!D)
			continue
		R.taken_by = src
		open_door(D)
		say_it(pick("Door's open, [asker.name].", "Got it.", "There you go."))
		return

/// Whoever's wanted, if a camera can see them. An AI watching the cameras is why a suspect doesn't stay lost for long.
/datum/bot_silicon/ai/proc/watch_the_cameras()
	for(var/datum/weakref/ref as anything in GLOB.bot_security_wanted)
		var/mob/living/carbon/human/H = ref.resolve()
		var/datum/bot_wanted/W = GLOB.bot_security_wanted[ref]
		if(!H || H.stat == DEAD || H.handcuffed || W.severity < BOT_CRIME_MAJOR || LAZYACCESS(called_out, ref) > world.time)
			continue
		var/turf/T = get_turf(H)
		if(!T || !is_station_level(T.z) || !GLOB.cameranet.checkTurfVis(T))
			continue
		W.last_seen = T
		W.last_seen_at = world.time
		LAZYSET(called_out, ref, world.time + BOT_AI_CALLOUT_GAP)
		say_it(":s [H.name], [get_area_name(T, TRUE)].")
		bot_dispatch_security(T, H.name) //goals/security_tactics.dm
		return

/datum/bot_silicon/ai/proc/read_the_crew_monitor()
	for(var/mob/living/carbon/human/H in GLOB.dead_mob_list)
		if(!H.mind?.assigned_role || !is_station_level(H.z))
			continue
		var/datum/weakref/ref = WEAKREF(H)
		if(ref in bodies_reported)
			continue
		LAZYADD(bodies_reported, ref)
		var/obj/item/clothing/under/U = H.w_uniform
		if(!istype(U) || !U.sensor_mode) //nothing on the monitor to read
			continue
		say_it(":m Crew monitor has [H.real_name] dead, [get_area_name(H, TRUE)].")
		return

/datum/bot_silicon/ai/heard(atom/movable/speaker, lower_msg, radio_freq)
	var/mob/living/talker = speaker
	if(istype(speaker, /atom/movable/virtualspeaker))
		var/atom/movable/virtualspeaker/V = speaker
		talker = V.source
	if(!isliving(talker) || talker == owner || !bot_text_has_any(lower_msg, list("ai")))
		return
	if(bot_text_has_any(lower_msg, list("law", "laws")))
		if(world.time >= next_law_recital)
			next_law_recital = world.time + 1 MINUTES
			state_laws()
		return
	if(bot_text_has_any(lower_msg, list("open", "door", "let me", "unbolt")))
		var/obj/machinery/door/airlock/D = door_near(talker)
		if(D)
			open_door(D)
			say_it(pick("Done.", "Opening.", "Got it, [talker.name]."))

/datum/bot_silicon/ai/proc/state_laws()
	set waitfor = FALSE
	for(var/line in owner.laws.get_law_list(TRUE))
		say_it(";[strip_html_simple(line)]")
		sleep(2 SECONDS)

// ---------------------------------------------------------------------------------------------
// Cyborgs
// ---------------------------------------------------------------------------------------------

/datum/bot_silicon/borg
	/// For the routes: its doors open for it when it gets there, and the route finder wants a card to know that.
	var/obj/item/card/id/route_card
	var/list/route
	var/atom/heading_for
	/// When it gives up on where it's going.
	var/give_up_at = 0
	/// Going to where the crew are rather than to a job: it keeps an eye out for work on the way.
	var/wandering = FALSE
	var/next_job_look = 0
	/// REF() of the last thing it set off for, and how many times in a row: blood behind a window is a tile away and out of reach for good.
	var/last_target_ref
	var/same_target_tries = 0
	/// REF() -> when it'll try that again.
	var/list/skip_until

/datum/bot_silicon/borg/New(mob/living/silicon/S)
	route_card = new
	route_card.access = get_all_accesses()
	if(!S.hud_used) //a player's comes with their client, and the module slots it holds are where a cyborg's tools go
		S.hud_used = new S.hud_type(S)
	S.a_intent = INTENT_HELP //so people swap places with it in a corridor, as they do with a player's
	return ..()

/datum/bot_silicon/borg/lost_body()
	QDEL_NULL(route_card)
	return ..()

/datum/bot_silicon/borg/next_look()
	return length(route) ? BOT_BORG_STEP : BOT_SILICON_TICK

/datum/bot_silicon/borg/proc/robot()
	return owner

/datum/bot_silicon/borg/proc/tool(path)
	var/mob/living/silicon/robot/R = owner
	for(var/obj/item/I in R.module.modules)
		if(istype(I, path))
			return I
	return null

/// With this tool active, a click on that: what a player's cyborg does. The tool goes in a free slot (a click on it in the module panel)
/// and gets selected (a click on the slot, or 1-3).
/datum/bot_silicon/borg/proc/use_on(obj/item/I, atom/A)
	var/mob/living/silicon/robot/R = owner
	if(!I || !A)
		return
	var/slot = R.held_items.Find(I)
	if(!slot)
		if(!R.activate_module(I)) //all three slots full
			R.uneq_module(R.held_items[3])
			R.activate_module(I)
		slot = R.held_items.Find(I)
	if(!slot)
		return
	if(R.module_active != I)
		R.select_module(slot)
	R.a_intent = INTENT_HELP
	note("using [I] on [A] ([get_area_name(A, TRUE)])")
	R.ClickOn(A, "")

/// Sets off for it, up to `min_dist` tiles short. FALSE if there's no way there, or it's been this way too often for nothing.
/datum/bot_silicon/borg/proc/go_to(atom/A, min_dist = 1)
	var/turf/T = get_turf(A)
	if(!T || T.z != owner.z || skipping(A))
		return FALSE
	var/ref = REF(A)
	if(ref == last_target_ref)
		if(++same_target_tries > 4)
			skip(A)
			return FALSE
	else
		last_target_ref = ref
		same_target_tries = 0
	route = get_path_to(owner, T, /turf/proc/Distance_cardinal, 0, 400, min_dist, id = route_card)
	if(!length(route))
		skip(A)
		return FALSE
	heading_for = A
	give_up_at = world.time + 1 MINUTES
	note("heading for [A] ([get_area_name(A, TRUE)]): [length(route)] steps from [AREACOORD(owner)]")
	return TRUE

/datum/bot_silicon/borg/proc/skipping(atom/A)
	return LAZYACCESS(skip_until, REF(A)) > world.time

/datum/bot_silicon/borg/proc/skip(atom/A)
	for(var/ref in skip_until)
		if(skip_until[ref] <= world.time)
			skip_until -= ref
	LAZYSET(skip_until, REF(A), world.time + 5 MINUTES)
	same_target_tries = 0

/datum/bot_silicon/borg/proc/keep_walking()
	if(!length(route) || world.time > give_up_at || QDELETED(heading_for) || owner.Adjacent(heading_for))
		route = null
		heading_for = null
		return FALSE
	var/turf/next = route[1]
	if(get_dist(owner, next) > 1)
		route = null
		return FALSE
	step_towards(owner, next)
	if(get_turf(owner) == next)
		route.Cut(1, 2)
	return TRUE

/datum/bot_silicon/borg/think()
	var/mob/living/silicon/robot/R = owner
	if(R.incapacitated() || R.lockcharge)
		return
	if(wandering && world.time >= next_job_look)
		next_job_look = world.time + BOT_SILICON_TICK
		if(job())
			wandering = FALSE
			return
	if(keep_walking())
		return
	wandering = FALSE
	if(job())
		return
	var/list/crew = GLOB.bot_crew_members
	if(length(crew))
		var/mob/living/carbon/human/H = pick(crew)
		if(!QDELETED(H) && H.stat != DEAD && H.z == owner.z && go_to(H))
			wandering = TRUE
			next_job_look = world.time + BOT_SILICON_TICK

/// Security's radio call (bot_dispatch_security()): a security cyborg goes too, looking out for whoever it's about on the way.
/datum/bot_silicon/borg/proc/answer_call(turf/T)
	var/mob/living/silicon/robot/R = owner
	if(R.module.type != /obj/item/robot_module/security || R.stat != CONSCIOUS || T.z != R.z || (heading_for && !wandering) || get_dist(R, T) > BOT_BORG_RANGE)
		return
	if(go_to(T))
		wandering = TRUE
		next_job_look = world.time

/// What its module's for. TRUE if it's seeing to something.
/datum/bot_silicon/borg/proc/job()
	var/mob/living/silicon/robot/R = owner
	switch(R.module.type)
		if(/obj/item/robot_module/medical)
			return medical_job()
		if(/obj/item/robot_module/janitor)
			return janitor_job()
		if(/obj/item/robot_module/engineering)
			return engineer_job()
		if(/obj/item/robot_module/security)
			return security_job()
	return FALSE

/datum/bot_silicon/borg/proc/medical_job()
	var/mob/living/carbon/human/best
	var/best_dist
	for(var/mob/living/carbon/human/H in GLOB.alive_mob_list)
		if(H.z != owner.z || H.stat == DEAD || max(H.getBruteLoss(), H.getFireLoss()) < BOT_BORG_HURT || skipping(H))
			continue
		var/dist = get_dist(owner, H)
		if(dist <= BOT_BORG_RANGE && (!best || dist < best_dist))
			best = H
			best_dist = dist
	if(!best)
		return FALSE
	if(owner.Adjacent(best))
		var/obj/item/reagent_containers/borghypo/hypo = tool(/obj/item/reagent_containers/borghypo)
		var/datum/reagent/medicine = best.getBruteLoss() >= best.getFireLoss() ? /datum/reagent/medicine/bicaridine : /datum/reagent/medicine/kelotane
		if(!hypo || best.reagents.get_reagent_amount(medicine) >= 10) //a dose is working: give it time
			return TRUE
		var/i = hypo.reagent_ids.Find(medicine)
		if(i)
			hypo.mode = i //what its menu does
		use_on(hypo, best)
		return TRUE
	return go_to(best)

/datum/bot_silicon/borg/proc/janitor_job()
	var/obj/effect/decal/cleanable/best
	var/best_dist
	for(var/obj/effect/decal/cleanable/C in view(BOT_BORG_SIGHT, owner))
		if(skipping(C))
			continue
		var/dist = get_dist(owner, C)
		if(!best || dist < best_dist)
			best = C
			best_dist = dist
	if(!best)
		return FALSE
	if(owner.Adjacent(best))
		//a janitor cyborg cleans whatever it drives over (its module's clean_on_move), which is how players do it; its mop starts dry, so
		//anything it can't drive onto gets the soap
		if(owner.loc == best.loc || !owner.Move(best.loc, get_dir(owner, best)))
			use_on(tool(/obj/item/soap), best)
		return TRUE
	return go_to(best, 0) //onto it

/datum/bot_silicon/borg/proc/engineer_job()
	var/obj/structure/window/best
	for(var/obj/structure/window/W in view(BOT_BORG_SIGHT, owner))
		if(W.obj_integrity < W.max_integrity && !skipping(W))
			best = W
			break
	if(!best)
		return FALSE
	if(owner.Adjacent(best))
		var/obj/item/weldingtool/welder = tool(/obj/item/weldingtool)
		if(welder && !welder.welding)
			welder.attack_self(owner)
		use_on(welder, best)
		return TRUE
	return go_to(best)

/// Stops them, and leaves the rest to Security: it doesn't drag anybody to the Brig.
/datum/bot_silicon/borg/proc/security_job()
	for(var/mob/living/carbon/human/H in view(BOT_BORG_SIGHT, owner))
		if(H.stat == DEAD || H.handcuffed || !bot_is_wanted(H) || skipping(H))
			continue
		var/next_to = owner.Adjacent(H)
		if(!(H.mobility_flags & MOBILITY_STAND)) //down: walk over and cuff them
			if(next_to)
				use_on(tool(/obj/item/restraints/handcuffs), H)
				return TRUE
			return go_to(H)
		var/obj/item/gun/G = tool(/obj/item/gun)
		if(!next_to && G)
			use_on(G, H)
			return TRUE
		if(next_to)
			use_on(tool(/obj/item/melee/baton), H)
			return TRUE
		return go_to(H)
	return FALSE

#undef BOT_SILICON_TICK
#undef BOT_BORG_STEP
#undef BOT_AI_CALLOUT_GAP
#undef BOT_BORG_SIGHT
#undef BOT_BORG_RANGE
#undef BOT_BORG_HURT
