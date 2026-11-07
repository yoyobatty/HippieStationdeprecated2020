// Circuit assemblies with a combat circuit in them are fair game, like turrets and mechs.
// ListTargets() finds them through GLOB.hostile_machines: an assembly joins it while it has one (assemblies.dm).
/mob/living/simple_animal/hostile/CanAttack(atom/the_target)
	if(search_objects < 2)
		if(istype(the_target, /obj/item/electronic_assembly))
			var/obj/item/electronic_assembly/O = the_target
			if(O.combat_circuits)
				return TRUE
	return ..()
