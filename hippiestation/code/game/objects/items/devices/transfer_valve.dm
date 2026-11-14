/obj/item/transfer_valve
	w_class = WEIGHT_CLASS_NORMAL

/// Ready-made max-cap bombs (admin spawn): hot plasma and tritium on cold oxygen already on the valve, and the trigger fitted and
/// secured the way a player attaches one, so it's armed and set up the same (timer at its 5 s, health sensor scanning, and so on).
/// The mix comes to light 88-100 uncapped (tools/bot_gym/run_ttv_bench.sh BENCH=maxcap), so it maxes at any BOMBCAP the config sets.
/// Plasma and oxygen alone top out at light 20.
/obj/item/transfer_valve/maxcap
	var/list/hot_gases = list(/datum/gas/plasma = 1, /datum/gas/tritium = 1)
	var/hot_kelvin = 3000
	var/hot_kpa = 2533
	var/oxygen_kelvin = 73
	var/oxygen_kpa = 2533
	/// The assembly fitted to the valve, or none: opened by hand
	var/device_type

/obj/item/transfer_valve/maxcap/Initialize()
	. = ..()
	tank_one = new /obj/item/tank/internals/plasma(src)
	maxcap_fill(tank_one, hot_gases, hot_kelvin, hot_kpa)
	tank_two = new /obj/item/tank/internals/oxygen(src)
	maxcap_fill(tank_two, list(/datum/gas/oxygen = 1), oxygen_kelvin, oxygen_kpa)
	if(device_type)
		var/obj/item/assembly/A = new device_type(src)
		A.secured = FALSE
		A.holder = src
		attached_device = A
		A.toggle_secure()
	update_icon()

/// The tank's air made `kpa` at `kelvin`, of the gases in the shares given
/obj/item/transfer_valve/maxcap/proc/maxcap_fill(obj/item/tank/T, list/shares, kelvin, kpa)
	var/datum/gas_mixture/air = T.air_contents
	for(var/other in air.moles)
		air.moles[other] = 0
	air.temperature = kelvin
	var/total = kpa * air.volume / (R_IDEAL_GAS_EQUATION * kelvin)
	var/sum = 0
	for(var/gas in shares)
		sum += shares[gas]
	for(var/gas in shares)
		air.assert_gas(gas)
		air.moles[gas] = total * shares[gas] / sum

/obj/item/transfer_valve/maxcap/timer
	device_type = /obj/item/assembly/timer

/obj/item/transfer_valve/maxcap/signaler
	device_type = /obj/item/assembly/signaler

/obj/item/transfer_valve/maxcap/health
	device_type = /obj/item/assembly/health

/obj/item/transfer_valve/maxcap/proximity
	device_type = /obj/item/assembly/prox_sensor

/obj/item/transfer_valve/maxcap/voice
	device_type = /obj/item/assembly/voice

/obj/item/transfer_valve/maxcap/infrared
	device_type = /obj/item/assembly/infra

/obj/item/transfer_valve/maxcap/mousetrap
	device_type = /obj/item/assembly/mousetrap
