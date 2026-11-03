// Playing it the way a good player does, modelled on real rounds of one: the player log (player_log.dm) read with
// tools/bot_gym/player_report.py, three rounds as a traitor Chief Engineer. Two of them were over a remote desktop and short of time,
// so this copies what they chose to do, and how fast they did it isn't a target.
//
//  - The uplink comes first and all of it goes on the nanosuit, 25 seconds into the last two rounds. Putting one on empties every slot on
//    to the floor (nanosuit.dm), so the bag, the belt and the ID go back on straight after.
//  - Then there's no more hiding. Whoever could end it goes first: anybody it's been told to kill, the Captain, Security, the other heads.
//    After those come its objectives, and then whoever's closest.
//  - Strength mode to fight, Speed mode to get there, Armor mode when it's going badly. A jump closes the gap, which was the button they
//    pressed most, and bare hands do the rest: 322 of 394 clicks on somebody had nothing in hand, and 91% were on harm intent.
//  - Hurt, it leaves at about half health, heals up and comes back.
//
// The style's rolled like any other too, and a robust bot who isn't a traitor just fights harder and goes to heal in time (bot_fighting.dm).
//
// That player was asked what a traitor should be like once everybody knows, and what's here is their answer. Not all of them go loud:
// some stay undercover with an emag and their objectives, and only turn once they're caught. How far a loud one takes it depends on the
// bot, the hit list or everybody. Once exposed it drops the act (gone_loud()): no more job, no shouting for Security with a Syndicate
// suit on, and it's paranoid, armed, out of the crowds and on the move. Traitors don't trust each other either: usually it's every one
// for itself, some fall into a truce and stay out of each other's way, and now and then the code words really do make a team of two.
//
// What the crew does about all of this is at the end of this file.

// nanosuit.dm's own defines are further down the .dme
#define BOT_SUIT_STRENGTH "strength"
#define BOT_SUIT_SPEED "speed"
#define BOT_SUIT_ARMOR "armor"
#define BOT_SUIT_JUMP_COST 30
/// How long a mode stays on before it's thought about again. They changed mode 21 times in 8 minutes: a person doesn't flick it every second.
#define BOT_SUIT_MODE_GAP (3 SECONDS)
#define BOT_SUIT_JUMP_GAP (2 SECONDS)
/// The furthest a jump is any use from. It goes three tiles.
#define BOT_SUIT_JUMP_RANGE 4
/// How long it keeps after somebody it can't catch.
#define BOT_ROBUST_CHASE (90 SECONDS)
/// Before somebody it gave up on is worth another try.
#define BOT_ROBUST_REST (1 MINUTES)
/// The rank it gives each kind of person, added to how far off they are: lowest goes first.
#define BOT_ROBUST_RANK_MARK -1000
#define BOT_ROBUST_RANK_CAPTAIN -800
#define BOT_ROBUST_RANK_SECURITY -600
#define BOT_ROBUST_RANK_HEAD -400
/// Bodies before the crew stops acting as if it's an ordinary shift.
#define BOT_BODIES_TO_WORRY 3

/// Out of a hundred, the traitors who stay undercover.
#define BOT_UNDERCOVER_SHARE 50
#define BOT_UNDERCOVER_WAIT_MIN (8 MINUTES)
#define BOT_UNDERCOVER_WAIT_MAX (13 MINUTES)
#define BOT_LOUD_WAIT_MIN (30 SECONDS)
#define BOT_LOUD_WAIT_MAX (90 SECONDS)
/// How wild it has to be, out of 1, to go for everybody and not just the hit list. Half of those who go loud, near enough.
#define BOT_RAMPAGE_TEMPER 0.5
/// Out of a hundred, the traitors who'd try the code words at all.
#define BOT_CODEWORD_CHANCE 20
/// Out of a hundred, two exposed traitors who come to an understanding. Usually they don't.
#define BOT_TRUCE_CHANCE 30
#define BOT_PACT_NONE 0
#define BOT_PACT_TRUCE 1
#define BOT_PACT_TEAM 2
#define BOT_THREAT_GAP_MIN (20 SECONDS)
#define BOT_THREAT_GAP_MAX (45 SECONDS)
/// Between one try of the code words and the next.
#define BOT_CODEWORD_GAP (6 MINUTES)
/// A patch gets used out of a fight below this share of its health.
#define BOT_PATCH_AT 0.75

/datum/bot_brain
	/// A traitor, by bot_make_traitors() or a Bot Gym scenario. Who's on the wanted list is asked every tick, so this goes first.
	var/bot_traitor = FALSE
	/// BOT_TRAITOR_*
	var/traitor_plan = BOT_TRAITOR_HIT_LIST
	/// Whether it would ever try the code words.
	var/uses_codewords = FALSE
	var/next_codeword_time = 0
	var/next_threat_time = 0
	/// Threats and taunts made, for the Bot Gym.
	var/threats_made = 0
	var/next_arm_time = 0
	var/next_suit_mode_time = 0
	var/next_suit_jump_time = 0
	/// Jumps made, for the Bot Gym.
	var/suit_jumps = 0
	/// Weakref of somebody it gave up on -> when they're worth another try.
	var/list/robust_rested
	/// Tried a NanoMed and got nothing: not again before this.
	var/next_nanomed_try = 0

/// What it still does once it's gone loud: the Syndicate's business, staying alive, and getting off the station. Most job duties are in the
/// urgent tier as well (a job that's never finished would otherwise starve the rest), so the tier alone doesn't tell them apart.
GLOBAL_LIST_INIT(bot_duties_when_loud, typecacheof(list(/datum/bot_duty/traitor, /datum/bot_duty/nuke_op, /datum/bot_duty/wizard, /datum/bot_duty/evacuate, /datum/bot_duty/shelter_from_storm, /datum/bot_duty/rad_shelter)))

/datum/bot_brain/proc/plays_robust()
	return playstyle == BOT_STYLE_ROBUST

/// A traitor everybody knows about: the Syndicate read its name out for wearing the suit, or Security wants it for something serious. It
/// stops pretending, and that's every duty, every chain of work and every word it says (bot_say()).
/datum/bot_brain/proc/gone_loud()
	if(op_team || bot_wizard) //goals/nuke_ops.dm, goals/wizard.dm: there's no passing for crew in that suit, or those robes
		return TRUE
	if(!bot_traitor)
		return FALSE
	if(nanosuit_on())
		return TRUE
	var/datum/bot_wanted/W = bot_get_wanted_entry(owner)
	return W && W.severity >= BOT_CRIME_MAJOR

/// Whether it goes loud at all, and how far it takes it. Half stay undercover. Of the rest, the short-tempered and the fearless go for everybody.
/datum/bot_brain/proc/pick_traitor_plan()
	uses_codewords = prob(BOT_CODEWORD_CHANCE)
	var/forced = world.params["bot-traitor-plan"] //a Bot Shift that wants a particular kind
	if(forced == BOT_TRAITOR_UNDERCOVER || (!forced && prob(BOT_UNDERCOVER_SHARE)))
		traitor_plan = BOT_TRAITOR_UNDERCOVER
		traitor_business_after = world.time + rand(BOT_UNDERCOVER_WAIT_MIN, BOT_UNDERCOVER_WAIT_MAX)
		if(plays_robust())
			set_playstyle(BOT_STYLE_NORMAL) //it's the style that buys the suit, and one in twelve rolled it at the start of the round
	else
		traitor_plan = forced || ((nerve + temper) / 2 >= BOT_RAMPAGE_TEMPER ? BOT_TRAITOR_RAMPAGE : BOT_TRAITOR_HIT_LIST)
		set_playstyle(BOT_STYLE_ROBUST)
		traitor_business_after = world.time + rand(BOT_LOUD_WAIT_MIN, BOT_LOUD_WAIT_MAX)
	bot_log(src, "traitor plan: [traitor_plan][uses_codewords ? ", code words" : ""]")

/// Caught, or as good as: the job's over, so it stops acting like it's still got one.
/datum/bot_brain/proc/turn_hostile()
	bot_log(src, "the game's up")
	if(traitor_plan == BOT_TRAITOR_UNDERCOVER)
		traitor_plan = BOT_TRAITOR_HIT_LIST
	set_playstyle(BOT_STYLE_ROBUST)
	say_something_hostile()

/// What it says instead of calling for help. Up close to whoever's there, and now and then to the whole station.
/datum/bot_brain/proc/say_something_hostile()
	if(world.time < next_threat_time || QDELETED(owner) || owner.stat != CONSCIOUS)
		return
	next_threat_time = world.time + rand(BOT_THREAT_GAP_MIN, BOT_THREAT_GAP_MAX)
	threats_made++
	bot_say(owner, pick(prob(25) ? GLOB.bot_radio_taunts : GLOB.bot_threat_lines), TRUE)

/// Something it can use in a fight, in its hand. A gun first, whatever it can reach after that. Nobody who's wanted walks about with their hands empty.
/datum/bot_brain/proc/stay_armed()
	if(world.time < next_arm_time || !gone_loud())
		return
	next_arm_time = world.time + 5 SECONDS
	var/obj/item/in_hand = owner.get_active_held_item()
	if(istype(in_hand, /obj/item/gun) || in_hand?.force >= BOT_COMBAT_WEAPON_FORCE)
		return
	var/obj/item/gun/G = find_carried_tool(/obj/item/gun)
	if(G?.can_shoot())
		ready_in_hand(G)
	else
		reach_for_weapon()

/// Strength mode's fists hit harder than anything it's carrying, so a gun in the hand stays for range and a swing goes in empty-handed.
/datum/bot_brain/proc/fights_barehanded()
	var/obj/item/clothing/suit/space/hardsuit/nano/N = nanosuit_on()
	return N && !N.shutdown && N.mode == BOT_SUIT_STRENGTH

/// The nanosuit it's wearing, if it is.
/datum/bot_brain/proc/nanosuit_on()
	var/mob/living/carbon/human/H = owner
	var/obj/item/clothing/suit/space/hardsuit/nano/N = H.wear_suit
	return istype(N) ? N : null

// ---------------------------------------------------------------------------------------------
// The suit
// ---------------------------------------------------------------------------------------------

/// Off the uplink, every telecrystal of it. TRUE if there's a kit to open.
/datum/bot_brain/proc/buy_nanosuit()
	if(nanosuit_on() || find_carried_tool(/obj/item/storage/box/syndie_kit/nanosuit))
		return TRUE
	. = buy_from_uplink(/obj/item/storage/box/syndie_kit/nanosuit)
	bot_log(src, . ? "bought a nanosuit off the uplink" : "couldn't buy a nanosuit")

/// Out of the box and on. Everything it had on lands at its feet, so what's worth having goes back on, one thing at a time, the bag first.
/datum/bot_brain/proc/put_on_nanosuit()
	var/mob/living/carbon/human/H = owner
	if(nanosuit_on())
		return TRUE
	var/obj/item/storage/box/syndie_kit/nanosuit/kit = find_carried_tool(/obj/item/storage/box/syndie_kit/nanosuit)
	var/obj/item/clothing/suit/space/hardsuit/nano/N = locate() in kit
	if(!N)
		return FALSE
	human_pause(kit)
	if(QDELETED(N) || H.incapacitated() || !SEND_SIGNAL(kit, COMSIG_TRY_STORAGE_TAKE, N, H.drop_location()))
		return FALSE
	free_hand_for(null)
	if(!H.put_in_hands(N))
		return FALSE
	var/list/keeping = list(H.back, H.belt, H.wear_id, H.l_store, H.r_store)
	if(H.wear_suit)
		H.dropItemToGround(H.wear_suit)
	human_pause(N)
	being_issued_kit = TRUE //the suit's parts go on by themselves: that's the suit, not the bot
	. = H.equip_to_slot_if_possible(N, ITEM_SLOT_OCLOTHING, FALSE, TRUE, TRUE)
	being_issued_kit = FALSE
	if(!.)
		return FALSE
	bot_log(src, "put the nanosuit on")
	for(var/obj/item/I in keeping)
		if(QDELETED(I) || !isturf(I.loc) || get_dist(H, I) > 1)
			continue
		human_pause(I)
		if(H.incapacitated())
			break
		if(H.put_in_hands(I) && !H.equip_to_appropriate_slot(I))
			stow_or_drop(I)

/// Who it's after right now, in a fight or on its way to one.
/datum/bot_brain/proc/current_foe()
	if(state == BOT_STATE_COMBAT)
		return attacker
	var/datum/bot_goal/traitor_kill/G = current_goal
	return istype(G) ? G.victim() : null

/// Speed to get there, Strength once they're in sight, Armor when it's going badly or there's nothing on.
/datum/bot_brain/proc/mind_nanosuit()
	var/obj/item/clothing/suit/space/hardsuit/nano/N = nanosuit_on()
	if(!N || N.shutdown)
		return
	var/mob/living/foe = current_foe()
	var/wanted = BOT_SUIT_ARMOR
	if(owner.health > owner.maxHealth * 0.5)
		if(foe && get_dist(owner, foe) <= BOT_SIGHT_RANGE)
			wanted = BOT_SUIT_STRENGTH
		else if(N.mode == BOT_SUIT_SPEED ? N.cell.charge > N.cell.maxcharge * 0.3 : ((foe || pursuing_kind) && N.cell.charge > N.cell.maxcharge * 0.7))
			wanted = BOT_SUIT_SPEED //only burns anything on the move, so it stays on until the cell's low, and comes back once it's mostly full
	// Somebody in sight doesn't wait for the gap: at speed it's on them before the next look
	if(N.mode == wanted || (wanted != BOT_SUIT_STRENGTH && world.time < next_suit_mode_time))
		return
	next_suit_mode_time = world.time + BOT_SUIT_MODE_GAP
	N.toggle_mode(wanted)
	telemetry_ui_action(N, "[wanted] mode")

/// In strength mode a jump covers the ground a walk would give them time to use. It goes the way the bot's facing, so somebody has to be
/// more or less in a line with it.
/datum/bot_brain/proc/try_suit_jump(mob/living/target)
	var/obj/item/clothing/suit/space/hardsuit/nano/N = nanosuit_on()
	if(!N || N.shutdown || N.mode != BOT_SUIT_STRENGTH || world.time < next_suit_jump_time || N.cell.charge < BOT_SUIT_JUMP_COST || owner.incapacitated())
		return FALSE
	var/dist = get_dist(owner, target)
	if(dist < 2 || dist > BOT_SUIT_JUMP_RANGE)
		return FALSE
	var/dx = target.x - owner.x
	var/dy = target.y - owner.y
	if(min(abs(dx), abs(dy)) > 1 || !has_clear_shot(target))
		return FALSE
	var/mob/living/carbon/human/H = owner
	var/obj/item/clothing/shoes/combat/coldres/nanojump/boots = H.shoes
	if(!istype(boots))
		return FALSE
	next_suit_jump_time = world.time + BOT_SUIT_JUMP_GAP
	owner.setDir(abs(dx) >= abs(dy) ? (dx > 0 ? EAST : WEST) : (dy > 0 ? NORTH : SOUTH))
	telemetry_ui_action(boots, "strength jump")
	boots.ui_action_click(owner, null)
	suit_jumps++
	bot_log(src, "jumping at [target] (dist [dist])")
	return TRUE

// ---------------------------------------------------------------------------------------------
// Going loud
// ---------------------------------------------------------------------------------------------

/// Who's next: lowest rank first, with how far off they are breaking ties. With `important_only` nobody who's just in the way.
/datum/bot_brain/proc/next_victim(datum/antagonist/traitor/T, important_only = FALSE)
	var/list/marks = list()
	for(var/datum/objective/O as anything in T?.objectives)
		if((istype(O, /datum/objective/assassinate) || istype(O, /datum/objective/maroon)) && !objective_finished(O))
			marks |= O.target?.current
	var/list/options = list() //mob -> rank
	for(var/mob/living/carbon/human/H in GLOB.carbon_list)
		if(H == owner || !H.mind?.assigned_role || H.stat == DEAD || H.z != owner.z || !isturf(H.loc))
			continue
		if(gym_run && get_area(H) != get_area(owner))
			continue //somebody else's arena
		if(LAZYACCESS(robust_rested, WEAKREF(H)) > world.time)
			continue
		if(pact_with(H) != BOT_PACT_NONE || on_my_side(H))
			continue
		var/job = H.mind.assigned_role
		var/rank = get_dist(owner, H)
		if(H in marks)
			rank += BOT_ROBUST_RANK_MARK
		else if(job == "Captain")
			rank += BOT_ROBUST_RANK_CAPTAIN
		else if(job in GLOB.security_positions)
			rank += BOT_ROBUST_RANK_SECURITY
		else if(job in GLOB.command_positions)
			rank += BOT_ROBUST_RANK_HEAD
		else if(important_only)
			continue
		options[H] = rank
	var/tries = 0
	while(length(options) && tries++ < 4)
		var/mob/living/carbon/human/best
		for(var/mob/living/carbon/human/H as anything in options)
			if(!best || options[H] < options[best])
				best = H
		options -= best
		if(can_walk_lawfully_to(best))
			return best
	return null

/// The next thing to do as a robust traitor: heal if it needs it, then the people who matter, then its objectives, then anybody.
/datum/bot_brain/proc/robust_business()
	var/datum/antagonist/traitor/T = owner.mind?.has_antag_datum(/datum/antagonist/traitor) || null
	if(!T || owner.incapacitated())
		return FALSE
	if(owner.health <= owner.maxHealth * health_to_run_at() && patch_up())
		return TRUE
	if(owner.health <= owner.maxHealth * BOT_PATCH_AT && pick_treatment_item(owner, TRUE) && try_self_heal_round())
		return TRUE
	var/mob/living/foe = foe_of_my_partner()
	if(foe && assign_goal(new /datum/bot_goal/traitor_kill/robust(null, foe)))
		return TRUE
	var/mob/living/carbon/human/V = next_victim(T, TRUE)
	if(V && assign_goal(new /datum/bot_goal/traitor_kill/robust(null, V)))
		return TRUE
	for(var/datum/objective/O as anything in T.objectives)
		if(LAZYACCESS(objectives_parked, O) > world.time || objective_finished(O))
			continue
		var/datum/bot_goal/goal = goal_for_objective(O)
		if(goal && assign_goal(goal))
			return TRUE
	if(traitor_plan == BOT_TRAITOR_RAMPAGE)
		V = next_victim(T)
		if(V && assign_goal(new /datum/bot_goal/traitor_kill/robust(null, V)))
			return TRUE
	return assign_goal(new /datum/bot_goal/lay_low())

/// Keeps to the maintenance tunnels, a stop at a time, until there's something worth coming out for. It doesn't stand about, and it doesn't
/// stand about where people are.
/datum/bot_brain/proc/quiet_spot()
	var/list/found = list()
	for(var/obj/machinery/door/airlock/A as anything in bot_instances_of(/obj/machinery/door/airlock))
		if(QDELETED(A) || A.z != owner.z || A.welded || A.locked)
			continue
		var/dist = get_dist(owner, A)
		if(dist < BOT_SIGHT_RANGE || dist > BOT_SIGHT_RANGE * 8)
			continue
		for(var/d in GLOB.cardinals)
			var/turf/T = get_step(A, d)
			if(isopenturf(T) && istype(T.loc, /area/maintenance) && !is_blocked_turf(T, TRUE))
				found += T
	var/tries = 0
	while(length(found) && tries++ < 4)
		var/turf/T = pick_n_take(found)
		if(can_walk_lawfully_to(T))
			return T
	return null

/datum/bot_goal/lay_low
	doing = "keeping out of sight"

/datum/bot_goal/lay_low/resolve_target(datum/bot_brain/bot)
	target = bot.quiet_spot()

/datum/bot_goal/lay_low/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/lay_low/S = new
	S.steps = list(new /datum/bot_step/move_to(), new /datum/bot_step/paced/keep_watch())
	return list(S)

/datum/bot_goal/lay_low/on_success(datum/bot_brain/bot)
	bot.continue_goal_chain(CALLBACK(bot, TYPE_PROC_REF(/datum/bot_brain, keep_going)), TRUE)

/datum/bot_strategy/lay_low/is_feasible(datum/bot_brain/bot)
	return TRUE

/// A few seconds, and it's off again.
/datum/bot_step/paced/keep_watch
	var/waited = FALSE

/datum/bot_step/paced/keep_watch/start(datum/bot_brain/bot)
	waited = FALSE
	return TRUE

/datum/bot_step/paced/keep_watch/do_click(datum/bot_brain/bot)
	if(waited)
		return FALSE
	waited = TRUE
	wait_for = rand(4 SECONDS, 10 SECONDS)
	return TRUE

/// A bandage won't go on through the suit and the sleepers are never free when it counts, so patches, out of the nearest NanoMed. That's how
/// the player did it: three brute patches, stuck on where they stood, and back to it. Three of every four trips to a sleeper came to nothing.
/datum/bot_brain/proc/patch_up()
	if(pick_treatment_item(owner, TRUE))
		return try_self_heal_round()
	if(world.time >= next_nanomed_try && assign_goal(new /datum/bot_goal/patch_up()))
		return TRUE
	return try_seek_medbay_healing()

/datum/bot_brain/proc/find_nanomed()
	var/obj/machinery/vending/best
	var/best_dist
	for(var/path in list(/obj/machinery/vending/wallmed, /obj/machinery/vending/medical))
		for(var/obj/machinery/vending/V as anything in bot_instances_of(path))
			if(QDELETED(V) || V.z != owner.z || (V.stat & (BROKEN|NOPOWER)) || V.panel_open || !length(vendor_stock(V, list(/obj/item/reagent_containers/pill/patch/styptic))))
				continue
			if(gym_run && get_area(V) != get_area(owner))
				continue
			var/dist = get_dist(owner, V)
			if((!best || dist < best_dist) && can_walk_lawfully_to(V))
				best = V
				best_dist = dist
	return best

/datum/bot_goal/patch_up
	doing = "getting patched up"

/datum/bot_goal/patch_up/resolve_target(datum/bot_brain/bot)
	target = bot.find_nanomed()

/datum/bot_goal/patch_up/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/patch_up/S = new
	S.steps = list(new /datum/bot_step/move_to(), new /datum/bot_step/vend_patches())
	return list(S)

/datum/bot_goal/patch_up/on_success(datum/bot_brain/bot)
	bot.continue_goal_chain(CALLBACK(bot, TYPE_PROC_REF(/datum/bot_brain, keep_going)), TRUE)

/datum/bot_goal/patch_up/on_give_up(datum/bot_brain/bot)
	bot.next_nanomed_try = world.time + BOT_ROBUST_REST

/datum/bot_strategy/patch_up/is_feasible(datum/bot_brain/bot)
	return bot.current_goal?.target && !QDELETED(bot.current_goal.target)

/datum/bot_step/vend_patches/execute(datum/bot_brain/bot)
	var/obj/machinery/vending/V = bot.current_goal?.target
	if(!istype(V) || !bot.owner.Adjacent(V))
		return GOAL_STEP_FAIL
	var/got = 0
	for(var/i in 1 to 3)
		var/obj/item/patch = bot.vend_from(V, /obj/item/reagent_containers/pill/patch/styptic)
		if(!patch || !bot.try_pickup_target(patch))
			break
		bot.put_away(patch, allow_equip = FALSE)
		got++
	bot_log(bot, "got [got] patches out of [V]")
	return got ? GOAL_STEP_SUCCESS : GOAL_STEP_FAIL

/// One kill after another, with no stroll in between.
/datum/bot_brain/proc/keep_going()
	if(!QDELETED(owner) && owner.stat == CONSCIOUS)
		robust_business()

/datum/bot_goal/traitor_kill/robust
	doing = "going after somebody"
	var/datum/weakref/mark_ref

/datum/bot_goal/traitor_kill/robust/New(datum/objective/O, mob/living/carbon/human/H)
	. = ..(O)
	mark_ref = WEAKREF(H)

/datum/bot_goal/traitor_kill/robust/victim()
	return mark_ref?.resolve()

/datum/bot_goal/traitor_kill/robust/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/traitor_kill/S = new
	S.steps = list(new /datum/bot_step/paced/close_in(), new /datum/bot_step/paced/strike/robust(), new /datum/bot_step/loot_card())
	return list(S)

/datum/bot_goal/traitor_kill/robust/on_give_up(datum/bot_brain/bot)
	if(mark_ref)
		LAZYSET(bot.robust_rested, mark_ref, world.time + BOT_ROBUST_REST)
	bot.continue_goal_chain(CALLBACK(bot, TYPE_PROC_REF(/datum/bot_brain, keep_going)), TRUE)

/datum/bot_goal/traitor_kill/robust/on_success(datum/bot_brain/bot)
	bot.continue_goal_chain(CALLBACK(bot, TYPE_PROC_REF(/datum/bot_brain, keep_going)), TRUE)

/// Straight to them, with no waiting for the room to clear.
/datum/bot_step/paced/close_in
	var/give_up_at = 0
	var/got_there = FALSE

/datum/bot_step/paced/close_in/start(datum/bot_brain/bot)
	give_up_at = world.time + BOT_ROBUST_CHASE
	got_there = FALSE
	return TRUE

/datum/bot_step/paced/close_in/do_click(datum/bot_brain/bot)
	var/datum/bot_goal/traitor_kill/G = bot.current_goal
	var/mob/living/V = G?.victim()
	var/turf/there = get_turf(V)
	if(!there || V.stat == DEAD || there.z != bot.owner.z || !isturf(V.loc) || world.time > give_up_at)
		return FALSE
	if(bot.owner.Adjacent(V))
		got_there = TRUE
		return FALSE
	bot.mind_nanosuit()
	if(bot.try_suit_jump(V) || bot.try_attack_from_range(V))
		wait_for = CLICK_CD_RANGE
		return TRUE
	if(bot.pursuing_kind != "follow")
		if(!bot.can_walk_lawfully_to(V))
			return FALSE
		bot.pursue(V, "follow", force = TRUE)
	wait_for = get_dist(bot.owner, V) <= BOT_SIGHT_RANGE * 2 ? 2 : 10 //a look every couple of tiles, once it's close enough for a jump to matter
	return TRUE

/datum/bot_step/paced/close_in/finish(datum/bot_brain/bot)
	bot.stop_pursuit()
	return got_there ? GOAL_STEP_SUCCESS : GOAL_STEP_FAIL

/// Until they're dead, unless it's the one going down first.
/datum/bot_step/paced/strike/robust

/datum/bot_step/paced/strike/robust/do_click(datum/bot_brain/bot)
	var/datum/bot_goal/traitor_kill/G = bot.current_goal
	var/mob/living/V = G?.victim()
	if(QDELETED(V) || V.stat == DEAD || !isturf(V.loc))
		return FALSE
	if(bot.owner.health <= bot.owner.maxHealth * bot.health_to_run_at() && V.stat == CONSCIOUS)
		return FALSE //off to heal: bot.keep_going() sees to it
	if(!bot.owner.Adjacent(V))
		if(get_dist(bot.owner, V) > BOT_SIGHT_RANGE)
			return FALSE //got away
		if(bot.try_suit_jump(V) || bot.try_attack_from_range(V))
			wait_for = CLICK_CD_RANGE
			return TRUE
		bot.combat_chase(V)
		wait_for = 5
		return TRUE
	bot.stop_pursuit()
	bot.fight_in_reach(V) //bot_fighting.dm
	bot.try_combat_sidestep(V)
	wait_for = CLICK_CD_MELEE
	return TRUE

/// Strips a body for what opens more doors than its own card does. A cargo technician who kills an officer in the Brig has no other way
/// back out of it, and the player this comes from went through the pockets of everybody who mattered.
/datum/bot_step/loot_card/execute(datum/bot_brain/bot)
	var/datum/bot_goal/traitor_kill/G = bot.current_goal
	var/mob/living/carbon/human/V = G?.victim()
	if(!istype(V) || !bot.owner.Adjacent(V))
		return GOAL_STEP_SUCCESS
	if(!V.wear_id)
		bot.take_gun_off(V)
		return GOAL_STEP_SUCCESS
	var/obj/item/card/id/theirs = V.wear_id.GetID()
	var/obj/item/card/id/mine = bot.route_card()
	if(theirs && (!mine || length(theirs.access) > length(mine.access)))
		bot.take_card_off(V, V.wear_id)
	bot.take_gun_off(V)
	return GOAL_STEP_SUCCESS

/// A gun, if it's got none of its own. The player left with an energy gun, a stun gun and a Captain's laser, all of them off bodies or the floor.
/datum/bot_brain/proc/take_gun_off(mob/living/carbon/human/V)
	if(find_carried_tool(/obj/item/gun) || owner.incapacitated() || !owner.Adjacent(V))
		return
	var/obj/item/gun/G = locate() in get_turf(V)
	if(G)
		try_pickup_target(G)
		return
	for(var/obj/item/gun/held in V.held_items)
		G = held
		free_hand_for(null)
		owner.stripPanelUnequip(G, V, list("hand", V.get_held_index_of_item(G)))
		return
	for(var/slot in list(ITEM_SLOT_BELT, ITEM_SLOT_SUITSTORE))
		G = V.get_item_by_slot(slot)
		if(istype(G))
			free_hand_for(null)
			owner.stripPanelUnequip(G, V, slot)
			return

/// Off a body or the floor and on to itself, its own card going in the bag. TRUE if it's got it, even if it could only hold it: a card in
/// the hand opens the same doors, and works the same consoles.
/datum/bot_brain/proc/take_card_off(atom/A, obj/item/I)
	var/mob/living/carbon/human/H = owner
	var/mob/living/carbon/human/body = A
	human_pause(A)
	if(QDELETED(I) || !H.Adjacent(A) || H.incapacitated())
		return FALSE
	H.face_atom(A)
	free_hand_for(null)
	telemetry_clicked(A)
	if(istype(body))
		H.stripPanelUnequip(I, body, ITEM_SLOT_ID)
	else
		H.put_in_hands(I)
	if(!(I in H.held_items))
		bot_log(src, "couldn't get [I] off [A]: it's at [I.loc]")
		return FALSE
	bot_log(src, "took [I] off [A == I ? "the floor" : A]")
	var/obj/item/mine = H.wear_id
	if(mine && H.temporarilyRemoveItemFromInventory(mine))
		if(!H.put_in_hands(mine))
			mine.forceMove(H.drop_location())
		stow_or_drop(mine)
	if(!H.wear_id && H.temporarilyRemoveItemFromInventory(I) && !H.equip_to_slot_if_possible(I, ITEM_SLOT_ID, FALSE, TRUE, TRUE))
		H.put_in_hands(I)
	return TRUE

// ---------------------------------------------------------------------------------------------
// Nobody trusts anybody
// ---------------------------------------------------------------------------------------------

GLOBAL_LIST_INIT(bot_threat_lines, list("Stay back!", "That's far enough.", "Keep walking.", "You want some too?", "Come on then.", "Try me.", "Who's next?", "Walk away while you can.", "Get out of my way.", "I see you."))
GLOBAL_LIST_INIT(bot_radio_taunts, list(";Still looking for me?", ";You'll have to do better than that.", ";Anybody else want to try?", ";Wrong place again, Security.", ";Better get to the shuttle while you can.", ";Run.", ";Tell Central Command I said hello.", ";Who's next?"))
GLOBAL_LIST_INIT(bot_team_words, list("team", "truce", "ally", "allies", "work together", "friend", "syndie", "syndicate", "comrade"))
/// "pair of them" -> BOT_PACT_*, settled the first time one of the two has to decide.
GLOBAL_LIST_EMPTY(bot_traitor_pacts)

/// The round's code words in lower case, the way heard speech is compared. Asked for by heard_codeword(), which only runs once they're picked.
/proc/bot_lowered(list/words)
	. = list()
	for(var/word in words)
		. += lowertext(word)

/proc/bot_pact_key(mob/A, mob/B)
	var/a = REF(A)
	var/b = REF(B)
	return sorttext(a, b) > 0 ? "[a]|[b]" : "[b]|[a]"

/// What this traitor is to somebody it knows is one too, which is only anybody in the suit: their name got read out. A bot has no other way
/// of telling, short of the code words. Usually that's nothing at all, and it's every traitor for itself.
/datum/bot_brain/proc/pact_with(mob/living/carbon/human/H)
	if(!bot_traitor || !istype(H))
		return BOT_PACT_NONE
	var/key = bot_pact_key(owner, H)
	var/pact = GLOB.bot_traitor_pacts[key]
	if(!isnull(pact))
		return pact
	if(!istype(H.wear_suit, /obj/item/clothing/suit/space/hardsuit/nano))
		return BOT_PACT_NONE
	pact = prob(BOT_TRUCE_CHANCE) ? BOT_PACT_TRUCE : BOT_PACT_NONE
	GLOB.bot_traitor_pacts[key] = pact
	if(pact)
		bot_log(src, "a truce with [H]: I stay out of their way, they stay out of mine")
	return pact

/// A truce doesn't outlive the first blow.
/datum/bot_brain/proc/break_pact_with(mob/living/carbon/human/H)
	if(bot_traitor && istype(H) && GLOB.bot_traitor_pacts[bot_pact_key(owner, H)])
		bot_log(src, "[H] broke the truce")
		GLOB.bot_traitor_pacts[bot_pact_key(owner, H)] = BOT_PACT_NONE

/// Whoever its partner's fighting, if it's got one and they're close enough to matter.
/datum/bot_brain/proc/foe_of_my_partner()
	for(var/datum/bot_brain/B as anything in GLOB.bot_brains)
		if(B == src || !B.bot_traitor || B.state != BOT_STATE_COMBAT || QDELETED(B.attacker) || !ishuman(B.attacker))
			continue
		if(GLOB.bot_traitor_pacts[bot_pact_key(owner, B.owner)] == BOT_PACT_TEAM && B.owner.z == owner.z && get_dist(owner, B.owner) <= BOT_SIGHT_RANGE * 3 && B.attacker != owner)
			return B.attacker
	return null

/// Somebody asking to team up, to a traitor everybody's after. It answers, which is more than it used to.
/datum/bot_brain/proc/heard_team_offer(mob/living/carbon/human/talker, lower_msg, radio_freq)
	if(radio_freq || !istype(talker) || get_dist(owner, talker) > BOT_SIGHT_RANGE || !bot_text_has_any(lower_msg, GLOB.bot_team_words))
		return FALSE
	next_threat_time = world.time + BOT_THREAT_GAP_MIN
	switch(pact_with(talker))
		if(BOT_PACT_TEAM)
			bot_say(owner, pick("Stick close.", "Watch my back and I'll watch yours."), TRUE)
		if(BOT_PACT_TRUCE)
			bot_say(owner, pick("Stay out of my way and I'll stay out of yours.", "You didn't see me."), TRUE)
		else
			bot_say(owner, pick("Not a chance.", "Nice try.", "Get lost.", "I don't know you."), TRUE)
	return TRUE

/// The game's own code words. The odd traitor listens out for them and tries them now and then, and when both halves get said by two people
/// that really is a team. A player who knows the words gets the same answer as a bot would.
/datum/bot_brain/proc/heard_codeword(mob/living/talker, lower_msg)
	if(!bot_traitor || !uses_codewords || !ishuman(talker) || talker == owner || !GLOB.syndicate_code_phrase)
		return FALSE
	// The words are jobs and everyday things, so the crew say them all the time. In the first round of this a traitor teamed up with
	// somebody who'd only mentioned one, and was attacked by them. Saying them by accident isn't knowing them.
	if(!(talker.mind?.has_antag_datum(/datum/antagonist/traitor) || null))
		return FALSE
	if(bot_text_has_any(lower_msg, bot_lowered(GLOB.syndicate_code_response)))
		make_team_with(talker)
		return TRUE
	if(!bot_text_has_any(lower_msg, bot_lowered(GLOB.syndicate_code_phrase)))
		return FALSE
	make_team_with(talker)
	bot_say(owner, codeword_line(GLOB.syndicate_code_response), TRUE)
	return TRUE

/datum/bot_brain/proc/make_team_with(mob/living/carbon/human/H)
	if(GLOB.bot_traitor_pacts[bot_pact_key(owner, H)] != BOT_PACT_TEAM)
		GLOB.bot_traitor_pacts[bot_pact_key(owner, H)] = BOT_PACT_TEAM
		bot_log(src, "[H] knows the words: we're on the same side")

/// A word on the radio, for anybody who knows what it means.
/datum/bot_brain/proc/try_codewords()
	if(!uses_codewords || world.time < next_codeword_time || !GLOB.syndicate_code_phrase)
		return
	next_codeword_time = world.time + BOT_CODEWORD_GAP
	bot_say(owner, codeword_line(GLOB.syndicate_code_phrase), TRUE)

/// Slipped into something a person might say on the radio. "Ninjas." by itself gives the game away.
/datum/bot_brain/proc/codeword_line(list/words)
	var/word = lowertext(pick(words))
	return pick(";Anybody seen [word] around?", ";Has anyone heard about [word]?", ";I could really go for [word] right now.", ";Somebody was asking me about [word].", ";Can't stop thinking about [word] today.")

// ---------------------------------------------------------------------------------------------
// What the crew does about it
// ---------------------------------------------------------------------------------------------

GLOBAL_VAR_INIT(bot_dead_crew, 0)
GLOBAL_VAR_INIT(bot_dead_crew_counted_at, -100)

/// How many of the crew are lying dead. Counted now and then: it's asked every time somebody opens their mouth.
/proc/bot_dead_crew_count()
	if(world.time >= GLOB.bot_dead_crew_counted_at)
		GLOB.bot_dead_crew_counted_at = world.time + 10 SECONDS
		GLOB.bot_dead_crew = 0
		for(var/mob/living/carbon/human/H in GLOB.carbon_list)
			if(H.stat == DEAD && H.mind?.assigned_role)
				GLOB.bot_dead_crew++
	return GLOB.bot_dead_crew

/// Whether it's the sort of shift where people stop talking about the weather. A bot said "quiet shift so far" with 17 dead.
/proc/bot_shift_gone_bad()
	return bot_dead_crew_count() >= BOT_BODIES_TO_WORRY

/// It's just been read out to the whole station who put one on. Anybody who heard that knows, so the name goes on the record and Security
/// has somewhere to start. In the round this came from nobody took any notice.
/proc/bot_nanosuit_announced(mob/living/carbon/human/H)
	var/datum/bot_brain/heard
	for(var/datum/bot_brain/B as anything in GLOB.bot_brains)
		if(B.owner == H || QDELETED(B.owner) || B.owner.stat != CONSCIOUS)
			continue
		heard = B
		if(B.is_security_job())
			break
	if(!heard)
		return
	heard.file_crime(H, "Possession of Dangerous Equipment", "The Syndicate announced it to the whole station: [H.real_name], in a nanosuit.", BOT_CRIME_MAJOR)
	bot_dispatch_security(get_turf(H), H.real_name) //goals/security_tactics.dm
	bot_say(heard.owner, pick(";[H.real_name] has a nanosuit on, you all heard that. Watch yourselves.", ";Did everybody hear that? [H.real_name], [get_area_name(H, TRUE)]. Security, get on it.", ";That's [H.real_name] in a Syndicate suit. They're armed and dangerous."))

/// Whether a bot who isn't a hunter by nature goes after a name on the radio: it's seen enough, it's got the nerve, and it's that kind of shift.
/datum/bot_brain/proc/fights_back_now()
	if(owner.mind?.has_antag_datum(/datum/antagonist/traitor) || null)
		return FALSE //two traitors in suits, both on the wanted list, and each hunted the other down in the first round this was tried
	return playstyle == BOT_STYLE_HUNTER || plays_robust() || (hardened && nerve >= 0.4 && bot_shift_gone_bad())

GLOBAL_LIST_INIT(bot_confession_words, list(
	"i'm traitor", "im traitor", "i am traitor", "i'm a traitor", "im a traitor", "i am a traitor", "i'm the traitor", "im the traitor", "i am the traitor",
	"i'm antag", "im antag", "i'm the antag", "im the antag", "i'm syndicate", "im syndicate", "i am syndicate", "i'm with the syndicate",
	"i killed cap", "i killed the cap", "i murdered cap", "i murdered the cap",
))

/// Somebody saying what they are, out loud. A person would take that seriously, and shout about it.
/datum/bot_brain/proc/heard_confession(mob/living/carbon/human/talker, lower_msg, radio_freq)
	if(!istype(talker) || (!radio_freq && get_dist(owner, talker) > BOT_SIGHT_RANGE))
		return FALSE
	if(!bot_text_has_any(replacetext(lower_msg, "&#39;", "'"), GLOB.bot_confession_words))
		return FALSE
	var/datum/bot_wanted/W = bot_get_wanted_entry(talker)
	if(W && W.severity >= BOT_CRIME_MAJOR)
		W.last_seen = get_turf(talker)
		W.last_seen_at = world.time
		return FALSE
	file_crime(talker, "Subversion of the Chain of Command", "Said so out loud.", BOT_CRIME_MAJOR)
	bot_log(src, "[talker] just owned up to it")
	bot_say(owner, pick(";Security! [talker.name] just said they're with the Syndicate, [get_area_name(talker, TRUE)]!", "You what?! Security!", ";[talker.name]'s bragging about it, [get_area_name(talker, TRUE)]. Somebody get down here!"))
	return TRUE

// With every head of staff dead nobody could call the shuttle, and a round with no shuttle never ends: 25 died in 29 minutes and it went
// uncalled. The console only takes an ID with head access, so somebody takes one off a body, or from where it was dropped, the same as a
// player would, and if nobody can find one Central Command notices in the end (shuttle_console_down()).

/// Whether a head of staff is still on their feet.
/datum/bot_brain/proc/head_still_standing()
	for(var/mob/living/carbon/human/H in GLOB.carbon_list)
		if(gym_run && get_area(H) != get_area(owner))
			continue
		if(H.stat != DEAD && (H.mind?.assigned_role in GLOB.command_positions))
			return TRUE
	return FALSE

/// The ID in this, if it's one that works the console.
/proc/bot_head_card_in(obj/item/I)
	var/obj/item/card/id/C = I?.GetID()
	return C && (ACCESS_HEADS in C.GetAccess()) ? C : null

/// The nearest head's ID it could get to: on a body, or on the floor. What's on the floor is the PDA or the card, whichever was thrown.
/datum/bot_brain/proc/find_head_card()
	var/atom/best
	var/best_dist
	for(var/mob/living/carbon/human/H in GLOB.carbon_list)
		if(H.stat != DEAD || H.z != owner.z || !isturf(H.loc) || !bot_head_card_in(H.wear_id))
			continue
		if(gym_run && get_area(H) != get_area(owner))
			continue
		var/dist = get_dist(owner, H)
		if((!best || dist < best_dist) && can_walk_lawfully_to(H))
			best = H
			best_dist = dist
	for(var/path in list(/obj/item/card/id, /obj/item/pda))
		for(var/obj/item/I as anything in bot_instances_of(path))
			if(QDELETED(I) || !isturf(I.loc) || I.z != owner.z || !bot_head_card_in(I))
				continue
			if(gym_run && get_area(I) != get_area(owner))
				continue
			var/dist = get_dist(owner, I)
			if((!best || dist < best_dist) && can_walk_lawfully_to(I))
				best = I
				best_dist = dist
	return best

/datum/bot_duty/stand_in_for_command
	name = "getting the shuttle called"
	tier = BOT_DUTY_URGENT
	priority = 50
	interval_min = 300
	interval_max = 900

/datum/bot_duty/stand_in_for_command/applies_to(datum/bot_brain/bot)
	return !(bot.work_role() in GLOB.command_positions)

/datum/bot_duty/stand_in_for_command/try_start(datum/bot_brain/bot)
	if(world.time < bot.shuttle_call_blocked_until || bot.up_to_no_good() || (bot.owner.mind?.has_antag_datum(/datum/antagonist/traitor) || null))
		return FALSE
	var/reason = bot.reason_to_call_shuttle()
	if(!reason || bot.head_still_standing())
		return FALSE
	if(bot_head_card_in(bot.owner.wear_id) || bot_head_card_in(bot.owner.get_active_held_item()) || bot_head_card_in(bot.owner.get_inactive_held_item()))
		return bot.call_shuttle_for(reason)
	var/atom/card = bot.find_head_card()
	if(!card)
		bot.shuttle_console_down(reason, ";There's nobody left in command and no ID to be had. Central Command, we need that shuttle.")
		return FALSE
	var/datum/bot_goal/borrow_head_card/G = new
	G.where = WEAKREF(card)
	G.reason = reason
	return bot.assign_goal(G)

/datum/bot_brain/proc/call_shuttle_for(reason)
	var/datum/bot_goal/call_shuttle/G = new
	G.reason = reason
	return find_comms_console() && assign_goal(G)

/// Goes and gets it, and wears it: every door between here and the console is about to care.
/datum/bot_goal/borrow_head_card
	lawful = TRUE
	exclusive = TRUE
	doing = "seeing about the shuttle"
	var/datum/weakref/where
	var/reason

/datum/bot_goal/borrow_head_card/resolve_target(datum/bot_brain/bot)
	target = where?.resolve()

/datum/bot_goal/borrow_head_card/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/borrow_head_card/S = new
	S.steps = list(new /datum/bot_step/move_to(), new /datum/bot_step/borrow_head_card())
	return list(S)

/datum/bot_goal/borrow_head_card/on_give_up(datum/bot_brain/bot)
	bot.shuttle_call_blocked_until = world.time + 1 MINUTES

/datum/bot_goal/borrow_head_card/on_success(datum/bot_brain/bot)
	bot_say(bot.owner, pick(";Command's gone. I've got an ID, I'm calling the shuttle.", ";Nobody left in charge, so I'm calling it. Get to Departures."))
	bot.continue_goal_chain(CALLBACK(bot, TYPE_PROC_REF(/datum/bot_brain, call_shuttle_for), reason))

/datum/bot_strategy/borrow_head_card/is_feasible(datum/bot_brain/bot)
	return bot.current_goal?.target && !QDELETED(bot.current_goal.target)

/datum/bot_step/borrow_head_card/execute(datum/bot_brain/bot)
	var/atom/A = bot.current_goal?.target
	var/mob/living/carbon/human/H = bot.owner
	if(QDELETED(A) || !H.Adjacent(A))
		return GOAL_STEP_FAIL
	var/mob/living/carbon/human/body = A
	var/obj/item/I = istype(body) ? body.wear_id : A
	if(!bot_head_card_in(I) || !bot.take_card_off(A, I))
		return GOAL_STEP_FAIL
	return GOAL_STEP_SUCCESS

#undef BOT_UNDERCOVER_SHARE
#undef BOT_UNDERCOVER_WAIT_MIN
#undef BOT_UNDERCOVER_WAIT_MAX
#undef BOT_LOUD_WAIT_MIN
#undef BOT_LOUD_WAIT_MAX
#undef BOT_RAMPAGE_TEMPER
#undef BOT_CODEWORD_CHANCE
#undef BOT_TRUCE_CHANCE
#undef BOT_PACT_NONE
#undef BOT_PACT_TRUCE
#undef BOT_PACT_TEAM
#undef BOT_THREAT_GAP_MIN
#undef BOT_THREAT_GAP_MAX
#undef BOT_CODEWORD_GAP
#undef BOT_PATCH_AT
#undef BOT_SUIT_STRENGTH
#undef BOT_SUIT_SPEED
#undef BOT_SUIT_ARMOR
#undef BOT_SUIT_JUMP_COST
#undef BOT_SUIT_MODE_GAP
#undef BOT_SUIT_JUMP_GAP
#undef BOT_SUIT_JUMP_RANGE
#undef BOT_ROBUST_CHASE
#undef BOT_ROBUST_REST
#undef BOT_ROBUST_RANK_MARK
#undef BOT_ROBUST_RANK_CAPTAIN
#undef BOT_ROBUST_RANK_SECURITY
#undef BOT_ROBUST_RANK_HEAD
#undef BOT_BODIES_TO_WORRY
