/datum/reagent
	reagent_state = LIQUID//since reagent states are now interchangeable it makes sense for them to all start as liquids preventing unnescessary messages
	var/boiling_point = 500//the point at which a reagent changes from a liquid to a gaseous state
	var/melting_point = 273//the point at which a reagent changes from a liquid to a solid state
	var/processes = FALSE
	var/can_synth_seeds = TRUE
	var/can_forge = TRUE

/datum/reagent/New()
	..()
	if(processes)
		START_PROCESSING(SSreagent_states, src)

/datum/reagent/Destroy() // This should only be called by the holder, so it's already handled clearing its references
	if(processes)
		STOP_PROCESSING(SSreagent_states, src)
	holder = null
	. = ..()

/datum/reagent/proc/FINISHONMOBLIFE(mob/living/M)
	current_cycle++
	M.reagents.remove_reagent(type, metabolization_rate * M.metabolism_efficiency) //By default it slowly disappears.
	return TRUE

/// Reagent vapour of `reagent_path` on `T`: a vapour of the same reagent already there is topped up (`add`: by `volume`, else up to
/// it), otherwise a new one starts, `log_text` going to the game log, unless the station already has VAPOUR_MAX. Matched by type:
/// a vapour holds its own copy of the reagent, so comparing datums never matched and every call made a new vapour.
/proc/release_reagent_vapour(turf/T, reagent_path, volume, add, log_text)
	if(!T || !ispath(reagent_path, /datum/reagent))
		return
	if(locate(/obj/effect/particle_effect/vapour) in T)
		for(var/obj/effect/particle_effect/vapour/V in T)
			if(V.reagent_type?.type != reagent_path)
				continue
			if(V.VM)
				V.VM.volume = add ? V.VM.volume + volume : max(V.VM.volume, volume)
			return V.VM
	if(length(GLOB.vapour) >= VAPOUR_MAX)
		return
	var/obj/effect/particle_effect/vapour/master/M = new(T)
	M.volume = volume
	M.reagent_type = new reagent_path
	if(log_text)
		log_game(log_text)
	return M

/datum/reagent/proc/handle_state_change(turf/T, volume, atom)
	if(!QDELETED(src))	//otherwise it starts getting called on null holders
		var/touch_msg
		var/mob/living/touch_mob
		if(!istype(T))
			return
		if(is_type_in_typecache(T, GLOB.statechange_turf_blacklist))
			return
		if(!volume)
			return
		if(volume * 0.25 < 1)
			return
		if(atom)
			if(is_type_in_typecache(atom, GLOB.no_reagent_statechange_typecache))
				return
			if(istype(atom, /obj/item))
				var/obj/item/I = atom
				touch_mob = I.fingerprintslast
				if(istype(touch_mob))
					touch_msg = get_mob_by_key(touch_mob)
					touch_msg = "[ADMIN_LOOKUPFLW(touch_msg)]"

		if(is_type_in_typecache(src, GLOB.statechange_reagent_blacklist)) //Reagent states are interchangeable, so one blacklist to rule them all.
			return
		if(reagent_state == GAS) //VAPOR
			if(is_type_in_typecache(src, GLOB.vaporchange_reagent_blacklist))
				return
			if(atom && istype(atom, /obj/effect/particle_effect))
				volume *= GAS_PARTICLE_EFFECT_EFFICIENCY//big nerf to smoke and foam duping

			var/turf/open/O = T
			if(istype(O))
				// if there's an existing vapour of the same type it's topped up, otherwise a new one starts. This compared the
				// vapour's reagent (its own copy) with src, which is never the same datum, and looked only at the first vapour on the
				// tile: every call made a new vapour master, each of which pulls every other master of its type within 5 tiles into
				// itself. Smoke of a boiling reagent calls this for the tile and for every object on it, every tick, so a cloud over a
				// pile made hundreds of masters a tick; with the timers each master starts, SStimer never caught up (2026-11-13,
				// a pile of acid rain and hellfire grenades: 35,000 vapours a minute, timers minutes late, then a 6 s freeze)
				release_reagent_vapour(O, type, volume * 50, FALSE, "Reagent vapour of type [src] was released at [COORD(T)] Last Fingerprint: [touch_msg] ")


		if(reagent_state == LIQUID) //LIQUID
			if(is_type_in_typecache(src, GLOB.vaporchange_reagent_blacklist)) //this is to prevent lube and clf3 from making chempiles
				return
			if(atom && istype(atom, /obj/effect/particle_effect))
				volume *= LIQUID_PARTICLE_EFFECT_EFFICIENCY//big nerf to smoke and foam duping

			for(var/obj/effect/decal/cleanable/chempile/c in T.contents)//handles merging existing chempiles
				if(c.reagents)
					if(touch_msg)
						c.add_fingerprint(touch_mob)
					c.reagents.add_reagent(type, volume)
					c.queue_recolor()
					if(c.reagents && c.reagents.total_volume >= 5)
						DISABLE_BITFIELD(c.reagents.flags, NO_REACT)
					return TRUE

			var/obj/effect/decal/cleanable/chempile/C = new (T)//otherwise makes a new one
			if(C.reagents)
				if(touch_msg)
					C.add_fingerprint(touch_mob)
				C.reagents.add_reagent(type, volume)
				C.queue_recolor()

		if(reagent_state == SOLID) //SOLID
			if(is_type_in_typecache(src, GLOB.solidchange_reagent_blacklist))
				return
			if(atom && istype(atom, /obj/effect/particle_effect))
				volume *= SOLID_PARTICLE_EFFECT_EFFICIENCY//big nerf to smoke and foam duping

			for(var/obj/item/reagent_containers/food/snacks/solid_reagent/SR in T.contents)
				if(SR.reagents && SR.reagent_type == type && SR.reagents.total_volume < 200)
					if(touch_msg)
						SR.add_fingerprint(touch_mob)
					SR.reagents.add_reagent(type, volume)
					return TRUE

			var/obj/item/reagent_containers/food/snacks/solid_reagent/Sr = new (T)
			if(touch_msg)
				Sr.add_fingerprint(touch_mob)
			Sr.reagents.add_reagent(type, volume)
			Sr.reagent_type = type
			Sr.name = "solidified [src]"
			Sr.add_atom_colour(color, FIXED_COLOUR_PRIORITY)
			Sr.filling_color = color
