// More atmos machines go idle (idle_machines.dm): a gas pump that's off or unpowered, a connector with nothing on it, and a
// portable scrubber or pump that's off. On the station that's ~150 machines that ran every atmos tick, every one of them to
// find out it was still off (63 connectors, 53 pumps, 34 portables; tools/atmos_ab atmos_ab_awake()). Each now goes idle and
// is run again when its settings could have changed: anything that redraws it (every toggle does: tgui, Ctrl/Alt-click,
// radio), a tgui action, a radio signal, an EMP, its power changing, or a portable connecting to or leaving its connector.
// The 20 s recheck still backs that up. -params "atmos-idle-more=off" runs them every tick as before.

/datum/controller/subsystem/air
	/// The machines above go idle when there's nothing for them to do
	var/atmos_idle_more = TRUE

/datum/controller/subsystem/air/Initialize(timeofday)
	atmos_idle_more = world.params["atmos-idle-more"] != "off"
	return ..()

// Gas pump: off or unpowered

/obj/machinery/atmospherics/components/binary/pump/process_atmos()
	if(SSair.atmos_idle_more && (!on || !is_operational()))
		return ATMOS_IDLE
	return ..()

/obj/machinery/atmospherics/components/binary/pump/update_icon()
	. = ..()
	atmos_wake()

/obj/machinery/atmospherics/components/binary/pump/ui_act(action, params)
	. = ..()
	atmos_wake()

/obj/machinery/atmospherics/components/binary/pump/receive_signal(datum/signal/signal)
	. = ..()
	atmos_wake()

// Connector: nothing on it. A portable connecting or leaving wakes it (portable_atmospherics connect()/disconnect()).

/obj/machinery/atmospherics/components/unary/portables_connector/process_atmos()
	if(SSair.atmos_idle_more && !connected_device)
		return ATMOS_IDLE
	return ..()

/obj/machinery/portable_atmospherics/connect(obj/machinery/atmospherics/components/unary/portables_connector/new_port)
	. = ..()
	new_port?.atmos_wake()

/obj/machinery/portable_atmospherics/disconnect()
	var/obj/machinery/atmospherics/components/unary/portables_connector/old_port = connected_port
	. = ..()
	old_port?.atmos_wake()

// Portable scrubber and pump: off. What's inside still reacts while it's off and not on a connector (the pipes do that when
// it is), so it only idles once nothing in it reacts.

/obj/machinery/portable_atmospherics/scrubber/process_atmos()
	if(SSair.atmos_idle_more && !on)
		if(!connected_port && air_contents.react(src))
			return
		return ATMOS_IDLE
	return ..()

/obj/machinery/portable_atmospherics/pump/process_atmos()
	if(SSair.atmos_idle_more && !on)
		if(!connected_port && air_contents.react(src))
			return
		pump.airs[1] = null
		pump.airs[2] = null
		return ATMOS_IDLE
	return ..()

/obj/machinery/portable_atmospherics/update_icon()
	. = ..()
	atmos_wake()

/obj/machinery/portable_atmospherics/ui_act(action, params)
	. = ..()
	atmos_wake()

// Any atmos machine: an EMP, or its power changing

/obj/machinery/atmospherics/emp_act(severity)
	. = ..()
	atmos_wake()

/obj/machinery/portable_atmospherics/emp_act(severity)
	. = ..()
	atmos_wake()

/obj/machinery/atmospherics/power_change()
	. = ..()
	atmos_wake()
