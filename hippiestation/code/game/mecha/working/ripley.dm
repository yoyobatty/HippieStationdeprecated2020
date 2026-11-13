/obj/mecha/working/ripley/mining_roundstart
	desc = "A complimentary APLU fitted with an array of tools suitable for mining, \
			courtesy of the Nanotrasen geological exploitation department.  \
			Don't forget to bring your minerals to the hard working boys at R&D \
			and not to pinch the ORM so they can upgrade it for you."
	name = "\improper APLU \"Miner\""

/obj/mecha/working/ripley/mining_roundstart/Initialize()
	var/obj/item/mecha_parts/mecha_equipment/drill/D = new
	D.attach(src)
	.=..()

	cargo.Add(new /obj/structure/ore_box(src)) //Starts with its own nice little ore box.

	//A free clamp too, gosh am I generous!
	var/obj/item/mecha_parts/mecha_equipment/hydraulic_clamp/HC = new
	HC.attach(src)

	var/obj/item/mecha_parts/mecha_equipment/mining_scanner/scanner = new //And a free scanner just for you!
	scanner.attach(src)
// The drill fills the hold's ore box with what it digs out, as it's meant to. tg's check read "locate(clamp) in chassis.equipment &&
// istype(chassis, ripley)", and DM's "in" takes everything after it, so it looked for the clamp in TRUE and never found it: the ore stayed
// on the floor until the Ripley drove over it (ripley/Move()). Found when the bots' mech miner came back with an empty box (2026-11-12).
/obj/item/mecha_parts/mecha_equipment/drill/move_ores()
	if((locate(/obj/item/mecha_parts/mecha_equipment/hydraulic_clamp) in chassis.equipment) && istype(chassis, /obj/mecha/working/ripley))
		var/obj/mecha/working/ripley/R = chassis
		R.collect_ore()
