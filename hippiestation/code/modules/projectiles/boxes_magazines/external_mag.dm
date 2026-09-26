/obj/item/ammo_box/magazine/g17
	name = "Glock 17 magazine (9mm)"
	desc = "A gun magazine."
	icon = 'hippiestation/icons/obj/ammo/ammo.dmi'
	icon_state = "g17"
	ammo_type = /obj/item/ammo_casing/c9mm
	caliber = "9mm"
	max_ammo = 14

/obj/item/ammo_box/magazine/g17/update_icon()
	..()
	icon_state = "[initial(icon_state)]-[CEILING(ammo_count(0)/14, 1)*14]"

// Pre-loaded Bulldog drum magazines, following the same pattern as m12g/dragon etc. in the core file

/obj/item/ammo_box/magazine/m12g/rodshot
	name = "shotgun magazine (12g rod shot)"
	icon_state = "m12gb" // no dedicated sprite yet
	ammo_type = /obj/item/ammo_casing/shotgun/rodshot

/obj/item/ammo_box/magazine/m12g/fragshot
	name = "shotgun magazine (12g fragmentation shot)"
	icon_state = "m12gb" // no dedicated sprite yet
	ammo_type = /obj/item/ammo_casing/shotgun/fragshot
