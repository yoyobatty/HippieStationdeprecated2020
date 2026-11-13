// The meta book (the plan's foundation/meta_book.dm, M4): the numbers a player who knows the game fights by, worked out from the game's
// own items rather than written down. What a weapon does a second, in a hand or a gun; how long somebody takes to put down, through their
// armour. Combat (apex/combat.dm) and the tactics (tactics.dm) read it.

/// Damage a second from swinging I (or a fist): its force each melee click (CLICK_CD_MELEE)
/proc/bot_melee_dps(obj/item/I)
	var/force = I ? bot_weapon_force(I) : 0
	if(force < 5)
		force = 5 //a punch, about
	return force / (CLICK_CD_MELEE / 10)

/// The shot a gun fires now or can be switched to that does the most damage: list(projectile type, damage, kind), kind "lethal" or "stun"
/proc/bot_gun_best_shot(obj/item/gun/G)
	var/list/shots = list()
	var/obj/item/gun/energy/E = G
	if(istype(E))
		if(E.cell)
			for(var/obj/item/ammo_casing/energy/C in E.ammo_type)
				if(E.cell.charge >= C.e_cost)
					shots += C.projectile_type
	else
		var/obj/item/gun/ballistic/B = G
		if(istype(B) && B.can_shoot())
			var/obj/item/ammo_casing/C = B.chambered
			if(!C?.BB && B.magazine && length(B.magazine.stored_ammo))
				C = B.magazine.stored_ammo[1]
			if(C)
				shots += C.projectile_type
	var/best
	var/best_damage = 0
	var/best_kind
	for(var/path in shots)
		if(!ispath(path, /obj/item/projectile))
			continue
		var/obj/item/projectile/P = path
		var/damage = initial(P.nodamage) ? 0 : initial(P.damage)
		var/kind = (initial(P.damage_type) == BRUTE || initial(P.damage_type) == BURN) ? "lethal" : "stun"
		if(kind == "stun")
			damage = max(damage, initial(P.stamina), 1)
		if(!best || (kind == "lethal" && best_kind != "lethal") || (kind == best_kind && damage > best_damage))
			best = path
			best_damage = damage
			best_kind = kind
	return best ? list(best, best_damage, best_kind) : null

/// Damage a second from a gun's best lethal shot, 0 for none
/proc/bot_gun_dps(obj/item/gun/G)
	var/list/shot = bot_gun_best_shot(G)
	if(!shot || shot[3] != "lethal")
		return 0
	var/delay = max(G.fire_delay, CLICK_CD_RANGE) / 10
	return shot[2] * max(G.burst_size, 1) / max(delay, 0.4)

/// What somebody's got to hurt with: list(melee damage a second, ranged damage a second, ranged stun)
/proc/bot_threat_of(mob/living/L)
	var/melee = bot_melee_dps(null)
	var/ranged = 0
	var/stun = FALSE
	for(var/obj/item/I in L?.held_items)
		var/obj/item/gun/G = I
		if(istype(G))
			var/dps = bot_gun_dps(G)
			ranged = max(ranged, dps)
			var/list/shot = bot_gun_best_shot(G)
			if(shot && shot[3] == "stun")
				stun = TRUE
			continue
		melee = max(melee, bot_melee_dps(I))
	return list(melee, ranged, stun)

/// How long, in seconds, it'd take `by` to put L down from here at its best, through L's chest armour
/proc/bot_time_to_down(mob/living/L, mob/living/by, at_range = FALSE)
	if(!L || !by)
		return INFINITY
	var/list/threat = bot_threat_of(by)
	var/dps = at_range ? threat[2] : max(threat[1], threat[2])
	if(dps <= 0)
		return INFINITY
	var/armour = clamp(L.getarmor(BODY_ZONE_CHEST, at_range ? "laser" : "melee"), 0, 90)
	var/health_left = max(L.health - HEALTH_THRESHOLD_CRIT, 1)
	return health_left / (dps * (1 - armour / 100))

/// How far a fuel tank's blast would reach where it stands, in tiles: the light blast and the flames, from the fuel left in it
/// (fueltank/boom(), hippiestation reagent_dispenser.dm), and with explosion realism on, the air it's in and how much harder a small
/// sealed room makes it (explosion_realism/blast_air.dm). 0 for one that would only rupture.
/proc/bot_tank_blast_reach(obj/structure/reagent_dispensers/fueltank/tank)
	if(QDELETED(tank) || !tank.reagents)
		return 0
	var/fuel = tank.reagents.get_reagent_amount(/datum/reagent/fuel)
	if(fuel < FUEL_TANK_BLAST_MIN)
		return 0
	var/size = round(5 * (fuel / tank.tank_volume) ** (1 / 3), 1)
	var/turf/T = get_turf(tank)
	// By name: explosion realism is its own module, and the tank sums stand without it
	var/air_proc = text2path("/proc/blast_air_factor")
	var/confine_proc = text2path("/proc/blast_confinement")
	if(!T || !air_proc || !confine_proc || !GLOB.vars["explosion_realism"])
		return size
	var/air = call(air_proc)(T)
	var/light = size * air
	if(air > 0 && size > 0)
		var/list/found = call(confine_proc)(T, size)
		light *= found[1]
	return max(light, size * min(air, 1))

/// How far off to be to set one off: past its blast (above). The fragments of its casing go further (blast_injuries.dm), as far as
/// it can see and more: past this a shard may still find it, but the blast won't.
/proc/bot_tank_clear(obj/structure/reagent_dispensers/fueltank/tank)
	return max(CEILING(bot_tank_blast_reach(tank), 1) + 1, 2)
