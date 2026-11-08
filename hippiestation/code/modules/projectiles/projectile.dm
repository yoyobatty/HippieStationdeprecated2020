/obj/item/projectile
	speed = 0.2 //four times faster

/obj/item/projectile/magic
	speed = 0.8 //as before because hyper fireball isnt fun

/obj/item/projectile/special
	speed = 0.8 //as before

/obj/item/projectile/energy
	speed = 0.8

/obj/item/projectile/beam/disabler
	speed = 0.7

/obj/item/projectile/beam
	speed = 0.2

/obj/item/projectile/bullet/p50
	speed = 0.2


// One that was never fired (spawned in, or one a code sweep made) bumps like anything else: it has no trajectory, and every bump was a
// runtime (832 in an acts sweep, things knocking them about)
/obj/item/projectile/Bump(atom/A)
	if(!trajectory)
		return
	return ..()
