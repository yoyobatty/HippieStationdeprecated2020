/**
  * The tesla annihilator: a variant of the tesla revolver rebuilt around an uncontained engine core. Where the revolver's bolt
  * zaps once and vanishes, this one keeps flying after every hit, and at every single thing it touches along the way (mobs,
  * machines, structures) it does two things at once: a chain lightning arc off the tesla coil's own code, and the same
  * structure-wrecking blast wave a fiery explosion's blast wave uses (blast_atom(), see effects_blast.dm) at devastating
  * strength, which is what actually blows out windows, wrecks machines and throws debris the way the admin explosion tools do.
  * Any SMES, APC or exposed cable it crosses discharges the same way it would in a real explosion. It only stops when its
  * range runs out or it reaches a dead end, and finishes with a screen shockwave at wherever that is.
  *
  * It's built as its own projectile type, not a subtype of the ordinary tesla bolt, because that one's on_hit() zaps once and
  * deletes itself; there's no clean way to reuse the good parts of that (the trailing beam effect) without also inheriting the
  * single-shot behavior this weapon is specifically meant not to have.
  */

/obj/item/gun/energy/tesla_revolver/annihilator
	name = "tesla annihilator"
	desc = "A tesla revolver torn apart and rebuilt around a raw, uncontained engine core. It's not made for aiming, only for \
		pointing down something you want gone. Whatever the bolt touches, chain lightning follows, all the way to the end of \
		the room. Empties an entire power cell in a single shot."
	ammo_type = list(/obj/item/ammo_casing/energy/tesla_annihilator) // the parent's ammo_type points at the stock casing, not ours
	pin = /obj/item/firing_pin

/obj/item/ammo_casing/energy/tesla_annihilator
	fire_sound = 'sound/magic/lightningbolt.ogg'
	e_cost = 1 // a stock cell (1000 charge) is exactly one shot: this gun is meant to be devastating and rare, not spammable
	select_name = "annihilate"
	projectile_type = /obj/item/projectile/energy/tesla_annihilator

/obj/item/projectile/energy/tesla_annihilator
	name = "annihilating bolt"
	icon_state = "tesla_projectile"
	impact_effect_type = /obj/effect/temp_visual/impact_effect/blue_laser
	damage = 30 // burn damage to whatever it directly strikes, on top of the chain lightning arcing off it
	movement_type = FLYING | UNSTOPPABLE // keeps flying through walls, mobs and machines instead of stopping at the first one
	var/tesla_flags = TESLA_DEFAULT_FLAGS
	// Kept tight on purpose, matching the base tesla bolt's own default (3) instead of a wider search. TESLA_DEFAULT_FLAGS
	// includes TESLA_ALLOW_DUPLICATES, which lets the chain re-select the same nearby target every hop instead of moving on;
	// a tight radius means it usually has nowhere else to go and hammers whoever's closest with hit after hit. A wide radius
	// instead gives it somewhere new to jump to almost every time, spreading the same number of hits thin across a crowd
	// instead of piling them onto one or two people, which is a lot less dramatic even if the total damage is similar.
	var/zap_range = 3
	var/power = 100000 // scale for tesla_zap's electrical chain, unrelated to blast_power below
	var/blast_power = 6 // scale for blast_atom's structural blast wave; 5+ is the devastate tier, see effects_fiery_explosion.dm's docs
	var/chain // the visual beam trailing from the gun to the bolt
	var/list/arced = list() // power equipment blast_atom() has already discharged this flight, so it isn't re-arced at every tile
	// Every target tesla_zap() has already arced into, shared across the whole flight so the same person isn't re-chained into
	// from every single tile the bolt passes, only jolted directly once (see on_hit) plus however many times a chain reaches them.
	var/list/shocked_targets = list()

/obj/item/projectile/energy/tesla_annihilator/fire(setAngle)
	if(firer)
		chain = firer.Beam(src, icon_state = "lightning[rand(1, 12)]", time = INFINITY, maxdistance = INFINITY)
	..()

/obj/item/projectile/energy/tesla_annihilator/Move(atom/newloc, dir = NONE)
	. = ..()
	// tesla_zap() only ever fired from on_hit(), which only runs when the bolt actually collides with something, so open
	// floor tiles with nothing to hit were completely silent. This fires one from wherever the bolt currently is on every
	// tile it successfully enters, hit or not, so it's arcing lightning at everything nearby the whole way down its flight,
	// not just at the handful of tiles it happens to land a direct hit on.
	if(. && loc && !QDELETED(src))
		tesla_zap(src, zap_range, 2000, tesla_flags, shocked_targets)

/obj/item/projectile/energy/tesla_annihilator/Destroy()
	QDEL_NULL(chain)
	return ..()

/obj/item/projectile/energy/tesla_annihilator/on_hit(atom/target, blocked = FALSE)
	. = ..() // the usual impact effects: wall dents, blood splatter, hit messages. The mob/obj's own bullet_act() applies the flat damage.
	if(ismovable(target))
		// The real devastation: the same blast wave a fiery explosion uses. Discharges power equipment, wrecks machines,
		// blows out windows and throws debris, all at once, on whatever it just hit.
		blast_atom(target, blast_power, get_turf(src), arced)
	if(isliving(target))
		var/mob/living/L = target
		// tesla_zap() never actually shocks the thing it's called "on": that atom is only the point it searches outward from
		// for OTHER nearby things to chain into. Left as the only source of damage, whatever's directly struck barely feels
		// it unless something else happens to be standing right next to them. So the bolt itself lands a real, guaranteed
		// hit here, at the same damage cap tesla_zap's own chain uses, and a real knockdown: electrocute_act() takes a
		// "stun" argument, but no mob type in this codebase actually reads it, so tesla shocks never knock anyone down
		// on their own. TESLA_MOB_STUN in tesla_flags below is doing nothing for the same reason; this is done for real instead.
		if(!HAS_TRAIT(L, TRAIT_SHOCKIMMUNE))
			L.electrocute_act(clamp(round(power / 600), 20, 90), src, 1, tesla_shock = 1)
			L.Knockdown(60)
	tesla_zap(target, zap_range, power, tesla_flags, shocked_targets) // a bonus chain onto anyone else standing nearby
	return BULLET_ACT_FORCE_PIERCE // keep flying: hit everything else on this tile too, then carry on to the next one

/obj/item/projectile/energy/tesla_annihilator/on_range()
	if(loc)
		screen_shockwave(get_turf(src), 4, 15) // a last punch of screen distortion where the bolt finally burns itself out
	return ..()
