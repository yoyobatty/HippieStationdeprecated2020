// hippie -- the thermoelectric generator's window is tgui: its output, and each loop's inlet and outlet. It was only ever a
// readout, and still is.

/obj/machinery/power/generator/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, datum/tgui/master_ui = null, datum/ui_state/state = GLOB.default_state)
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "thermoelectric_generator", name, 420, 220, master_ui, state)
		ui.open()

/obj/machinery/power/generator/ui_data(mob/user)
	var/list/data = list()
	data["connected"] = !!powernet
	data["output"] = DisplayPower(lastgenlev)
	data["output_level"] = lastgenlev
	data["cold"] = generator_loop(cold_circ)
	data["hot"] = generator_loop(hot_circ)
	return data

/// A circulator's inlet and outlet, or null without one
/obj/machinery/power/generator/proc/generator_loop(obj/machinery/atmospherics/components/binary/circulator/circ)
	if(!circ)
		return null
	var/datum/gas_mixture/outlet = circ.airs[1]
	var/datum/gas_mixture/inlet = circ.airs[2]
	return list(
		"inlet_temperature" = round(inlet.temperature, 0.1),
		"inlet_pressure" = round(inlet.return_pressure(), 0.1),
		"outlet_temperature" = round(outlet.temperature, 0.1),
		"outlet_pressure" = round(outlet.return_pressure(), 0.1),
		"flowing" = circ.last_pressure_delta > 0,
	)
