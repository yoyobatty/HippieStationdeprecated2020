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
