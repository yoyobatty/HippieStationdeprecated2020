// Duplicates inside the right-hand list of | and |=. Stand-alone: dm list_union.dm, then dd list_union.dmb -invisible.
// The reference: "If A and B are lists, any items in B that are not already in A are added to A."

/world
	fps = 20

/proc/show(label, list/L, expected)
	world.log << "[label]: [L.len] items [json_encode(L)], the reference's reading gives [expected]"

/proc/run_cases()
	world.log << "BYOND [world.byond_version].[world.byond_build]"

	var/list/a = list(1)
	a |= list(2, 2)
	show("a = list(1); a |= list(2, 2)", a, 2)

	var/list/b = list()
	b |= list("x", "x", "x")
	show("b = list(); b |= list(\"x\", \"x\", \"x\")", b, 1)

	var/list/c = list(2)
	c |= list(2, 2)
	show("c = list(2); c |= list(2, 2)", c, 1)

	var/list/f = list(2, 2)
	f |= list(2, 2, 2)
	show("f = list(2, 2); f |= list(2, 2, 2)", f, 2)

	show("list(1) | list(2, 2)", list(1) | list(2, 2), 2)
	show("list() | list(\"x\", \"x\", \"x\")", list() | list("x", "x", "x"), 1)

	var/list/d = list(1)
	for(var/item in list(2, 2))
		d |= item
	show("d = list(1); for each of list(2, 2): d |= item", d, 2)

	var/datum/thing = new
	var/list/e = list()
	e |= list(thing, thing)
	world.log << "e = list(); e |= list(datum, datum): [e.len] items, the reference's reading gives 1"

	world.log << "done"
	del(world)

/world/New()
	. = ..()
	spawn(5)
		run_cases()
