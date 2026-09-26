/obj/item/projectile/rod
	name = "metal rod"
	icon = 'hippiestation/icons/obj/guns/crossbow.dmi'
	icon_state = "rod_proj"
	suppressed = TRUE
	damage = 10 // multiply by how drawn the bow string is
	range = 10 // also multiply by the bow string
	damage_type = BRUTE
	flag = "bullet"
	hitsound = null // We use our own for different circumstances
	var/impale_sound = 'hippiestation/sound/weapons/rodgun_pierce.ogg'
	var/hitsound_override = 'sound/weapons/pierce.ogg'
	var/charge = 0 // How much power is in the bolt, transferred from the crossbow

/obj/item/projectile/rod/on_range()
	// we didn't hit anything, place a rod here
	new /obj/item/stack/rods(get_turf(src))
	..()

obj/item/projectile/rod/proc/Impale(mob/living/carbon/human/H)
	if (H)
		var/hit_zone = H.check_limb_hit(def_zone)
		var/obj/item/bodypart/BP = H.get_bodypart(hit_zone)
		var/obj/item/stack/rods/R = new(H.loc, 1, FALSE) // Don't merge

		if (istype(BP))
			R.add_blood_DNA(H.return_blood_DNA())
			R.forceMove(H)
			BP.embedded_objects += R
			H.update_damage_overlays()
			visible_message("<span class='warning'>The [R] has embedded into [H]'s [BP]!</span>",
							"<span class='userdanger'>You feel [R] lodge into your [BP]!</span>")
			playsound(H, impale_sound, 50, 1)
			H.emote("scream")
			var/turf/T = get_step(H, dir)
			if (istype(T) && T.density && !H.pinned_to) // Can only pin someone once
				H.pinned_to = T
				T.pinned = H
				H.anchored = TRUE
				H.update_mobility()
				H.do_pindown(T, 1)
				R.pinned = T

			log_combat(firer, H, "shot", src, addition="[H.pinned_to ? " PINNED" : ""]")

/obj/item/projectile/rod/on_hit(atom/target, blocked = FALSE)
	..()
	var/volume = vol_by_damage()
	if (istype(target, /mob))
		playsound(target, impale_sound, volume, 1, -1)
		if (ishuman(target) && charge > 2) // Only fully charged shots can impale
			var/mob/living/carbon/human/H = target
			Impale(H)
		else
			new /obj/item/stack/rods(get_turf(src))
	else
		playsound(target, hitsound_override, volume, 1, -1)
		new /obj/item/stack/rods(get_turf(src))
	qdel(src)

/**
  * A lighter rod for the "rod shot" shotgun shell: several of these leave the barrel at once (see the ammo casing in
  * ammunition/ballistic/shotgun.dm), so each one is tuned down from the crossbow's full-power bolt. Charge stays at
  * the inherited 0, so unlike a fully-drawn crossbow shot these never impale-and-pin a target (that needs charge > 2)
  * - a shotgun blast pinning someone to a wall six times over would be absurd. They still clatter to the ground as
  * actual /obj/item/stack/rods on a miss or a shallow hit, so a rod shot volley litters the ground with scrap metal.
  */
/obj/item/projectile/rod/pellet
	name = "rod fragment"
	damage = 11 // comparable to a buckshot pellet (12.5), rods are sharper but this is spread across more pellets
	range = 7 // shotgun pellets don't carry as far as a full crossbow draw
	var/tile_dropoff = 1.5 // falls off faster than buckshot's 0.75, these are unbalanced scrap, not proper shot

/obj/item/projectile/rod/pellet/Range()
	..()
	if(damage > 0)
		damage -= tile_dropoff
	if(damage <= 0)
		qdel(src)

/**
  * A shotgun pellet that bursts into a tiny fragmentation blast wherever it lands, using the game's own explosion()
  * rather than blast_atom(): light severity only (devastation and heavy are both switched off), reaching one tile out
  * so it actually catches whoever's standing next to the point of impact, not just the thing directly hit - real
  * shrapnel spread, which a single-target blast_atom() call can't give. Silent and left out of the admin log since a
  * 6-pellet shell would otherwise fire off up to six of these in an instant; the shot's own bang is noise enough.
  * Kept to light severity on purpose - devastating tier at zero range would gib whatever's hit outright, on every pellet.
  */
/obj/item/projectile/bullet/pellet/frag
	name = "fragmentation pellet"
	damage = 9 // a touch below buckshot's 12.5, since the burst below adds its own extra punch on top

/obj/item/projectile/bullet/pellet/frag/on_hit(atom/target, blocked = FALSE)
	. = ..()
	explosion(target, -1, -1, 1, flash_range = 0, adminlog = FALSE, flame_range = 0)

/obj/item/projectile/plasma/watcher
	name = "freezing blast"
	icon_state = "ice_2"
	damage = 10
	flag = "energy"
	damage_type = BURN
	range = 4
	mine_range = 0
	var/temperature = -100
	dismemberment = FALSE

/obj/item/projectile/plasma/watcher/on_hit(atom/target, blocked = 0)
	. = ..()
	if(isliving(target))
		var/mob/living/L = target
		L.adjust_bodytemperature(((100-blocked)/100)*(temperature - L.bodytemperature)) // the new body temperature is adjusted by 100-blocked % of the delta between body temperature and the bullet's effect temperature
