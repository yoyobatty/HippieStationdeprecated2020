/atom
	var/next_spam_shot = 0
// Hippie sprites are merged into tg's own sheets at build time (tools/icon_merge), so there's no icon swap here.

/// Reagent scanners (science goggles) also read what's in a container you can't see into but can see the level of (a chem tank,
/// a fuel tank), and the temperature of any of them
/atom/examine(mob/user)
	. = ..()
	if(!reagents || !reagents.total_volume || !(reagents.flags & (TRANSPARENT | AMOUNT_VISIBLE)) || !user?.can_see_reagents())
		return
	if(!(reagents.flags & TRANSPARENT))
		. += "It contains:"
		for(var/datum/reagent/R in reagents.reagent_list)
			. += "[R.volume] units of [R.name]"
	. += "<span class='notice'>Temperature: [round(reagents.chem_temp)] K</span>"
