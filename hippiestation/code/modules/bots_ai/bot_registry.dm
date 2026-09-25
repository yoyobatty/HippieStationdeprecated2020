// Live instance lists for bot AI target searches.
//
// Goals used to find candidates with `for(var/obj/X in world)`, which walks every atom in
// the world (~970k on the station map) no matter how narrow the type filter is. Measured
// at ~17ms per scan against a 50ms server tick, and acquire_tool could run up to five of
// those in one decision. Iterating a list of just the instances takes ~0.01ms.
//
// Lists are built lazily: the first bot_instances_of(type) call pays for one world scan,
// after which /obj/Initialize() and /obj/Destroy() keep the list current. Until a bot asks
// for a type, the per-object cost is a length() check on an empty list.

/// Typepath -> assoc list of live instances (instance -> TRUE) of that type and its subtypes.
GLOBAL_LIST_EMPTY(bot_type_registry)

/// Returns the live instances of `type` (and subtypes) as an assoc list; iterate its keys.
/// The returned list is the registry's own - don't modify it. Entries can still be mid-deletion,
/// so callers should keep their usual QDELETED()/loc checks.
/proc/bot_instances_of(type)
	var/list/instances = GLOB.bot_type_registry[type]
	if(instances)
		return instances
	instances = list()
	for(var/obj/O in world)
		if(istype(O, type) && !QDELETED(O))
			instances[O] = TRUE
	GLOB.bot_type_registry[type] = instances
	return instances

/// Called from /obj/Initialize() once any type is being tracked.
/proc/bot_registry_add(obj/O)
	for(var/type in GLOB.bot_type_registry)
		if(istype(O, type))
			var/list/instances = GLOB.bot_type_registry[type]
			instances[O] = TRUE

/// Called from /obj/Destroy() once any type is being tracked.
/proc/bot_registry_remove(obj/O)
	for(var/type in GLOB.bot_type_registry)
		if(istype(O, type))
			var/list/instances = GLOB.bot_type_registry[type]
			instances -= O
