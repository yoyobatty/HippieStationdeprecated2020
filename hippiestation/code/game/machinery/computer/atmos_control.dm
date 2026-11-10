// hippie -- code/game/machinery/computer/atmos_control.dm rewritten whole (that file is out of the .dme). Gas tanks after tg's
// own rework (tg master 287fa83d, code/game/machinery/computer/atmos_computers/): a tank's gas sensor is its hub. It holds
// the tank's input injector and output vent, and the consoles find the sensor by its chamber and read and drive all three
// directly. Before, everything went by radio, tied to tags that only the mapped types carried: a console lagged two
// seconds behind, an injector or vent built to replace a broken one could never be linked, Reconnect only listed devices
// that were still linked, and a sensor couldn't be built at all.
//
// How a tank is put back together:
// - The gas sensor is made at the autolathe. Wrench it down on the floor and pick its chamber.
// - A sensor and an injector or vent in the same closed chamber (a sealed tank: not open to space, at most
//   ATMOS_CHAMBER_MAX_TILES tiles) link by themselves, whichever is put down last. So does a mapped injector or vent
//   wrenched back down from the fitting it dropped, with the sensor that had it.
// - A multitool links them anywhere on the same z: use it on one, then the other. Using it twice on a sensor clears its
//   links.
// - A tank console finds the closest sensor of its chamber on its z, so a rebuilt sensor shows up with no button pressed.
//   Reconnect points it at another chamber with a sensor.
//
// The mapped types and their vars are kept, so no map changes: a sensor's chamber comes from its old id_tag (o2_sensor is
// chamber o2), and at roundstart each sensor takes the devices its old tags name (o2_in, o2_out), or the ones its
// console's input_tag and output_tag name (the ruins). The injectors and vents keep their radio, which air alarms and the
// incinerator still use; the consoles and sensors no longer go through it.

#define CHAMBER_INLET 1
#define CHAMBER_OUTLET 2
/// The largest closed chamber that devices and sensors link up in by themselves
#define ATMOS_CHAMBER_MAX_TILES 64
/// vent_pump.dm's values, which it #undefs
#define CHAMBER_VENT_SIPHONING 0
#define CHAMBER_VENT_INT_BOUND 2

/// Every gas sensor
GLOBAL_LIST_EMPTY(air_sensors)
/// Every atmos monitoring and tank console
GLOBAL_LIST_EMPTY(atmos_air_controllers)
/// Mapped injectors and vents by their old radio tag: tag = list of weakrefs. A sensor finds its mapped devices here.
GLOBAL_LIST_EMPTY(atmos_tagged_ports)
/// Names of the chambers the maps brought that aren't the station's, by chamber id (from their consoles)
GLOBAL_LIST_EMPTY(atmos_chamber_names)
/// Every chamber that's had a sensor this round, as chamber id = TRUE: a monitoring console leaves out the ones its map never had
GLOBAL_LIST_EMPTY(atmos_chambers_seen)

/// The station's chambers, by chamber id (the old tags' prefixes)
GLOBAL_LIST_INIT(station_gas_chambers, list(
	"o2" = "Oxygen Supply",
	"n2" = "Nitrogen Supply",
	"co2" = "Carbon Dioxide Supply",
	"tox" = "Plasma Supply",
	"n2o" = "Nitrous Oxide Supply",
	"air" = "Mixed Air Supply",
	"mix" = "Mix Chamber",
	"incinerator" = "Incinerator Chamber",
	"toxinslab" = "Toxins Mixing Chamber",
))

/// The chamber an old sensor tag stands for: "o2_sensor" is "o2", "n2_sensor_bunker" is "n2_bunker"
/proc/atmos_chamber_from_tag(old_tag)
	if(!old_tag)
		return null
	return replacetext("[old_tag]", "_sensor", "")

/proc/atmos_chamber_name(chamber_id)
	if(!chamber_id)
		return "No chamber"
	return GLOB.station_gas_chambers[chamber_id] || GLOB.atmos_chamber_names[chamber_id] || "[chamber_id]"

/// The open turfs joined to T by air, as turf = TRUE, if they make a closed chamber: none open to space, at most
/// max_tiles of them. Null otherwise.
/proc/atmos_closed_chamber(turf/open/T, max_tiles = ATMOS_CHAMBER_MAX_TILES)
	if(!istype(T) || isspaceturf(T))
		return null
	var/list/found = list()
	found[T] = TRUE
	var/i = 1
	while(i <= length(found))
		var/turf/open/here = found[i++]
		for(var/turf/open/next in here.atmos_adjacent_turfs)
			if(found[next])
				continue
			if(isspaceturf(next) || length(found) >= max_tiles)
				return null
			found[next] = TRUE
	return found

/// The closest sensor of a chamber on a z level
/proc/atmos_find_chamber_sensor(chamber_id, atom/near) as /obj/machinery/air_sensor
	if(!chamber_id || !near)
		return null
	var/turf/here = get_turf(near)
	if(!here)
		return null
	var/best_dist = INFINITY
	for(var/obj/machinery/air_sensor/S as anything in GLOB.air_sensors)
		if(S.chamber_id != chamber_id || S.z != here.z)
			continue
		var/dist = get_dist(here, S)
		if(dist < best_dist)
			best_dist = dist
			. = S

/// Chambers a new sensor on this z can be for, as name = chamber id: the ones its consoles know that have lost their sensor
/// first, then the rest its consoles and sensors know, the station's (on a station z), and one per gas for a tank of anyone's
/// own making
/proc/atmos_sensor_chamber_choices(z)
	var/list/ids = list()
	for(var/obj/machinery/computer/atmos_control/C as anything in GLOB.atmos_air_controllers)
		if(C.z != z)
			continue
		for(var/id in C.chamber_ids())
			ids |= id
	var/list/sensed = list()
	for(var/obj/machinery/air_sensor/S as anything in GLOB.air_sensors)
		if(S.z == z && S.chamber_id)
			sensed[S.chamber_id] = TRUE
	var/list/ordered = list()
	for(var/id in ids)
		if(!sensed[id])
			ordered += id
	for(var/id in sensed)
		ordered |= id
	ordered |= ids
	if(is_station_level(z))
		for(var/id in GLOB.station_gas_chambers)
			ordered |= id
	var/list/choices = list()
	for(var/id in ordered)
		choices[atmos_chamber_name(id)] = id
	var/list/gas_names = GAS_META[META_GAS_NAME]
	var/list/gas_ids = GAS_META[META_GAS_ID]
	for(var/gas_path in gas_names)
		var/name = "[gas_names[gas_path]] Supply"
		if(!choices[name])
			choices[name] = "gas_[gas_ids[gas_path]]"
	return choices

/////////////////////////////////////////////////////////////
// GAS SENSOR (found in gas tanks)
/////////////////////////////////////////////////////////////

/obj/machinery/air_sensor
	name = "gas sensor"
	desc = "Reads a gas tank's air, and holds its input injector and output vent for the tank's console."
	icon = 'icons/obj/stationobjs.dmi'
	icon_state = "gsensor1"
	resistance_flags = FIRE_PROOF
	use_power = NO_POWER_USE

	/// Which chamber this is the sensor of
	var/chamber_id
	/// The input injector, as a weakref
	var/datum/weakref/inlet
	/// The output vent, as a weakref
	var/datum/weakref/outlet
	/// The old radio tags of the mapped injector and vent this chamber had, so one wrenched back down links again
	var/legacy_inlet_tag
	var/legacy_outlet_tag

	var/on = TRUE
	/// Old tag the maps give, which the chamber comes from
	var/id_tag
	/// Old radio frequency, which some maps still set: unused
	var/frequency = FREQ_ATMOS_STORAGE

/obj/machinery/air_sensor/atmos/toxin_tank
	name = "plasma tank gas sensor"
	id_tag = ATMOS_GAS_MONITOR_SENSOR_TOX
/obj/machinery/air_sensor/atmos/toxins_mixing_tank
	name = "toxins mixing gas sensor"
	id_tag = ATMOS_GAS_MONITOR_SENSOR_TOXINS_LAB
/obj/machinery/air_sensor/atmos/oxygen_tank
	name = "oxygen tank gas sensor"
	id_tag = ATMOS_GAS_MONITOR_SENSOR_O2
/obj/machinery/air_sensor/atmos/nitrogen_tank
	name = "nitrogen tank gas sensor"
	id_tag = ATMOS_GAS_MONITOR_SENSOR_N2
/obj/machinery/air_sensor/atmos/mix_tank
	name = "mix tank gas sensor"
	id_tag = ATMOS_GAS_MONITOR_SENSOR_MIX
/obj/machinery/air_sensor/atmos/nitrous_tank
	name = "nitrous oxide tank gas sensor"
	id_tag = ATMOS_GAS_MONITOR_SENSOR_N2O
/obj/machinery/air_sensor/atmos/air_tank
	name = "air mix tank gas sensor"
	id_tag = ATMOS_GAS_MONITOR_SENSOR_AIR
/obj/machinery/air_sensor/atmos/carbon_tank
	name = "carbon dioxide tank gas sensor"
	id_tag = ATMOS_GAS_MONITOR_SENSOR_CO2
/obj/machinery/air_sensor/atmos/incinerator_tank
	name = "incinerator chamber gas sensor"
	id_tag = ATMOS_GAS_MONITOR_SENSOR_INCINERATOR

/obj/machinery/air_sensor/Initialize(mapload, new_chamber_id)
	. = ..()
	GLOB.air_sensors += src
	if(new_chamber_id)
		chamber_id = new_chamber_id
		name = "gas sensor ([atmos_chamber_name(chamber_id)])"
	else if(!chamber_id)
		chamber_id = atmos_chamber_from_tag(id_tag)
	if(chamber_id)
		GLOB.atmos_chambers_seen[chamber_id] = TRUE

/obj/machinery/air_sensor/LateInitialize()
	. = ..()
	// the mapped devices of the old naming: o2_sensor's are o2_in and o2_out (consoles hand over theirs too)
	if(chamber_id)
		adopt_legacy_tags("[chamber_id]_in", "[chamber_id]_out")

/obj/machinery/air_sensor/Destroy()
	GLOB.air_sensors -= src
	inlet = null
	outlet = null
	return ..()

/obj/machinery/air_sensor/update_icon()
	icon_state = "gsensor[on]"

/obj/machinery/air_sensor/process()
	return PROCESS_KILL

/obj/machinery/air_sensor/examine(mob/user)
	. = ..()
	. += "<span class='notice'>Chamber: <b>[atmos_chamber_name(chamber_id)]</b>.</span>"
	var/obj/machinery/atmospherics/components/unary/in_port = get_port(CHAMBER_INLET)
	var/obj/machinery/atmospherics/components/unary/out_port = get_port(CHAMBER_OUTLET)
	. += "<span class='notice'>Input: [in_port ? "[in_port]" : "none"]. Output: [out_port ? "[out_port]" : "none"].</span>"
	. += "<span class='notice'>A multitool links an injector or vent to it. A wrench takes it down.</span>"

/obj/machinery/air_sensor/proc/get_port(kind)
	var/datum/weakref/ref = kind == CHAMBER_INLET ? inlet : outlet
	var/obj/machinery/atmospherics/components/unary/port = ref?.resolve()
	if(QDELETED(port))
		return null
	return port

/obj/machinery/air_sensor/proc/get_inlet()
	return get_port(CHAMBER_INLET)

/obj/machinery/air_sensor/proc/get_outlet()
	return get_port(CHAMBER_OUTLET)

/// Whether a device can be one of our ports, and which
/proc/atmos_port_kind(obj/machinery/atmospherics/components/unary/port)
	if(istype(port, /obj/machinery/atmospherics/components/unary/outlet_injector))
		return CHAMBER_INLET
	if(istype(port, /obj/machinery/atmospherics/components/unary/vent_pump))
		return CHAMBER_OUTLET
	return 0

/// The sensor a device is a port of, if any
/proc/atmos_port_sensor(obj/machinery/atmospherics/components/unary/port)
	var/kind = atmos_port_kind(port)
	if(!kind)
		return null
	for(var/obj/machinery/air_sensor/S as anything in GLOB.air_sensors)
		if(S.get_port(kind) == port)
			return S

/// Makes a device our input or output (by what it is), taking it off any other sensor. Returns the kind, or 0.
/obj/machinery/air_sensor/proc/link_port(obj/machinery/atmospherics/components/unary/port)
	var/kind = atmos_port_kind(port)
	if(!kind || QDELETED(port) || port.z != z)
		return 0
	for(var/obj/machinery/air_sensor/S as anything in GLOB.air_sensors)
		if(S != src && S.get_port(kind) == port)
			S.set_port(kind, null)
	set_port(kind, port)
	if(kind == CHAMBER_INLET)
		var/obj/machinery/atmospherics/components/unary/outlet_injector/injector = port
		if(!injector.id) // one built for the tank, not the mapped one: as fast as it goes, as the mapped ones are
			var/datum/gas_mixture/pipe_air = injector.airs[1]
			injector.volume_rate = min(MAX_TRANSFER_RATE, pipe_air.return_volume())
	else
		var/obj/machinery/atmospherics/components/unary/vent_pump/vent = port
		if(vent.pump_direction != CHAMBER_VENT_SIPHONING) // a room's vent: a tank's outlet siphons the tank into the pipe
			vent.pump_direction = CHAMBER_VENT_SIPHONING
			vent.pressure_checks = CHAMBER_VENT_INT_BOUND
			vent.internal_pressure_bound = MAX_OUTPUT_PRESSURE
			vent.external_pressure_bound = 0
		if(vent.frequency == FREQ_ATMOS_CONTROL && text2num(vent.id_tag) != null) // and the room's air alarm lets it go
			var/area/A = get_area(vent)
			A.air_vent_names -= vent.id_tag
			A.air_vent_info -= vent.id_tag
			SSradio.remove_object(vent, vent.frequency)
			vent.frequency = 0
			vent.radio_connection = null
	port.atmos_wake()
	port.update_icon()
	return kind

/obj/machinery/air_sensor/proc/set_port(kind, obj/machinery/atmospherics/components/unary/port)
	var/datum/weakref/ref = port ? WEAKREF(port) : null
	if(kind == CHAMBER_INLET)
		inlet = ref
	else
		outlet = ref

/// A port nobody else has: not some other live sensor's
/obj/machinery/air_sensor/proc/port_free(obj/machinery/atmospherics/components/unary/port)
	var/obj/machinery/air_sensor/owner = atmos_port_sensor(port)
	return !owner || owner == src

/// Takes the mapped devices these old tags name, for any port we don't have yet
/obj/machinery/air_sensor/proc/adopt_legacy_tags(in_tag, out_tag)
	if(in_tag && !legacy_inlet_tag && atmos_tagged_port(in_tag, CHAMBER_INLET, z))
		legacy_inlet_tag = in_tag
	if(out_tag && !legacy_outlet_tag && atmos_tagged_port(out_tag, CHAMBER_OUTLET, z))
		legacy_outlet_tag = out_tag
	for(var/kind in list(CHAMBER_INLET, CHAMBER_OUTLET))
		if(get_port(kind))
			continue
		var/obj/machinery/atmospherics/components/unary/port = atmos_tagged_port(kind == CHAMBER_INLET ? legacy_inlet_tag : legacy_outlet_tag, kind, z)
		if(port && port_free(port))
			link_port(port)

/// A mapped device by its old tag, on a z level
/proc/atmos_tagged_port(old_tag, kind, z)
	if(!old_tag)
		return null
	for(var/datum/weakref/ref as anything in GLOB.atmos_tagged_ports[old_tag])
		var/obj/machinery/atmospherics/components/unary/port = ref.resolve()
		if(!QDELETED(port) && port.z == z && atmos_port_kind(port) == kind)
			return port

/// For a sensor just put down: links what it can of its chamber's devices, and says what it found
/obj/machinery/air_sensor/proc/autolink(mob/user)
	// the old tags this chamber's consoles name, then the old naming's
	for(var/obj/machinery/computer/atmos_control/tank/C in GLOB.atmos_air_controllers)
		if(C.z == z && C.chamber_id == chamber_id)
			adopt_legacy_tags(C.input_tag, C.output_tag)
	adopt_legacy_tags("[chamber_id]_in", "[chamber_id]_out")
	// then whatever injector and vent share our closed chamber, the closest first
	var/list/chamber = atmos_closed_chamber(get_turf(src))
	if(chamber)
		for(var/kind in list(CHAMBER_INLET, CHAMBER_OUTLET))
			if(get_port(kind))
				continue
			var/best
			var/best_dist = INFINITY
			for(var/turf/T as anything in chamber)
				for(var/obj/machinery/atmospherics/components/unary/port in T)
					if(atmos_port_kind(port) != kind || !port_free(port))
						continue
					var/dist = get_dist(src, port)
					if(dist < best_dist)
						best_dist = dist
						best = port
			if(best)
				link_port(best)
	if(!user)
		return
	var/list/found = list()
	var/obj/machinery/atmospherics/components/unary/in_port = get_port(CHAMBER_INLET)
	var/obj/machinery/atmospherics/components/unary/out_port = get_port(CHAMBER_OUTLET)
	if(in_port)
		found += "[in_port]"
	if(out_port)
		found += "[out_port]"
	if(length(found))
		to_chat(user, "<span class='notice'>[src] links [english_list(found)].</span>")
	else
		to_chat(user, "<span class='notice'>[src] finds no injector or vent of its own. Link them with a multitool.</span>")

/obj/machinery/air_sensor/wrench_act(mob/living/user, obj/item/I)
	to_chat(user, "<span class='notice'>You start unfastening [src]...</span>")
	if(!I.use_tool(src, user, 20, volume = 50))
		return TRUE
	user.visible_message("[user] unfastens [src].", "<span class='notice'>You unfasten [src].</span>")
	var/obj/item/air_sensor/item = new(drop_location())
	transfer_fingerprints_to(item)
	qdel(src)
	return TRUE

/obj/machinery/air_sensor/multitool_act(mob/living/user, obj/item/I)
	if(!multitool_check_buffer(user, I))
		return TRUE
	var/obj/item/multitool/M = I
	if(M.buffer == src)
		if(!get_port(CHAMBER_INLET) && !get_port(CHAMBER_OUTLET))
			to_chat(user, "<span class='notice'>[src] has no links to clear.</span>")
			return TRUE
		if(tgui_alert(user, "Clear [src]'s links to its injector and vent?", "Gas sensor", list("Clear", "Cancel")) != "Clear")
			return TRUE
		if(QDELETED(src) || M.buffer != src || !user.canUseTopic(src, BE_CLOSE))
			return TRUE
		inlet = null
		outlet = null
		to_chat(user, "<span class='notice'>You clear [src]'s links.</span>")
		return TRUE
	var/obj/machinery/atmospherics/components/unary/port = M.buffer
	if(atmos_port_kind(port))
		if(port.z != z)
			to_chat(user, "<span class='warning'>[port] is too far away to link.</span>")
		else
			var/kind = link_port(port)
			to_chat(user, "<span class='notice'>You link [port] to [src] as its [kind == CHAMBER_INLET ? "input" : "output"].</span>")
	else
		to_chat(user, "<span class='notice'>You save [src] in [M]'s buffer.</span>")
	M.atmos_buffer(src)
	return TRUE

/// Puts a sensor, injector or vent in the buffer, and takes it out again if it's deleted, so the buffer doesn't keep it alive
/obj/item/multitool/proc/atmos_buffer(obj/machinery/thing)
	buffer = thing
	RegisterSignal(thing, COMSIG_PARENT_QDELETING, PROC_REF(atmos_buffer_deleted), override = TRUE)

/obj/item/multitool/proc/atmos_buffer_deleted(datum/source)
	SIGNAL_HANDLER
	if(buffer == source)
		buffer = null

/////////////////////////////////////////////////////////////
// THE INJECTORS AND VENTS' SIDE
/////////////////////////////////////////////////////////////

/// A mapped device with an old tag goes in the index, for its sensor to find
/obj/machinery/atmospherics/components/unary/proc/atmos_port_tag()
	return null

/obj/machinery/atmospherics/components/unary/outlet_injector/atmos_port_tag()
	return id

/obj/machinery/atmospherics/components/unary/vent_pump/atmos_port_tag()
	if(id_tag && text2num(id_tag) == null) // a room's vent has a number
		return id_tag

/obj/machinery/atmospherics/components/unary/outlet_injector/Initialize()
	. = ..()
	atmos_index_port()

/obj/machinery/atmospherics/components/unary/vent_pump/Initialize()
	. = ..()
	atmos_index_port()

/obj/machinery/atmospherics/components/unary/proc/atmos_index_port()
	var/port_tag = atmos_port_tag()
	if(!port_tag)
		return
	var/list/refs = GLOB.atmos_tagged_ports[port_tag]
	if(!refs)
		refs = GLOB.atmos_tagged_ports[port_tag] = list()
	for(var/i in length(refs) to 1 step -1) // drop the dead
		var/datum/weakref/ref = refs[i]
		if(!ref.resolve())
			refs.Cut(i, i + 1)
	refs += WEAKREF(src)

/obj/machinery/atmospherics/components/unary/outlet_injector/on_construction()
	. = ..()
	atmos_autolink()

/obj/machinery/atmospherics/components/unary/vent_pump/on_construction()
	. = ..()
	atmos_autolink()

/// Just wrenched down: back to the sensor that had a mapped device of our tag, or to the sensor of the closed chamber we're in
/obj/machinery/atmospherics/components/unary/proc/atmos_autolink()
	var/kind = atmos_port_kind(src)
	if(!kind || atmos_port_sensor(src))
		return
	var/obj/machinery/air_sensor/found
	var/port_tag = atmos_port_tag()
	if(port_tag)
		for(var/obj/machinery/air_sensor/S as anything in GLOB.air_sensors)
			if(S.z == z && (kind == CHAMBER_INLET ? S.legacy_inlet_tag : S.legacy_outlet_tag) == port_tag && !S.get_port(kind))
				found = S
				break
	if(!found)
		var/list/chamber = atmos_closed_chamber(get_turf(src))
		if(chamber)
			var/best_dist = INFINITY
			for(var/obj/machinery/air_sensor/S as anything in GLOB.air_sensors)
				if(!chamber[get_turf(S)] || S.get_port(kind))
					continue
				var/dist = get_dist(src, S)
				if(dist < best_dist)
					best_dist = dist
					found = S
	if(!found)
		return
	found.link_port(src)
	playsound(found, 'sound/machines/twobeep.ogg', 30, TRUE)
	visible_message("<span class='notice'>[found] links [src] as its [kind == CHAMBER_INLET ? "input" : "output"].</span>")

/obj/machinery/atmospherics/components/unary/outlet_injector/multitool_act(mob/living/user, obj/item/I)
	return atmos_port_multitool(user, I)

/obj/machinery/atmospherics/components/unary/vent_pump/multitool_act(mob/living/user, obj/item/I)
	return atmos_port_multitool(user, I)

/// A multitool holding a sensor links us to it; otherwise we go in its buffer
/obj/machinery/atmospherics/components/unary/proc/atmos_port_multitool(mob/living/user, obj/item/I)
	if(!multitool_check_buffer(user, I))
		return TRUE
	var/obj/item/multitool/M = I
	var/obj/machinery/air_sensor/S = M.buffer
	if(istype(S))
		if(S.z != z)
			to_chat(user, "<span class='warning'>[S] is too far away to link.</span>")
			return TRUE
		var/kind = S.link_port(src)
		to_chat(user, "<span class='notice'>You link [src] to [S] as its [kind == CHAMBER_INLET ? "input" : "output"].</span>")
		return TRUE // the sensor stays in the buffer, for the next device
	M.atmos_buffer(src)
	to_chat(user, "<span class='notice'>You save [src] in [M]'s buffer.</span>")
	return TRUE

/obj/machinery/atmospherics/components/unary/outlet_injector/examine(mob/user)
	. = ..()
	. += atmos_port_examine()

/obj/machinery/atmospherics/components/unary/vent_pump/examine(mob/user)
	. = ..()
	. += atmos_port_examine()

/obj/machinery/atmospherics/components/unary/proc/atmos_port_examine()
	var/obj/machinery/air_sensor/S = atmos_port_sensor(src)
	if(S)
		return "<span class='notice'>It's linked to [S].</span>"
	return "<span class='notice'>A multitool can link it to a gas sensor.</span>"

/////////////////////////////////////////////////////////////
// GAS SENSOR, NOT PUT DOWN
/////////////////////////////////////////////////////////////

/obj/item/air_sensor
	name = "gas sensor"
	desc = "A gas tank's sensor, not put down yet. Wrench it to the floor of a tank and pick its chamber."
	icon = 'icons/obj/stationobjs.dmi'
	icon_state = "gsensor0"
	w_class = WEIGHT_CLASS_SMALL
	materials = list(MAT_METAL = 500, MAT_GLASS = 100)

/obj/item/air_sensor/wrench_act(mob/living/user, obj/item/I)
	if(!isopenturf(loc))
		to_chat(user, "<span class='warning'>Put [src] down on the floor first.</span>")
		return TRUE
	if(locate(/obj/machinery/air_sensor) in loc)
		to_chat(user, "<span class='warning'>There's already a gas sensor here.</span>")
		return TRUE
	var/list/choices = atmos_sensor_chamber_choices(z)
	var/guess = atmos_chamber_here(loc)
	var/picked = tgui_input_list(user, "Chamber", "Gas sensor", choices, guess ? atmos_chamber_name(guess) : null)
	if(!picked || QDELETED(src) || !isopenturf(loc) || !user.canUseTopic(src, BE_CLOSE))
		return TRUE
	to_chat(user, "<span class='notice'>You start fastening [src]...</span>")
	if(!I.use_tool(src, user, 20, volume = 50) || !isopenturf(loc) || (locate(/obj/machinery/air_sensor) in loc))
		return TRUE
	var/obj/machinery/air_sensor/S = new(loc, choices[picked])
	transfer_fingerprints_to(S)
	user.visible_message("[user] fastens [S].", "<span class='notice'>You fasten [S].</span>")
	S.autolink(user)
	qdel(src)
	return TRUE

/// The chamber a closed chamber at T belongs to, going by the mapped injectors and vents in it: what its console names them
/// for, or else the old naming's (o2_in is the chamber o2's). Null if there's no telling.
/proc/atmos_chamber_here(turf/T)
	var/list/chamber = atmos_closed_chamber(T)
	if(!chamber)
		return null
	for(var/turf/here as anything in chamber)
		for(var/obj/machinery/atmospherics/components/unary/port in here)
			var/port_tag = port.atmos_port_tag()
			if(!port_tag)
				continue
			for(var/obj/machinery/computer/atmos_control/tank/C in GLOB.atmos_air_controllers)
				if(C.z == T.z && C.chamber_id && (C.input_tag == port_tag || C.output_tag == port_tag))
					return C.chamber_id
			for(var/suffix in list("_in", "_out"))
				if(findtext(port_tag, suffix, -length(suffix)))
					var/id = copytext(port_tag, 1, -length(suffix))
					if(GLOB.atmos_chambers_seen[id])
						return id

/datum/design/air_sensor
	name = "Gas Sensor"
	id = "air_sensor"
	build_type = AUTOLATHE
	materials = list(MAT_METAL = 500, MAT_GLASS = 100)
	build_path = /obj/item/air_sensor
	category = list("initial", "Construction")

/////////////////////////////////////////////////////////////
// GENERAL AIR CONTROL (a.k.a atmos computer)
/////////////////////////////////////////////////////////////

/obj/machinery/computer/atmos_control
	name = "atmospherics monitoring"
	desc = "Used to monitor the station's atmospherics sensors."
	icon_screen = "tank"
	icon_keyboard = "atmos_key"
	circuit = /obj/item/circuitboard/computer/atmos_control
	ui_x = 460
	ui_y = 700

	/// What the maps list: old sensor or meter tag = name. Sensors become chambers, tags ending _meter stay meters.
	var/list/sensors = list(
		ATMOS_GAS_MONITOR_SENSOR_N2 = "Nitrogen Tank",
		ATMOS_GAS_MONITOR_SENSOR_O2 = "Oxygen Tank",
		ATMOS_GAS_MONITOR_SENSOR_CO2 = "Carbon Dioxide Tank",
		ATMOS_GAS_MONITOR_SENSOR_TOX = "Plasma Tank",
		ATMOS_GAS_MONITOR_SENSOR_N2O = "Nitrous Oxide Tank",
		ATMOS_GAS_MONITOR_SENSOR_AIR = "Mixed Air Tank",
		ATMOS_GAS_MONITOR_SENSOR_MIX = "Mix Tank",
		ATMOS_GAS_MONITOR_LOOP_DISTRIBUTION = "Distribution Loop",
		ATMOS_GAS_MONITOR_LOOP_ATMOS_WASTE = "Atmos Waste Loop",
		ATMOS_GAS_MONITOR_SENSOR_INCINERATOR = "Incinerator Chamber",
		ATMOS_GAS_MONITOR_SENSOR_TOXINS_LAB = "Toxins Mixing Chamber"
	)
	/// Old radio frequency, which some maps still set: unused
	var/frequency = FREQ_ATMOS_STORAGE
	/// What we show, in order: chamber id or "meter:<tag>" = name
	var/list/entries
	/// Meters found, by entry key, as weakrefs
	var/list/meter_refs

	light_color = LIGHT_COLOR_CYAN

/obj/machinery/computer/atmos_control/Initialize()
	. = ..()
	GLOB.atmos_air_controllers += src
	entries = list()
	for(var/old_tag in sensors)
		if(findtext(old_tag, "_meter", -6))
			entries["meter:[old_tag]"] = sensors[old_tag]
		else
			var/id = atmos_chamber_from_tag(old_tag)
			entries[id] = GLOB.station_gas_chambers[id] || sensors[old_tag]

/obj/machinery/computer/atmos_control/Destroy()
	GLOB.atmos_air_controllers -= src
	return ..()

/// The chambers we show
/obj/machinery/computer/atmos_control/proc/chamber_ids()
	. = list()
	for(var/key in entries)
		if(!findtext(key, "meter:", 1, 7))
			. += key

/obj/machinery/computer/atmos_control/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, \
									datum/tgui/master_ui = null, datum/ui_state/state = GLOB.default_state)
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "atmos_control", name, ui_x, ui_y, master_ui, state)
		ui.open()

/// A mixture for the window
/obj/machinery/computer/atmos_control/proc/air_data(datum/gas_mixture/air)
	if(!air)
		return list("present" = FALSE)
	return list(
		"present" = TRUE,
		"pressure" = round(air.return_pressure(), 0.1),
		"temperature" = round(air.temperature, 0.1),
		"moles" = round(air.total_moles(), 0.1),
		"gases" = tgui_gas_list(air),
	)

/obj/machinery/computer/atmos_control/proc/find_meter(key)
	var/datum/weakref/ref = LAZYACCESS(meter_refs, key)
	var/obj/machinery/meter/M = ref?.resolve()
	if(!QDELETED(M))
		return M
	for(var/datum/weakref/meter_ref as anything in GLOB.atmos_tagged_meters[copytext(key, 7)])
		var/obj/machinery/meter/candidate = meter_ref.resolve()
		if(!QDELETED(candidate) && candidate.z == z)
			LAZYSET(meter_refs, key, WEAKREF(candidate))
			return candidate

/// Mapped meters by their old tag, for the monitoring consoles: tag = list of weakrefs
GLOBAL_LIST_EMPTY(atmos_tagged_meters)

/obj/machinery/meter/Initialize(mapload, new_piping_layer)
	. = ..()
	if(id_tag)
		LAZYADD(GLOB.atmos_tagged_meters[id_tag], WEAKREF(src))

/obj/machinery/computer/atmos_control/ui_data(mob/user)
	var/list/data = list()
	var/list/rows = list()
	var/list/shown = list()
	for(var/key in entries)
		var/list/row
		if(findtext(key, "meter:", 1, 7))
			if(!GLOB.atmos_tagged_meters[copytext(key, 7)])
				continue // never on this map
			var/obj/machinery/meter/M = find_meter(key)
			row = air_data(M?.target?.return_air())
			row["kind"] = "loop"
			row["missing"] = M ? "Meter on no pipe" : "No meter"
		else
			if(!GLOB.atmos_chambers_seen[key])
				continue // never on this map
			var/obj/machinery/air_sensor/S = atmos_find_chamber_sensor(key, src)
			row = air_data(S?.return_air())
			row["kind"] = "tank"
			row["missing"] = "No gas sensor"
			shown[key] = TRUE
		row["id"] = key
		row["name"] = entries[key]
		rows += list(row)
	// and chambers of anyone's own making, with a sensor on our z
	var/list/extra = list()
	for(var/obj/machinery/air_sensor/S as anything in GLOB.air_sensors)
		if(S.z != z || !S.chamber_id || shown[S.chamber_id])
			continue
		shown[S.chamber_id] = TRUE
		var/list/row = air_data(atmos_find_chamber_sensor(S.chamber_id, src)?.return_air())
		row["kind"] = "tank"
		row["id"] = S.chamber_id
		row["name"] = atmos_chamber_name(S.chamber_id)
		extra[row["name"]] = row
	for(var/name in sortList(extra))
		rows += list(extra[name])
	data["chambers"] = rows
	return data

/////////////////////////////////////////////////////////////
// LARGE TANK CONTROL
/////////////////////////////////////////////////////////////

/obj/machinery/computer/atmos_control/tank
	name = "gas tank control"
	desc = "Drives a gas tank's input injector and output vent, through the tank's gas sensor."
	circuit = /obj/item/circuitboard/computer/atmos_control/tank
	sensors = list()
	ui_x = 440
	ui_y = 360

	/// The chamber we control
	var/chamber_id
	/// Its sensor, as a weakref
	var/datum/weakref/sensor_ref
	/// Old radio tags of the chamber's mapped injector and vent, handed to its sensor at roundstart
	var/input_tag
	var/output_tag
	/// Only tg's debug verb reads these (the verb is Hippie's: admin_reports_tgui.dm)
	var/list/input_info
	var/list/output_info

/obj/machinery/computer/atmos_control/tank/oxygen_tank
	name = "Oxygen Supply Control"
	input_tag = ATMOS_GAS_MONITOR_INPUT_O2
	output_tag = ATMOS_GAS_MONITOR_OUTPUT_O2
	sensors = list(ATMOS_GAS_MONITOR_SENSOR_O2 = "Oxygen Tank")
	circuit = /obj/item/circuitboard/computer/atmos_control/tank/oxygen_tank

/obj/machinery/computer/atmos_control/tank/toxin_tank
	name = "Plasma Supply Control"
	input_tag = ATMOS_GAS_MONITOR_INPUT_TOX
	output_tag = ATMOS_GAS_MONITOR_OUTPUT_TOX
	sensors = list(ATMOS_GAS_MONITOR_SENSOR_TOX = "Plasma Tank")
	circuit = /obj/item/circuitboard/computer/atmos_control/tank/toxin_tank

/obj/machinery/computer/atmos_control/tank/air_tank
	name = "Mixed Air Supply Control"
	input_tag = ATMOS_GAS_MONITOR_INPUT_AIR
	output_tag = ATMOS_GAS_MONITOR_OUTPUT_AIR
	sensors = list(ATMOS_GAS_MONITOR_SENSOR_AIR = "Air Mix Tank")
	circuit = /obj/item/circuitboard/computer/atmos_control/tank/air_tank

/obj/machinery/computer/atmos_control/tank/mix_tank
	name = "Gas Mix Tank Control"
	input_tag = ATMOS_GAS_MONITOR_INPUT_MIX
	output_tag = ATMOS_GAS_MONITOR_OUTPUT_MIX
	sensors = list(ATMOS_GAS_MONITOR_SENSOR_MIX = "Gas Mix Tank")
	circuit = /obj/item/circuitboard/computer/atmos_control/tank/mix_tank

/obj/machinery/computer/atmos_control/tank/nitrous_tank
	name = "Nitrous Oxide Supply Control"
	input_tag = ATMOS_GAS_MONITOR_INPUT_N2O
	output_tag = ATMOS_GAS_MONITOR_OUTPUT_N2O
	sensors = list(ATMOS_GAS_MONITOR_SENSOR_N2O = "Nitrous Oxide Tank")
	circuit = /obj/item/circuitboard/computer/atmos_control/tank/nitrous_tank

/obj/machinery/computer/atmos_control/tank/nitrogen_tank
	name = "Nitrogen Supply Control"
	input_tag = ATMOS_GAS_MONITOR_INPUT_N2
	output_tag = ATMOS_GAS_MONITOR_OUTPUT_N2
	sensors = list(ATMOS_GAS_MONITOR_SENSOR_N2 = "Nitrogen Tank")
	circuit = /obj/item/circuitboard/computer/atmos_control/tank/nitrogen_tank

/obj/machinery/computer/atmos_control/tank/carbon_tank
	name = "Carbon Dioxide Supply Control"
	input_tag = ATMOS_GAS_MONITOR_INPUT_CO2
	output_tag = ATMOS_GAS_MONITOR_OUTPUT_CO2
	sensors = list(ATMOS_GAS_MONITOR_SENSOR_CO2 = "Carbon Dioxide Tank")
	circuit = /obj/item/circuitboard/computer/atmos_control/tank/carbon_tank

/obj/machinery/computer/atmos_control/tank/incinerator
	name = "Incinerator Air Control"
	input_tag = ATMOS_GAS_MONITOR_INPUT_INCINERATOR
	output_tag = ATMOS_GAS_MONITOR_OUTPUT_INCINERATOR
	sensors = list(ATMOS_GAS_MONITOR_SENSOR_INCINERATOR = "Incinerator Chamber")
	circuit = /obj/item/circuitboard/computer/atmos_control/tank/incinerator

/obj/machinery/computer/atmos_control/tank/Initialize()
	. = ..()
	entries = list()
	if(!chamber_id && length(sensors))
		chamber_id = atmos_chamber_from_tag(sensors[1])
	if(chamber_id && !GLOB.station_gas_chambers[chamber_id] && !GLOB.atmos_chamber_names[chamber_id])
		// a ruin's: "Nitrogen Supply Control" is the chamber "Nitrogen Supply"
		var/chamber_name = "[name]"
		if(findtext(chamber_name, " Control", -8))
			chamber_name = copytext(chamber_name, 1, -8)
		GLOB.atmos_chamber_names[chamber_id] = chamber_name

/obj/machinery/computer/atmos_control/tank/LateInitialize()
	. = ..()
	var/obj/machinery/air_sensor/S = find_sensor()
	S?.adopt_legacy_tags(input_tag, output_tag)

/obj/machinery/computer/atmos_control/tank/chamber_ids()
	return chamber_id ? list(chamber_id) : list()

/// Our chamber's sensor: the one we had, or else the closest of our chamber on our z
/obj/machinery/computer/atmos_control/tank/proc/find_sensor()
	var/obj/machinery/air_sensor/S = sensor_ref?.resolve()
	if(!QDELETED(S) && S.chamber_id == chamber_id && S.z == z)
		return S
	S = atmos_find_chamber_sensor(chamber_id, src)
	sensor_ref = S ? WEAKREF(S) : null
	return S

/// What an injector or vent is up to, for the window
/obj/machinery/computer/atmos_control/tank/proc/port_state(obj/machinery/atmospherics/components/unary/port)
	if(port.stat & BROKEN)
		return "Broken"
	if(port.stat & NOPOWER)
		return "No power"
	var/obj/machinery/atmospherics/components/unary/vent_pump/vent = port
	if(istype(vent) && vent.welded)
		return "Welded"
	return null

/obj/machinery/computer/atmos_control/tank/ui_data(mob/user)
	var/list/data = list()
	data["tank"] = TRUE
	data["chamber"] = chamber_id ? atmos_chamber_name(chamber_id) : null
	var/obj/machinery/air_sensor/S = find_sensor()
	data["sensor"] = !!S
	data["air"] = air_data(S?.return_air())
	data["maxRate"] = MAX_TRANSFER_RATE
	data["maxPressure"] = MAX_OUTPUT_PRESSURE
	var/obj/machinery/atmospherics/components/unary/outlet_injector/injector = S?.get_port(CHAMBER_INLET)
	if(injector)
		data["input"] = list(
			"name" = "[injector]",
			"on" = !!injector.on,
			"rate" = round(injector.volume_rate, 0.1),
			"state" = port_state(injector),
		)
	var/obj/machinery/atmospherics/components/unary/vent_pump/vent = S?.get_port(CHAMBER_OUTLET)
	if(vent)
		data["output"] = list(
			"name" = "[vent]",
			"on" = !!vent.on,
			"pressure" = round(vent.internal_pressure_bound, 0.1),
			"state" = port_state(vent),
		)
	return data

/obj/machinery/computer/atmos_control/tank/ui_act(action, params)
	if(..())
		return
	if(action == "reconnect")
		reconnect(usr)
		return TRUE
	var/obj/machinery/air_sensor/S = find_sensor()
	if(!S)
		return
	switch(action)
		if("input", "rate")
			var/obj/machinery/atmospherics/components/unary/outlet_injector/injector = S.get_port(CHAMBER_INLET)
			if(!injector)
				return
			if(action == "input")
				injector.on = !injector.on
				injector.investigate_log("was turned [injector.on ? "on" : "off"] by [key_name(usr)] at [src]", INVESTIGATE_ATMOS)
			else
				var/rate = params["rate"] == "max" ? MAX_TRANSFER_RATE : text2num(params["rate"])
				if(isnull(rate))
					return
				var/datum/gas_mixture/pipe_air = injector.airs[1]
				injector.volume_rate = clamp(rate, 0, min(MAX_TRANSFER_RATE, pipe_air.return_volume()))
				injector.investigate_log("was set to [injector.volume_rate] L/s by [key_name(usr)] at [src]", INVESTIGATE_ATMOS)
			injector.atmos_wake()
			injector.update_icon()
			return TRUE
		if("output", "pressure")
			var/obj/machinery/atmospherics/components/unary/vent_pump/vent = S.get_port(CHAMBER_OUTLET)
			if(!vent)
				return
			if(action == "output")
				vent.on = !vent.on
				vent.investigate_log("was turned [vent.on ? "on" : "off"] by [key_name(usr)] at [src]", INVESTIGATE_ATMOS)
			else
				var/pressure = params["pressure"] == "max" ? MAX_OUTPUT_PRESSURE : text2num(params["pressure"])
				if(isnull(pressure))
					return
				vent.internal_pressure_bound = clamp(pressure, 0, MAX_OUTPUT_PRESSURE)
				vent.investigate_log("output pressure was set to [vent.internal_pressure_bound] kPa by [key_name(usr)] at [src]", INVESTIGATE_ATMOS)
			vent.atmos_wake()
			vent.update_icon()
			return TRUE

/// Points us at another chamber with a sensor on our z
/obj/machinery/computer/atmos_control/tank/proc/reconnect(mob/user)
	var/list/choices = list()
	for(var/obj/machinery/air_sensor/S as anything in GLOB.air_sensors)
		if(S.z == z && S.chamber_id)
			choices[atmos_chamber_name(S.chamber_id)] = S.chamber_id
	if(!length(choices))
		to_chat(user, "<span class='warning'>[src] finds no gas sensors.</span>")
		return
	var/picked = tgui_input_list(user, "Chamber", "Reconnect", sortList(choices), chamber_id ? atmos_chamber_name(chamber_id) : null)
	if(!picked || !choices[picked] || QDELETED(src) || !user.canUseTopic(src, !issilicon(user)))
		return
	chamber_id = choices[picked]
	sensor_ref = null
	name = "[picked] Control"
	SStgui.update_uis(src)

#undef CHAMBER_INLET
#undef CHAMBER_OUTLET
#undef ATMOS_CHAMBER_MAX_TILES
#undef CHAMBER_VENT_SIPHONING
#undef CHAMBER_VENT_INT_BOUND
