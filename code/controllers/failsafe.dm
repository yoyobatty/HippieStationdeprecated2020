 /**
  * Failsafe
  *
  * Pretty much pokes the MC to make sure it's still alive.
 **/

GLOBAL_REAL(Failsafe, /datum/controller/failsafe)

/datum/controller/failsafe // This thing pretty much just keeps poking the master controller
	name = "Failsafe"

	// The length of time to check on the MC (in deciseconds).
	// Set to 0 to disable.
	var/processing_interval = 20
	// The alert level. For every failed poke, we drop a DEFCON level. Once we hit DEFCON 1, restart the MC.
	var/defcon = 5
	//the world.time of the last check, so the mc can restart US if we hang.
	//	(Real friends look out for *eachother*)
	var/lasttick = 0

	// Track the MC iteration to make sure its still on track.
	var/master_iteration = 0
	var/running = TRUE

/datum/controller/failsafe/New()
	// Highlander-style: there can only be one! Kill off the old and replace it with the new.
	if(Failsafe != src)
		if(istype(Failsafe))
			qdel(Failsafe)
	Failsafe = src
	Initialize()

/datum/controller/failsafe/Initialize()
	set waitfor = 0
	Failsafe.Loop()
	if(!QDELETED(src))
		qdel(src) //when Loop() returns, we delete ourselves and let the mc recreate us

/datum/controller/failsafe/Destroy()
	running = FALSE
	..()
	return QDEL_HINT_HARDDEL_NOW

/datum/controller/failsafe/proc/Loop()
	while(running)
		lasttick = world.time
		// hippie -- a runtime in here used to end the Failsafe; only the MC brings it back, so with the MC down too nothing did
		try
			poke()
		catch(var/exception/e)
			log_world("Failsafe: [e] at [e.file]:[e.line]")
		// hippie -- the watchdog (mc_watchdog.dm) and the Failsafe each restart the other if it stops
		if(!MCWatchdog || MCWatchdog.lasttick + 5 SECONDS < world.time)
			new /datum/mc_watchdog()
		if (defcon <= 1)
			sleep(processing_interval*2)
		else if (processing_interval > 0)
			sleep(processing_interval)
		else
			sleep(initial(processing_interval))

/datum/controller/failsafe/proc/poke()
	if(!Master)
		// Replace the missing Master! This should never, ever happen.
		new /datum/controller/master()
	// Only poke it if overrides are not in effect.
	if(processing_interval > 0)
		if(Master.processing && Master.iteration)
			// hippie -- the MC's Loop() is gone (ported from tg): restart it now rather than counting down from DEFCON 5
			if (defcon > 1 && (!Master.stack_end_detector || !Master.stack_end_detector.check()))
				log_world("Failsafe: the MC's loop has exited, restarting it.")
				mc_watchdog_alert("The MC's loop stopped unexpectedly. Restarting it now.")
				var/rtn = Recreate_MC()
				if(rtn > 0)
					defcon = 4
					master_iteration = 0
					to_chat(GLOB.admins, "<span class='adminnotice'>MC restarted successfully</span>")
				else
					defcon = 0 // try again each pass
				return
			// Check if processing is done yet.
			if(Master.iteration == master_iteration)
				switch(defcon)
					if(4,5)
						--defcon
					if(3)
						message_admins("<span class='adminnotice'>Notice: DEFCON [defcon_pretty()]. The Master Controller has not fired in the last [(5-defcon) * processing_interval] ticks.</span>")
						--defcon
					if(2)
						to_chat(GLOB.admins, "<span class='boldannounce'>Warning: DEFCON [defcon_pretty()]. The Master Controller has not fired in the last [(5-defcon) * processing_interval] ticks. Automatic restart in [processing_interval] ticks.</span>")
						--defcon
					if(1)

						to_chat(GLOB.admins, "<span class='boldannounce'>Warning: DEFCON [defcon_pretty()]. The Master Controller has still not fired within the last [(5-defcon) * processing_interval] ticks. Killing and restarting...</span>")
						mc_watchdog_alert("The MC hasn't run for [round((5-defcon) * processing_interval / 10)] s. Restarting it.") // hippie
						--defcon
						var/rtn = Recreate_MC()
						if(rtn > 0)
							defcon = 4
							master_iteration = 0
							to_chat(GLOB.admins, "<span class='adminnotice'>MC restarted successfully</span>")
						else if(rtn < 0)
							log_game("FailSafe: Could not restart MC, runtime encountered. Entering defcon 0")
							to_chat(GLOB.admins, "<span class='boldannounce'>ERROR: DEFCON [defcon_pretty()]. Could not restart MC, runtime encountered. I will silently keep retrying.</span>")
						//if the return number was 0, it just means the mc was restarted too recently, and it just needs some time before we try again
						//no need to handle that specially when defcon 0 can handle it
					if(0) //DEFCON 0! (mc failed to restart)
						var/rtn = Recreate_MC()
						if(rtn > 0)
							defcon = 4
							master_iteration = 0
							to_chat(GLOB.admins, "<span class='adminnotice'>MC restarted successfully</span>")
			else
				defcon = min(defcon + 1,5)
				master_iteration = Master.iteration
	else
		defcon = 5

/datum/controller/failsafe/proc/defcon_pretty()
	return defcon

/datum/controller/failsafe/stat_entry()
	if(!statclick)
		statclick = new/obj/effect/statclick/debug(null, "Initializing...", src)

	stat("Failsafe Controller:", statclick.update("Defcon: [defcon_pretty()] (Interval: [Failsafe.processing_interval] | Iteration: [Failsafe.master_iteration])"))
