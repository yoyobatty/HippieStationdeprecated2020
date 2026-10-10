// EVA gearing: suits a bot up in its department's hardsuit (suit + helmet), the correct
// mask for that hardsuit, and an internals tank before doing anything that risks
// exposure to space - the tesla engine setup (setup_tesla_engine.dm) in particular is
// commonly done in a depressurized/exposed room. Runs once per bot (it stops
// re-triggering the moment is_eva_ready() is true).
//
// The lookup table below (hardsuit/mask/preferred-SSU per job) covers every job that
// has a real hardsuit + dedicated suit_storage_unit variant in the base game
// (suit_storage_unit.dm) - not just the three engineering roles - so the mechanism
// itself is correct for any of them (right mask type per hardsuit matters: atmos and
// security/captain hardsuits pair with a gas mask, not the plain breath mask engineering
// and medical use - getting that wrong would have left is_eva_ready() permanently
// false for those jobs). is_eva_job() below is what actually gates who gets
// auto-triggered to gear up - deliberately still just the three engineering roles, the
// only ones with a task that actually goes into space right now. Adding another job to
// that check later is enough to turn this on for it; nothing else needs to change.
GLOBAL_LIST_INIT(bot_eva_loadouts, list(
	// No "boots" entry for Station Engineer/Atmospheric Technician - unlike the Chief
	// Engineer, whose SSU already comes stocked with a pair (free to grab while already
	// raiding it for the hardsuit), theirs would be a whole separate fetch for something
	// they don't need almost all of the time. get_job_boots_type() below still pulls
	// them in dynamically for these two jobs specifically, but only once gravity's
	// actually off - see that proc's comment.
	"Station Engineer" = list(
		"hardsuit" = /obj/item/clothing/suit/space/hardsuit/engine,
		"mask" = /obj/item/clothing/mask/breath,
		"ssu" = /obj/machinery/suit_storage_unit/engine),
	"Chief Engineer" = list(
		"hardsuit" = /obj/item/clothing/suit/space/hardsuit/engine/elite,
		"mask" = /obj/item/clothing/mask/breath,
		"ssu" = /obj/machinery/suit_storage_unit/ce,
		"boots" = /obj/item/clothing/shoes/magboots),
	"Atmospheric Technician" = list(
		"hardsuit" = /obj/item/clothing/suit/space/hardsuit/engine/atmos,
		"mask" = /obj/item/clothing/mask/gas,
		"ssu" = /obj/machinery/suit_storage_unit/atmos),
	"Security Officer" = list(
		"hardsuit" = /obj/item/clothing/suit/space/hardsuit/security,
		"mask" = /obj/item/clothing/mask/gas/sechailer,
		"ssu" = /obj/machinery/suit_storage_unit/security),
	"Head of Security" = list(
		"hardsuit" = /obj/item/clothing/suit/space/hardsuit/security/hos,
		"mask" = /obj/item/clothing/mask/gas/sechailer,
		"ssu" = /obj/machinery/suit_storage_unit/hos),
	"Chief Medical Officer" = list(
		"hardsuit" = /obj/item/clothing/suit/space/hardsuit/medical,
		"mask" = /obj/item/clothing/mask/breath,
		"ssu" = /obj/machinery/suit_storage_unit/cmo),
	"Research Director" = list(
		"hardsuit" = /obj/item/clothing/suit/space/hardsuit/rd,
		"mask" = /obj/item/clothing/mask/breath,
		"ssu" = /obj/machinery/suit_storage_unit/rd),
	"Shaft Miner" = list(
		"hardsuit" = /obj/item/clothing/suit/space/hardsuit/mining,
		"mask" = /obj/item/clothing/mask/breath,
		"ssu" = /obj/machinery/suit_storage_unit/mining/eva),
	"Captain" = list(
		"hardsuit" = /obj/item/clothing/suit/space/hardsuit/swat/captain,
		"mask" = /obj/item/clothing/mask/gas/sechailer,
		"ssu" = /obj/machinery/suit_storage_unit/captain),
))

/datum/bot_brain/proc/get_eva_loadout()
	return GLOB.bot_eva_loadouts[owner.mind?.assigned_role]

// Deliberately narrower than "every job with a loadout entry above" - see the big
// comment at the top of this file for why.
/datum/bot_brain/proc/is_eva_job()
	var/role = owner.mind?.assigned_role
	return role == "Station Engineer" || role == "Chief Engineer" || role == "Atmospheric Technician"

/datum/bot_brain/proc/get_job_hardsuit_type()
	var/list/loadout = get_eva_loadout()
	return loadout ? loadout["hardsuit"] : null

/datum/bot_brain/proc/get_job_mask_type()
	var/list/loadout = get_eva_loadout()
	return loadout ? loadout["mask"] : /obj/item/clothing/mask/breath //sane fallback if a job's missing from the table

// Null (not a fallback type) for any job without a "boots" entry above - unlike the
// hardsuit/mask, going without magboots is a legitimate configuration for a job whose
// EVA work never actually crosses open space, so equip_eva_gear()/is_eva_ready() below
// both treat null as "not required" rather than substituting some default pair.
//
// Station Engineer/Atmospheric Technician have no static "boots" entry (see the loadout
// table above) and, unlike the CE, deliberately get no DYNAMIC one either anymore - this
// used to send them after a plain pair via a world-wide acquire_item_type fetch the
// instant needs_mag_pulse() (below) turned true, which sounded reasonable but doesn't
// match this station's actual access layout: confirmed via the map source, the ONLY loose
// pair of plain (non-CE) magboots anywhere on it sits on a rack in "EVA Storage"
// (area/ai_monitored/storage/eva), behind an airlock req_access-gated to ACCESS_EVA
// (access.dm) - which neither job's access list includes (station_engineer.dm/
// atmospheric_technician.dm; only chief_engineer.dm has it). A real Station Engineer
// player has no legitimate way to get magboots either, then - the CE's own SSU stocking a
// pair for free (loadout table above) is the intended, CE-exclusive perk, not a baseline
// every engineering job eventually reaches. Confirmed in-game as the actual cause of a
// Station Engineer bot stuck looping instead of finishing the tesla checklist a CE bot
// breezed through: is_eva_ready() kept requiring magboots that flat-out don't exist
// anywhere reachable, so equip_eva_gear's fetch kept targeting the same unreachable
// EVA-locked pair, failing, and immediately retrying on the very next next_eva_check_time
// poll (gear_up_eva.dm has no blacklist for a specific failed fetch target the way
// failed_engine_parts does for engine parts) - forever. Since bot_turf_crossable_without_
// boots()/bot_turf_has_pushoff_backup() (bot_pathing_permissive.dm) already let a
// suited-but-bootless bot cross a real, player-reachable space tile via push-off physics
// same as a real player without magboots can, there's no actual survival gap left for
// these two jobs to compensate for by fetching gear they can't get to anyway.
/datum/bot_brain/proc/get_job_boots_type()
	var/list/loadout = get_eva_loadout()
	return loadout ? loadout["boots"] : null

// Standardized per-role stash lookup: every job above already has its own dedicated
// suit_storage_unit subtype in the base game - the CE's own is mapped in their office,
// separate from the general engineering one. Same mechanism, same proc, for every role -
// just a different preferred type per job, pulled from the same table.
/datum/bot_brain/proc/get_preferred_ssu_type()
	var/list/loadout = get_eva_loadout()
	return loadout ? loadout["ssu"] : null

// Prefers the job's own dedicated SSU (score 0) over any other one that still has
// something in it (score 1, distance tiebreak) - "the CE prefers their own office"
// falls out of this naturally, since the /ce SSU variant is normally only mapped there.
/datum/bot_brain/proc/find_eva_ssu()
	var/preferred = get_preferred_ssu_type()
	var/obj/machinery/suit_storage_unit/best
	var/best_dist
	var/best_score
	for(var/obj/machinery/suit_storage_unit/S in GLOB.machines)
		if(S.z != owner.z)
			continue
		if(!S.suit && !S.mask && !S.storage)
			continue //empty - nothing left to raid
		var/dist = get_dist(owner, S)
		if(dist > 100)
			continue
		var/score = (preferred && istype(S, preferred)) ? 0 : 1
		if(!best || score < best_score || (score == best_score && dist < best_dist))
			best = S
			best_dist = dist
			best_score = score
	return best

// True when the bot's immediate surroundings are hazardous enough that a real engineer
// would actually clip their mag-boots down - no gravity, a hull breach (pressure under
// HAZARD_LOW_PRESSURE, __DEFINES/atmospherics.dm), an active fire tile (active_hotspot,
// LINDA_fire.dm), or standing right next to open space - rather than unconditionally on
// the moment boots are worn. Deliberately disabled that unconditional version: mag-pulse
// carries a real movement penalty (slowdown_active, magboots.dm), so toggling it on in an
// ordinary pressurized, gravity-on room was pure downside for no benefit.
//
// Checks the tile ADJACENT to space too, not just the bot's own tile - is_eva_ready()
// below is what actually gates whether the pathfinder is allowed to route through a real
// space turf at all (can_path_through_space()), re-evaluated fresh before every path
// attempt, but the periodic recheck that notices a hazard appeared (next_eva_check_time,
// bot_brain.dm) only runs every 5-15 real seconds - relying on "am I currently ON a
// hazardous tile" alone would leave a real gap where the bot could already be mid-route
// onto space with mag-pulse still off. Reacting one tile early closes that gap in
// practice, since a bot approaching a room boundary crosses several ordinary tiles first.
/datum/bot_brain/proc/needs_mag_pulse()
	var/turf/T = get_turf(owner)
	if(!T)
		return FALSE
	if(!owner.has_gravity())
		return TRUE
	if(istype(T, /turf/open))
		var/turf/open/O = T
		if(O.active_hotspot)
			return TRUE
		var/datum/gas_mixture/environment = O.return_air()
		if(environment && environment.return_pressure() < HAZARD_LOW_PRESSURE)
			return TRUE
	for(var/turf/adjacent in RANGE_TURFS(1, T))
		if(isspaceturf(adjacent))
			return TRUE
	return FALSE

// Suit worn, helmet engaged (suittoggled - see ToggleHelmet(), suits/toggles.dm), the
// job's own mask type on, and an internals tank carried on the body (eva_tank(),
// refill_internals.dm) - its valve is opened and shut as the air around the bot changes.
// can_path_through_space=0 flickering to 1 and back within a handful of seconds in the
// verbose logs (a "gear-up succeeded" moments before a "no path next to space" failure)
// pointed at is_eva_ready() itself flapping, not a one-time gearing failure - but WHICH
// sub-check flaps wasn't visible from outside. Logging the specific reason on every
// FALSE turns that from a guess into a direct read on the next test.
/datum/bot_brain/proc/is_eva_ready()
	var/obj/item/clothing/suit/space/hardsuit/suit = owner.wear_suit
	if(!istype(suit))
		bot_log_verbose(src, "is_eva_ready: FALSE - wear_suit is [owner.wear_suit] (not a hardsuit)")
		return FALSE
	if(!suit.suittoggled)
		bot_log_verbose(src, "is_eva_ready: FALSE - [suit] helmet not toggled")
		return FALSE
	var/mask_type = get_job_mask_type()
	if(mask_type && !istype(owner.wear_mask, mask_type))
		bot_log_verbose(src, "is_eva_ready: FALSE - wear_mask is [owner.wear_mask], need [mask_type]")
		return FALSE
	// A tank on the body, where its valve can be reached - not one already open. This used to be "owner.internal
	// is set", which made being ready for space the same thing as breathing from the tank all shift
	// (manage_internals(), refill_internals.dm, opens it when the air calls for it).
	if(!eva_tank())
		bot_log_verbose(src, "is_eva_ready: FALSE - no internals tank on me")
		return FALSE
	// Wearing magboots alone isn't enough to move purposefully in zero-g - negates_gravity()
	// (magboots.dm) only returns TRUE once the mag-pulse is actually toggled ON. Without
	// this, can_path_through_space() (below) would say "yes, safe to cross space" the
	// moment boots were merely equipped, and the bot would path onto a real space turf
	// and then just drift there uncontrolled - worse than never allowing the crossing at
	// all. Checked against needs_mag_pulse() (above), not just "is it on" - a mismatch in
	// EITHER direction counts as not ready, so a bot that no longer needs it (gravity
	// came back, hazard passed) re-triggers gearing just as readily as one that newly
	// does, and equip_eva_gear's toggle (below) brings it back into sync either way.
	var/boots_type = get_job_boots_type()
	if(boots_type)
		var/obj/item/clothing/shoes/magboots/boots = owner.shoes
		if(!istype(boots, boots_type))
			bot_log_verbose(src, "is_eva_ready: FALSE - shoes is [owner.shoes], need [boots_type]")
			return FALSE
		if(boots.magpulse != needs_mag_pulse())
			bot_log_verbose(src, "is_eva_ready: FALSE - [boots] mag-pulse is [boots.magpulse ? "on" : "off"], needs to be [needs_mag_pulse() ? "on" : "off"]")
			return FALSE
	return TRUE

// Same as is_eva_ready() minus the magboots/mag-pulse check - TRUE once suit+helmet+
// mask+tank are all set, regardless of boots. Used by bot_turf_crossable_without_boots()
// (bot_pathing_permissive.dm) to tell "genuinely can't survive out there at all" (no
// hardsuit/tank - space is lethal, no exception should ever apply) apart from "just
// missing the stability magboots give" (survivable, just not smoothly walkable - a real
// player without magboots can still cross by pushing off nearby dense objects,
// get_spacemove_backup()/mob_movement.dm, same mechanic bot_step_towards() already uses,
// bot_movement.dm). No bot_log_verbose here unlike is_eva_ready() - this gets called
// once per candidate turf during pathfinding, not once per readiness check, so logging
// every call would flood the log for no benefit.
/datum/bot_brain/proc/is_space_protected_without_boots()
	var/obj/item/clothing/suit/space/hardsuit/suit = owner.wear_suit
	if(!istype(suit) || !suit.suittoggled)
		return FALSE
	var/mask_type = get_job_mask_type()
	if(mask_type && !istype(owner.wear_mask, mask_type))
		return FALSE
	if(!eva_tank())
		return FALSE
	// Standing in good air on the last quarter of a tank: nobody sets out across space on that (kept up to date
	// once a second by mind_air_supply(), refill_internals.dm, because this runs once per tile in a route search)
	if(low_air_stay_in)
		return FALSE
	return TRUE

// Every get_path_to() call in this module defaults to simulated_only=TRUE (AStar.dm),
// which excludes actual space turfs from pathing UNCONDITIONALLY - regardless of
// whether the bot is suited and breathing from a tank. That's what stranded a fully
// geared-up engineer bot unable to plan a route to the far corners of a tesla engine
// room that's open to space (this file's header comment already called that room type
// out as the reason EVA gearing exists at all) - the gearing goal ran and succeeded,
// but nothing ever told the pathfinder it could now rely on that. Passed as
// `simulated_only = !can_path_through_space(...)` at every get_path_to() call site in
// bot_movement.dm and goals/acquire_tool.dm.
//
// If mag-pulse specifically is the only thing wrong (boots already worn, just not
// toggled to match needs_mag_pulse() yet), fix it right here instead of just reporting
// not-ready - confirmed in-game: a CE successfully grabbed the singularity generator
// (remove_singularity_generator, setup_tesla_engine.dm), then failed to path it to
// storage because mag-pulse read off at that exact tile, and the whole goal gave up
// with a 1-2 minute cooldown (on_give_up(), failed_engine_parts) - the VERY NEXT tick's
// ordinary eva-gearing check (handle_wander(), bot_brain.dm) turned mag-pulse on anyway,
// one step too late to save the pursuit that had already given up by then. Unlike
// fetching missing gear (a real trip, correctly left to the periodic eva-gearing goal),
// toggling mag-pulse on already-worn boots is free and instant - a real player just
// flips their own boots on, no reason a mid-pursuit repath should ever fail for it.
/datum/bot_brain/proc/can_path_through_space()
	if(!is_eva_ready())
		var/boots_type = get_job_boots_type()
		if(boots_type)
			var/obj/item/clothing/shoes/magboots/boots = owner.shoes
			if(istype(boots, boots_type) && boots.magpulse != needs_mag_pulse())
				telemetry_shortcut("attack_self", boots, null) //telemetry
				boots.attack_self(owner)
	if(!is_eva_ready() || low_air_stay_in)
		return FALSE
	// Suited up is not the same as able to get about out there. Nothing moves in open space without something
	// to push against - gravity, a wall or girder alongside, a lattice within a tile - or a jetpack
	// (Process_Spacemove(), which bot_step_towards() goes through; magboots don't come into it). Bots were told
	// all of space was open to them the moment they were suited, walked out past the last thing they could push
	// off, and hung there until their air ran out - every route home failed at its first step ("still stuck at
	// space"). So this is only true with a jetpack running. Without one a bot keeps to the space tiles it can
	// actually cross: bot_turf_crossable_without_boots() (bot_pathing_permissive.dm), which is what the route
	// planner applies while this is FALSE.
	var/obj/item/tank/jetpack/jetpack = owner.get_jetpack()
	return istype(jetpack) && jetpack.on

/datum/bot_brain/proc/try_eva_gearing_round()
	if(!is_eva_job() || is_eva_ready())
		return FALSE
	return assign_goal(new /datum/bot_goal/gear_up_for_eva())

/datum/bot_brain/proc/continue_eva_round()
	continue_goal_chain(CALLBACK(src, PROC_REF(try_eva_gearing_round)))

/datum/bot_goal/gear_up_for_eva/resolve_target(datum/bot_brain/bot)
	target = bot.owner //no real "target" atom for this goal - just needs to be non-null so assign_goal() doesn't reject it

/datum/bot_goal/gear_up_for_eva/get_strategies(datum/bot_brain/bot)
	return list(new /datum/bot_strategy/gear_up())

/datum/bot_goal/gear_up_for_eva/on_success(datum/bot_brain/bot)
	bot.continue_eva_round()

/datum/bot_strategy/gear_up/New()
	. = ..()
	steps = list(new /datum/bot_step/equip_eva_gear())

/datum/bot_strategy/gear_up/is_feasible(datum/bot_brain/bot)
	return TRUE

// Re-derives what's still missing from scratch on every call rather than tracking its
// own progress - the same idiom ensure_tools/ensure_wrench use, so a resumed goal after
// a suspended fetch (suspend_goal_for(), bot_items.dm) just naturally picks up from
// wherever gearing actually is instead of needing separate state to track it. Each
// missing piece is fetched via the generic acquire_item_type goal (same one used for
// personal objectives and medical supply restocking) if not already carried, then worn
// immediately - equipping doesn't need a move_to of its own, the bot's already standing
// wherever the fetch left it.
/datum/bot_step/equip_eva_gear
	// One-shot per goal attempt, same idea as ensure_wrench's tried_fetch - a suit
	// storage unit either has what's needed or it doesn't, no point re-checking every
	// single re-entry into this step.
	var/tried_ssu = FALSE

/datum/bot_step/equip_eva_gear/execute(datum/bot_brain/bot)
	var/mob/living/carbon/human/H = bot.owner
	var/suit_type = bot.get_job_hardsuit_type()
	var/mask_type = bot.get_job_mask_type()

	// Try the real place this gear actually lives FIRST - a suit storage unit (a
	// locked cabinet, not a loose floor item) - before falling through to
	// acquire_item_type's plain "on a turf somewhere" search below, which can never
	// find anything still sitting inside one (confirmed in-game: EVA gear fetch failed
	// outright every time, because every piece was inside an SSU the whole time).
	if(!tried_ssu)
		var/missing_suit = suit_type && !istype(H.wear_suit, suit_type) && !(locate(suit_type) in H.GetAllContents())
		var/missing_mask = mask_type && !istype(H.wear_mask, mask_type) && !(locate(mask_type) in H.GetAllContents())
		var/missing_tank = !H.internal && !(locate(/obj/item/tank/internals) in H.GetAllContents())
		if(missing_suit || missing_mask || missing_tank)
			tried_ssu = TRUE
			var/obj/machinery/suit_storage_unit/SSU = bot.find_eva_ssu()
			if(SSU)
				var/datum/bot_goal/raid_suit_storage_unit/raid = new()
				raid.ssu = SSU
				if(bot.suspend_goal_for(raid))
					return GOAL_STEP_PENDING

	if(suit_type && !istype(H.wear_suit, suit_type))
		var/obj/item/clothing/suit/space/hardsuit/suit = locate(suit_type) in H.GetAllContents()
		if(!suit)
			var/datum/bot_goal/acquire_item_type/sub = new()
			sub.item_type = suit_type
			if(bot.suspend_goal_for(sub))
				return GOAL_STEP_PENDING
			bot_log(bot, "no hardsuit reachable to gear up with")
			return GOAL_STEP_FAIL
		// wear() (engineer_gear.dm), not a bare equip: out of the bag or box into a hand first, then on,
		// one piece at a time. Telemetry caught a breath mask going from the box in the backpack straight
		// onto the face.
		bot.wear(suit, ITEM_SLOT_OCLOTHING)

	if(mask_type && !istype(H.wear_mask, mask_type))
		var/obj/item/clothing/mask/mask = locate(mask_type) in H.GetAllContents()
		if(!mask)
			var/datum/bot_goal/acquire_item_type/sub = new()
			sub.item_type = mask_type
			if(bot.suspend_goal_for(sub))
				return GOAL_STEP_PENDING
			bot_log(bot, "no [mask_type] reachable to gear up with")
			return GOAL_STEP_FAIL
		bot.wear(mask, ITEM_SLOT_MASK)

	if(!bot.eva_tank())
		// Any /obj/item/tank/internals subtype works - which one's "correct" varies by
		// job (plain oxygen for most, the ERT double-tank for response teams, etc), and
		// whatever's actually in that job's SSU storage slot (raid_ssu below) already
		// carries the right one over regardless of subtype.
		var/obj/item/tank/internals/tank = locate(/obj/item/tank/internals) in H.GetAllContents()
		if(!tank)
			var/datum/bot_goal/acquire_item_type/sub = new()
			sub.item_type = /obj/item/tank/internals/oxygen //sane fallback if nothing better's already been carried in via the SSU raid
			if(bot.suspend_goal_for(sub))
				return GOAL_STEP_PENDING
			bot_log(bot, "no internals tank reachable to gear up with")
			return GOAL_STEP_FAIL
		// Not just isturf(tank.loc) - GetAllContents() above also matches a tank sitting
		// ONE LEVEL NESTED inside a worn backpack/belt, whose .loc is that container, not
		// H directly. get_breath_from_internal() (life.dm) nulls owner.internal on the
		// very next life tick whenever internal.loc != src - it does NOT walk into
		// containers, so a merely-carried (not top-level worn/held) tank looked "set" for
		// one instant and then silently reverted, over and over, every single gear-up
		// re-check (confirmed in-game: "opened the valve..." logged repeatedly, seconds
		// apart, with is_eva_ready() reporting "no internal tank set" every time in
		// between - the goal kept "succeeding" at something that never actually stuck).
		// try_pickup_target() (bot_items.dm)/stow_item() relocate correctly regardless of
		// the tank's current loc (ground OR nested in a container) MOST of the time - but
		// stow_item()'s own fallback chain can itself choose to insert into an already-worn
		// backpack/belt (COMSIG_TRY_STORAGE_INSERT) rather than a hand, which reproduces
		// the exact same "nested, not top-level" problem this whole block exists to avoid.
		// put_in_hands() as a last-resort guarantees src == H directly - verified after the
		// fact rather than trusted, same "don't believe a return value, check the real
		// state" pattern the rest of this file already uses (wear_pda_in_id_slot, etc).
		if(tank.loc != H)
			bot.try_pickup_target(tank)
		if(tank.loc != H)
			H.put_in_hands(tank)
		if(tank.loc != H)
			bot_log(bot, "couldn't get [tank] onto myself directly (still in [tank.loc]) - can't open its valve")
			return GOAL_STEP_FAIL
		// Carried where its valve can be reached, and that's all for now: it gets opened where the air isn't
		// breathable and shut again where it is. Opening it here and leaving it open ran every suited bot's
		// tank dry inside ten minutes, indoors - see manage_internals() (refill_internals.dm).
		bot_log(bot, "got [tank] on me ([round(tank.air_contents.return_pressure())] kPa) - keeping its valve shut while there's air to breathe")
		bot.manage_internals()

	// Not in any engineering SSU's storage slot (suit_storage_unit.dm) - always fetched
	// via acquire_item_type, same as a personal objective would. Worn AND mag-pulse
	// toggled on here (magboots.dm's own toggle() verb is what a real player would use -
	// attack_self() is the same proc it calls into) - a suit/mask/tank without working
	// magboots still leaves the bot unable to move once it actually reaches open space,
	// so this isn't optional for a job that has a boots_type at all.
	var/boots_type = bot.get_job_boots_type()
	if(boots_type)
		var/obj/item/clothing/shoes/magboots/boots = H.shoes
		if(!istype(boots, boots_type))
			boots = locate(boots_type) in H.GetAllContents()
			if(!boots)
				var/datum/bot_goal/acquire_item_type/sub = new()
				sub.item_type = boots_type
				if(bot.suspend_goal_for(sub))
					return GOAL_STEP_PENDING
				bot_log(bot, "no magboots reachable to gear up with")
				return GOAL_STEP_FAIL
			bot.wear(boots, ITEM_SLOT_FEET)
		// Only actually toggled when needs_mag_pulse() (above) says the surroundings
		// call for it - not unconditionally the moment boots are worn. Bidirectional:
		// turns back off again once the hazard's gone, same as it turns on for one.
		var/desired_pulse = bot.needs_mag_pulse()
		if(boots.magpulse != desired_pulse)
			bot.telemetry_shortcut("attack_self", boots, null) //telemetry
			boots.attack_self(H)
			bot_log(bot, "[desired_pulse ? "activated" : "deactivated"] the mag-pulse traction system on [boots]")

	if(istype(H.wear_suit, /obj/item/clothing/suit/space/hardsuit))
		var/obj/item/clothing/suit/space/hardsuit/suit = H.wear_suit
		if(!suit.suittoggled)
			// ToggleHelmet() (suits/toggles.dm) hard-refuses whenever H.head is occupied
			// at all - both CE and Station Engineer spawn wearing a hardhat by default
			// (their job outfits), which was never getting out of the way on its own,
			// so this condition just stayed permanently false and the bot got stuck
			// here forever. The hardhat's own "appropriate" slot IS the head slot it's
			// already in, so stow_item() would just leave it there unchanged - simplest
			// fix is to just take it off outright, it's redundant once the hardsuit
			// helmet (better protection anyway) is on.
			if(H.head)
				H.dropItemToGround(H.head)
			if(!H.head)
				suit.ToggleHelmet()
				bot_log(bot, "engaged the hardsuit helmet")

	return bot.is_eva_ready() ? GOAL_STEP_SUCCESS : GOAL_STEP_FAIL

// ============================================================
// Raiding a suit storage unit - walk to it, open it (bypassing the lock the same way
// every other machine in this system is driven: setting state directly rather than
// going through Topic()/ui_act(), which expect a real client), and pull out everything
// inside: suit, helmet, mask, and whatever's in the auxiliary storage slot - magboots,
// a watertank, a geiger counter, a spare tank, whatever that particular SSU variant
// holds (suit_storage_unit.dm's per-job subtypes each put something different there).
// Carried along regardless of type rather than filtered to just tanks - equip_eva_gear
// above only actively puts ON the suit/mask/internals-tank, but there's no reason to
// leave useful department equipment sitting in the cabinet once it's already open.
// ============================================================

/datum/bot_goal/raid_suit_storage_unit
	var/obj/machinery/suit_storage_unit/ssu

/datum/bot_goal/raid_suit_storage_unit/resolve_target(datum/bot_brain/bot)
	if(!ssu || QDELETED(ssu))
		return
	target = ssu

/datum/bot_goal/raid_suit_storage_unit/get_strategies(datum/bot_brain/bot)
	return list(new /datum/bot_strategy/raid_ssu())

/datum/bot_strategy/raid_ssu/New()
	. = ..()
	steps = list(new /datum/bot_step/move_to(), new /datum/bot_step/raid_ssu())

/datum/bot_strategy/raid_ssu/is_feasible(datum/bot_brain/bot)
	return TRUE

/datum/bot_step/raid_ssu/execute(datum/bot_brain/bot)
	var/obj/machinery/suit_storage_unit/SSU = bot.current_goal?.target
	if(!SSU || QDELETED(SSU))
		return GOAL_STEP_FAIL
	if(!bot.owner.Adjacent(SSU))
		return GOAL_STEP_FAIL
	// Done the way a player does it through the unit's panel: open the door, then press
	// "dispense" for one item at a time (each drops onto the unit's tile) and pick it up, at a
	// human click rhythm. This used to reach inside and pull all four items out in the same
	// instant - telemetry recorded the hardsuit, mask, magboots and tank arriving within 2ms.
	// (ui_act() itself refuses to run without an open tgui window, so each panel action's own
	// effect is performed here, one paced click each.)
	bot.human_pause(SSU)
	bot.owner.face_atom(SSU)
	if(!SSU.state_open)
		bot.telemetry_ui_action(SSU, "door")
		SSU.open_machine(0)
		if(SSU.occupant)
			SSU.dump_contents()
		SSU.update_icon()
	var/took_any = FALSE
	for(var/slot in list("suit", "helmet", "mask", "storage"))
		if(QDELETED(SSU) || !SSU.state_open || !bot.owner.Adjacent(SSU))
			break
		var/obj/item/I = SSU.vars[slot]
		if(!I)
			continue
		bot.human_pause(SSU)
		if(QDELETED(SSU) || !bot.owner.Adjacent(SSU))
			break //the pause sleeps - still at the unit?
		bot.owner.face_atom(SSU) //back to the panel: picking the last piece up and stowing it turned the bot away
		bot.telemetry_ui_action(SSU, "dispense [slot]")
		SSU.vars[slot] = null
		I.forceMove(SSU.loc) //exactly what the panel's "dispense" button does
		SSU.update_icon()
		if(bot.try_pickup_target(I))
			took_any = TRUE
	bot_log(bot, "took the EVA gear out of [SSU]")
	return took_any ? GOAL_STEP_SUCCESS : GOAL_STEP_FAIL
