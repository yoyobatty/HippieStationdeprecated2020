// Live instance lists for bot AI target searches.
//
// Goals used to find candidates with `for(var/obj/X in world)`, which walks every atom in
// the world (~970k on the station map) no matter how narrow the type filter is. Measured
// at ~17ms per scan against a 50ms server tick, and acquire_tool could run up to five of
// those in one decision. Iterating a list of just the instances takes ~0.01ms.
//
// One world scan files every obj under its exact type, as the first bot wakes up (bot_index_objs()),
// and /obj/Initialize() and /obj/Destroy() keep that current. A type's first bot_instances_of()
// puts its list together from the types under it. That used to be a world scan of its own, one a
// type, in the middle of a bot's thinking: 44-77 ms each, late ticks all through the early round.
// With no bots there's no scan, and the per-object cost is one check of a global.

/// Typepath -> assoc list of live instances (instance -> TRUE) of that type and its subtypes.
GLOBAL_LIST_EMPTY(bot_type_registry)
/// Exact typepath -> assoc list of live objs of just that type.
GLOBAL_LIST_EMPTY(bot_objs_by_type)
/// Exact typepath -> the types in bot_type_registry it counts towards. Cleared whenever one is added.
GLOBAL_LIST_EMPTY(bot_tracked_parents)
GLOBAL_VAR_INIT(bot_objs_indexed, FALSE)

/proc/bot_index_objs()
	if(GLOB.bot_objs_indexed)
		return
	GLOB.bot_objs_indexed = TRUE
	for(var/obj/O in world)
		if(!QDELETED(O))
			bot_registry_add(O)

/// Returns the live instances of `type` (and subtypes) as an assoc list; iterate its keys.
/// The returned list is the registry's own - don't modify it. Entries can still be mid-deletion,
/// so callers should keep their usual QDELETED()/loc checks.
/proc/bot_instances_of(type)
	var/list/instances = GLOB.bot_type_registry[type]
	if(instances)
		return instances
	bot_index_objs()
	instances = list()
	var/list/by_type = GLOB.bot_objs_by_type
	for(var/path in typesof(type))
		for(var/obj/O as anything in by_type[path])
			instances[O] = TRUE
	GLOB.bot_type_registry[type] = instances
	GLOB.bot_tracked_parents.Cut()
	return instances

/// The tracked types an exact type counts towards, so a new or deleted obj doesn't have to ask about every tracked type.
/proc/bot_tracked_parents_of(path)
	. = GLOB.bot_tracked_parents[path]
	if(.)
		return
	. = list()
	for(var/type in GLOB.bot_type_registry)
		if(ispath(path, type))
			. += type
	GLOB.bot_tracked_parents[path] = .

/// Called from /obj/Initialize() once the index exists.
/proc/bot_registry_add(obj/O)
	var/path = O.type
	var/list/same = GLOB.bot_objs_by_type[path]
	if(!same)
		same = list()
		GLOB.bot_objs_by_type[path] = same
	same[O] = TRUE
	for(var/type in bot_tracked_parents_of(path))
		var/list/instances = GLOB.bot_type_registry[type]
		instances[O] = TRUE

/// Called from /obj/Destroy() once the index exists.
/proc/bot_registry_remove(obj/O)
	var/path = O.type
	var/list/same = GLOB.bot_objs_by_type[path]
	if(same) //something deleted in the middle of being made never got as far as being added
		same -= O
	for(var/type in bot_tracked_parents_of(path))
		var/list/instances = GLOB.bot_type_registry[type]
		instances -= O
