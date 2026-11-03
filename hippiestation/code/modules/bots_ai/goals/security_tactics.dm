// Security against somebody it can't just walk up to and cuff. Officers used to do exactly that, one at a time: in the rounds with suited
// traitors they were the first to die, usually inside twelve minutes, each of them having walked into arm's reach alone with a baton.
//
// None of what beats a nanosuit needs anything new, it only needs doing the way a good team does it:
//  - Nobody goes in alone. The first officer to see them calls it in and everybody free comes (bot_dispatch_security()).
//  - It's done from range. A wearer shrugs off the first few taser hits, but seven to ten stam-crit even a suit, and that's only quick with
//    two or three shooting at once. So officers stop short, keep shooting, and step back from anybody who closes in. Cuffs go on once
//    they're down, by the arrest procedure as usual.
//  - Hurt, an officer falls back and patches up instead of dying where it stands.
//  - An EMP drops the suit for 30 seconds, so the Warden or the Head of Security fetches the armory's ion rifle, or failing that a laser.
//    Lethal force goes by Space Law's cases (bot_may_use_lethal_force()), and it stops when they're down.

/// Between one call for backup and the next from the same officer.
#define BOT_BACKUP_GAP (20 SECONDS)
/// How close an officer lets somebody dangerous get before stepping back.
#define BOT_SEC_KEEP_AWAY 3
/// How far off it stops to shoot.
#define BOT_SEC_HOLD_AT 5
/// Share of its health at which an officer stops and falls back from somebody it can't take.
#define BOT_SEC_FALL_BACK_AT 0.4
/// How long it stays out of it after falling back, for patching up.
#define BOT_SEC_FALL_BACK_TIME (45 SECONDS)
/// Before it looks in the armory again.
#define BOT_ARMORY_REST (3 MINUTES)

/datum/bot_brain
	var/next_dispatch_call = 0
	var/next_armory_try = 0
	/// Until when it's out of the fight, patching up.
	var/fallen_back_until = 0

/// Somebody you don't walk up to on your own: a Syndicate suit, a gun or something heavy in their hand, or blood on them already.
/proc/bot_too_dangerous(mob/living/carbon/human/S)
	if(!istype(S))
		return FALSE
	if(istype(S.wear_suit, /obj/item/clothing/suit/space/hardsuit/nano))
		return TRUE
	if(bot_armed_and_dangerous(S))
		return TRUE
	var/datum/bot_wanted/W = bot_get_wanted_entry(S)
	return W?.severity >= BOT_CRIME_MURDER

/// Everybody on Security who's free heads there. An officer already in a fight or walking a prisoner down stays where it is.
/proc/bot_dispatch_security(turf/T, what, mob/living/caller_mob)
	if(!T)
		return
	for(var/datum/bot_brain/B as anything in GLOB.bot_security_brains)
		if(QDELETED(B.owner) || B.owner.stat != CONSCIOUS || B.owner == caller_mob || B.owner.z != T.z || B.goal_chain_pending || !B.can_drop_for_call())
			continue
		if(world.time < B.next_security_call_time || B.gym_run && get_area(B.owner) != get_area(T))
			continue
		B.next_security_call_time = world.time + BOT_BACKUP_GAP
		if(B.state == BOT_STATE_GOAL)
			B.abandon_goals_for_arrest()
		var/datum/bot_goal/respond_to_call/G = new()
		G.caller_turf = T
		G.caller_name = what
		B.assign_goal(G)
	for(var/datum/bot_silicon/borg/S in GLOB.bot_silicons) //goals/silicon.dm
		S.answer_call(T)

/datum/bot_brain/proc/call_for_backup(mob/living/carbon/human/S)
	if(world.time < next_dispatch_call)
		return
	next_dispatch_call = world.time + BOT_BACKUP_GAP
	bot_say(owner, ":s [pick("Need backup", "All units", "Backup needed")], [S.name], [get_area_name(S, TRUE)]. Don't go in alone.")
	bot_dispatch_security(get_turf(S), S.name, owner)

/// A gun's lethal setting, if it has one with the charge for it.
/datum/bot_brain/proc/ready_lethal_gun()
	for(var/obj/item/gun/energy/G in owner.GetAllContents())
		if(istype(G, /obj/item/gun/energy/ionrifle) || !G.ammo_type || !G.ammo_type.len)
			continue
		for(var/i in 1 to G.ammo_type.len)
			var/obj/item/ammo_casing/energy/shot = G.ammo_type[i]
			var/obj/item/projectile/beam = shot.projectile_type
			if(is_nonlethal_shot(shot) || (beam && (initial(beam.nodamage) || initial(beam.damage) <= 0)) || G.cell.charge < shot.e_cost)
				continue //a practice laser's beam does nothing: one was being fired at a blob, and would have been at anybody due lethal force
			var/guard = G.ammo_type.len
			while(G.select != i && guard-- > 0)
				G.select_fire(owner)
			if(G.select == i)
				return G
	return null

/// What to shoot them with. The ion rifle for a suit, whatever the law allows after that, and a taser for everything else.
/datum/bot_brain/proc/best_gun_against(mob/living/carbon/human/S)
	if(istype(S.wear_suit, /obj/item/clothing/suit/space/hardsuit/nano))
		var/obj/item/gun/energy/ionrifle/ion = find_carried_tool(/obj/item/gun/energy/ionrifle)
		if(ion?.can_shoot())
			return ion
	if(bot_may_use_lethal_force(S)) //bot_law.dm
		var/obj/item/gun/lethal = ready_lethal_gun()
		if(lethal)
			return lethal
	return ready_nonlethal_gun()

/datum/bot_brain/proc/shoot_at_range(mob/living/carbon/human/S)
	if(world.time < next_taser_time || !has_clear_shot(S))
		return FALSE
	var/obj/item/gun/G = best_gun_against(S)
	if(!G)
		return FALSE
	if(owner.get_active_held_item() != G)
		free_hand_for(G)
		if(!owner.put_in_hands(G))
			return FALSE
	var/nonlethal = FALSE
	var/obj/item/gun/energy/E = G
	if(istype(E) && E.ammo_type?.len)
		nonlethal = is_nonlethal_shot(E.ammo_type[E.select])
	owner.a_intent = nonlethal ? INTENT_HELP : INTENT_HARM
	owner.face_atom(S)
	owner.changeNext_move(CLICK_CD_RANGE)
	next_taser_time = world.time + max(CLICK_CD_RANGE, G.fire_delay) + 5
	bot_log(src, "firing [G] at [S] (dist [get_dist(owner, S)])")
	INVOKE_ASYNC(G, TYPE_PROC_REF(/obj/item/gun, afterattack), S, owner, FALSE, null)
	return TRUE

/// A step straight away from them, if the floor's there for it.
/datum/bot_brain/proc/step_back_from(atom/A)
	var/turf/T = get_step_away(owner, A)
	if(T && !T.density && !is_blocked_turf(T, TRUE))
		step_towards(owner, T)

/// Hurt, and there's nothing to be gained by staying. It says so, and goes and patches up.
/datum/bot_brain/proc/fall_back_from(mob/living/carbon/human/S)
	fallen_back_until = world.time + BOT_SEC_FALL_BACK_TIME
	bot_say(owner, ":s I'm hit, falling back. [S.name], [get_area_name(S, TRUE)].")
	bot_log(src, "falling back from [S]")
	end_arrest("falling back")
	if(!try_self_heal_round())
		run_from(S, "falling back")

/// One go of the arrest loop against somebody dangerous. FALSE leaves the ordinary arrest to carry on: they're out of range, or it's got no gun.
/datum/bot_brain/proc/keep_it_at_range(mob/living/carbon/human/S, dist)
	call_for_backup(S)
	if(owner.health <= owner.maxHealth * BOT_SEC_FALL_BACK_AT)
		fall_back_from(S)
		return TRUE
	if(!find_usable_gun())
		return FALSE
	shoot_at_range(S)
	if(dist <= BOT_SEC_HOLD_AT)
		stop_pursuit()
		if(dist < BOT_SEC_KEEP_AWAY)
			step_back_from(S)
		return TRUE
	var/turf/spot = spot_short_of(S)
	if(!spot)
		return FALSE
	if(pursuing_kind != "arrest" || pursue_target != spot)
		pursue(spot, "arrest", force = TRUE)
	return TRUE

/// Somewhere to stop on the way to something, or null if that's in a wall. At a run a bot covers ten tiles between one look and the next, so
/// heading for the suspect itself had it in arm's reach before it knew it.
/datum/bot_brain/proc/spot_short_of(atom/A)
	var/list/line = getline(owner, A)
	var/turf/spot = line[max(1, length(line) - BOT_SEC_HOLD_AT)]
	return !spot || spot.density || is_blocked_turf(spot, TRUE) ? null : spot

/// Whether there's a charged gun on it at all.
/datum/bot_brain/proc/find_usable_gun()
	for(var/obj/item/gun/G in owner.GetAllContents())
		if(G.can_shoot())
			return G
	return null

/// What's worth having from the armory just now, going by who's at large.
/datum/bot_brain/proc/armory_want()
	var/suited = FALSE
	var/dangerous = FALSE
	for(var/datum/weakref/ref as anything in GLOB.bot_security_wanted)
		var/mob/living/carbon/human/H = ref.resolve()
		if(!H || H.stat == DEAD || H.handcuffed || !bot_too_dangerous(H))
			continue
		dangerous = TRUE
		if(istype(H.wear_suit, /obj/item/clothing/suit/space/hardsuit/nano))
			suited = TRUE
	if(suited && !find_carried_tool(/obj/item/gun/energy/ionrifle))
		for(var/obj/item/gun/energy/ionrifle/ion as anything in bot_instances_of(/obj/item/gun/energy/ionrifle))
			if(!QDELETED(ion) && isturf(ion.loc) && ion.z == owner.z)
				return /obj/item/gun/energy/ionrifle
	if((dangerous || length(GLOB.blob_cores)) && !find_carried_tool(/obj/item/gun/energy/laser)) //a blob takes a laser's whole burn
		return /obj/item/gun/energy/laser
	return null

/datum/bot_duty/arm_up
	name = "getting something heavier from the armory"
	jobs = list("Warden", "Head of Security")
	tier = BOT_DUTY_URGENT
	priority = 30
	interval_min = 100
	interval_max = 200

/datum/bot_duty/arm_up/try_start(datum/bot_brain/bot)
	if(world.time < bot.next_armory_try || (!length(GLOB.bot_security_wanted) && !length(GLOB.blob_cores)))
		return FALSE
	var/want = bot.armory_want()
	if(!want)
		return FALSE
	bot.next_armory_try = world.time + BOT_ARMORY_REST
	var/datum/bot_goal/acquire_item_type/G = new()
	G.item_type = want
	G.lawful = TRUE
	if(!bot.assign_goal(G))
		return FALSE
	bot_say(bot.owner, ":s Getting something heavier from the armory.")
	return TRUE

#undef BOT_BACKUP_GAP
#undef BOT_SEC_KEEP_AWAY
#undef BOT_SEC_HOLD_AT
#undef BOT_SEC_FALL_BACK_AT
#undef BOT_SEC_FALL_BACK_TIME
#undef BOT_ARMORY_REST
