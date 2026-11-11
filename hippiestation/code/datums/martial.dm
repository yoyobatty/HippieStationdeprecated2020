/datum/martial_art
	var/mob/living/carbon/human/owner // was it this fucking hard to add a simple link to the human?

/datum/martial_art/teach(mob/living/carbon/human/H,make_temporary=0)
	. = ..()
	if(.)
		set_owner(H)

/datum/martial_art/remove(mob/living/carbon/human/H)
	reset_streak() // just in case
	set_owner(null)
	..()

/// A gibbed body's mind is in its brain by the time the body is deleted, so the human's Destroy() can't find this to let go: an owner kept
/// here was a hard delete. Lets go when the owner is deleted, wherever the mind is.
/datum/martial_art/proc/set_owner(mob/living/carbon/human/H)
	if(owner)
		UnregisterSignal(owner, COMSIG_PARENT_QDELETING)
	owner = H
	if(owner)
		RegisterSignal(owner, COMSIG_PARENT_QDELETING, PROC_REF(owner_deleted), override = TRUE)

/datum/martial_art/proc/owner_deleted(datum/source)
	SIGNAL_HANDLER
	set_owner(null)

/datum/martial_art/add_to_streak(element,mob/living/carbon/human/D)
	..()
	addtimer(CALLBACK(src, PROC_REF(reset_streak)), 100, TIMER_OVERRIDE|TIMER_UNIQUE)

/datum/martial_art/proc/reset_streak()
	streak = "" // cleared whoever's fighting: it sat inside the client check, so a bot's combo never ran out
	if(owner?.client && owner.hud_used?.combo_object)
		owner.hud_used.combo_object.reset_streak()
