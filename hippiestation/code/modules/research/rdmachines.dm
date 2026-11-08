/obj/machinery/rnd
	icon_hippie = 'hippiestation/icons/obj/machines/research.dmi'

/obj/machinery/rnd/server
	icon_hippie = 'hippiestation/icons/obj/machines/research.dmi'

// An experiment that deleted what it was testing (a grenade going off in it) still had it put out on the floor afterwards, deleted:
// it and the beakers in it were hard deletes (105 ms, stress bench 2026-11-08)
/obj/machinery/rnd/experimentor/ejectItem(delete = FALSE)
	if(QDELETED(loaded_item))
		loaded_item = null
		return
	return ..()
