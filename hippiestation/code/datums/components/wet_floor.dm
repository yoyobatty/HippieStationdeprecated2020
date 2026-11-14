/datum/component/wet_floor
	var/static/mutable_appearance/lube_overlay = mutable_appearance('icons/effects/atmospherics.dmi', "freon_old")

// A wet floor's slip goes by what's on it now. LoadComponent() hands back the slip the floor already has, untouched: lube worn off a
// floor still wet with water kept the lube's slip, down walking or not, while the floor looked and read as water (bots said "wet
// floor ahead - walking" and went down on it fifteen times in one round), and water that froze kept the water's, safe to walk on ice.
/datum/component/wet_floor/update_flags()
	qdel(parent.GetComponent(/datum/component/slippery))
	return ..()
