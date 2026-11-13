// Plastic explosives (C4, X4), on top of tg's code/game/objects/items/grenades/plastic.dm.
//  - X4 is a shaped charge. tg's checked whether the wall was still solid only after breaking it, so it never was: X4 went off as a
//    plain round blast on the wall's own tile, the planter one tile away in heavy range. Now a jet of metal punches on through the
//    wall, and the blast goes off on the far side while the wall still stands, so the planter's side only gets what leaks past it.
//  - A charge whose target is destroyed before it goes off (cremated, eaten, gibbed, smashed) falls off, still counting down. It used
//    to fizzle and keep the deleted thing referenced.
//  - X4's timer counts seconds, from 10. The screwdriver and multitool went to the grenade timer, which counts tenths of a second
//    and has a 0: a screwdriver twice gave an X4 that went off the moment it was planted.
//  - C4's detonator can be cut off with wirecutters while its panel's shut. tg's wire code took every wirecutter.
//  - Sensors in the detonator work. A proximity sensor's field followed the assembly, which sits inside the charge and never moves,
//    so it watched nothing: now it watches round the charge, or round what it's planted on (a wall, a door, a person). A health
//    sensor reads whoever the charge is planted on, and whoever dropped it from their hands as they fell.
//  - A heavy blast on what a charge is planted on sets it off (the user's ruling, 2026-11-13): charges chain. A planted charge sits in
//    nullspace, so nothing touched it before.
//  - The wall tile a charge breaches keeps its floor (the user's ruling): the blast reaches it as the new plating and used to tear
//    that up too, opening both rooms to space.

/obj/item/grenade/plastic
	/// prime() runs once
	var/primed = FALSE
	/// When the fuse runs out (world.time), once it's planted
	var/fuse_ends
	/// How many tiles past what it's planted on a shaped charge's jet reaches. 0 for none.
	var/jet_length = 0

/obj/item/grenade/plastic/Initialize()
	. = ..()
	plastic_overlay = mutable_appearance(icon, "[item_state]2", ABOVE_ALL_MOB_LAYER)

/obj/item/grenade/plastic/Destroy()
	if(nadeassembly)
		watch_from(nadeassembly, nadeassembly) //its proximity sensor's field would hold on to us
	return ..()

/obj/item/grenade/plastic/x4
	can_attach_mob = TRUE // oh no no no no no
	full_damage_on_mobs = TRUE // OHHHHHHHH
	jet_length = 4

/obj/item/grenade/plastic/examine(mob/user)
	. = ..()
	if(fuse_ends && !primed)
		. += "<span class='danger'>It's counting down: [DisplayTimeText(max(fuse_ends - world.time, 0))] left.</span>"

/obj/item/grenade/plastic/afterattack(atom/movable/AM, mob/user, flag)
	var/obj/item/assembly_holder/H = nadeassembly
	if(H && flag)
		watch_from(H, H) //going into nullspace as it's planted counts as moving, and an armed proximity sensor would go off in their hands
	. = ..() //tg's: three seconds to plant it, then into nullspace with the fuse started
	if(!flag || primed || loc || target != AM)
		if(H && nadeassembly == H && !QDELETED(src))
			watch_from(H, src)
		return
	var/ends = world.time + det_time * 10
	fuse_ends = fuse_ends ? min(fuse_ends, ends) : ends //picked up after falling off and planted again: the first fuse is still going
	if(ismovable(AM)) //a turf that changes (a wall taken down) is still the same turf, and the charge stays on it
		RegisterSignal(AM, COMSIG_PARENT_QDELETING, PROC_REF(target_destroyed), TRUE)
	RegisterSignal(AM, COMSIG_ATOM_EX_ACT, PROC_REF(target_blasted), TRUE)
	if(nadeassembly)
		watch_from(nadeassembly, AM)

/// What it's planted on is going: the charge falls off where it was, still counting down
/obj/item/grenade/plastic/proc/target_destroyed(atom/movable/gone)
	SIGNAL_HANDLER
	UnregisterSignal(gone, list(COMSIG_PARENT_QDELETING, COMSIG_ATOM_EX_ACT))
	if(target == gone)
		target = null
	if(primed || QDELETED(src))
		return
	var/atom/drop = gone.drop_location()
	if(!drop)
		return
	forceMove(drop)
	if(nadeassembly)
		watch_from(nadeassembly, src)
	if(isturf(drop))
		visible_message("<span class='warning'>[src] falls to the floor, still counting down!</span>")

/// What it's planted on is hit by a blast: a heavy one sets it off. Next tick, as the blast may be in the middle of breaking what it's on.
/obj/item/grenade/plastic/proc/target_blasted(atom/source, severity, blast_target)
	SIGNAL_HANDLER
	if(primed || severity == EXPLODE_NONE || severity > EXPLODE_HEAVY)
		return
	UnregisterSignal(source, COMSIG_ATOM_EX_ACT) //once
	addtimer(CALLBACK(src, PROC_REF(prime)), 1)

/obj/item/grenade/plastic/attack_self(mob/user)
	if(!nadeassembly && fuse_ends)
		to_chat(user, "<span class='warning'>[src] is already counting down!</span>")
		return
	return ..()

/obj/item/grenade/plastic/attackby(obj/item/I, mob/user, params)
	if(I.tool_behaviour == TOOL_SCREWDRIVER || I.tool_behaviour == TOOL_MULTITOOL) //C4 takes these for its panel and wires first
		set_fuse(user)
		return
	var/obj/item/assembly_holder/had = nadeassembly
	. = ..() //tg's: puts a detonator assembly on, or cuts it off with wirecutters
	if(nadeassembly != had)
		if(had)
			watch_from(had, had)
		if(nadeassembly)
			watch_from(nadeassembly, src)

/// Where a proximity sensor in the detonator `H` watches round: the charge, what it's planted on, or `H` itself once it's off
/obj/item/grenade/plastic/proc/watch_from(obj/item/assembly_holder/H, atom/watcher)
	for(var/obj/item/assembly/prox_sensor/P in list(H.a_left, H.a_right))
		var/datum/proximity_monitor/field = P.proximity_monitor
		if(!field)
			continue
		field.ignore_if_not_on_turf = !isturf(watcher) //planted on a wall: round the wall
		field.SetHost(watcher, P)
		field.SetRange(field.current_range, TRUE)

/obj/item/grenade/plastic/dropped(mob/user)
	. = ..()
	if(!nadeassembly || !isliving(user))
		return
	for(var/obj/item/assembly/health/sensor in list(nadeassembly.a_left, nadeassembly.a_right))
		if(sensor.scanning && sensor.secured)
			sensor.read_health(user) //falling into crit empties the hands: one last reading of who let go, as a bare sensor gets

/// A health sensor on a planted charge reads who it's planted on. It looks for a mob up the charge's loc, and a planted charge has none.
/obj/item/assembly/health/process()
	. = ..()
	if(!scanning || !secured)
		return
	var/obj/item/grenade/plastic/charge = holder?.master
	if(istype(charge) && !charge.loc && isliving(charge.target))
		read_health(charge.target)

/// The timer, in seconds from 10, as using it in hand sets it
/obj/item/grenade/plastic/proc/set_fuse(mob/user)
	if(fuse_ends)
		to_chat(user, "<span class='warning'>[src] is already counting down!</span>")
		return
	var/newtime = tgui_input_number(user, "Please set the timer.", "Timer", det_time, 60000, 10, allow_cancel = FALSE)
	if(isnull(newtime) || QDELETED(src) || (user.client && !user.canUseTopic(src, BE_CLOSE)))
		return
	det_time = clamp(round(newtime), 10, 60000)
	to_chat(user, "<span class='notice'>Timer set for [det_time] seconds.</span>")

/obj/item/grenade/plastic/c4/attackby(obj/item/I, mob/user, params)
	if(nadeassembly && !open_panel && I.tool_behaviour == TOOL_WIRECUTTER)
		I.play_tool_sound(src, 20)
		watch_from(nadeassembly, nadeassembly)
		nadeassembly.forceMove(get_turf(src))
		nadeassembly.master = null
		nadeassembly = null
		update_icon()
		to_chat(user, "<span class='notice'>You cut the detonator off [src].</span>")
		return
	return ..()

/obj/item/grenade/plastic/prime()
	if(primed || QDELETED(src))
		return
	primed = TRUE
	var/atom/hit = target
	target = null
	var/turf/location
	if(hit && !QDELETED(hit))
		UnregisterSignal(hit, list(COMSIG_PARENT_QDELETING, COMSIG_ATOM_EX_ACT))
		location = get_turf(hit)
		hit.cut_overlay(plastic_overlay, TRUE)
	else
		hit = null
		location = get_turf(src)
	if(location)
		// The blast first, while what it's on still stands: explosion() works out who's hit there and then (it's applied later), so a
		// wall it's on shields what's behind it, and it's the room's air the blast reads, not the fresh plating's left by the breach
		// (none yet: blast_air_factor() took that for vacuum and shrank C4 on a wall to light 1.5)
		var/shaped = directional && aim_dir && hit && hit.density
		explosion(shaped ? shaped_epicenter(location) : location, boom_sizes[1], boom_sizes[2], boom_sizes[3])
		if(shaped)
			shaped_jet(location)
		if(hit && (!ismob(hit) || full_damage_on_mobs))
			var/wall = isclosedturf(hit)
			hit.ex_act(EXPLODE_HEAVY, hit)
			if(wall && istype(hit, /turf/open/floor)) //the same turf, now the floor the wall stood on
				var/turf/open/floor/breach = hit
				breach.breached_until = world.time + 2 SECONDS
	if(ismob(hit) && !QDELETED(hit))
		var/mob/M = hit
		if(ishuman(M)) //allows gibbing of human corpses, instagibbing with X4
			if(M.stat || full_damage_on_mobs)
				M.gib(1, 1, 1)
		else
			M.gib()
	qdel(src)

/// Where a shaped charge on something solid sets its blast off: two tiles on, or as far as it gets before something solid
/obj/item/grenade/plastic/proc/shaped_epicenter(turf/location)
	. = location
	var/turf/front = get_step(location, aim_dir)
	if(front && !front.density)
		. = front
		var/turf/further = get_step(front, aim_dir)
		if(further && !further.density)
			. = further

/// The jet: on through whoever's in line, weaker each tile, until it's spent or stops in the next solid thing
/obj/item/grenade/plastic/proc/shaped_jet(turf/location)
	var/turf/T = location
	for(var/i in 1 to jet_length)
		T = get_step(T, aim_dir)
		if(!T)
			return
		do_sparks(1, FALSE, T)
		var/damage = 55 - i * 10
		for(var/mob/living/L in T)
			if(L.status_flags & GODMODE)
				continue
			var/zone = ran_zone(BODY_ZONE_CHEST)
			L.apply_damage(damage, BRUTE, zone, L.getarmor(zone, "bomb"))
		if(T.density)
			T.ex_act(EXPLODE_HEAVY)
			return
		for(var/obj/O in T)
			if(O.density && !(O.pass_flags & LETPASSTHROW))
				O.ex_act(EXPLODE_HEAVY)
				return

/// Until when (world.time) a floor a charge has just breached a wall onto holds: the blast already on its way reaches it as a light one
/turf/open/floor/var/breached_until = 0

/turf/open/floor/ex_act(severity, target)
	if(breached_until > world.time && severity && severity < EXPLODE_LIGHT && target != src)
		severity = EXPLODE_LIGHT
	return ..()
