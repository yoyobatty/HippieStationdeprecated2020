// Telecomms signal quality and upkeep. A hurt network sounds hurt: every machine a radio signal passes adds noise for
// its damage, an EMP and being swamped with traffic, and the room's warmth adds noise to all of it. At the broadcaster the
// noise turns into static: light noise drops or crackles the odd word; heavy noise garbles the message and holds it back a
// second or two. Servers heat their room as they work (it's kept at 80 K, TCOMMS_ATMOS) and shut down past their limit
// until it's cooled; a channel whose server is down goes out unfiltered, with heavy static. The user's rulings, 2026-11-06.

#define TCOMMS_TEMP_SAFE 200 // K: below this the room's warmth adds nothing
#define TCOMMS_TEMP_LIMIT 373 // K: servers shut down above this...
#define TCOMMS_TEMP_RESTART 323 // K: ...and start again once it's back below this
#define TCOMMS_HEAT_BASE 500 // W a working server puts into its room: 8 servers take Box's 60-tile room from 80 K to static (200 K) in about an hour
#define TCOMMS_HEAT_PER_TRAFFIC 150 // W more for each unit of traffic it's handling, so a flood of messages heats it fast
#define TCOMMS_HEAT_DUMP_TICKS 15 // the heat goes into the air every this many process() ticks, so the room isn't kept awake in SSair
#define TCOMMS_NOISE_LIGHT 0.05 // below this, a signal goes out clean
#define TCOMMS_NOISE_HEAVY 0.5 // from here, garbled and delayed
#define TCOMMS_NOISE_NO_SERVER 0.6 // a channel that went past a server that's down

/obj/machinery/telecomms
	var/overheated = FALSE
	/// Joules made since the heat last went into the air
	var/heat_buffer = 0
	var/heat_ticks = 0

/obj/machinery/telecomms/proc/machine_temperature()
	var/turf/T = get_turf(src)
	var/datum/gas_mixture/air = T?.return_air()
	return air ? air.temperature : T20C

/// What this machine's own state adds to a signal through it: damage, an EMP, too much traffic
/obj/machinery/telecomms/proc/own_noise()
	. = 0
	if(max_integrity)
		. += (1 - obj_integrity / max_integrity) * 0.6
	if(stat & EMPED)
		. += 0.6
	. += clamp((traffic - 15) / 45, 0, 1) * 0.3
	return clamp(., 0, 1)

/// What the warmth of this machine's room adds
/obj/machinery/telecomms/proc/heat_noise()
	return clamp((machine_temperature() - TCOMMS_TEMP_SAFE) / (TCOMMS_TEMP_LIMIT - TCOMMS_TEMP_SAFE), 0, 1) * 0.6

/// Relays stand in outposts at room temperature, not the cold telecomms room, and only add their level to a signal
/obj/machinery/telecomms/relay/heat_noise()
	return 0

/// Adds this machine's noise to a signal, once per machine per signal
/obj/machinery/telecomms/proc/add_signal_noise(datum/signal/subspace/signal)
	if(!istype(signal) || !signal.data)
		return
	var/list/seen = signal.data["noise_seen"]
	if(!seen)
		seen = list()
		signal.data["noise_seen"] = seen
	var/key = REF(src)
	if(key in seen)
		return
	seen += key
	var/noise = own_noise()
	if(noise > 0)
		signal.data["noise"] = min(1, (signal.data["noise"] || 0) + noise)
	signal.data["noise_heat"] = max(signal.data["noise_heat"] || 0, heat_noise())

/obj/machinery/telecomms/relay_information(datum/signal/subspace/signal, filter, copysig, amount = 20)
	if(on)
		add_signal_noise(signal)
	return ..()

/obj/machinery/telecomms/relay_direct_information(datum/signal/signal, obj/machinery/telecomms/machine)
	if(on)
		add_signal_noise(signal)
	return ..()

// An EMP no longer switches a machine off (telecomunications.dm did): it stays up, with heavy static, as the user ruled.
// Overheating does switch it off.
/obj/machinery/telecomms/update_power()
	on = toggled && !(stat & (BROKEN|NOPOWER)) && !overheated

// A bus hands a signal straight to the hub when the channel's server is down (bus.dm): it goes out unfiltered
/obj/machinery/telecomms/hub/receive_information(datum/signal/signal, obj/machinery/telecomms/machine_from)
	var/datum/signal/subspace/S = signal
	if(istype(S) && S.data && istype(machine_from, /obj/machinery/telecomms/bus) && S.data["message"] && !S.data["noise_server"])
		S.data["noise_server"] = TRUE
		S.data["noise"] = min(1, (S.data["noise"] || 0) + TCOMMS_NOISE_NO_SERVER)
	return ..()

// The server marks the signals it handled, so the hub can tell which ones skipped it
/obj/machinery/telecomms/server/receive_information(datum/signal/subspace/vocal/signal, obj/machinery/telecomms/machine_from)
	if(istype(signal) && signal.data && on && is_freq_listening(signal))
		signal.data["noise_server"] = TRUE
	return ..()

GLOBAL_VAR(tcomms_last_broadcast) // for the self-test: list(message sent, noise, delay, message before the static, frequency)
GLOBAL_LIST_EMPTY(tcomms_recent_broadcasts) // the last 20 of those

// The noise turns into static once, before the broadcasters' duplicate check, so both broadcasters send the same words
/obj/machinery/telecomms/broadcaster/receive_information(datum/signal/subspace/signal, obj/machinery/telecomms/machine_from)
	if(istype(signal, /datum/signal/subspace/vocal) && signal.data && !signal.data["noise_applied"] && signal.data["message"] && !signal.data["reject"])
		if(on)
			add_signal_noise(signal)
		signal.data["noise_applied"] = TRUE
		var/original = signal.data["message"]
		var/noise = min(1, (signal.data["noise"] || 0) + (signal.data["noise_heat"] || 0))
		if(noise >= TCOMMS_NOISE_LIGHT)
			signal.data["message"] = tcomms_static(signal.data["message"], noise)
			if(noise >= TCOMMS_NOISE_HEAVY)
				signal.data["slow"] = (signal.data["slow"] || 0) + round(noise * 20) // up to 2 s
		var/list/record = list(signal.data["message"], noise, signal.data["slow"] || 0, original, signal.frequency)
		GLOB.tcomms_last_broadcast = record
		GLOB.tcomms_recent_broadcasts += list(record)
		if(GLOB.tcomms_recent_broadcasts.len > 20)
			GLOB.tcomms_recent_broadcasts.Cut(1, 2)
	return ..()

/// Static over a message: light noise crackles or drops the odd word, heavy noise garbles it
/proc/tcomms_static(message, noise)
	if(noise >= TCOMMS_NOISE_HEAVY)
		return Gibberish(message, round(noise * 70))
	var/list/words = splittext(message, " ")
	var/list/out = list()
	for(var/word in words)
		if(prob(noise * 35))
			if(prob(50))
				out += pick("*kzzt*", "*krrk*", "*bzzt*")
			continue // dropped
		out += word
	if(!out.len)
		return "*kzzt*"
	return out.Join(" ")

// Servers heat their room

/obj/machinery/telecomms/server/process()
	. = ..()
	if(on)
		heat_buffer += (TCOMMS_HEAT_BASE + TCOMMS_HEAT_PER_TRAFFIC * max(traffic, 0)) * (SSmachines.wait / 10)
	if(++heat_ticks >= TCOMMS_HEAT_DUMP_TICKS)
		heat_ticks = 0
		var/turf/open/T = get_turf(src)
		var/datum/gas_mixture/env = istype(T) ? T.return_air() : null
		if(env && heat_buffer > 0)
			var/capacity = env.heat_capacity()
			if(capacity > 0)
				env.temperature += heat_buffer / capacity
				air_update_turf(FALSE, FALSE) // as the space heater wakes its tile
		heat_buffer = 0
	var/temperature = machine_temperature()
	if(!overheated && temperature > TCOMMS_TEMP_LIMIT)
		overheated = TRUE
		visible_message("<span class='warning'>[src] shuts down with a whine as it overheats!</span>")
		playsound(src, 'sound/machines/buzz-two.ogg', 50, TRUE)
		update_power()
	else if(overheated && temperature < TCOMMS_TEMP_RESTART)
		overheated = FALSE
		visible_message("<span class='notice'>[src] hums back to life.</span>")
		update_power()

// The machine's own window shows its condition

/obj/machinery/telecomms/ui_data(mob/user)
	. = ..()
	.["temperature"] = round(machine_temperature(), 0.1)
	.["temp_safe"] = TCOMMS_TEMP_SAFE
	.["temp_limit"] = TCOMMS_TEMP_LIMIT
	.["integrity"] = max_integrity ? round(obj_integrity / max_integrity * 100) : 100
	.["emped"] = !!(stat & EMPED)
	.["overheated"] = overheated
	.["traffic"] = max(traffic, 0)
	.["noise"] = round(min(1, own_noise() + heat_noise()) * 100)

#undef TCOMMS_TEMP_SAFE
#undef TCOMMS_TEMP_LIMIT
#undef TCOMMS_TEMP_RESTART
#undef TCOMMS_HEAT_BASE
#undef TCOMMS_HEAT_PER_TRAFFIC
#undef TCOMMS_HEAT_DUMP_TICKS
#undef TCOMMS_NOISE_LIGHT
#undef TCOMMS_NOISE_HEAVY
#undef TCOMMS_NOISE_NO_SERVER
