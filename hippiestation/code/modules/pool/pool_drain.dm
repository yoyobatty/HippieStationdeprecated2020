/obj/machinery/drain
	name = "drain"
	icon = 'hippiestation/icons/turf/pool.dmi'
	icon_state = "drain"
	desc = "This removes things that clog the pool."
	anchored = TRUE
	var/active = FALSE
	var/status = FALSE //1 is drained, 0 is full.
	var/srange = 6
	var/timer = 0
	var/cooldown
	var/obj/machinery/poolcontroller/poolcontrol = null
	resistance_flags = UNACIDABLE|INDESTRUCTIBLE

/obj/machinery/drain/Initialize()
	. = ..()
	STOP_PROCESSING(SSmachines, src)
	START_PROCESSING(SSprocessing, src)
	for(var/obj/machinery/poolcontroller/control in range(srange,src))
		poolcontrol = control // was +=, which turned this into a list with two controllers in range
		break

/obj/machinery/drain/Destroy()
	if(poolcontrol?.linkeddrain == src)
		poolcontrol.linkeddrain = null
	poolcontrol = null
	return ..()

/// The pool tiles this drain empties and fills: its controller's, so the two always agree
/obj/machinery/drain/proc/pool_turfs()
	if(poolcontrol && length(poolcontrol.linkedturfs))
		return poolcontrol.linkedturfs
	. = list()
	for(var/turf/open/pool/P in range(srange, src))
		. += P

/obj/machinery/drain/process()
	if(!status) //don't drain an empty pool.
		absorb_debris()
	if(!active)
		return
	if(status) //filling back up
		if(timer > 0)
			timer--
			playsound(src, 'hippiestation/sound/effects/fillingwatter.ogg', 100, 1)
			for(var/obj/whirlo in orange(1,src))
				if(!whirlo.anchored)
					step_away(whirlo,src)
			for(var/mob/living/carbon/human/whirlm in orange(2,src))
				step_away(whirlm,src)
		else
			finish_filling()
		return
	if(timer > 0) //draining
		timer--
		playsound(src, 'hippiestation/sound/effects/pooldrain.ogg', 100, TRUE)
		playsound(src, pick('hippiestation/sound/effects/water_wade1.ogg','hippiestation/sound/effects/water_wade2.ogg','hippiestation/sound/effects/water_wade3.ogg','hippiestation/sound/effects/water_wade4.ogg'), 60, TRUE)
		for(var/obj/whirlo in orange(2,src))
			if(!whirlo.anchored)
				step_towards(whirlo,src)
		for(var/mob/living/carbon/human/whirlm in orange(2,src))
			if(istype(whirlm.loc, /turf/open/pool)) // the whirlpool is in the water: it used to drag people in off the deck too
				whirlpool_pull(whirlm)
	else
		finish_draining()

/// Tiny things near an open drain get pulled onto it, then swallowed into the filter a tick later - time to grab them
/obj/machinery/drain/proc/absorb_debris()
	var/obj/machinery/poolfilter/filter = locate() in range(srange, src)
	if(filter)
		for(var/obj/item/absorb in loc)
			if(absorb.w_class == WEIGHT_CLASS_TINY)
				absorb.forceMove(filter)
	// (this used to spawn() a fresh sleeping proc for the swallowing every single tick)
	for(var/obj/item/absorbo in orange(1,src))
		if(absorbo.w_class == WEIGHT_CLASS_TINY)
			step_towards(absorbo, src)

/// Sucks a swimmer down into the drain while it empties
/obj/machinery/drain/proc/whirlpool_pull(mob/living/carbon/human/whirlm)
	step_towards(whirlm,src)
	if(prob(20))
		whirlm.Knockdown(40)
	whirlm.SpinAnimation(7, 1) //swirl! (this used to sleep() in process(), holding up the whole processing subsystem)
	if(!whirlm.forceMove(loc))
		return
	if(whirlm.health <= -50) //If very damaged, gib.
		whirlm.gib()
		return // gone - the rest of this used to run on the deleted body
	playsound(src, pick('hippiestation/sound/misc/crack.ogg','hippiestation/sound/misc/crunch.ogg'), 50, TRUE)
	if(whirlm.stat != CONSCIOUS || whirlm.lying)
		whirlm.adjustBruteLoss(5)
		to_chat(whirlm, "<span class='danger'>You're caught in the drain!</span>")
	else
		whirlm.apply_damage(4, BRUTE, pick(BODY_ZONE_L_LEG, BODY_ZONE_R_LEG)) //drain should only target the legs
		to_chat(whirlm, "<span class='danger'>Your legs are caught in the drain!</span>")

/obj/machinery/drain/proc/finish_draining()
	for(var/turf/open/pool/drained in pool_turfs())
		drained.filled = FALSE
		drained.update_icon()
	for(var/obj/effect/whirlpool/drained3 in range(1,src))
		qdel(drained3)
	if(poolcontrol)
		poolcontrol.drained = TRUE
		poolcontrol.bloody = FALSE // the blood went down the drain with the water
		poolcontrol.mistoff()
	status = TRUE
	active = FALSE

/obj/machinery/drain/proc/finish_filling()
	for(var/turf/open/pool/undrained in pool_turfs())
		undrained.filled = TRUE
		undrained.update_icon()
	for(var/obj/effect/effect/waterspout/undrained3 in range(1,src))
		qdel(undrained3)
	if(poolcontrol)
		poolcontrol.drained = FALSE
		poolcontrol.changecolor() // fresh water overlays: tint them for whatever's in the beaker
	status = FALSE
	active = FALSE

/obj/effect/whirlpool
	name = "Whirlpool"
	icon = 'hippiestation/icons/effects/96x96.dmi'
	icon_state = "whirlpool"
	layer = 5
	anchored = TRUE
	mouse_opacity = 0
	pixel_x = -32
	pixel_y = -32
	alpha = 90

/obj/effect/effect/waterspout
	name = "Waterspout"
	icon_state = "waterspout"
	color = "#3399AA"
	layer = 5
	anchored = TRUE
	mouse_opacity = 0
	icon = 'hippiestation/icons/effects/96x96.dmi'
	pixel_x = -32
	pixel_y = -32
	alpha = 120

/obj/machinery/poolfilter
	name = "Filter"
	icon = 'hippiestation/icons/turf/pool.dmi'
	icon_state = "filter"
	desc = "The part of the pool that swallows dangerous stuff and ID's"
	anchored = TRUE
	resistance_flags = UNACIDABLE|INDESTRUCTIBLE

/obj/machinery/poolfilter/emag_act(user as mob)
	if(!(obj_flags & EMAGGED))
		to_chat(user, "<span class='warning'>You disable the [src]'s shark filter! Run!</span>")
		obj_flags |= EMAGGED
		do_sparks(5, TRUE, src)
		icon_state = "filter_b"
		addtimer(CALLBACK(src, PROC_REF(release_shark)), 5 SECONDS)
		if(GLOB.adminlog)
			log_game("[key_name(user)] emagged the pool filter and probably spawned sharks")
			message_admins("[key_name_admin(user)] emagged the pool filter and probably spawned sharks")


/obj/machinery/poolfilter/proc/release_shark()
	var/shark_type = pick(prob(50); /mob/living/simple_animal/hostile/shark, prob(25); /mob/living/simple_animal/hostile/shark/kawaii, prob(25); /mob/living/simple_animal/hostile/shark/laser)
	new shark_type(loc)

/obj/machinery/poolfilter/attack_hand(mob/user)
	to_chat(user, "You search the filter.")
	for(var/obj/O in contents)
		O.forceMove(loc)
