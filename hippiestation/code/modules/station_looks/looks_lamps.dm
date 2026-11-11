// What the station looks do to a lamp. A lamp keeps what it looked like before any look touched it, and works its colour
// and power out from that and whatever's on it now, so looks can come and go in any order and leave it as it was.
// Wear (yellowed, sputtering, buzzing) belongs to the tube: a new tube in the fitting is a clean one.

/obj/machinery/light
	/// The lamp before any look touched it: list(colour, power, night colour, night power)
	var/list/look_base
	/// An old tube gone yellow (Tired wiring): tinted and a bit dimmer until it's swapped
	var/yellowed = FALSE
	/// An old tube that sputters and will burn out in the end (Tired wiring)
	var/tired = FALSE
	/// Hums to anyone close by (Tired wiring)
	var/buzzing = FALSE

/obj/machinery/light/small
	nightshift_brightness = 4 //tg left it at the tube's 8, so a bulb on night lighting reached twice as far as it does by day

/// Works the lamp's colour and power out afresh from how it was and the looks on it. relight FALSE leaves the relighting to the caller.
/obj/machinery/light/proc/refresh_look(relight = TRUE)
	if(flickering) //flicker() has its own colour in for now and puts the real one back when it's done: come back after
		addtimer(CALLBACK(src, PROC_REF(refresh_look)), 3 SECONDS, TIMER_UNIQUE | TIMER_OVERRIDE)
		return
	if(!look_base)
		look_base = list(bulb_colour, bulb_power, nightshift_light_color, nightshift_light_power)
	var/colour = look_base[1]
	var/power = look_base[2]
	var/night_colour = look_base[3]
	var/night_power = look_base[4]
	if(plain_lamp())
		colour = look_tint(colour, SSstation_looks.lamp_tint)
		power *= SSstation_looks.lamp_power
		if(SSstation_looks.night_tint)
			night_colour = look_tint(look_base[1], SSstation_looks.night_tint)
	if(yellowed)
		colour = look_tint(colour, LOOK_YELLOWED_TINT)
		night_colour = look_tint(night_colour, LOOK_YELLOWED_TINT)
		power *= LOOK_YELLOWED_POWER
		night_power *= LOOK_YELLOWED_POWER
	bulb_colour = colour
	bulb_power = power
	nightshift_light_color = night_colour
	nightshift_light_power = night_power
	if(relight)
		var/switched = switchcount
		update(FALSE)
		switchcount = switched //a look isn't switching: it doesn't bring the tube nearer burning out

/// A plain white lamp, or one in its room's mood colour (lamp_mood.dm): the ones a shift time tints. A lamp with a colour of its own keeps it.
/obj/machinery/light/proc/plain_lamp()
	if(color || !look_base)
		return FALSE
	var/base = look_base[1]
	if(base == "#FFFFFF")
		return TRUE
	var/area/A = get_area(src)
	return A?.lamp_colour && base == A.lamp_colour

/obj/machinery/light/update(trigger = TRUE)
	if(status == LIGHT_EMPTY && (yellowed || tired || buzzing || worn))
		fresh_tube()
	return ..()

/// The old tube's out, so its yellowing, sputter and hum went with it: the next one in is new.
/obj/machinery/light/proc/fresh_tube()
	worn = FALSE
	GLOB.worn_lights -= src
	tired = FALSE
	stop_buzz()
	if(yellowed)
		yellowed = FALSE
		refresh_look(FALSE) //update() is lighting it

// ---- The hum: a lamp's ballast going. Played every LAMP_BUZZ_LOOP to the players near enough to hear it, no one else.

GLOBAL_LIST_EMPTY(buzzing_lights)

/obj/machinery/light/proc/start_buzz()
	if(buzzing)
		return
	buzzing = TRUE
	if(!length(GLOB.buzzing_lights))
		addtimer(CALLBACK(GLOBAL_PROC, GLOBAL_PROC_REF(buzz_lights)), LAMP_BUZZ_LOOP)
	GLOB.buzzing_lights += src

/obj/machinery/light/proc/stop_buzz()
	buzzing = FALSE
	GLOB.buzzing_lights -= src

/proc/buzz_lights()
	if(!length(GLOB.buzzing_lights))
		return //the next lamp to start it goes again
	addtimer(CALLBACK(GLOBAL_PROC, GLOBAL_PROC_REF(buzz_lights)), LAMP_BUZZ_LOOP)
	var/list/near = list()
	for(var/mob/M as anything in GLOB.player_list)
		var/turf/T = get_turf(M)
		if(T)
			near[M] = T
	if(!length(near))
		return
	for(var/obj/machinery/light/L as anything in GLOB.buzzing_lights)
		if(!L.on || L.status != LIGHT_OK)
			continue
		var/turf/source = get_turf(L)
		for(var/mob/M as anything in near)
			var/turf/T = near[M]
			if(T.z == source.z && get_dist(T, source) <= LAMP_BUZZ_RANGE)
				M.playsound_local(source, 'hippiestation/sound/effects/lamp_buzz.wav', 30, FALSE, falloff = 2, pressure_affected = FALSE)
