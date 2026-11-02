/mob/living
	/// The slowdown of the floor we're on, as far as our movespeed modifiers know. See update_turf_movespeed().
	var/last_turf_slowdown

/mob/living/update_pull_movespeed()
	remove_movespeed_modifier(MOVESPEED_ID_PRONE_DRAGGING)
	update_crate_trolley_movespeed() // hippiestation/code/game/objects/structures/crate_trolley.dm
