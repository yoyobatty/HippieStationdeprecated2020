// Explosion blame: every explosion is logged with what caused it, who might be responsible and the call stack that
// set it off, so none go unexplained. Most explosion() callers only pass a turf, so the call stack (BYOND 515+ callee
// frames) is what names the object - "/obj/structure/reagent_dispensers/fueltank/proc/boom on the fuel tank".

#define EXPLOSION_TRACE_DEPTH 8

/// Works out what to blame for an explosion. `origin` is whatever was passed to explosion() before it became a turf.
/// Returns list("cause", "suspects", "admin_suspects", "trace") of text for the logs.
/proc/explosion_blame(atom/origin, atom/explosion_cause)
	var/atom/cause = explosion_cause
	if(!cause && origin && !isturf(origin))
		cause = origin

	// The explosion machinery itself tells us nothing, so skip past it to whoever called it
	var/static/list/skip_procs = list(
		/proc/explosion,
		/proc/dyn_explosion,
		/proc/explosion_blame,
		/datum/controller/subsystem/explosions/proc/explode,
	)
	var/list/trace = list()
	var/list/involved = list() //atoms the stack ran on, or reagents were held in
	if(cause)
		involved += cause
	var/list/suspects = list() //ckey or mob -> list of reasons
	var/callee/frame = caller
	while(frame && length(trace) < EXPLOSION_TRACE_DEPTH)
		var/reagent_explosion_start = istype(frame.src, /datum/effect_system/reagents_explosion) && frame.name == "start" //an override, so it has no /proc/ path to list
		if(!(frame.proc in skip_procs) && !reagent_explosion_start)
			var/frame_src = frame.src
			var/where = frame.file ? " ([frame.file]:[frame.line])" : ""
			trace += "[frame.proc][frame_src ? " on [explosion_blame_describe(frame_src, involved)]" : ""][where]"
			// what was handed to it: the projectile in bullet_act(P), the user in attackby(I, user)...
			for(var/arg in frame.args)
				if(istype(arg, /obj/item/projectile))
					var/obj/item/projectile/P = arg
					explosion_blame_suspect(suspects, P.firer, "fired [P] at [frame_src]")
				else if(ismob(arg) && arg != frame_src)
					explosion_blame_suspect(suspects, arg, "was involved in [frame.name]()")
		frame = frame.caller

	if(!cause) //nothing was passed but a turf - blame the nearest object the stack ran on
		for(var/atom/A as anything in involved)
			if(!isturf(A))
				cause = A
				break
	if(istype(cause, /obj/item/projectile))
		var/obj/item/projectile/P = cause
		explosion_blame_suspect(suspects, P.firer, "fired [P]")
	for(var/atom/A as anything in involved)
		if(QDELETED(A))
			continue
		if(ismob(A))
			explosion_blame_suspect(suspects, A, "is where it started")
		if(A.fingerprintslast)
			explosion_blame_suspect(suspects, A.fingerprintslast, "last touched [A]")
		var/mob/holder = get(A.loc, /mob)
		if(holder && holder != A)
			explosion_blame_suspect(suspects, holder, "was carrying [A]")
	if(ismob(usr))
		explosion_blame_suspect(suspects, usr, "was acting (usr)")

	var/list/log_suspects = list()
	var/list/admin_suspects = list()
	for(var/who in suspects)
		var/reasons = jointext(suspects[who], ", ")
		var/mob/M = ismob(who) ? who : get_mob_by_key(who)
		log_suspects += "[M ? key_name(M) : who] ([reasons])"
		admin_suspects += "[M ? ADMIN_LOOKUPFLW(M) : who] ([reasons])"

	. = list(
		"cause" = cause ? "[cause] ([cause.type])[isturf(cause.loc) ? "" : " inside [cause.loc]"]" : "unknown",
		"suspects" = length(log_suspects) ? jointext(log_suspects, "; ") : "none found",
		"admin_suspects" = length(admin_suspects) ? jointext(admin_suspects, "; ") : "none found",
		"trace" = length(trace) ? jointext(trace, " <- ") : "none",
	)

/// Names a call stack frame's src for the trace, adding any atom it involves to `involved`.
/proc/explosion_blame_describe(datum/D, list/involved)
	if(!istype(D)) //world procs
		return "[D]"
	if(isatom(D))
		involved |= D
		var/atom/A = D
		return "[A] ([A.type])"
	if(istype(D, /datum/reagent))
		var/datum/reagent/R = D
		var/atom/container = R.holder?.my_atom
		if(container)
			involved |= container
		return "[R.name] in [container ? "[container] ([container.type])" : "nothing"]"
	if(istype(D, /datum/reagents))
		var/datum/reagents/holder = D
		if(holder.my_atom)
			involved |= holder.my_atom
		return "reagents of [holder.my_atom ? "[holder.my_atom] ([holder.my_atom.type])" : "nothing"]"
	return "[D.type]"

/// Adds `who` (a mob or a ckey) to the suspect list with a reason. Players are keyed by ckey so their fingerprints
/// and their mob land in one entry; mobs with no player (bots, monkeys) are keyed by the mob.
/proc/explosion_blame_suspect(list/suspects, who, reason)
	if(!who)
		return
	if(ismob(who))
		var/mob/M = who
		if(M.ckey)
			who = M.ckey
	var/list/reasons = suspects[who]
	if(!reasons)
		suspects[who] = reasons = list()
	reasons |= reason

#undef EXPLOSION_TRACE_DEPTH
