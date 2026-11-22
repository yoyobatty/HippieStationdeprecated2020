// A crew that knows its blob (2026-11-22, the user: "they should do all 5 honestly, like a real crew would"):
//
//  - Somebody puts an analyzer on it and tells the radio what strain it is, and from then on the crew pick their weapons by it
//    (bot_strain_tactic()): no welders or lasers on a blob that spreads or bursts into flame when burnt, extinguishers on the one water
//    hurts, no clubs or bullets on the one that lashes out at a blow.
//  - Science's maxcap goes on the blob, not the test range: carried to the blob's side nearest its core, set going, and everybody clear;
//    once it's gone off the volunteers rush the hole it made instead of gathering first. Science makes another while the blob lasts.
//
// What a maxcap does to a blob here (BOMBCAP 20): devastation (5 tiles) deletes every blob, the core aside; the heavy ring (10) does
// 100-250 brute at a quarter, which kills most plain blobs and resource blobs; the core takes 20 of its 400 (core.dm ex_act()). It
// clears the way to the core, it doesn't end it.
//
// The rest of the crew's side (the core first, then what feeds it; emitters on lines through the core; the rally) is in goals/blob.dm.

/// Seconds on a blob bomb's timer: time to get well clear, not so long the blob grows over it first. The timer counts once per SSobj
/// tick, two seconds (assembly/timer.dm process()): it's set to half this. A first try set 20 and took it for seconds: forty, and the
/// crew were sent in before it went, three of them into the blast.
#define BOT_BLOB_BOMB_FUSE 20
/// How far back from the blob's edge it's set down: one tile more and the blob has to grow twice to reach it
#define BOT_BLOB_BOMB_BACK 2
/// Bombs a blob gets from Science in a round
#define BOT_BLOB_BOMBS_MAX 3
/// A blob smaller than this is welders' work, not worth a hole in the station
#define BOT_BLOB_BOMB_LEAST 30
/// Everybody this near a blob bomb that's set clears out, told on the radio: past the heavy ring
#define BOT_BLOB_BOMB_CLEAR 14
/// After a blob bomb's gone off, volunteers go straight in this long, with no gathering first
#define BOT_BLOB_RUSH (90 SECONDS)

/// Till then a bomb's just opened it up, or the core's badly hurt: volunteers go straight in, no gathering first (send_volunteers(),
/// goals/blob.dm)
/datum/bot_blob/var/rush_until = 0

// Where the blob is, the air's often gone bad (maintenance, a breach it's eaten through): a player puts a mask on and goes. The rally
// in a shift of these was put in a corridor with no air, and all 22 sent refused it, the core left to grow back from 114 to 400.
/datum/bot_goal/approach_blob
	on_internals = TRUE
/datum/bot_goal/rally_for_blob
	on_internals = TRUE
/datum/bot_goal/fight_blob
	on_internals = TRUE

/// The core's hurt: everybody who'll fight it goes straight in, as a crew does when somebody calls it out on the radio. One shift had
/// it at 114 of 400 in the first minutes, then nobody sent for two minutes, and it was whole again in one.
/datum/bot_blob/proc/press_a_hurt_core()
	var/obj/structure/blob/core/C = owner?.blob_core
	if(QDELETED(C) || C.obj_integrity >= C.max_integrity * 0.6 || world.time < rush_until)
		return
	rush_until = world.time + 60 SECONDS
	next_dispatch = 0
	log_game("BOT BLOB: the core's hurt ([round(C.obj_integrity)]/[C.max_integrity]): everybody in")

/mob/camera/blob/var/bot_strain_known = FALSE
/mob/camera/blob/var/bot_bombs_had = 0

/// Science's bomb for a blob, announced: nobody takes its carrier for a bomber or pulls its timer.
/obj/item/transfer_valve/var/bot_for_blob = FALSE

/// Till then a bomb's on its way to this blob or ticking by it, and the crew gathering for it wait
/mob/camera/blob/var/bot_bomb_due = 0
/// The blob a rally's gathering for (send_volunteers(), goals/blob.dm)
/datum/bot_blob_rally/var/core_ref

// ---------------------------------------------------------------------------------------------
// The strain
// ---------------------------------------------------------------------------------------------

/// What a strain means for whoever's fighting it: BLOB_TACTIC_* flags (code/__DEFINES/~hippie_defines/bots_ai.dm).
/proc/bot_strain_tactic(datum/blobstrain/S)
	if(istype(S, /datum/blobstrain/multiplex))
		var/datum/blobstrain/multiplex/M = S
		. = 0
		for(var/datum/blobstrain/sub as anything in M.blobstrains)
			. |= bot_strain_tactic(sub)
		return
	if(istype(S, /datum/blobstrain/reagent/replicating_foam)) //burn: 60% it grows a new blob; brute does double
		return BLOB_TACTIC_NO_BURN
	if(istype(S, /datum/blobstrain/reagent/blazing_oil)) //burn throws flames round it; water does it harm
		return BLOB_TACTIC_NO_BURN | BLOB_TACTIC_SPRAY
	if(istype(S, /datum/blobstrain/reagent/reactive_spines)) //any blow it lives through, it hits everybody beside it
		return BLOB_TACTIC_NO_BRUTE
	if(istype(S, /datum/blobstrain/reagent/explosive_lattice))
		return BLOB_TACTIC_NO_BOMB
	return 0

/// The blob this bot would be fighting: the one the crew have been told of on its level (in the Bot Gym, its own arena's), nearest.
/datum/bot_brain/proc/crew_blob_core()
	var/obj/structure/blob/core/best
	for(var/obj/structure/blob/core/C as anything in GLOB.blob_cores)
		if(QDELETED(C) || !C.overmind || C.z != owner.z)
			continue
		if(gym_run && get_area(C) != get_area(owner))
			continue
		if(!best || get_dist(owner, C) < get_dist(owner, best))
			best = C
	return best

/// What that blob's strain means for this bot, once somebody's scanned it and said: 0 till then, welders and lasers as for any blob.
/datum/bot_brain/proc/blob_tactic()
	var/obj/structure/blob/core/C = crew_blob_core()
	return C?.overmind.bot_strain_known ? bot_strain_tactic(C.overmind.blobstrain) : 0

/// What the one who scanned it tells the radio.
/proc/bot_strain_advice(datum/blobstrain/S)
	var/tactic = bot_strain_tactic(S)
	if(tactic & BLOB_TACTIC_SPRAY)
		return "Fire just sets it off, get extinguishers on it!"
	if(tactic & BLOB_TACTIC_NO_BURN)
		return "Burning it makes it spread, hit it with something heavy, no welders or lasers!"
	if(tactic & BLOB_TACTIC_NO_BRUTE)
		return "It lashes out when it's hit, welders and lasers only!"
	if(tactic & BLOB_TACTIC_NO_BOMB)
		return "Bombs won't touch it, welders and lasers!"
	return "Welders and lasers on it!"

/// An analyzer on the bit of blob it's beside, and the radio told, if nobody's said what it is yet: from hit_blob() before the first
/// blow. TRUE if that's what it did this click.
/datum/bot_brain/proc/scan_blob(obj/structure/blob/B)
	var/mob/camera/blob/O = B?.overmind
	if(!O || O.bot_strain_known || !owner.Adjacent(B))
		return FALSE
	var/obj/item/analyzer/A = find_carried_tool(/obj/item/analyzer)
	if(!A || !ready_in_hand(A))
		return FALSE
	owner.face_atom(B)
	use_item_on(A, B)
	O.bot_strain_known = TRUE
	bot_log(src, "scanned the blob: [O.blobstrain.name]")
	bot_tally("blobs scanned")
	log_game("BOT BLOB: [owner.real_name] scanned it: [O.blobstrain.name]")
	bot_say(owner, ";The blob's [lowertext(O.blobstrain.name)]. [bot_strain_advice(O.blobstrain)]")
	return TRUE

/// Science and Engineering going to a blob nobody's scanned take an analyzer: the strain's what tells the crew how to fight it. Never
/// a reason not to go: no analyzer to be had, and on it goes without.
/datum/bot_step/ready_analyzer
	var/fetched = FALSE

/datum/bot_step/ready_analyzer/execute(datum/bot_brain/bot)
	var/obj/structure/blob/core/C = bot.crew_blob_core()
	if(fetched || bot.find_carried_tool(/obj/item/analyzer) || !C || C.overmind.bot_strain_known)
		return GOAL_STEP_SUCCESS
	var/role = bot.work_role()
	if(!(role in GLOB.engineering_positions) && !(role in list("Scientist", "Research Director", "Roboticist")))
		return GOAL_STEP_SUCCESS
	fetched = TRUE
	bot_log(bot, "getting an analyzer for the blob")
	if(bot.suspend_goal_for(new /datum/bot_goal/acquire_tool(/obj/item/analyzer)))
		return GOAL_STEP_PENDING
	return GOAL_STEP_SUCCESS

// ---------------------------------------------------------------------------------------------
// Weapons by the strain (used by goals/blob.dm)
// ---------------------------------------------------------------------------------------------

/// An extinguisher with water in, for a blob water hurts.
/datum/bot_brain/proc/blob_extinguisher()
	if(!(blob_tactic() & BLOB_TACTIC_SPRAY))
		return null
	var/obj/item/extinguisher/E = find_carried_tool(/obj/item/extinguisher)
	return (E && E.reagents.total_volume >= 1) ? E : null

/// One spray at it from where it stands, safety off: TRUE if it sprayed.
/datum/bot_brain/proc/spray_blob(obj/structure/blob/B, obj/item/extinguisher/E)
	if(!ready_in_hand(E))
		return FALSE
	if(E.safety)
		toggle_in_hand(E)
	owner.face_atom(B)
	E.afterattack(get_turf(B), owner, FALSE)
	return TRUE

/// Fetches what the strain wants, when there's nothing on it that'll do: an extinguisher for a blob burning makes worse (a heavy thing
/// to hit with, and water for the one water hurts), otherwise a welder (ready_welder).
/datum/bot_step/ensure_extinguisher/for_blob

/datum/bot_step/ensure_extinguisher/for_blob/execute(datum/bot_brain/bot)
	if(bot.armed_against_blob())
		return GOAL_STEP_SUCCESS
	. = ..()
	if(. == GOAL_STEP_FAIL) //none to be had: in with whatever's to hand, never the welder
		bot_log(bot, "no extinguisher for the blob, going in with what I've got")
		return GOAL_STEP_SUCCESS

/// Arming for the blob by what it is: what the strain wants, the welder otherwise.
/datum/bot_brain/proc/blob_arming_steps()
	if(blob_tactic() & BLOB_TACTIC_NO_BURN)
		return list(new /datum/bot_step/kit_up_for_air(), new /datum/bot_step/ready_analyzer(), new /datum/bot_step/ensure_extinguisher/for_blob())
	return list(new /datum/bot_step/kit_up_for_air(), new /datum/bot_step/ready_analyzer(), new /datum/bot_step/ready_welder/arm_for_blob())

// ---------------------------------------------------------------------------------------------
// The bomb
// ---------------------------------------------------------------------------------------------

/// A blob that Science's maxcap goes on instead of the range: one the crew have been told of, aboard, big enough, that a bomb does
/// something to, short of its fill of them. Its core, or null.
/proc/bot_blob_bomb_core(datum/bot_brain/asking)
	var/obj/structure/blob/core/C = bot_blob_alert(asking)
	var/mob/camera/blob/O = C?.overmind
	if(!O || O.bot_bombs_had >= BOT_BLOB_BOMBS_MAX || length(O.blobs_legit) < BOT_BLOB_BOMB_LEAST)
		return null
	if(O.bot_strain_known && (bot_strain_tactic(O.blobstrain) & BLOB_TACTIC_NO_BOMB))
		return null
	return C

/proc/bot_blob_bomb_pending(core_ref)
	var/obj/structure/blob/core/C = locate(core_ref)
	return istype(C) && !QDELETED(C) && C.overmind && world.time < C.overmind.bot_bomb_due

/// Floor two tiles off the blob's edge, as near its core as that goes, that it can walk to: where the bomb's set down. Not at the edge:
/// the blob eats what's on a tile it grows on to, and a bomb eaten before it goes is a bomb wasted.
/datum/bot_brain/proc/blob_bomb_spot(obj/structure/blob/core/C)
	var/list/scored = list()
	for(var/obj/structure/blob/B as anything in C.overmind.blobs_legit)
		if(QDELETED(B) || B.z != C.z)
			continue
		for(var/turf/open/floor/T in orange(BOT_BLOB_BOMB_BACK, B))
			if(get_dist(T, B) != BOT_BLOB_BOMB_BACK || scored[T])
				continue
			scored[T] = get_dist(T, C) + 1
	var/tried = 0
	while(length(scored) && tried < 6)
		var/turf/best
		for(var/turf/T as anything in scored)
			if(!best || scored[T] < scored[best])
				best = T
		scored -= best
		if(best.density || is_blocked_turf(best, TRUE) || (locate(/obj/structure/blob) in orange(BOT_BLOB_BOMB_BACK - 1, best)) || isspaceturf(best))
			continue
		tried++
		if(can_walk_lawfully_to(best))
			return best
	return null

/// Science's maxcap, made as for the range (goals/toxins.dm), taken to the blob instead.
/datum/bot_goal/toxins/blob_bomb
	doing = "taking a bomb to the blob"
	braves_bad_air = TRUE
	var/core_ref
	var/turf/spot

/datum/bot_goal/toxins/blob_bomb/New(datum/bot_toxins/L, obj/structure/blob/core/C)
	. = ..(L)
	core_ref = REF(C)

/datum/bot_goal/toxins/blob_bomb/resolve_target(datum/bot_brain/bot)
	target = null
	var/obj/structure/blob/core/C = locate(core_ref)
	if(!istype(C) || QDELETED(C) || QDELETED(lab.valve))
		return
	if(!spot || (locate(/obj/structure/blob) in orange(BOT_BLOB_BOMB_BACK - 1, spot)))
		spot = bot.blob_bomb_spot(C)
	target = spot

/datum/bot_goal/toxins/blob_bomb/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/toxins/S = new
	S.steps = list(new /datum/bot_step/fetch_valve(lab), new /datum/bot_step/announce_blob_bomb(), new /datum/bot_step/move_to(), new /datum/bot_step/set_blob_bomb())
	return list(S)

/datum/bot_goal/toxins/blob_bomb/on_success(datum/bot_brain/bot)
	var/obj/item/transfer_valve/V = lab.valve
	bot.continue_goal_chain(CALLBACK(bot, TYPE_PROC_REF(/datum/bot_brain, run_from), V || spot, "a bomb going off"))

/datum/bot_goal/toxins/blob_bomb/on_give_up(datum/bot_brain/bot)
	var/obj/structure/blob/core/C = locate(core_ref)
	if(istype(C) && C.overmind)
		C.overmind.bot_bomb_due = 0
	if(!QDELETED(lab.valve) && !lab.finished)
		lab.valve.bot_for_blob = FALSE
	lab.failed(bot) //the bomb's still on it: the next look takes it to the blob again, or to the range

/// On the radio before it goes: the crew have been told, so the one carrying it isn't a bomber and the bomb isn't one to pull the timer on.
/datum/bot_step/announce_blob_bomb
	var/said = FALSE

/datum/bot_step/announce_blob_bomb/execute(datum/bot_brain/bot)
	var/datum/bot_goal/toxins/blob_bomb/G = bot.current_goal
	if(!istype(G) || !G.spot || QDELETED(G.lab.valve))
		return GOAL_STEP_FAIL
	G.lab.valve.bot_for_blob = TRUE
	var/obj/structure/blob/core/C = locate(G.core_ref)
	if(istype(C) && C.overmind)
		C.overmind.bot_bomb_due = world.time + 3 MINUTES
	if(!said)
		said = TRUE
		bot_log(bot, "TOXINS: taking the bomb to the blob, at [bot_coord(G.spot)]")
		bot_say(bot.owner, ";Got a maxcap for the blob, taking it to [get_area_name(G.spot, TRUE)]. Everybody hold back till it's gone off!")
		log_game("BOT BLOB: [bot.owner.real_name] is taking a tank bomb to the blob at [AREACOORD(G.spot)]")
	return GOAL_STEP_SUCCESS

/datum/bot_step/set_blob_bomb/execute(datum/bot_brain/bot)
	var/datum/bot_goal/toxins/blob_bomb/G = bot.current_goal
	var/obj/item/transfer_valve/V = G?.lab.valve
	var/obj/structure/blob/core/C = locate(G?.core_ref)
	if(QDELETED(V) || !istype(C) || QDELETED(C) || !bot.ready_in_hand(V))
		return GOAL_STEP_FAIL
	var/obj/item/assembly/timer/T = V.attached_device
	if(!istype(T))
		return GOAL_STEP_FAIL
	V.bot_for_blob = TRUE
	if(!T.secured)
		T.toggle_secure()
	T.time = round(BOT_BLOB_BOMB_FUSE / 2)
	T.saved_time = T.time
	T.timing = TRUE
	T.update_icon()
	bot.owner.dropItemToGround(V)
	LAZYREMOVE(bot.set_down_items, V) //left there on purpose (goals/toxins.dm set_down_bomb)
	G.lab.finished = TRUE
	C.overmind.bot_bombs_had++
	C.overmind.bot_bomb_due = world.time + (BOT_BLOB_BOMB_FUSE + 30) SECONDS //cleared when it goes (bot_blob_bomb went_off())
	new /datum/bot_blob_bomb(V, C, G.lab)
	bot_tally("bombs on the blob")
	log_game("BOT BLOB: [bot.owner.real_name] set a tank bomb ([BOT_BLOB_BOMB_FUSE]s) at [AREACOORD(V)], [get_dist(V, C)] tiles from the core, [length(C.overmind.blobs_legit)] tiles of blob")
	bot_say(bot.owner, ";Bomb's set by the blob in [get_area_name(V, TRUE)], [BOT_BLOB_BOMB_FUSE] seconds! Get clear!")
	// They heard it: anybody near it gets out, whether or not they can see it from where they are.
	for(var/datum/bot_brain/B as anything in GLOB.bot_brains)
		var/mob/living/carbon/human/H = B.owner
		if(B == bot || QDELETED(H) || H.stat != CONSCIOUS || H.z != V.z || get_dist(H, V) > BOT_BLOB_BOMB_CLEAR)
			continue
		B.run_from(V, "a bomb by the blob")
	return GOAL_STEP_SUCCESS

/// One set by a blob, watched till it's gone off: then the crew rush in, and Science starts another while the blob's still there.
/datum/bot_blob_bomb
	var/obj/item/transfer_valve/valve
	var/core_ref
	var/datum/bot_toxins/lab
	var/tiles_before = 0
	var/core_before = 0
	/// Given up on by then: pulled, eaten by the blob, or a dud
	var/give_up_at = 0
	/// When its valve opened: the blast's a moment behind (SSexplosions), counted a few seconds on
	var/opened_at = 0

/datum/bot_blob_bomb/New(obj/item/transfer_valve/V, obj/structure/blob/core/C, datum/bot_toxins/L)
	. = ..()
	valve = V
	core_ref = REF(C)
	lab = L
	tiles_before = length(C.overmind.blobs_legit)
	core_before = C.obj_integrity
	give_up_at = world.time + (BOT_BLOB_BOMB_FUSE + 30) SECONDS
	START_PROCESSING(SSprocessing, src)

/datum/bot_blob_bomb/Destroy()
	STOP_PROCESSING(SSprocessing, src)
	valve = null
	lab = null
	return ..()

/datum/bot_blob_bomb/process()
	if(!opened_at && (QDELETED(valve) || valve.valve_open))
		opened_at = world.time
	if(opened_at ? world.time < opened_at + 3 SECONDS : world.time < give_up_at)
		return
	went_off()
	qdel(src)

/datum/bot_blob_bomb/proc/went_off()
	var/obj/structure/blob/core/C = locate(core_ref)
	var/alive = istype(C) && !QDELETED(C)
	if(alive && C.overmind)
		C.overmind.bot_bomb_due = 0
	log_game("BOT BLOB: [opened_at ? "the bomb's gone off" : "the bomb never went off"]: blob [tiles_before] -> [alive ? length(C.overmind.blobs_legit) : 0] tiles, core [round(core_before)] -> [alive ? round(C.obj_integrity) : 0]")
	if(!opened_at || !alive)
		return
	var/datum/bot_blob/BB = C.overmind.bot_blob
	if(BB)
		BB.rush_until = world.time + BOT_BLOB_RUSH
		BB.next_dispatch = 0 //the next think() sends the crew in
	if(lab && C.overmind.bot_bombs_had < BOT_BLOB_BOMBS_MAX)
		lab.again_for_blob()

/// Another bomb from the lab, for a blob still standing: from fresh tanks, as for a scientist taking over (handover()).
/datum/bot_toxins/proc/again_for_blob()
	finished = FALSE
	valve = null
	hot_tank = null
	cold_tank = null
	stage = 4 //stage 4 takes the tanks from the dispenser
	stage_failures = 0
	rest_until = 0
	plasma_in_kpa = 0
	for(var/obj/machinery/portable_atmospherics/canister/C as anything in bot_instances_of(/obj/machinery/portable_atmospherics/canister))
		if(!istype(get_area(C), /area/science) || C.connected_port || (C.stat & BROKEN) || C.air_contents.return_pressure() < 2000 || C == oxygen_can)
			continue
		if(istype(C, /obj/machinery/portable_atmospherics/canister/toxins) && (QDELETED(plasma_can) || plasma_can.air_contents.return_pressure() < 2000))
			plasma_can = C
		else if(istype(C, /obj/machinery/portable_atmospherics/canister/oxygen) && (QDELETED(burn_oxygen_can) || burn_oxygen_can.air_contents.return_pressure() < 2000))
			burn_oxygen_can = C
	log_game("BOT TOXINS: another bomb for the blob")

/// The crew's side of one: told of on the radio, so nobody pulls its timer, and anybody near it gets clear. TRUE if it dealt with it.
/datum/bot_brain/proc/react_to_blob_bomb(obj/item/transfer_valve/V)
	if(istype(current_goal, /datum/bot_goal/run_from) || get_dist(owner, V) > BOT_BLOB_BOMB_CLEAR)
		return FALSE
	return run_from(V, "a bomb by the blob")

#undef BOT_BLOB_BOMB_FUSE
#undef BOT_BLOB_BOMB_BACK
#undef BOT_BLOB_BOMBS_MAX
#undef BOT_BLOB_BOMB_LEAST
#undef BOT_BLOB_BOMB_CLEAR
#undef BOT_BLOB_RUSH
