/datum/mind
	var/no_cloning_at_all = FALSE

/datum/mind/transfer_to(mob/new_character, var/force_key_move = 0)
	if(!QDELETED(current) && !(/mob/living/proc/guardian_comm in new_character.verbs))
		current.verbs -= /mob/living/proc/guardian_comm
		current.verbs -= /mob/living/proc/guardian_recall
		current.verbs -= /mob/living/proc/guardian_reset
	var/mob/living/carbon/human/body_before = current
	var/datum/bot_brain/brain = istype(body_before) ? body_before.bot_brain : null
	. = ..()
	var/mob/living/carbon/human/body_after = new_character
	if(brain && istype(body_after) && !body_after.bot_brain) //a clone, say (goals/cloning.dm): the same bot, in a new body
		brain.move_to_body(body_after)
	if(current && current.stat != DEAD)
		var/has_stando = FALSE
		for(var/mob/living/simple_animal/hostile/guardian/jojo in GLOB.parasites)
			if(jojo.summoner == src)
				has_stando = TRUE
				jojo.forceMove(current)
				jojo.revive()
				jojo.RegisterSignal(current, COMSIG_MOVABLE_MOVED, TYPE_PROC_REF(/mob/living/simple_animal/hostile/guardian, OnMoved))
				var/mob/gost = jojo.grab_ghost(TRUE)
				if(gost)
					jojo.ckey = gost.ckey
				to_chat(jojo, "<span class='notice'>You manifest into existence, as your master's soul appears in a new body!</span>")
		if(has_stando)
			current.verbs += /mob/living/proc/guardian_comm
			current.verbs += /mob/living/proc/guardian_recall
			current.verbs += /mob/living/proc/guardian_reset
