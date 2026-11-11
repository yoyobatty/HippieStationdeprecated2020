/obj/item/bodypart/head/drop_limb(special)
	. = ..()
	if(ishuman(owner))
		var/mob/living/carbon/human/H = owner
		H.checknoosedrop()
		
/obj/item/organ/brain/transfer_to_limb(obj/item/bodypart/head/LB, mob/living/carbon/human/C)
	Remove(C)	//Changeling brain concerns are now handled in Remove
	forceMove(LB)
	LB.brain = src
	if(brainmob)
		LB.brainmob = brainmob
		brainmob = null
		LB.brainmob.forceMove(LB)
		LB.brainmob.stat = DEAD
		C.set_species()

// The chest's own dismember() (organs spilling out) skipped the godmode check the other limbs make
/obj/item/bodypart/chest/dismember()
	if(owner && (owner.status_flags & GODMODE))
		return FALSE
	return ..()
