/obj/machinery/computer/pod
	icon = 'icons/obj/airlock_machines.dmi'

/// Off the launch controls round it when it's gone: their `connected` kept a destroyed mass driver for good, a hard delete
/// (the chapel's Holy Driver in a Bot Shift)
/obj/machinery/mass_driver/Destroy()
	for(var/obj/machinery/computer/pod/P in GLOB.machines)
		if(P.connected == src)
			P.connected = null
	return ..()