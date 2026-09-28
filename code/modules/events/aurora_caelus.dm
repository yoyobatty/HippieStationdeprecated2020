/datum/round_event_control/aurora_caelus
	name = "Aurora Caelus"
	typepath = /datum/round_event/aurora_caelus
	max_occurrences = 1
	weight = 1
	earliest_start = 5 MINUTES

/datum/round_event_control/aurora_caelus/canSpawnEvent(players, gamemode)
	if(!CONFIG_GET(flag/starlight))
		return FALSE
	return ..()

// Recolors starlight through set_starlight() (space.dm), as tgstation does - only the space tiles that are actually lit
// (GLOB.starlight). This used to set_light() every space turf in every starlit area, /area/space included: hundreds
// of thousands of new light sources.
/datum/round_event/aurora_caelus
	announceWhen = 1
	startWhen = 21
	endWhen = 80
	var/list/aurora_colors = list("#A2FF80", "#A2FF8B", "#A2FF96", "#A2FFA5", "#A2FFB6", "#A2FFC7", "#A2FFDE", "#A2FFEE")
	var/aurora_progress = 0 //this cycles from 1 to 8, slowly changing colors from gentle green to gentle blue

/datum/round_event/aurora_caelus/announce()
	priority_announce("[station_name()]: A harmless cloud of ions is approaching your station, and will exhaust their energy battering the hull. Nanotrasen has approved a short break for all employees to relax and observe this very rare event. During this time, starlight will be bright but gentle, shifting between quiet green and blue colors. Any staff who would like to view these lights for themselves may proceed to the area nearest to them with viewing ports to open space. We hope you enjoy the lights.",
	sound = 'sound/misc/notice2.ogg',
	sender_override = "Nanotrasen Meteorology Division")
	for(var/V in GLOB.player_list)
		var/mob/M = V
		if((M.client.prefs.toggles & SOUND_MIDI) && is_station_level(M.z))
			M.playsound_local(M, 'sound/ambience/aurora_caelus.ogg', 20, FALSE, pressure_affected = FALSE)
	fade_space(fade_in = TRUE)
	fade_kitchen(fade_in = TRUE)

/datum/round_event/aurora_caelus/tick()
	if(activeFor % 8 != 0 || aurora_progress >= length(aurora_colors))
		return
	aurora_progress++
	var/aurora_color = aurora_colors[aurora_progress]
	set_starlight(aurora_color)
	for(var/turf/open/kitchen_floor in get_area_turfs(/area/crew_quarters/kitchen))
		kitchen_floor.set_light(l_color = aurora_color)

/datum/round_event/aurora_caelus/end()
	fade_space()
	fade_kitchen()
	priority_announce("The aurora caelus event is now ending. Starlight conditions will slowly return to normal. When this has concluded, please return to your workplace and continue work as normal. Have a pleasant shift, [station_name()], and thank you for watching with us.",
	sound = 'sound/misc/notice2.ogg',
	sender_override = "Nanotrasen Meteorology Division")

/datum/round_event/aurora_caelus/proc/fade_space(fade_in = FALSE)
	set waitfor = FALSE
	var/start_color = aurora_colors[length(aurora_colors)]
	var/start_range = GLOB.starlight_range * 1.75
	var/start_power = GLOB.starlight_power * 0.6
	var/end_color = GLOB.base_starlight_color
	var/end_range = GLOB.starlight_range
	var/end_power = GLOB.starlight_power
	if(fade_in)
		end_color = aurora_colors[1]
		end_range = start_range
		end_power = start_power
		start_color = GLOB.base_starlight_color
		start_range = GLOB.starlight_range
		start_power = GLOB.starlight_power

	for(var/i in 1 to 5)
		set_starlight(gradient(start_color, end_color, index = i/5), LERP(start_range, end_range, i/5), LERP(start_power, end_power, i/5))
		sleep(8 SECONDS)
	set_starlight(end_color, end_range, end_power)

/datum/round_event/aurora_caelus/proc/fade_kitchen(fade_in = FALSE)
	set waitfor = FALSE
	var/start_color = aurora_colors[length(aurora_colors)]
	var/start_range = 1
	var/start_power = 0.75
	var/end_color = COLOR_BLACK
	var/end_range = 0.5
	var/end_power = 0
	if(fade_in)
		end_color = aurora_colors[1]
		end_range = start_range
		end_power = start_power
		start_color = COLOR_BLACK
		start_range = 0.5
		start_power = 0

	var/list/kitchen = get_area_turfs(/area/crew_quarters/kitchen)
	for(var/i in 1 to 5)
		var/walked_color = gradient(start_color, end_color, index = i/5)
		for(var/turf/open/kitchen_floor in kitchen)
			kitchen_floor.set_light(LERP(start_range, end_range, i/5), LERP(start_power, end_power, i/5), walked_color)
		sleep(8 SECONDS)
	for(var/turf/open/kitchen_floor in kitchen)
		kitchen_floor.set_light(end_range, end_power, end_color)
