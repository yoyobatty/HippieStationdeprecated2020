/obj/effect/spawner/template
	name = "map template spawner"
	var/template_name

/obj/effect/spawner/template/Initialize() // I am so glad SSmapping initializes before SSatoms, otherwise so much fuckery would be needed here
	. = ..()
	if(!template_name)
		stack_trace("Tried to spawn a non-existent structure at [COORD(src)]!")
	var/datum/map_template/template = SSmapping.map_templates[template_name]
	if(!template)
		stack_trace("Tried to spawn a non-existent structure ([template_name]) at [COORD(src)]!")
	var/turf/T = get_turf(src)
	if(!T)
		return
	// Deliberately inside Initialize(): the map reader yields, so at boot this shows in initialize.log as "Slept during
	// Initialize()". Loading async or from LateInitialize() would run the template's own atom pass in among SSatoms' pass
	// (which saves and restores SSatoms.initialized) or its late loaders (a shared list it cuts).
	if(!UNLINT(template.load(T, centered = TRUE)))
		stack_trace("Failed to place structure \"[template_name]\" at [COORD(src)]!")
	return INITIALIZE_HINT_QDEL