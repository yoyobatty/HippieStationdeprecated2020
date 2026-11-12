// One piece of glass answers a step (2026-11-11). Every shard on a tile played its own glass_step and ran its own caltrop for each
// mob that stepped there: two facing conveyors bouncing corpses over 50 shards a tile (a griefer's lag machine) sent 50 sounds to
// every client in earshot and 50 leg cuts per body per move. Now the first piece of glass on the tile answers a mob's step and the
// rest of the pile keeps quiet for it; the next step onto glass is answered again. A step is a mob arriving on a tile, so glass
// under a mob standing still was never crossed again anyway.

/mob/living
	/// The tick and the tile of this mob's last step that a piece of glass answered (glass_step_once())
	var/glass_step_time = -1
	var/turf/glass_step_turf

/// TRUE for the first piece of glass to answer this step; another on the same tile in the same tick gets FALSE
/mob/living/proc/glass_step_once()
	var/turf/T = loc
	if(glass_step_time == world.time && glass_step_turf == T)
		return FALSE
	glass_step_time = world.time
	glass_step_turf = T
	return TRUE

/obj/item/shard/Crossed(mob/living/L)
	if(istype(L) && !L.glass_step_once())
		return // the pile already answered this step: no sound, no cut (the caltrop listens through ..())
	return ..()
