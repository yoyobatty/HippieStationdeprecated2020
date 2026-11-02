/atom/movable
	/// Never in anyone's way and never reacts to being walked over, so nothing moving past it has to ask. Every object on a tile
	/// costs anything that crosses that tile four proc calls, and most of what's on a tile is under the floor.
	/// Don't set this on anything that overrides Cross(), Uncross(), Crossed(), Uncrossed(), CanPass() or CheckExit().
	var/no_cross_checks = FALSE

/atom/movable/lighting_object
	no_cross_checks = TRUE

/obj/structure/cable
	no_cross_checks = TRUE

/obj/machinery/atmospherics/pipe
	no_cross_checks = TRUE

/obj/structure/disposalpipe
	no_cross_checks = TRUE

/obj/item/do_pickup_animation(atom/target)
	return

/atom/movable/Moved(atom/OldLoc, Dir)
	. = ..()
	SSdemo.mark_dirty(src)
