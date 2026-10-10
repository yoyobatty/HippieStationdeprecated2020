// Civilians and command: the jobs whose work is mostly a matter of being somewhere and being seen at it.
//
//  - a Mime can't speak (mind.miming), so everything a bot would have said comes out as a gesture
//  - a Clown or a Mime with somebody nearby puts on a bit of a show: the horn and a joke, or the invisible wall
//  - whoever has an office spends some of the shift sat at the desk in it (the HoP says the desk is open)
//  - the Captain picks the nuclear disk up and keeps it, and says a word to the crew over the announcement
//    system once the shift is under way
//  - the Chaplain, and the doctors when nobody needs treating, take the dead to the morgue: drag the body to a
//    free tray, slide it in, shut the drawer

// ---------------------------------------------------------------------------------------------
// Mime
// ---------------------------------------------------------------------------------------------

GLOBAL_LIST_INIT(bot_mime_gestures, list("gestures.", "waves a hand about.", "mimes something.", "shrugs expressively.", "pulls a face."))
GLOBAL_LIST_INIT(bot_mime_acts, list(
	"presses both hands flat against an invisible wall.",
	"feels along an invisible wall, looking for the way out.",
	"hauls on an invisible rope, hand over hand.",
	"leans into an invisible wind.",
	"juggles three invisible balls.",
	"is trapped in an invisible box!",
	"walks down an invisible staircase.",
	"takes a deep bow.",
))
GLOBAL_LIST_INIT(bot_clown_lines, list(
	"Honk!",
	"Why did the clown go to medbay? He was feeling a little funny.",
	"What do you call a security officer with a banana? An upgrade.",
	"I'd tell you a joke about the engine, but it'd blow up in my face.",
	"Knock knock. Who's there? Honk.",
	"I'm not saying the captain's a clown. That would be an insult to my profession.",
	"What's the difference between a clown and an assistant? I chose this.",
))

/// What a mime does in place of saying `line`. Nothing at all for the radio.
/datum/bot_brain/proc/mime_instead(line)
	if(!line || QDELETED(owner) || owner.stat != CONSCIOUS)
		return
	var/first = copytext(line, 1, 2)
	if(first == ";" || first == ":")
		return
	var/lower = lowertext(line)
	if(bot_text_has_any(lower, GLOB.bot_greeting_words))
		owner.emote("wave")
	else if(bot_text_has_any(lower, list("no idea", "not sure", "beats me", "tell you", "wish i knew", "nothing much")))
		owner.emote("shrug")
	else if(bot_text_has_any(lower, list("thanks", "sure", "alright", "no problem", "on my way", "coming", "yeah", "anytime", "fine")))
		owner.emote("nod")
	else if(findtext(lower, "?"))
		owner.emote("me", EMOTE_VISIBLE, pick("tilts [owner.p_their()] head.", "raises an eyebrow.", "spreads [owner.p_their()] hands questioningly."), TRUE)
	else
		owner.emote("me", EMOTE_VISIBLE, pick(GLOB.bot_mime_gestures), TRUE)
	bot_log(src, "mimed it instead of saying \"[line]\"")

// ---------------------------------------------------------------------------------------------
// Performing
// ---------------------------------------------------------------------------------------------

/datum/bot_brain
	var/shows_put_on = 0

/datum/bot_duty/perform
	name = "performing"
	jobs = list("Clown", "Mime")
	interval_min = 600
	interval_max = 1500

/// Somebody awake nearby to perform for, who isn't in the middle of a fight.
/datum/bot_duty/perform/proc/find_audience(datum/bot_brain/bot)
	var/mob/living/carbon/human/nearest
	for(var/mob/living/carbon/human/H in view(6, bot.owner))
		if(H == bot.owner || H.stat != CONSCIOUS || (H.mind?.assigned_role in jobs))
			continue
		if(H.bot_brain && (H.bot_brain.state == BOT_STATE_COMBAT || H.bot_brain.state == BOT_STATE_ARREST))
			continue
		if(!nearest || get_dist(bot.owner, H) < get_dist(bot.owner, nearest))
			nearest = H
	return nearest

/datum/bot_duty/perform/try_start(datum/bot_brain/bot)
	if(bot.owner.mind?.assigned_role == "Clown" && !bot.find_carried_tool(/obj/item/bikehorn))
		return FALSE //no horn, no act
	var/mob/living/carbon/human/audience = find_audience(bot)
	return audience ? bot.assign_goal(new /datum/bot_goal/perform(audience)) : FALSE

/datum/bot_goal/perform
	lawful = TRUE
	doing = "putting on a bit of a show"

/datum/bot_goal/perform/New(mob/living/audience)
	. = ..()
	target = audience

/datum/bot_goal/perform/resolve_target(datum/bot_brain/bot)
	if(QDELETED(target))
		target = null

/datum/bot_goal/perform/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/perform/S = new
	S.steps = list(new /datum/bot_step/paced/perform())
	return list(S)

/datum/bot_strategy/perform/is_feasible(datum/bot_brain/bot)
	return bot.current_goal?.target && !QDELETED(bot.current_goal.target)

/// A few turns of the act, a couple of seconds apart, from where the bot is stood: the audience is in sight already.
/datum/bot_step/paced/perform
	var/list/done
	var/turns

/datum/bot_step/paced/perform/start(datum/bot_brain/bot)
	done = list()
	turns = rand(3, 4)
	return TRUE

/datum/bot_step/paced/perform/do_click(datum/bot_brain/bot)
	var/mob/living/audience = bot.current_goal?.target
	if(QDELETED(audience) || length(done) >= turns || audience.stat != CONSCIOUS || !(audience in view(7, bot.owner)))
		return FALSE
	bot.owner.face_atom(audience)
	wait_for = rand(25, 45)
	if(bot.owner.mind?.miming)
		var/act = pick(GLOB.bot_mime_acts - done)
		done += act
		bot.owner.emote("me", EMOTE_VISIBLE, act, TRUE)
		return TRUE
	var/obj/item/bikehorn/horn = bot.find_carried_tool(/obj/item/bikehorn)
	if(!horn)
		return FALSE
	// The horn, and every other turn a line to go with it.
	if(length(done) % 2)
		var/line = pick(GLOB.bot_clown_lines - done)
		done += line
		bot_say(bot.owner, line)
		return TRUE
	done += "honk [length(done)]"
	if(!bot.ready_in_hand(horn))
		return FALSE
	bot.toggle_in_hand(horn)
	return TRUE

/datum/bot_step/paced/perform/finish(datum/bot_brain/bot)
	var/obj/item/bikehorn/horn = bot.find_carried_tool(/obj/item/bikehorn)
	if(horn && (horn in bot.owner.held_items))
		bot.put_away(horn, allow_equip = FALSE)
	if(!length(done))
		return GOAL_STEP_FAIL
	bot.shows_put_on++
	return GOAL_STEP_SUCCESS

// ---------------------------------------------------------------------------------------------
// At the desk
// ---------------------------------------------------------------------------------------------

/// Job -> the kinds of area its desk is in.
GLOBAL_LIST_INIT(bot_desk_areas, list(
	"Head of Personnel" = list(/area/crew_quarters/heads/hop),
	"Captain" = list(/area/bridge, /area/crew_quarters/heads/captain),
	"Warden" = list(/area/security/warden),
	"Detective" = list(/area/security/detectives_office),
	"Lawyer" = list(/area/lawoffice),
	"Curator" = list(/area/library),
	"Chaplain" = list(/area/chapel/office, /area/chapel/main),
	"Research Director" = list(/area/crew_quarters/heads/hor),
	"Chief Medical Officer" = list(/area/crew_quarters/heads/cmo),
	"Head of Security" = list(/area/crew_quarters/heads/hos),
	"Quartermaster" = list(/area/quartermaster/qm),
))
/// When somebody last said over the radio that the HoP's desk is open.
GLOBAL_VAR_INIT(bot_hop_desk_called, 0)

/datum/bot_brain
	var/desk_sittings = 0
	var/list/desk_blocked

/// A free chair in this bot's office that it can walk to, the nearest first. In the Bot Gym, one in its arena.
/datum/bot_brain/proc/find_desk_chair()
	var/list/chairs = list() //chair -> how far off
	var/list/area_types = GLOB.bot_desk_areas[owner.mind?.assigned_role]
	if(gym_run)
		for(var/obj/structure/chair/C in get_area(owner))
			chairs[C] = get_dist(owner, C)
	else
		for(var/area_type in area_types)
			var/area/office = GLOB.areas_by_type[area_type]
			if(!office)
				continue
			for(var/obj/structure/chair/C in office)
				chairs[C] = get_dist(owner, C)
	var/tries = 0
	while(length(chairs) && tries++ < 4)
		var/obj/structure/chair/nearest
		for(var/obj/structure/chair/C as anything in chairs)
			if(!nearest || chairs[C] < chairs[nearest])
				nearest = C
		chairs -= nearest
		if(QDELETED(nearest) || nearest.z != owner.z || nearest.has_buckled_mobs() || LAZYACCESS(desk_blocked, nearest) > world.time)
			continue
		var/turf/seat = get_turf(nearest)
		if(locate(/mob/living) in (seat.contents - owner))
			continue
		if(can_walk_lawfully_to(nearest))
			return nearest
		LAZYSET(desk_blocked, nearest, world.time + 10 MINUTES)
	return null

/datum/bot_duty/desk
	name = "at the desk"
	interval_min = 900
	interval_max = 2400

/datum/bot_duty/desk/applies_to(datum/bot_brain/bot)
	return !!GLOB.bot_desk_areas[bot.owner.mind?.assigned_role]

/datum/bot_duty/desk/try_start(datum/bot_brain/bot)
	if(bot.owner.buckled || !prob(60))
		return FALSE
	var/obj/structure/chair/C = bot.find_desk_chair()
	return C ? bot.assign_goal(new /datum/bot_goal/sit_at_desk(C)) : FALSE

/datum/bot_goal/sit_at_desk
	lawful = TRUE
	doing = "heading back to my desk"
	var/obj/structure/chair/chair

/datum/bot_goal/sit_at_desk/New(obj/structure/chair/C)
	. = ..()
	chair = C

/datum/bot_goal/sit_at_desk/resolve_target(datum/bot_brain/bot)
	target = QDELETED(chair) ? null : get_turf(chair)

/datum/bot_goal/sit_at_desk/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/sit_at_desk/S = new
	S.steps = list(new /datum/bot_step/move_to(), new /datum/bot_step/sit_at_desk())
	return list(S)

/datum/bot_goal/sit_at_desk/on_give_up(datum/bot_brain/bot)
	if(chair)
		LAZYSET(bot.desk_blocked, chair, world.time + 10 MINUTES)

/datum/bot_strategy/sit_at_desk/is_feasible(datum/bot_brain/bot)
	return TRUE

/// Sits down, and stays for a few minutes (hangout_until, bot_brain.dm) unless work comes up.
/datum/bot_step/sit_at_desk/execute(datum/bot_brain/bot)
	var/datum/bot_goal/sit_at_desk/G = bot.current_goal
	var/obj/structure/chair/C = istype(G) ? G.chair : null
	if(QDELETED(C) || C.has_buckled_mobs() || get_turf(bot.owner) != get_turf(C))
		return GOAL_STEP_FAIL
	bot.human_pause(C)
	if(QDELETED(C) || C.has_buckled_mobs() || get_turf(bot.owner) != get_turf(C))
		return GOAL_STEP_FAIL
	bot.telemetry_event("sit", list("on" = "[C]"))
	if(!C.user_buckle_mob(bot.owner, bot.owner))
		return GOAL_STEP_FAIL
	bot.hangout_until = world.time + rand(1200, 3000)
	bot.desk_sittings++
	bot_log(bot, "sat down at the desk in [get_area_name(C, TRUE)]")
	if(bot.owner.mind?.assigned_role == "Head of Personnel" && !bot.gym_scripted && (!GLOB.bot_hop_desk_called || world.time > GLOB.bot_hop_desk_called + 10 MINUTES))
		GLOB.bot_hop_desk_called = world.time
		bot.say_after_typing(";[pick("HoP desk is open if anybody needs anything.", "HoP's at the desk - come by if you need access sorting out.", "Head of Personnel's office is open.")]")
	return GOAL_STEP_SUCCESS

// ---------------------------------------------------------------------------------------------
// Captain
// ---------------------------------------------------------------------------------------------

/// Whether the captain has said their piece to the crew this round.
GLOBAL_VAR_INIT(bot_captain_greeted, FALSE)
GLOBAL_LIST_INIT(bot_captain_greetings, list(
	"Good day, crew, this is your captain speaking. Keep it safe, keep it tidy, and have a productive shift.",
	"Attention all hands: captain on the bridge. Heads of staff, bring any problems straight to me. Carry on.",
	"This is the captain. Welcome aboard, everyone. Look after the station and it will look after you.",
))

/datum/bot_brain
	var/captain_blocked_until = 0

/datum/bot_brain/proc/find_comms_console()
	var/obj/machinery/computer/communications/best
	var/best_dist
	for(var/obj/machinery/computer/communications/C as anything in bot_instances_of(/obj/machinery/computer/communications))
		if(QDELETED(C) || C.z != owner.z || (C.stat & (BROKEN|NOPOWER)))
			continue
		if(gym_run && get_area(C) != get_area(owner))
			continue
		var/dist = get_dist(owner, C)
		if(!best || dist < best_dist)
			best = C
			best_dist = dist
	return best

/datum/bot_duty/captain
	name = "the captain's business"
	jobs = list("Captain")
	interval_min = 300
	interval_max = 900

/datum/bot_duty/captain/try_start(datum/bot_brain/bot)
	if(world.time < bot.captain_blocked_until)
		return FALSE
	// The disk goes on the captain's person and stays there.
	if(!bot.find_carried_tool(/obj/item/disk/nuclear))
		var/datum/bot_goal/acquire_item_type/secure_disk/fetch = new
		if(bot.assign_goal(fetch))
			return TRUE
	// A word to the crew, once the shift is properly under way.
	if(!GLOB.bot_captain_greeted && (bot.gym_run || world.time > SSticker.round_start_time + 2 MINUTES) && bot.find_comms_console())
		return bot.assign_goal(new /datum/bot_goal/captain_announce())
	return FALSE

/datum/bot_goal/acquire_item_type/secure_disk
	item_type = /obj/item/disk/nuclear
	lawful = TRUE
	doing = "securing the disk"

/datum/bot_goal/acquire_item_type/secure_disk/on_success(datum/bot_brain/bot)
	var/obj/item/disk/nuclear/disk = bot.find_carried_tool(/obj/item/disk/nuclear)
	if(disk && (disk in bot.owner.held_items))
		bot.put_away(disk, allow_equip = FALSE)
	bot_log(bot, "has the nuclear disk")

/datum/bot_goal/acquire_item_type/secure_disk/on_give_up(datum/bot_brain/bot)
	bot.captain_blocked_until = world.time + 5 MINUTES

/datum/bot_goal/captain_announce
	lawful = TRUE
	doing = "about to make an announcement"

/datum/bot_goal/captain_announce/resolve_target(datum/bot_brain/bot)
	target = bot.find_comms_console()

/datum/bot_goal/captain_announce/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/captain_announce/S = new
	S.steps = list(new /datum/bot_step/move_to(), new /datum/bot_step/captain_announce())
	return list(S)

/datum/bot_goal/captain_announce/on_give_up(datum/bot_brain/bot)
	bot.captain_blocked_until = world.time + 5 MINUTES

/datum/bot_strategy/captain_announce/is_feasible(datum/bot_brain/bot)
	return bot.current_goal?.target && !QDELETED(bot.current_goal.target)

/// At the communications console: the "make an announcement" option, and what it sends.
/datum/bot_step/captain_announce/execute(datum/bot_brain/bot)
	var/obj/machinery/computer/communications/C = bot.current_goal?.target
	if(!istype(C) || QDELETED(C) || !bot.owner.Adjacent(C) || GLOB.bot_captain_greeted)
		return GOAL_STEP_FAIL
	bot.human_pause(C)
	if(QDELETED(C) || !bot.owner.Adjacent(C) || (C.stat & (BROKEN|NOPOWER)) || GLOB.bot_captain_greeted)
		return GOAL_STEP_FAIL
	bot.owner.face_atom(C)
	var/line = pick(GLOB.bot_captain_greetings)
	bot.telemetry_ui_action(C, "make announcement")
	// Typing it out takes as long as it takes.
	sleep(bot_typing_time(line))
	if(QDELETED(C) || QDELETED(bot.owner) || bot.owner.stat != CONSCIOUS || !bot.owner.Adjacent(C))
		return GOAL_STEP_FAIL
	if(!SScommunications.make_announcement(bot.owner, FALSE, line) && !GLOB.bot_captain_greeted)
		bot_log(bot, "the announcement system wouldn't take it")
	GLOB.bot_captain_greeted = TRUE
	bot_log(bot, "announced: \"[line]\"")
	return GOAL_STEP_SUCCESS

// ---------------------------------------------------------------------------------------------
// The morgue
// ---------------------------------------------------------------------------------------------

/// How long somebody has to have been dead before they're taken to the morgue: the doctors get first go at them.
#define BOT_MORGUE_AFTER (3 MINUTES)

/datum/bot_brain
	var/bodies_stored = 0
	var/list/morgue_blocked

/// A body lying about that ought to be in the morgue, the nearest this bot can walk to.
/datum/bot_brain/proc/find_body_for_morgue()
	var/list/bodies = list() //body -> how far off
	for(var/mob/living/carbon/human/H in GLOB.dead_mob_list)
		if(H.z != owner.z || !isturf(H.loc) || H.buckled || H.pulledby || world.time < H.timeofdeath + BOT_MORGUE_AFTER)
			continue
		if(gym_run && get_area(H) != get_area(owner))
			continue
		if(LAZYACCESS(morgue_blocked, H) > world.time || taken_by_another(H))
			continue
		bodies[H] = get_dist(owner, H)
	var/tries = 0
	while(length(bodies) && tries++ < 3)
		var/mob/living/carbon/human/nearest
		for(var/mob/living/carbon/human/H as anything in bodies)
			if(!nearest || bodies[H] < bodies[nearest])
				nearest = H
		bodies -= nearest
		if(can_walk_lawfully_to(nearest))
			return nearest
		LAZYSET(morgue_blocked, nearest, world.time + 5 MINUTES)
	return null

/// Where to stand to work a morgue drawer: beside the spot its tray slides out to, within reach of the drawer too.
/datum/bot_brain/proc/morgue_standing_spot(obj/structure/bodycontainer/morgue/M)
	var/turf/tray_spot = get_step(M, M.dir)
	if(!isopenturf(tray_spot) || is_blocked_turf(tray_spot, TRUE))
		return null
	for(var/turf/open/T in orange(1, tray_spot))
		if(T == get_turf(M) || T.density || is_blocked_turf(T, TRUE) || get_dist(T, M) > 1)
			continue
		if(T.Adjacent(tray_spot) && T.Adjacent(M))
			return T
	return null

/// An empty, shut morgue drawer with room to work at it, the nearest to `near`.
/datum/bot_brain/proc/find_free_morgue(atom/near)
	var/obj/structure/bodycontainer/morgue/best
	var/best_dist
	for(var/obj/structure/bodycontainer/morgue/M as anything in bot_instances_of(/obj/structure/bodycontainer/morgue))
		if(QDELETED(M) || M.z != owner.z || M.locked || !M.connected || M.connected.loc != M)
			continue
		if(gym_run && get_area(M) != get_area(owner))
			continue
		if((locate(/mob/living) in M) || LAZYACCESS(morgue_blocked, M) > world.time || !morgue_standing_spot(M))
			continue
		var/dist = get_dist(near, M)
		if(!best || dist < best_dist)
			best = M
			best_dist = dist
	return best

/datum/bot_duty/morgue
	name = "the morgue"
	jobs = list("Chaplain", "Medical Doctor", "Chief Medical Officer")
	interval_min = 400
	interval_max = 900

/datum/bot_duty/morgue/try_start(datum/bot_brain/bot)
	if(!length(GLOB.dead_mob_list))
		return FALSE
	var/mob/living/carbon/human/body = bot.find_body_for_morgue()
	if(!body)
		return FALSE
	var/obj/structure/bodycontainer/morgue/M = bot.find_free_morgue(body)
	return M ? bot.assign_goal(new /datum/bot_goal/morgue_body(body, M)) : FALSE

/datum/bot_goal/morgue_body
	lawful = TRUE
	exclusive = TRUE
	doing = "taking somebody to the morgue"
	var/obj/structure/bodycontainer/morgue/drawer
	var/turf/standing_spot

/datum/bot_goal/morgue_body/New(mob/living/body, obj/structure/bodycontainer/morgue/M)
	. = ..()
	target = body
	drawer = M

/datum/bot_goal/morgue_body/resolve_target(datum/bot_brain/bot)
	standing_spot = QDELETED(drawer) ? null : bot.morgue_standing_spot(drawer)
	if(QDELETED(target) || !standing_spot)
		target = null

/datum/bot_goal/morgue_body/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/morgue/S = new
	var/datum/bot_step/move_to/to_drawer = new
	to_drawer.step_target = standing_spot
	S.steps = list(new /datum/bot_step/move_to(), new /datum/bot_step/take_hold_of_body(), to_drawer, new /datum/bot_step/load_morgue())
	return list(S)

/datum/bot_goal/morgue_body/on_give_up(datum/bot_brain/bot)
	bot.owner.stop_pulling()
	if(target)
		LAZYSET(bot.morgue_blocked, target, world.time + 5 MINUTES)

/datum/bot_strategy/morgue/is_feasible(datum/bot_brain/bot)
	return bot.current_goal?.target && !QDELETED(bot.current_goal.target)

/datum/bot_step/take_hold_of_body/execute(datum/bot_brain/bot)
	var/mob/living/body = bot.current_goal?.target
	if(!istype(body) || QDELETED(body) || !bot.owner.Adjacent(body))
		return GOAL_STEP_FAIL
	bot.human_pause(body)
	if(QDELETED(body) || !bot.owner.Adjacent(body) || body.pulledby)
		return GOAL_STEP_FAIL
	bot.owner.face_atom(body)
	bot.telemetry_event("pull", list("target" = "[body]"))
	bot.owner.start_pulling(body)
	return bot.owner.pulling == body ? GOAL_STEP_SUCCESS : GOAL_STEP_FAIL

/// At the drawer with the body in tow: slide the tray out, the body onto it, and the tray back in.
/datum/bot_step/load_morgue/execute(datum/bot_brain/bot)
	var/datum/bot_goal/morgue_body/G = bot.current_goal
	var/mob/living/body = G?.target
	var/obj/structure/bodycontainer/morgue/M = istype(G) ? G.drawer : null
	if(QDELETED(body) || QDELETED(M) || !M.connected || bot.owner.pulling != body || !bot.owner.Adjacent(M))
		return GOAL_STEP_FAIL
	var/obj/structure/tray/tray = M.connected
	if(tray.loc == M)
		if(locate(/mob/living) in M)
			return GOAL_STEP_FAIL //somebody got there first
		bot.use_atom(M)
	if(QDELETED(tray) || !isturf(tray.loc) || !bot.owner.Adjacent(tray) || !bot.owner.Adjacent(body))
		return GOAL_STEP_FAIL
	bot.human_pause(tray)
	if(QDELETED(tray) || QDELETED(body) || !isturf(tray.loc) || !bot.owner.Adjacent(tray) || !bot.owner.Adjacent(body))
		return GOAL_STEP_FAIL
	bot.owner.face_atom(tray)
	bot.owner.stop_pulling()
	bot.telemetry_event("drag_onto", list("what" = "[body]", "onto" = "[tray]"))
	tray.MouseDrop_T(body, bot.owner)
	if(QDELETED(body) || body.loc != tray.loc)
		return GOAL_STEP_FAIL
	bot.use_atom(tray) //clicking the tray slides it back in
	if(QDELETED(body) || body.loc != M)
		return GOAL_STEP_FAIL
	bot.bodies_stored++
	bot_log(bot, "put [body] in the morgue")
	if(bot.owner.mind?.assigned_role == "Chaplain" && !bot.gym_scripted && prob(60))
		bot_say(bot.owner, pick("Rest in peace.", "May you find your way.", "Go gently."))
	return GOAL_STEP_SUCCESS

#undef BOT_MORGUE_AFTER
