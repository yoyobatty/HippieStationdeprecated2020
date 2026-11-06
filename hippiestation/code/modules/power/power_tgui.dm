// Power windows redone (tgui-next Apc.js, Smes.js, PowerMonitor.js): the raw figures behind the "1.35 kW" texts, so the windows
// can draw each channel's share of the load, an SMES's flow, and sort and filter the power monitor's areas.

/obj/machinery/power/apc
	ui_x = 500
	ui_y = 500

/obj/machinery/power/apc/ui_data(mob/user)
	. = ..()
	.["loadRaw"] = lastused_total
	.["channelLoads"] = list(lastused_equip, lastused_light, lastused_environ)
	// How long the cell keeps the area going at this load, if nothing charges it (the cell pays CELLRATE a watt each process)
	.["cellSeconds"] = (cell && lastused_total > 0) ? round(cell.charge / (GLOB.CELLRATE * lastused_total) * SSmachines.wait / 10) : null

/obj/machinery/power/smes
	ui_x = 420
	ui_y = 500

/obj/machinery/power/smes/ui_data(mob/user)
	. = ..()
	.["inputAvailableRaw"] = input_available
	.["outputUsedRaw"] = output_used
	// Roughly how long until it's full or empty at what goes in and out now (smes.dm's SMESRATE, 0.05 charge a watt each
	// process); unused output that comes back in restore() isn't counted, so emptying is the pessimistic side
	var/gain = (inputting ? min(input_level, input_available) : 0) - (outputting ? output_used : 0)
	var/seconds_a_process = SSmachines.wait / 10
	.["fullSeconds"] = gain > 0 ? round((capacity - charge) / (gain * 0.05) * seconds_a_process) : null
	.["emptySeconds"] = gain < 0 ? round(charge / (-gain * 0.05) * seconds_a_process) : null

// The power monitor's areas with the load as a number to sort by, whether there's a cell, and a reference to tell two
// areas of the same name apart. Shared by the console and the tablet program.
/datum/powernet/proc/tgui_power_areas()
	var/list/areas = list()
	for(var/obj/machinery/power/terminal/term in nodes)
		var/obj/machinery/power/apc/A = term.master
		if(!istype(A))
			continue
		areas += list(list(
			"name" = A.area.name,
			"ref" = REF(A),
			"charge" = A.cell ? A.cell.percent() : 0,
			"hasCell" = !!A.cell,
			"load" = DisplayPower(A.lastused_total),
			"loadRaw" = A.lastused_total,
			"charging" = A.charging,
			"eqp" = A.equipment,
			"lgt" = A.lighting,
			"env" = A.environ,
		))
	return areas

/obj/machinery/computer/monitor/ui_data()
	. = ..()
	var/datum/powernet/connected_powernet = get_powernet()
	if(!connected_powernet)
		return
	.["supplyRaw"] = connected_powernet.viewavail
	.["demandRaw"] = connected_powernet.viewload
	.["areas"] = connected_powernet.tgui_power_areas()

/datum/computer_file/program/power_monitor/ui_data()
	. = ..()
	var/datum/powernet/connected_powernet = get_powernet()
	if(!connected_powernet)
		return
	.["supplyRaw"] = connected_powernet.viewavail
	.["demandRaw"] = connected_powernet.viewload
	.["areas"] = connected_powernet.tgui_power_areas()
