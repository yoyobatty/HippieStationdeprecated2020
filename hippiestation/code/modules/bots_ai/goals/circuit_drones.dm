// Drones (the user's rulings, 2026-11-07): a traitor Scientist or Research Director sends a drone after its kill target instead of
// going itself. Two kinds, the same build (goals/circuits.dm) with the payload bought off the uplink:
//
//  - the special delivery: a minibomb in a grenade primer on a drone that finds its target by name, trundles after them and goes off
//    when it's beside them, all the while saying seven polite things at once, every six seconds ("Hello, Bob! You have a package!",
//    "Your package is a bomb.", "Please hold still to receive your delivery."). The user's description of the player who did it best:
//    five to ten sentences going at once, and then it blows you up.
//  - the hunter drone: a mini energy crossbow in a weapon firing mechanism, an examiner telling it where they are, and the same chase.
//
// Built without its cell, and with the panel open: switched on in the bag it would start talking from the bag. The traitor walks it to
// within sight of the target, puts it down, puts the cell in, shuts it, and gets clear.
//
// The crew: anybody with a gun and the nerve, Security above all, shoots an armed drone on sight (a disabler does nothing to an
// assembly; it takes something lethal, or a club). Everybody else gets away from one that's near, and its target from it when it hears
// its name (mind_armed_drones()).

/// How long a traitor keeps at a drone before it gives up on the idea and fetches the sword.
#define BOT_DRONE_PLAN_TIME (15 MINUTES)
/// How close it gets before letting the drone go: in sight, and not on top of them.
#define BOT_DRONE_RELEASE_RANGE 6

/datum/bot_brain
	/// The kind of drone it's going to send after its target ("delivery_drone" or "hunter_drone"), and since when.
	var/drone_plan
	var/drone_plan_since = 0
	/// Took too long or couldn't be done: the old way, then.
	var/drone_plan_dropped = FALSE
	/// The one it's sent, while it's out there, and how many it's sent: two, and then it does it itself.
	var/datum/weakref/drone_out
	var/drones_sent = 0
	var/next_drone_look = 0
	var/next_drone_shout = 0

GLOBAL_LIST_INIT(bot_delivery_lines, list("Your package is a bomb.", "Please hold still to receive your delivery.", "This delivery does not require a signature.",
	"Thank you for choosing Syndicate Express!", "Your call is important to us. Please stay on the line.", "Estimated time of delivery: now.",
	"Please rate your delivery experience after the explosion.", "Fragile. Explosive. Yours.", "Leave at door? Request denied.",
	"Your package has been dispatched. So have you.", "We tried to deliver your package. We will try again. And again.",
	"No refunds.", "Please be home to receive your delivery.", "Smile! This delivery is being recorded for quality assurance."))

/datum/bot_circuit_design/delivery_drone
	id = "delivery_drone"
	name = "special delivery"
	case_name = "electronic drone"
	power_on_release = TRUE
	payload_part = 6
	payload_type = /obj/item/grenade
	parts = list("fast ticker", "advanced locator", "basic pathfinder", "locomotion circuit", "advanced locator", "grenade primer", "slow ticker", "concatenator",
		"text-to-speech circuit", "text-to-speech circuit", "text-to-speech circuit", "text-to-speech circuit", "text-to-speech circuit", "text-to-speech circuit",
		"text-to-speech circuit", "text-to-speech circuit", "large tesla power relay")
	constants = list(list(1, 1, 1), list(2, 1, "victim_name"), list(2, 2, 8), list(5, 1, "victim_name"), list(5, 2, 1), list(6, 1, 3), list(7, 1, 1),
		list(8, 1, "Hello, "), list(8, 2, "victim_name"), list(8, 3, "! You have a package!"),
		list(10, 1, "line1"), list(11, 1, "line2"), list(12, 1, "line3"), list(13, 1, "line4"), list(14, 1, "line5"), list(15, 1, "line6"),
		list(16, 1, "Delivery complete. Have a nice day!"))
	wires = list(
		list(1, "A", 1, 2, "A", 1), //tick: where are they
		list(2, "O", 1, 3, "I", 1),
		list(2, "A", 2, 3, "A", 1), //there: which way
		list(3, "O", 1, 4, "I", 1),
		list(3, "A", 2, 4, "A", 1), //and a step
		list(1, "A", 1, 5, "A", 1), //right beside us?
		list(5, "A", 2, 6, "A", 1), //then the primer
		list(5, "A", 2, 16, "A", 1), //and a sign-off
		list(7, "A", 1, 8, "A", 1), //every six seconds, all of it at once
		list(8, "O", 1, 9, "I", 1),
		list(8, "A", 2, 9, "A", 1),
		list(8, "A", 2, 10, "A", 1),
		list(8, "A", 2, 11, "A", 1),
		list(8, "A", 2, 12, "A", 1),
		list(8, "A", 2, 13, "A", 1),
		list(8, "A", 2, 14, "A", 1),
		list(8, "A", 2, 15, "A", 1))

/datum/bot_circuit_design/hunter_drone
	id = "hunter_drone"
	name = "hunter drone"
	case_name = "electronic drone"
	power_on_release = TRUE
	payload_part = 6
	payload_type = /obj/item/gun/energy
	parts = list("fast ticker", "advanced locator", "basic pathfinder", "locomotion circuit", "examiner", "weapon firing mechanism", "large tesla power relay")
	constants = list(list(1, 1, 1), list(2, 1, "victim_name"), list(2, 2, 8), list(6, 3, "lethal"))
	wires = list(
		list(1, "A", 1, 2, "A", 1),
		list(2, "O", 1, 3, "I", 1),
		list(2, "A", 2, 3, "A", 1),
		list(3, "O", 1, 4, "I", 1),
		list(3, "A", 2, 4, "A", 1),
		list(2, "O", 1, 5, "I", 1), //where they are from here
		list(2, "A", 2, 5, "A", 1),
		list(5, "O", 3, 6, "I", 1),
		list(5, "O", 4, 6, "I", 2),
		list(5, "A", 2, 6, "A", 1)) //and fire

/// The words for a drone sent after somebody.
/datum/bot_brain/proc/drone_context(datum/bot_circuit_design/D, mob/living/carbon/human/V, lethal = TRUE)
	. = list("empty" = list(), "victim_name" = V.real_name, "victim" = WEAKREF(V), "lethal" = lethal ? 1 : 0)
	var/list/lines = GLOB.bot_delivery_lines.Copy()
	shuffle_inplace(lines)
	for(var/i in 1 to 6)
		.["line[i]"] = lines[i]

/// Somebody wanted for something major, alive and on this z-level, that nobody's got in cuffs: a known traitor, as far as the crew knows.
/proc/bot_dangerous_wanted(z)
	for(var/datum/weakref/ref as anything in GLOB.bot_security_wanted)
		var/datum/bot_wanted/W = GLOB.bot_security_wanted[ref]
		var/mob/living/carbon/human/H = ref.resolve()
		if(W && W.severity >= BOT_CRIME_MAJOR && H && H.stat != DEAD && H.z == z && !H.handcuffed)
			return H

/// Whether a drone still has something to do it with: a grenade not gone off, or a gun.
/proc/bot_drone_armed(obj/item/electronic_assembly/A)
	for(var/obj/item/integrated_circuit/manipulation/grenade/primer in A.assembly_components)
		if(primer.attached_grenade && !QDELETED(primer.attached_grenade) && !primer.attached_grenade.active)
			return TRUE
	for(var/obj/item/integrated_circuit/manipulation/weapon_firing/mechanism in A.assembly_components)
		if(mechanism.installed_gun)
			return TRUE
	return FALSE

/// A finished drone it's carrying, of either kind.
/datum/bot_brain/proc/carried_drone()
	for(var/obj/item/electronic_assembly/drone/D in owner.GetAllContents())
		if(GLOB.bot_circuit_made[D] == "delivery_drone" || GLOB.bot_circuit_made[D] == "hunter_drone")
			return D

// ---------------------------------------------------------------------------------------------
// The traitor's way of doing it (goal_for_objective(), goals/traitor.dm)
// ---------------------------------------------------------------------------------------------

/// The next goal towards sending a drone after a kill objective's target: a print at the lathe, the build, or letting it go. null when
/// it's waiting on something (research, materials) and FALSE when it's given up on the idea, for the sword.
/datum/bot_brain/proc/drone_goal_for_kill(datum/objective/O)
	if(drone_plan_dropped || plays_robust() || !(work_role() in list("Scientist", "Research Director")))
		return FALSE
	var/mob/living/carbon/human/V = O?.target?.current
	if(!istype(V) || V.stat == DEAD || V.z != owner.z)
		return FALSE
	return drone_goal_for_victim(V)

/datum/bot_brain/proc/drone_goal_for_victim(mob/living/carbon/human/V)
	// One's on its way: see how it does. (A traitor bought a second bomb two seconds after letting the first go.)
	var/obj/item/electronic_assembly/out = drone_out?.resolve()
	if(out && !QDELETED(out) && bot_drone_armed(out))
		return null
	if(drones_sent >= 2)
		drone_plan_dropped = TRUE
		bot_log(src, "two drones and [V] still about: doing it myself")
		return FALSE
	if(!drone_plan)
		drone_plan = prob(50) ? "delivery_drone" : "hunter_drone"
		drone_plan_since = world.time
		bot_log(src, "going to send a [drone_plan == "delivery_drone" ? "special delivery" : "hunter drone"] after [V]")
	if(world.time > drone_plan_since + BOT_DRONE_PLAN_TIME && !carried_drone())
		bot_log(src, "the drone's taking too long: doing it myself")
		drone_plan_dropped = TRUE
		return FALSE
	var/obj/item/electronic_assembly/drone/made = carried_drone()
	if(made)
		return new /datum/bot_goal/release_drone(made, V)
	// Its payload, off the uplink: a minibomb for a delivery, the mini crossbow for a hunter. The crossbow is dearer; short of crystals,
	// a delivery it is.
	var/datum/bot_circuit_design/D = GLOB.bot_circuit_designs[drone_plan]
	if(!find_circuit_supply(D.payload_type))
		var/bought = buy_from_uplink(drone_plan == "delivery_drone" ? /obj/item/grenade/syndieminibomb : /obj/item/gun/energy/kinetic_accelerator/crossbow)
		if(!bought && drone_plan == "hunter_drone")
			drone_plan = "delivery_drone"
			D = GLOB.bot_circuit_designs[drone_plan]
			bought = find_circuit_supply(D.payload_type) || buy_from_uplink(/obj/item/grenade/syndieminibomb)
		if(!bought)
			bot_log(src, "nothing to put in a drone: doing it myself")
			drone_plan_dropped = TRUE
			return FALSE
		bot_log(src, "bought [find_carried_tool(D.payload_type)] for the [D.name]")
	var/list/context = drone_context(D, V)
	var/prep = circuit_prerequisite(D, context, /datum/bot_duty/traitor)
	if(istype(prep, /datum/bot_goal))
		return prep
	if(!istype(prep, /obj/item/integrated_circuit_printer))
		return null
	return new /datum/bot_goal/build_circuit(prep, D, context, null)

// ---------------------------------------------------------------------------------------------
// Letting it go
// ---------------------------------------------------------------------------------------------

/datum/bot_brain/proc/release_drone(obj/item/electronic_assembly/drone/D, mob/living/carbon/human/V)
	if(QDELETED(D) || !V || V.stat == DEAD)
		return
	assign_goal(new /datum/bot_goal/release_drone(D, V))

/datum/bot_goal/release_drone
	lawful = TRUE
	breaks_in = TRUE
	doing = "taking a package to somebody"
	var/obj/item/electronic_assembly/drone/drone
	var/released = FALSE

/datum/bot_goal/release_drone/New(obj/item/electronic_assembly/drone/D, mob/living/carbon/human/V)
	. = ..()
	drone = D
	target = V

/datum/bot_goal/release_drone/resolve_target(datum/bot_brain/bot)
	var/mob/living/carbon/human/V = target
	if(QDELETED(drone) || !istype(V) || V.stat == DEAD || V.z != bot.owner.z)
		target = null

/datum/bot_goal/release_drone/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/robotics/S = new
	S.steps = list(new /datum/bot_step/paced/release_drone())
	return list(S)

/datum/bot_goal/release_drone/on_success(datum/bot_brain/bot)
	bot_log(bot, "let [drone] go at [target]")
	bot_tally("drones sent")
	bot.drone_out = WEAKREF(drone)
	bot.drones_sent++
	bot.continue_goal_chain(CALLBACK(bot, TYPE_PROC_REF(/datum/bot_brain, run_from), drone, "getting clear of my delivery"), TRUE)

/datum/bot_goal/release_drone/on_give_up(datum/bot_brain/bot)
	if(!released && world.time > bot.drone_plan_since + BOT_DRONE_PLAN_TIME)
		bot.drone_plan_dropped = TRUE

/// After them until they're in sight and a few steps off, then down it goes: the cell in, the screwdriver, and away.
/datum/bot_step/paced/release_drone
	max_clicks = 150

/datum/bot_step/paced/release_drone/do_click(datum/bot_brain/bot)
	var/datum/bot_goal/release_drone/G = bot.current_goal
	var/mob/living/carbon/human/V = G?.target
	var/obj/item/electronic_assembly/drone/D = G?.drone
	if(!istype(G) || !istype(V) || V.stat == DEAD || QDELETED(D))
		return FALSE
	if(G.released)
		return FALSE
	var/dist = get_dist(bot.owner, V)
	if(D in bot.owner.GetAllContents())
		if(dist > BOT_DRONE_RELEASE_RANGE || !(V in view(BOT_DRONE_RELEASE_RANGE, bot.owner)))
			bot.pursue(V, "follow")
			wait_for = 10
			return TRUE
		bot.stop_pursuit()
		// Following closes right up to them: a few steps back before it goes down. (It stood at their elbow, too close to let it go, for
		// three minutes, following them.)
		if(dist < 3)
			bot.step_back_from(V)
			wait_for = 4
			return TRUE
		if(!bot.ready_in_hand(D))
			return FALSE
		bot.human_pause(D)
		bot.owner.dropItemToGround(D)
		bot_log(bot, "put [D] down, [dist] tiles from [V]")
		return TRUE
	if(!isturf(D.loc) || !bot.owner.Adjacent(D))
		return FALSE
	if(!D.battery || D.opened)
		if(!bot.power_and_close_circuit(D))
			return FALSE
		if(D.battery && !D.opened)
			G.released = TRUE
			return FALSE
		return TRUE
	G.released = TRUE
	return FALSE

/datum/bot_step/paced/release_drone/finish(datum/bot_brain/bot)
	var/datum/bot_goal/release_drone/G = bot.current_goal
	return G?.released ? GOAL_STEP_SUCCESS : GOAL_STEP_FAIL

// ---------------------------------------------------------------------------------------------
// The crew
// ---------------------------------------------------------------------------------------------

/// An armed drone in sight (an assembly with a combat circuit, on the floor): shoot it, club it, or get away from it. Once a second, from
/// mind_hands() (bot_reflexes.dm).
/datum/bot_brain/proc/mind_armed_drones()
	if(world.time < next_drone_look || owner.incapacitated() || state == BOT_STATE_ARREST)
		return FALSE
	next_drone_look = world.time + 1 SECONDS
	var/turf/here = get_turf(owner)
	for(var/obj/item/electronic_assembly/A in GLOB.hostile_machines)
		if(QDELETED(A) || !A.combat_circuits || !A.battery || A.opened || !isturf(A.loc) || A.z != here.z || get_dist(here, A) > BOT_SIGHT_RANGE)
			continue //only one that's live: shut, with a cell in (the builder ran from its own, just out of the printer, empty, for a minute)
		var/datum/weakref/maker = GLOB.bot_circuit_makers[A]
		if(maker?.resolve() == src)
			continue //its own: it knows what it's for
		if(!(A in view(BOT_SIGHT_RANGE, owner)))
			continue
		return react_to_armed_drone(A)
	return FALSE

/// Who a drone's locator is looking for, by name: what the drone says it to anybody close enough to hear.
/proc/bot_drone_target_name(obj/item/electronic_assembly/A)
	for(var/obj/item/integrated_circuit/input/advanced_locator/L in A.assembly_components)
		var/datum/integrated_io/wanted = L.inputs[1]
		if(istext(wanted.data))
			return wanted.data

/// A shot at it with something that'll hurt it: an assembly shrugs off a disabler or a taser entirely.
/datum/bot_brain/proc/shoot_drone(obj/item/electronic_assembly/A)
	if(world.time < next_taser_time || !has_clear_shot(A))
		return FALSE
	var/obj/item/gun/G = ready_lethal_gun()
	if(!G || !G.can_shoot())
		return FALSE
	owner.a_intent = INTENT_HARM
	owner.face_atom(A)
	owner.changeNext_move(CLICK_CD_RANGE)
	next_taser_time = world.time + max(CLICK_CD_RANGE, G.fire_delay) + 5
	bot_log(src, "firing [G] at [A] (dist [get_dist(owner, A)])")
	INVOKE_ASYNC(G, TYPE_PROC_REF(/obj/item/gun, afterattack), A, owner, FALSE, null)
	return TRUE

/datum/bot_brain/proc/react_to_armed_drone(obj/item/electronic_assembly/A)
	var/dist = get_dist(owner, A)
	var/after_me = (bot_drone_target_name(A) == owner.real_name)
	// Shoot it: Security, and anybody else with a gun and the nerve.
	if((is_security_job() || nerve >= 0.7) && !istype(current_goal, /datum/bot_goal/run_from))
		if(world.time >= next_drone_shout)
			next_drone_shout = world.time + 20 SECONDS
			bot_say(owner, pick(";Armed drone in [get_area_name(A, TRUE)]! Shooting it down!", "Drone! Take it down!", "Get that thing!"), TRUE)
		if(shoot_drone(A))
			return TRUE
		var/obj/item/weapon = owner.get_active_held_item()
		if(dist <= 1 && weapon && weapon.force >= 5)
			owner.changeNext_move(CLICK_CD_MELEE)
			return use_item_on(weapon, A, harm = TRUE)
	// Get away from it.
	if(istype(current_goal, /datum/bot_goal/run_from) || (dist > 5 && !after_me))
		return FALSE
	if(world.time >= next_drone_shout)
		next_drone_shout = world.time + 20 SECONDS
		bot_say(owner, after_me ? pick("It's after me! Somebody shoot it!", "Why is it saying my name?!", "Get it away from me!") : pick(";There's a drone with a bomb on it in [get_area_name(A, TRUE)]!", "Drone! Get back!", "What is that thing?! Run!"), TRUE)
	return run_from(A, "an armed drone")

#undef BOT_DRONE_PLAN_TIME
#undef BOT_DRONE_RELEASE_RANGE
