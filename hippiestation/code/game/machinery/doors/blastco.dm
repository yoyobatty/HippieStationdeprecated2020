/obj/machinery/door/poddoor/shutters/blastco
	resistance_flags = INDESTRUCTIBLE

GLOBAL_LIST(blastco_doors)

/obj/machinery/door/poddoor/shutters/blastco/Initialize()
	. = ..()
	LAZYADD(GLOB.blastco_doors, src)

/obj/machinery/door/poddoor/shutters/blastco/Destroy()
	LAZYREMOVE(GLOB.blastco_doors, src) // it stayed on the list after it went: a hard delete (testkit sweep)
	return ..()
