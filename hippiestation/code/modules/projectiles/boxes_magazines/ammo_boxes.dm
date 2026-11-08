/obj/item/ammo_box/buckshotbox
	name = "box of buckshot"
	desc = "You'll never need to buy ammo again."
	icon = 'icons/obj/storage.dmi'
	icon_state = "lethalshot_box"
	ammo_type = /obj/item/ammo_casing/shotgun/buckshot
	max_ammo = 60

// The laser gatling's 5,000 rounds were 5,000 casings, each with its projectile, made with the gun and deleted with it: 10,000 objects,
// 805 ms when one was blown up (tools/code_sweep acts, 2026-11-08), as long again when one was made. Each is made as it's fired now.
/obj/item/ammo_box/magazine/internal/minigun
	start_empty = TRUE
	/// Rounds it holds that aren't made yet
	var/unmade = 0

/obj/item/ammo_box/magazine/internal/minigun/Initialize()
	. = ..()
	unmade = max_ammo

/obj/item/ammo_box/magazine/internal/minigun/get_round(keep = FALSE)
	if(!length(stored_ammo) && unmade > 0)
		unmade--
		stored_ammo += new ammo_type(src)
	return ..()

/obj/item/ammo_box/magazine/internal/minigun/ammo_count(countempties = TRUE)
	return ..() + unmade

/obj/item/ammo_box/magazine/internal/minigun/give_round(obj/item/ammo_casing/R, replace_spent = 0)
	if(length(stored_ammo) + unmade >= max_ammo)
		return FALSE
	return ..()
