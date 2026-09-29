// Screentip tips for the things people build, fix and use most. Each one mirrors the branches of that thing's own click
// handling (named above it), in the same order, so the tip says what the click will actually do. Where a click's result
// depends on something the player can't see, the tip doesn't give it away.

// Mirrors of state defines their own files #undef at the end
#define AIRLOCK_SECURITY_NONE			0
#define AIRLOCK_SECURITY_METAL			1
#define AIRLOCK_SECURITY_PLASTEEL_I_S	2
#define AIRLOCK_SECURITY_PLASTEEL_I		3
#define AIRLOCK_SECURITY_PLASTEEL_O_S	4
#define AIRLOCK_SECURITY_PLASTEEL_O		5
#define AIRLOCK_SECURITY_PLASTEEL		6
#define APC_ELECTRONICS_MISSING		0
#define APC_ELECTRONICS_INSTALLED	1
#define APC_ELECTRONICS_SECURED		2
#define APC_COVER_CLOSED	0
#define APC_COVER_OPENED	1
#define APC_COVER_REMOVED	2

// ---------------------------------------------------------------------------------------------------------------------
// Airlocks: /obj/machinery/door/airlock/attackby(), then /obj/machinery/door/attackby(), try_to_crowbar(), try_to_weld()
/obj/machinery/door/airlock/add_context(atom/source, list/context, obj/item/held_item, mob/living/user)
	if(!held_item)
		var/door_action = airlock_toggle_tip(user)
		if(door_action)
			context[SCREENTIP_LMB] = door_action
		return
	var/tool = held_item.tool_behaviour
	if(panel_open)
		switch(security_level)
			if(AIRLOCK_SECURITY_NONE)
				if(istype(held_item, /obj/item/stack/sheet/metal))
					context[SCREENTIP_LMB] = "Reinforce with metal"
					return
				if(istype(held_item, /obj/item/stack/sheet/plasteel))
					context[SCREENTIP_LMB] = "Reinforce with plasteel"
					return
			if(AIRLOCK_SECURITY_METAL)
				if(tool == TOOL_WELDER)
					context[SCREENTIP_LMB] = "Cut off shielding"
					return
			if(AIRLOCK_SECURITY_PLASTEEL_I_S)
				if(tool == TOOL_CROWBAR)
					context[SCREENTIP_LMB] = "Remove inner shielding"
					return
			if(AIRLOCK_SECURITY_PLASTEEL_I)
				if(tool == TOOL_WELDER)
					context[SCREENTIP_LMB] = "Cut inner shielding"
					return
			if(AIRLOCK_SECURITY_PLASTEEL_O_S)
				if(tool == TOOL_CROWBAR)
					context[SCREENTIP_LMB] = "Remove outer shielding"
					return
			if(AIRLOCK_SECURITY_PLASTEEL_O)
				if(tool == TOOL_WELDER)
					context[SCREENTIP_LMB] = "Cut outer shielding"
					return
			if(AIRLOCK_SECURITY_PLASTEEL)
				if(tool == TOOL_WIRECUTTER)
					context[SCREENTIP_LMB] = "Cut outer grille"
					return
	if(tool == TOOL_SCREWDRIVER)
		if(!(panel_open && detonated))
			context[SCREENTIP_LMB] = panel_open ? "Close panel" : "Open panel"
		return
	if(tool == TOOL_WIRECUTTER && note)
		context[SCREENTIP_LMB] = "Take down [note.name]"
		return
	if(is_wire_tool(held_item) && panel_open)
		if(!security_level)
			context[SCREENTIP_LMB] = "Wires"
		return
	if(istype(held_item, /obj/item/airlock_painter))
		context[SCREENTIP_LMB] = "Paint"
		return
	if(istype(held_item, /obj/item/paper) || istype(held_item, /obj/item/photo))
		if(!note)
			context[SCREENTIP_LMB] = "Pin up"
		return
	if(istype(held_item, /obj/item/pai_cable) || istype(held_item, /obj/item/doorCharge))
		return
	if(user.a_intent == INTENT_HARM)
		return
	if(tool == TOOL_CROWBAR || istype(held_item, /obj/item/twohanded/fireaxe))
		var/crowbar_action = airlock_crowbar_tip(held_item)
		if(crowbar_action)
			context[SCREENTIP_LMB] = crowbar_action
		return
	if(tool == TOOL_WELDER)
		if(operating || !density)
			return
		if(user.a_intent != INTENT_HELP)
			context[SCREENTIP_LMB] = welded ? "Unweld" : "Weld shut"
		else if(obj_integrity < max_integrity)
			context[SCREENTIP_LMB] = "Repair"
		return
	if(!(held_item.item_flags & NOBLUDGEON))
		var/door_action = airlock_toggle_tip(user)
		if(door_action)
			context[SCREENTIP_LMB] = door_action

/// Open or Close, when clicking would do it (try_to_activate_door(), then open()/close())
/obj/machinery/door/airlock/proc/airlock_toggle_tip(mob/living/user)
	if(operating || (obj_flags & EMAGGED) || locked || welded || !hasPower())
		return
	if(requiresID() && !allowed(user))
		return
	return density ? "Open" : "Close"

/// What a crowbar or fireaxe does to it (try_to_crowbar()). A door charge behind an open panel isn't given away: the
/// tip reads as if it weren't there.
/obj/machinery/door/airlock/proc/airlock_crowbar_tip(obj/item/held_item)
	var/forced = FALSE
	if(istype(held_item, /obj/item/crowbar))
		var/obj/item/crowbar/bar = held_item
		forced = bar.force_opens
	if(held_item.tool_behaviour == TOOL_CROWBAR && !security_level && panel_open && ((obj_flags & EMAGGED) || (density && welded && !operating && !hasPower() && !locked)))
		return "Remove electronics"
	if(locked || welded)
		return
	if(hasPower())
		return (forced && density) ? "Force open" : null
	if(operating)
		return
	if(istype(held_item, /obj/item/twohanded/fireaxe))
		var/obj/item/twohanded/fireaxe/axe = held_item
		if(!axe.wielded)
			return
	return density ? "Pry open" : "Pry closed"

// ---------------------------------------------------------------------------------------------------------------------
// Closets and crates: /obj/structure/closet/attack_hand(), tool_interact(), AltClick()
/obj/structure/closet/add_context(atom/source, list/context, obj/item/held_item, mob/living/user)
	if(secure && !broken && !opened)
		context[SCREENTIP_ALT_LMB] = locked ? "Unlock" : "Lock"
	if(user in src)
		return
	if(!held_item)
		if(opened)
			context[SCREENTIP_LMB] = "Close"
		else if(!welded && !locked)
			context[SCREENTIP_LMB] = "Open"
		else if(locked && secure && !broken)
			context[SCREENTIP_LMB] = "Unlock"
		return
	if(opened)
		if(istype(held_item, cutting_tool))
			context[SCREENTIP_LMB] = (held_item.tool_behaviour == TOOL_WELDER) ? "Slice apart" : "Cut apart"
		else
			context[SCREENTIP_LMB] = "Put in"
		return
	if(held_item.tool_behaviour == TOOL_WELDER && can_weld_shut)
		context[SCREENTIP_LMB] = welded ? "Unweld" : "Weld shut"
		return
	if(held_item.tool_behaviour == TOOL_WRENCH && anchorable)
		if(!(isinspace() && !anchored))
			context[SCREENTIP_LMB] = anchored ? "Unanchor" : "Anchor"
		return
	if(user.a_intent == INTENT_HARM)
		return
	if(held_item.GetID())
		if(secure && !broken)
			context[SCREENTIP_LMB] = locked ? "Unlock" : "Lock"
		return
	if(!(held_item.item_flags & NOBLUDGEON) && !welded && !locked)
		context[SCREENTIP_LMB] = "Open"

// ---------------------------------------------------------------------------------------------------------------------
// Tables: /obj/structure/table/attackby()
/obj/structure/table/add_context(atom/source, list/context, obj/item/held_item, mob/living/user)
	if(!held_item)
		return
	if(!(flags_1 & NODECONSTRUCT_1) && deconstruction_ready)
		if(held_item.tool_behaviour == TOOL_SCREWDRIVER)
			context[SCREENTIP_LMB] = "Disassemble"
			return
		if(held_item.tool_behaviour == TOOL_WRENCH)
			context[SCREENTIP_LMB] = "Deconstruct"
			return
	if(istype(held_item, /obj/item/storage/bag/tray))
		context[SCREENTIP_LMB] = "Unload tray"
		return
	if(user.a_intent != INTENT_HARM && !(held_item.item_flags & ABSTRACT))
		context[SCREENTIP_LMB] = "Place"

// Reinforced tables: a welder weakens or strengthens them first (/obj/structure/table/reinforced/attackby())
/obj/structure/table/reinforced/add_context(atom/source, list/context, obj/item/held_item, mob/living/user)
	if(held_item?.tool_behaviour == TOOL_WELDER)
		context[SCREENTIP_LMB] = deconstruction_ready ? "Weaken" : "Strengthen"
		return
	return ..()

// ---------------------------------------------------------------------------------------------------------------------
// Grilles: /obj/structure/grille/attackby()
/obj/structure/grille/add_context(atom/source, list/context, obj/item/held_item, mob/living/user)
	if(!held_item)
		return
	if(held_item.tool_behaviour == TOOL_WIRECUTTER)
		context[SCREENTIP_LMB] = "Cut apart"
	else if(held_item.tool_behaviour == TOOL_SCREWDRIVER && (isturf(loc) || anchored))
		context[SCREENTIP_LMB] = anchored ? "Unfasten" : "Fasten"
	else if(istype(held_item, /obj/item/stack/rods) && broken)
		context[SCREENTIP_LMB] = "Rebuild"
	else if(is_glass_sheet(held_item) && !broken && anchored)
		context[SCREENTIP_LMB] = "Build window"

// ---------------------------------------------------------------------------------------------------------------------
// Windows: /obj/structure/window/attackby()
/obj/structure/window/add_context(atom/source, list/context, obj/item/held_item, mob/living/user)
	if(!held_item || !can_be_reached(user))
		return
	var/tool = held_item.tool_behaviour
	if(tool == TOOL_WELDER && user.a_intent == INTENT_HELP)
		if(obj_integrity < max_integrity)
			context[SCREENTIP_LMB] = "Repair"
		return
	if(flags_1 & NODECONSTRUCT_1)
		return
	if(tool == TOOL_SCREWDRIVER)
		if(!reinf)
			context[SCREENTIP_LMB] = anchored ? "Unscrew from floor" : "Screw to floor"
		else if(state == WINDOW_SCREWED_TO_FRAME)
			context[SCREENTIP_LMB] = "Unscrew from frame"
		else if(state == WINDOW_IN_FRAME)
			context[SCREENTIP_LMB] = "Screw to frame"
		else if(state == WINDOW_OUT_OF_FRAME)
			context[SCREENTIP_LMB] = anchored ? "Unscrew frame from floor" : "Screw frame to floor"
	else if(tool == TOOL_CROWBAR && reinf && (state == WINDOW_OUT_OF_FRAME || state == WINDOW_IN_FRAME))
		context[SCREENTIP_LMB] = (state == WINDOW_OUT_OF_FRAME) ? "Pry into frame" : "Pry out of frame"
	else if(tool == TOOL_WRENCH && !anchored)
		context[SCREENTIP_LMB] = "Disassemble"

// ---------------------------------------------------------------------------------------------------------------------
// Walls: /turf/closed/wall/attackby() - try_clean(), try_wallmount(), try_decon()
/turf/closed/wall/add_context(atom/source, list/context, obj/item/held_item, mob/living/user)
	if(!held_item || !user.IsAdvancedToolUser() || !isturf(user.loc))
		return
	if(user.a_intent == INTENT_HELP && LAZYLEN(dent_decals) && held_item.tool_behaviour == TOOL_WELDER)
		context[SCREENTIP_LMB] = "Fix dents"
	else if(istype(held_item, /obj/item/wallframe))
		context[SCREENTIP_LMB] = "Mount"
	else if(istype(held_item, /obj/item/poster))
		context[SCREENTIP_LMB] = "Hang poster"
	else
		var/decon = wall_decon_tip(held_item)
		if(decon)
			context[SCREENTIP_LMB] = decon

/turf/closed/wall/proc/wall_decon_tip(obj/item/held_item)
	if(held_item.tool_behaviour == TOOL_WELDER)
		return "Slice through plating"

// Reinforced walls come apart in stages (/turf/closed/wall/r_wall/try_decon()); each stage's tool goes forward, and the
// previous stage's tool puts it back
/turf/closed/wall/r_wall/wall_decon_tip(obj/item/held_item)
	var/tool = held_item.tool_behaviour
	switch(d_state)
		if(INTACT)
			if(tool == TOOL_WIRECUTTER)
				return "Cut outer grille"
		if(SUPPORT_LINES)
			if(tool == TOOL_SCREWDRIVER)
				return "Unsecure support lines"
			if(tool == TOOL_WIRECUTTER)
				return "Repair outer grille"
		if(COVER)
			if(tool == TOOL_WELDER)
				return "Slice metal cover"
			if(tool == TOOL_SCREWDRIVER)
				return "Secure support lines"
		if(CUT_COVER)
			if(tool == TOOL_CROWBAR)
				return "Pry off cover"
			if(tool == TOOL_WELDER)
				return "Weld cover back on"
		if(ANCHOR_BOLTS)
			if(tool == TOOL_WRENCH)
				return "Loosen anchor bolts"
			if(tool == TOOL_CROWBAR)
				return "Pry cover back on"
		if(SUPPORT_RODS)
			if(tool == TOOL_WELDER)
				return "Slice support rods"
			if(tool == TOOL_WRENCH)
				return "Tighten anchor bolts"
		if(SHEATH)
			if(tool == TOOL_CROWBAR)
				return "Pry off outer sheath"
			if(tool == TOOL_WELDER)
				return "Weld support rods"

// ---------------------------------------------------------------------------------------------------------------------
// Girders: /obj/structure/girder/attackby(), screwdriver_act(), wirecutter_act(), wrench_act()
/obj/structure/girder/add_context(atom/source, list/context, obj/item/held_item, mob/living/user)
	if(!held_item)
		return
	var/tool = held_item.tool_behaviour
	if(istype(held_item, /obj/item/gun/energy/plasmacutter))
		context[SCREENTIP_LMB] = "Slice apart"
	else if(istype(held_item, /obj/item/stack))
		if(iswallturf(loc) || !isfloorturf(loc))
			return
		if(istype(held_item, /obj/item/stack/rods))
			context[SCREENTIP_LMB] = (state == GIRDER_DISPLACED) ? "Build false iron wall" : "Build iron wall"
		else if(istype(held_item, /obj/item/stack/sheet/metal))
			context[SCREENTIP_LMB] = (state == GIRDER_DISPLACED) ? "Build false wall" : "Add plating"
		else if(istype(held_item, /obj/item/stack/sheet/plasteel))
			if(state == GIRDER_DISPLACED)
				context[SCREENTIP_LMB] = "Build reinforced false wall"
			else if(state == GIRDER_REINF)
				context[SCREENTIP_LMB] = "Finish reinforced wall"
			else
				context[SCREENTIP_LMB] = "Reinforce girder"
		else if(istype(held_item, /obj/item/stack/sheet))
			var/obj/item/stack/sheet/sheet = held_item
			if(sheet.sheettype && sheet.sheettype != "runed")
				context[SCREENTIP_LMB] = (state == GIRDER_DISPLACED) ? "Build false wall" : "Add plating"
	else if(tool == TOOL_SCREWDRIVER)
		if(state == GIRDER_DISPLACED)
			context[SCREENTIP_LMB] = "Disassemble"
		else if(state == GIRDER_REINF)
			context[SCREENTIP_LMB] = "Unsecure support struts"
		else if(state == GIRDER_REINF_STRUTS)
			context[SCREENTIP_LMB] = "Secure support struts"
	else if(tool == TOOL_WIRECUTTER)
		if(state == GIRDER_REINF_STRUTS)
			context[SCREENTIP_LMB] = "Remove inner grille"
	else if(tool == TOOL_WRENCH)
		if(state == GIRDER_DISPLACED)
			context[SCREENTIP_LMB] = "Secure"
		else if(state == GIRDER_NORMAL && can_displace)
			context[SCREENTIP_LMB] = "Unsecure"

// ---------------------------------------------------------------------------------------------------------------------
// Floors: /turf/open/floor/crowbar_act() and attackby(), /turf/open/floor/plating/attackby() and welder_act()
/turf/open/floor/add_context(atom/source, list/context, obj/item/held_item, mob/living/user)
	if(!held_item || !intact)
		return
	if(held_item.tool_behaviour == TOOL_CROWBAR)
		context[SCREENTIP_LMB] = (broken || burnt) ? "Remove broken plating" : "Pry up tile"
	else if(istype(held_item, /obj/item/stack/tile))
		var/obj/item/stack/tile/new_tile = held_item
		if(new_tile.turf_type != type && user.is_holding_item_of_type(/obj/item/crowbar))
			context[SCREENTIP_LMB] = "Replace tile"

/turf/open/floor/plating/add_context(atom/source, list/context, obj/item/held_item, mob/living/user)
	if(!held_item)
		return
	if(istype(held_item, /obj/item/stack/rods) && attachment_holes && !broken && !burnt)
		context[SCREENTIP_LMB] = "Reinforce floor"
	else if(istype(held_item, /obj/item/stack/tile) && !broken && !burnt)
		context[SCREENTIP_LMB] = "Place tile"
	else if(held_item.tool_behaviour == TOOL_WELDER && (broken || burnt))
		context[SCREENTIP_LMB] = "Repair"

// Space: /turf/open/space/attackby(). Lattices and catwalks pass clicks through to the space under them.
/turf/open/space/add_context(atom/source, list/context, obj/item/held_item, mob/living/user)
	if(!held_item || !CanBuildHere())
		return
	var/obj/structure/lattice/lattice = locate(/obj/structure/lattice) in src
	if(istype(held_item, /obj/item/stack/rods))
		if(!istype(lattice, /obj/structure/lattice/catwalk) && !(locate(/obj/structure/lattice/catwalk) in src))
			context[SCREENTIP_LMB] = lattice ? "Build catwalk" : "Build lattice"
	else if(istype(held_item, /obj/item/stack/tile/plasteel) && lattice)
		context[SCREENTIP_LMB] = "Build floor"

/obj/structure/lattice/add_context(atom/source, list/context, obj/item/held_item, mob/living/user)
	var/turf/T = get_turf(src)
	T?.add_context(T, context, held_item, user)

// ---------------------------------------------------------------------------------------------------------------------
// Cables: /obj/structure/cable/handlecable()
/obj/structure/cable/add_context(atom/source, list/context, obj/item/held_item, mob/living/user)
	var/turf/T = get_turf(src)
	if(!held_item || T.intact)
		return
	if(held_item.tool_behaviour == TOOL_WIRECUTTER)
		context[SCREENTIP_LMB] = "Cut"
	else if(held_item.tool_behaviour == TOOL_MULTITOOL)
		context[SCREENTIP_LMB] = "Check power"

// ---------------------------------------------------------------------------------------------------------------------
// APCs: /obj/machinery/power/apc/attackby(), the tool acts, AltClick() and attack_hand()
/obj/machinery/power/apc/add_context(atom/source, list/context, obj/item/held_item, mob/living/user)
	var/can_swipe = !(obj_flags & EMAGGED) && !opened && !panel_open && !(stat & (BROKEN|MAINT))
	if(can_swipe)
		context[SCREENTIP_ALT_LMB] = locked ? "Unlock" : "Lock"
	if(!held_item)
		if(opened && cell && !issilicon(user))
			context[SCREENTIP_LMB] = "Remove cell"
		return
	var/tool = held_item.tool_behaviour
	if(tool == TOOL_CROWBAR)
		if(opened)
			if(has_electronics == APC_ELECTRONICS_INSTALLED)
				context[SCREENTIP_LMB] = "Remove board"
			else if(opened != APC_COVER_REMOVED && !integration_cog)
				context[SCREENTIP_LMB] = "Close cover"
		else if(!(stat & BROKEN) && !(coverlocked && !(stat & MAINT)) && !panel_open)
			context[SCREENTIP_LMB] = "Open cover"
	else if(tool == TOOL_SCREWDRIVER)
		if(opened)
			if(cell)
				context[SCREENTIP_LMB] = "Remove cell"
			else if(has_electronics == APC_ELECTRONICS_INSTALLED)
				context[SCREENTIP_LMB] = "Secure board"
			else if(has_electronics == APC_ELECTRONICS_SECURED)
				context[SCREENTIP_LMB] = "Unsecure board"
		else if(!(obj_flags & EMAGGED))
			context[SCREENTIP_LMB] = panel_open ? "Hide wires" : "Expose wires"
	else if(tool == TOOL_WIRECUTTER)
		if(terminal && opened)
			context[SCREENTIP_LMB] = "Cut terminal"
	else if(tool == TOOL_WELDER)
		if(opened && !has_electronics && !terminal)
			context[SCREENTIP_LMB] = "Cut from wall"
	else if(istype(held_item, /obj/item/stock_parts/cell))
		if(opened && !cell)
			context[SCREENTIP_LMB] = "Insert cell"
	else if(held_item.GetID())
		if(can_swipe)
			context[SCREENTIP_LMB] = locked ? "Unlock" : "Lock"
	else if(istype(held_item, /obj/item/stack/cable_coil))
		var/turf/host_turf = get_turf(src)
		if(opened && !terminal && has_electronics && host_turf && !host_turf.intact)
			context[SCREENTIP_LMB] = "Wire terminal"
	else if(istype(held_item, /obj/item/electronics/apc))
		if(opened && !has_electronics && !(stat & BROKEN))
			context[SCREENTIP_LMB] = "Install board"

// ---------------------------------------------------------------------------------------------------------------------
// Light fixtures: /obj/machinery/light/attackby() and attack_hand()
/obj/machinery/light/add_context(atom/source, list/context, obj/item/held_item, mob/living/user)
	if(!held_item)
		if(status != LIGHT_EMPTY)
			context[SCREENTIP_LMB] = "Remove [fitting]"
		return
	if(istype(held_item, /obj/item/light))
		if(status != LIGHT_OK && istype(held_item, light_type))
			context[SCREENTIP_LMB] = (status == LIGHT_EMPTY) ? "Insert [fitting]" : "Replace [fitting]"
	else if(status == LIGHT_EMPTY && held_item.tool_behaviour == TOOL_SCREWDRIVER)
		context[SCREENTIP_LMB] = "Open fixture"

// ---------------------------------------------------------------------------------------------------------------------
// Hydroponics trays: /obj/machinery/hydroponics/attackby() and attack_hand()
/obj/machinery/hydroponics/add_context(atom/source, list/context, obj/item/held_item, mob/living/user)
	if(!held_item)
		if(harvest)
			context[SCREENTIP_LMB] = "Harvest"
		else if(dead)
			context[SCREENTIP_LMB] = "Remove dead plant"
		return
	if(istype(held_item, /obj/item/reagent_containers))
		var/obj/item/reagent_containers/source_container = held_item
		if(!source_container.reagents?.total_volume)
			return
		if(istype(held_item, /obj/item/reagent_containers/syringe))
			var/obj/item/reagent_containers/syringe/syringe = held_item
			if(syringe.mode == 1)
				context[SCREENTIP_LMB] = "Inject"
		else if(istype(held_item, /obj/item/reagent_containers/food/snacks) || istype(held_item, /obj/item/reagent_containers/pill))
			context[SCREENTIP_LMB] = "Compost"
		else if(istype(held_item, /obj/item/reagent_containers/spray))
			context[SCREENTIP_LMB] = "Spray"
		else
			context[SCREENTIP_LMB] = "Pour in"
	else if(istype(held_item, /obj/item/seeds) && !istype(held_item, /obj/item/seeds/sample))
		if(!myseed)
			context[SCREENTIP_LMB] = "Plant"
	else if(istype(held_item, /obj/item/plant_analyzer))
		context[SCREENTIP_LMB] = myseed ? "Scan plant" : "Scan tray"
	else if(istype(held_item, /obj/item/cultivator))
		if(weedlevel > 0)
			context[SCREENTIP_LMB] = "Remove weeds"
	else if(istype(held_item, /obj/item/storage/bag/plants))
		if(harvest)
			context[SCREENTIP_LMB] = "Harvest into bag"
	else if(istype(held_item, /obj/item/shovel/spade))
		if(myseed)
			context[SCREENTIP_LMB] = "Dig up plant"
		else if(weedlevel)
			context[SCREENTIP_LMB] = "Dig up weeds"

// ---------------------------------------------------------------------------------------------------------------------
// Canisters, portable pumps and scrubbers: /obj/machinery/portable_atmospherics/attackby() and AltClick()
/obj/machinery/portable_atmospherics/add_context(atom/source, list/context, obj/item/held_item, mob/living/user)
	if(holding)
		context[SCREENTIP_ALT_LMB] = "Remove [holding.name]"
	if(!held_item || (stat & BROKEN))
		return
	if(istype(held_item, /obj/item/tank))
		context[SCREENTIP_LMB] = holding ? "Swap tank" : "Insert tank"
	else if(held_item.tool_behaviour == TOOL_WRENCH)
		if(connected_port)
			context[SCREENTIP_LMB] = "Disconnect from port"
		else if(locate(/obj/machinery/atmospherics/components/unary/portables_connector) in loc)
			context[SCREENTIP_LMB] = "Connect to port"

// Pumps, filters and mixers: their CtrlClick() and AltClick()
/obj/machinery/atmospherics/components/binary/pump/add_context(atom/source, list/context, obj/item/held_item, mob/living/user)
	context[SCREENTIP_CTRL_LMB] = on ? "Turn off" : "Turn on"
	context[SCREENTIP_ALT_LMB] = "Maximize pressure"
	return ..()

/obj/machinery/atmospherics/components/binary/volume_pump/add_context(atom/source, list/context, obj/item/held_item, mob/living/user)
	context[SCREENTIP_CTRL_LMB] = on ? "Turn off" : "Turn on"
	context[SCREENTIP_ALT_LMB] = "Maximize flow"
	return ..()

/obj/machinery/atmospherics/components/trinary/filter/add_context(atom/source, list/context, obj/item/held_item, mob/living/user)
	context[SCREENTIP_CTRL_LMB] = on ? "Turn off" : "Turn on"
	context[SCREENTIP_ALT_LMB] = "Maximize flow"
	return ..()

/obj/machinery/atmospherics/components/trinary/mixer/add_context(atom/source, list/context, obj/item/held_item, mob/living/user)
	context[SCREENTIP_CTRL_LMB] = on ? "Turn off" : "Turn on"
	context[SCREENTIP_ALT_LMB] = "Maximize pressure"
	return ..()

// Any pipe or atmos device that can come loose: /obj/machinery/atmospherics/wrench_act()
/obj/machinery/atmospherics/add_context(atom/source, list/context, obj/item/held_item, mob/living/user)
	if(held_item?.tool_behaviour == TOOL_WRENCH && can_unwrench(user))
		context[SCREENTIP_LMB] = "Unfasten"

#undef AIRLOCK_SECURITY_NONE
#undef AIRLOCK_SECURITY_METAL
#undef AIRLOCK_SECURITY_PLASTEEL_I_S
#undef AIRLOCK_SECURITY_PLASTEEL_I
#undef AIRLOCK_SECURITY_PLASTEEL_O_S
#undef AIRLOCK_SECURITY_PLASTEEL_O
#undef AIRLOCK_SECURITY_PLASTEEL
#undef APC_ELECTRONICS_MISSING
#undef APC_ELECTRONICS_INSTALLED
#undef APC_ELECTRONICS_SECURED
#undef APC_COVER_CLOSED
#undef APC_COVER_OPENED
#undef APC_COVER_REMOVED
