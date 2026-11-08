/obj/item/integrated_electronics/analyzer
	name = "circuit analyzer"
	desc = "This tool can scan an assembly and generate code necessary to recreate it in a circuit printer."
	icon = 'icons/obj/assemblies/electronic_tools.dmi'
	icon_state = "analyzer"
	flags_1 = CONDUCT_1
	w_class = WEIGHT_CLASS_SMALL

/obj/item/integrated_electronics/analyzer/afterattack(var/atom/A, var/mob/living/user)
	. = ..()
	if(istype(A, /obj/item/electronic_assembly))
		var/obj/item/electronic_assembly/EA = A
		if(EA.idlock)
			to_chat(user, "<span class='notice'>[A] is currently identity-locked and can't be analyzed.</span>")
			return FALSE

		var/saved = SScircuit.save_electronic_assembly(A)
		if(saved)
			to_chat(user, "<span class='notice'>You scan [A].</span>")
			circuit_show_code(user, "[A.name] analyzed", saved, A)
		else
			to_chat(user, "<span class='warning'>[A] is not complete enough to be encoded!</span>")
