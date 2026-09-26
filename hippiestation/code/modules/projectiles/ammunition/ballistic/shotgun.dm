/obj/item/ammo_casing/shotgun/buckshot
	pellets = 12

/obj/item/ammo_casing/shotgun/rubbershot
	pellets = 12

/obj/item/ammo_casing/shotgun/rodshot
	name = "rod shot shell"
	desc = "A 12 gauge shell packed with sharpened metal rod fragments, held together with pitch. Crude, but effective."
	icon_state = "gshell" // no dedicated sprite yet, reusing the buckshot shell's for now
	projectile_type = /obj/item/projectile/rod/pellet
	pellets = 6
	variance = 25
	materials = list(MAT_METAL = 2000)

/obj/item/ammo_casing/shotgun/fragshot
	name = "fragmentation shell"
	desc = "A 12 gauge shell packed with pellets rigged to punch a little harder than they should."
	icon_state = "heshell" // no dedicated sprite yet, reusing the FRAG-12 slug's for now
	projectile_type = /obj/item/projectile/bullet/pellet/frag
	pellets = 6
	variance = 25
	materials = list(MAT_METAL = 3000)
