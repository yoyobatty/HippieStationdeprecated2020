// The hardsuit's own jetpack, running off the tank in the suit's storage, has to stay on as its wearer moves: that's what gets
// anybody across open space (nuclear operatives, goals/nuke_ops.dm, and every player in a hardsuit).

/datum/bot_scenario/chat/jetpack
	name = "jetpack: a syndicate hardsuit's jetpack stays on while its wearer walks"
	desc = "Somebody in a syndicate hardsuit, an emergency tank in the suit's storage, turns the suit's jetpack on and walks five tiles. It stays on, and the tank gives a little gas for each step."
	layout = list(
		"##########",
		"#B.C.....#",
		"##########")
	time_limit = 15 SECONDS
	var/steps_taken = 0
	var/start_moles = 0

/datum/bot_scenario/chat/jetpack/post_spawn()
	..()
	var/obj/item/clothing/suit/space/hardsuit/syndi/suit = new(visitor.loc)
	visitor.equip_to_slot_if_possible(suit, ITEM_SLOT_OCLOTHING, FALSE, TRUE, TRUE, TRUE)
	var/obj/item/tank/internals/emergency_oxygen/engi/T = new(visitor.loc)
	visitor.equip_to_slot_if_possible(T, ITEM_SLOT_SUITSTORE, FALSE, TRUE, TRUE, TRUE)
	var/obj/item/tank/jetpack/J = visitor.get_jetpack()
	J?.cycle(visitor)
	start_moles = T.air_contents.total_moles()
	log_line("suit [visitor.wear_suit], tank [visitor.s_store], jetpack [J] [J?.on ? "on" : "off"], [start_moles] mol")
	addtimer(CALLBACK(src, PROC_REF(walk_on)), 1 SECONDS)

/datum/bot_scenario/chat/jetpack/proc/walk_on()
	if(result != BOT_GYM_PENDING || QDELETED(visitor))
		return
	visitor.Move(get_step(visitor, EAST), EAST)
	steps_taken++
	var/obj/item/tank/jetpack/J = visitor.get_jetpack()
	var/obj/item/tank/T = visitor.s_store
	log_line("step [steps_taken]: jetpack [J?.on ? "on" : "off"], tank [T ? T.air_contents.total_moles() : 0] mol")
	if(steps_taken < 5)
		addtimer(CALLBACK(src, PROC_REF(walk_on)), 5)

/datum/bot_scenario/chat/jetpack/check()
	if(steps_taken < 5)
		return BOT_GYM_PENDING
	var/obj/item/tank/jetpack/J = visitor.get_jetpack()
	if(!J?.on)
		fail_reason = "the jetpack went off"
		return BOT_GYM_FAIL
	return BOT_GYM_PASS

/// The records (datacore.dm) leave a crew member's photo to be taken the first time somebody looks, instead of at every join.
/datum/bot_scenario/chat/record_photo
	name = "records: a crew member's photo is taken the first time somebody looks at it"
	desc = "Somebody joins the crew records. Their photo fields hold a note until a records console asks; then both photos exist, front and side."
	layout = list(
		"######",
		"#B.C.#",
		"######")
	time_limit = 5 SECONDS

/datum/bot_scenario/chat/record_photo/check()
	visitor.mind_initialize()
	visitor.mind.assigned_role = "Assistant"
	GLOB.data_core.manifest_inject(visitor)
	var/datum/data/record/R = find_record("name", visitor.real_name, GLOB.data_core.general)
	if(!R)
		fail_reason = "no record made"
		return BOT_GYM_FAIL
	if(!istype(R.fields["photo_front"], /datum/record_photo_pending))
		fail_reason = "the photo was taken at the join: [R.fields["photo_front"]]"
		return BOT_GYM_FAIL
	var/obj/item/photo/front = record_photo(R, "photo_front")
	var/obj/item/photo/side = R.fields["photo_side"]
	if(!istype(front) || !istype(side) || !front.picture?.picture_image || !side.picture?.picture_image || front == side)
		fail_reason = "photos after looking: [front], [side]"
		return BOT_GYM_FAIL
	return BOT_GYM_PASS

/// Glowshrooms (glowshroom.dm) are made as new(loc, seed, mutate_stats). A stray argument in Initialize() had every one that spread
/// runtime on TRUE.Copy(), never light up or spread again, and every planted one throw away the seed it was grown from.
/datum/bot_scenario/chat/glowshroom
	name = "glowshroom: a planted one keeps its seed, lights up and spreads"
	desc = "A glowshroom is put down from a seed with 10 potency. It has its own copy of that seed and gives off light; a new one made the way Spread() makes them has a seed of its own and light too."
	layout = list(
		"#########",
		"#B.....C#",
		"#.......#",
		"#.......#",
		"#########")
	time_limit = 5 SECONDS

/datum/bot_scenario/chat/glowshroom/check()
	var/turf/T = get_step(get_step(visitor, EAST), EAST)
	var/obj/item/seeds/glowshroom/seed = new(T)
	seed.potency = 10
	var/obj/structure/glowshroom/G = new(T, seed)
	if(!istype(G.myseed, /obj/item/seeds) || G.myseed == seed || G.myseed.potency != 10 || !G.light_range)
		fail_reason = "planted: seed [G.myseed], potency [istype(G.myseed, /obj/item/seeds) ? G.myseed.potency : "-"], light [G.light_range]"
		return BOT_GYM_FAIL
	// Spread() itself picks its spot by view(), and an arena has no lights for that to see by: the same call it makes, then.
	var/obj/structure/glowshroom/child = new G.type(get_step(T, SOUTH), G.myseed, TRUE)
	if(!istype(child.myseed, /obj/item/seeds) || child.myseed == G.myseed || !child.light_range)
		fail_reason = "spread: seed [child.myseed], light [child.light_range]"
		return BOT_GYM_FAIL
	return BOT_GYM_PASS
