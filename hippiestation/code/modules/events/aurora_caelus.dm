
/datum/round_event/aurora_caelus/announce(fake)
	priority_announce("[station_name()]: A harmless cloud of ions is approaching your station, and will exhaust their energy battering the hull. Nanotrasen has approved a short break for all employees to relax and observe this very rare event. During this time, starlight will be bright but gentle, shifting between quiet green and blue colors. Any staff who would like to view these lights for themselves may proceed to the area nearest to them with viewing ports to open space. We hope you enjoy the lights.",
	sound = 'sound/misc/notice2.ogg',
	sender_override = "Nanotrasen Meteorology Division")
	for(var/V in GLOB.player_list)
		var/mob/M = V
		if((M.client.prefs.toggles & SOUND_MIDI) && is_station_level(M.z))
			M.playsound_local(M, 'hippiestation/sound/ambience/auroraborealis.ogg', 20, FALSE, pressure_affected = FALSE)
	if(fake) // a False Alarm: the announcement only. Nothing would ever fade the lights or the sky back (end() never runs)
		return
	fade_space(fade_in = TRUE) //starlight brightens and turns green (code/modules/events/aurora_caelus.dm)
	fade_kitchen(fade_in = TRUE)
	SSparallax.aurora_caelus_sky(TRUE) //curtains of light over the sky (sky_weather.dm)

/datum/round_event/aurora_caelus/end()
	. = ..()
	SSparallax.aurora_caelus_sky(FALSE)

/// An admin stopping the event early: end() won't run, so the curtains go here
/datum/round_event/aurora_caelus/kill()
	. = ..()
	SSparallax.aurora_caelus_sky(FALSE)
