// contender

/obj/item/ammo_box/magazine/internal/shot/contender
	name = "contender internal magazine"
	caliber = "all"
	ammo_type = /obj/item/ammo_casing
	start_empty = TRUE
	max_ammo = 2
	multiload = 0 // thou must load every shot individually

// Pre-loaded pump shotgun magazines, following the same pattern as /shot/lethal (buckshot) above

/obj/item/ammo_box/magazine/internal/shot/rodshot
	name = "shotgun internal magazine (rod shot)"
	ammo_type = /obj/item/ammo_casing/shotgun/rodshot

/obj/item/ammo_box/magazine/internal/shot/fragshot
	name = "shotgun internal magazine (fragmentation shot)"
	ammo_type = /obj/item/ammo_casing/shotgun/fragshot