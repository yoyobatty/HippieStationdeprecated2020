// Integrated circuits self-test: the restored circuits driven in the real engine, headless.
//
// Run:      tools/circuit_check/run_circuit_check.sh   (builds its own copy, so hippiestation.dmb is left alone)
// Results:  data/circuit_check/results.txt, one PASS/FAIL line per check.
//
// Part 1 is a player's way through: a printer fed metal sheets, an assembly and three circuits printed from its menu,
// circuits slotted in, two wires run with the wirer, a power cell, the panel screwed shut, the button pressed: the
// addition circuit's 2 + 3 lands in the memory chip and the text-to-speech circuit says it to someone standing by.
// Then the analyzer's save string printed again through the printer's Load Program path, and the copy does the same.
// Part 2 sweeps every circuit type: each in its own assembly, every input pin fed a value of its type, every input
// pulse fired, saved and reloaded, its window built. Errors are caught per circuit and listed.

/datum/controller/master/Initialize(delay, init_sss, tgs_prime)
	if("circuit-selftest" in world.params)
		sleep_offline_after_initializations = FALSE //nobody connects to this, so the world has to keep ticking
		INVOKE_ASYNC(GLOBAL_PROC, GLOBAL_PROC_REF(run_circuit_selftest))
	return ..()

#define CIRCUIT_CHECK_DIR "data/circuit_check/"

/proc/run_circuit_selftest()
	sleep(5 SECONDS)
	fdel(CIRCUIT_CHECK_DIR)
	GLOB.master_mode = "extended"
	SSticker.start_immediately = TRUE
	var/round_deadline = world.time + 3 MINUTES
	while(SSticker.current_state < GAME_STATE_PLAYING && world.time < round_deadline)
		sleep(1 SECONDS)
	var/datum/circuit_selftest/test = new
	test.run_all()
	text2file(jointext(test.lines, "\n"), "[CIRCUIT_CHECK_DIR]results.txt")
	log_world("CIRCUIT CHECK: done, [test.passed] passed, [test.failed] failed")
	Master.Shutdown()
	qdel(world)

/datum/circuit_selftest
	var/list/lines = list()
	var/passed = 0
	var/failed = 0
	var/datum/turf_reservation/reservation
	var/list/turf/open/floor/room = list()
	var/list/heard = list()

/datum/circuit_selftest/proc/check(name, condition, detail)
	if(condition)
		passed++
	else
		failed++
	lines += "[condition ? "PASS" : "FAIL"] [name][isnull(detail) ? "" : " - [detail]"]"

/datum/circuit_selftest/proc/note(text)
	lines += "     [text]"

/datum/circuit_selftest/proc/run_all()
	check("round started", SSticker.current_state >= GAME_STATE_PLAYING, "state [SSticker.current_state]")
	check("circuit subsystem initialized", SScircuit.initialized && length(SScircuit.all_components) > 100, "[length(SScircuit.all_components)] circuit types, [length(SScircuit.circuit_fabricator_recipe_list)] printer categories")
	check("printer is researchable", techweb_has_design("icprinter"), "Advanced Data Theory node")
	check("starter crate orderable", !isnull(SSshuttle.supply_packs[/datum/supply_pack/science/circuitry]))
	if(!build_site())
		check("test room reserved", FALSE)
		return
	try
		player_path()
	catch(var/exception/e)
		check("player path ran to the end", FALSE, "[e] at [e.file]:[e.line]")
	try
		window_path()
	catch(var/exception/e2)
		check("window path ran to the end", FALSE, "[e2] at [e2.file]:[e2.line]")
	microphone_check()
	sweep_all_circuits()

/datum/circuit_selftest/proc/techweb_has_design(id)
	for(var/node_id in SSresearch.techweb_nodes)
		var/datum/techweb_node/N = SSresearch.techweb_nodes[node_id]
		if(id in N.design_ids)
			return TRUE
	return FALSE

/datum/circuit_selftest/proc/build_site()
	reservation = SSmapping.RequestBlockReservation(20, 20)
	if(!reservation)
		return FALSE
	var/x0 = reservation.bottom_left_coords[1] + 2
	var/y0 = reservation.bottom_left_coords[2] + 2
	var/z = reservation.bottom_left_coords[3]
	var/area/test_area = new /area/bot_gym
	for(var/x in x0 to x0 + 13)
		for(var/y in y0 to y0 + 13)
			var/turf/T = locate(x, y, z)
			var/area/old_area = T.loc
			old_area.contents -= T
			test_area.contents += T
			T.change_area(old_area, test_area)
			if(x == x0 || x == x0 + 13 || y == y0 || y == y0 + 13)
				T.ChangeTurf(/turf/closed/indestructible/riveted, flags = CHANGETURF_IGNORE_AIR)
			else
				room += T.ChangeTurf(/turf/open/floor/plasteel, flags = CHANGETURF_IGNORE_AIR)
	for(var/turf/open/F in room)
		F.air.parse_gas_string(OPENTURF_DEFAULT_ATMOS)
		F.update_visuals()
		SSair.add_to_active(F)
	sleep(2 SECONDS)
	return TRUE

/datum/circuit_selftest/proc/spot(dx, dy)
	var/turf/first = room[1]
	return locate(first.x + dx - 1, first.y + dy - 1, first.z)

/datum/circuit_selftest/proc/make_human(turf/T, name)
	var/mob/living/carbon/human/H = new(T)
	H.real_name = name
	H.name = name
	H.equip_to_slot_or_del(new /obj/item/clothing/under/color/grey(H), ITEM_SLOT_ICLOTHING)
	return H

/// Something heard that ends ": <text>"
/datum/circuit_selftest/proc/heard_line(text)
	for(var/line in heard)
		if(line == text || copytext(line, -length(": [text]")) == ": [text]")
			return TRUE
	return FALSE

/datum/circuit_selftest/proc/on_hear(datum/source, list/hearing_args)
	SIGNAL_HANDLER
	var/atom/movable/speaker = hearing_args[HEARING_SPEAKER]
	heard += speaker ? "[speaker.name]: [hearing_args[HEARING_RAW_MESSAGE]]" : "[hearing_args[HEARING_RAW_MESSAGE]]"

/// Prints one thing from the printer's menu the way its window's link does, and returns what landed in the user's hands
/datum/circuit_selftest/proc/print_from_menu(obj/item/integrated_circuit_printer/printer, mob/living/carbon/human/H, path)
	var/list/before = H.held_items.Copy()
	usr = H
	printer.Topic("build=[path]", list("build" = "[path]"))
	for(var/obj/item/I in H.held_items)
		if(!(I in before) && istype(I, path))
			return I
	for(var/obj/item/I in get_turf(printer))
		if(istype(I, path))
			return I

/datum/circuit_selftest/proc/player_path()
	var/mob/living/carbon/human/H = make_human(spot(4, 4), "Circuit Tester")
	var/mob/living/carbon/human/listener = make_human(spot(6, 4), "Bystander")
	RegisterSignal(listener, COMSIG_MOVABLE_HEAR, PROC_REF(on_hear))
	var/obj/item/integrated_circuit_printer/printer = new(spot(5, 4))
	var/datum/component/material_container/mats = printer.GetComponent(/datum/component/material_container)

	// Metal in
	var/obj/item/stack/sheet/metal/sheets = new(spot(4, 4), 50)
	H.put_in_hands(sheets)
	printer.attackby(sheets, H)
	check("metal sheets go into the printer", mats.amount(MAT_METAL) > 0, "[mats.amount(MAT_METAL)] metal")
	H.dropItemToGround(H.get_active_held_item())
	H.dropItemToGround(H.get_inactive_held_item())

	// The window builds
	var/window_ok = TRUE
	try
		printer.interact(H)
	catch(var/exception/e1)
		window_ok = "[e1] at [e1.file]:[e1.line]"
	check("printer window builds", window_ok == TRUE, window_ok == TRUE ? null : window_ok)

	// Print an assembly and three circuits, one at a time, putting each on the table (the floor) to keep a hand free
	var/metal_before = mats.amount(MAT_METAL)
	var/obj/item/electronic_assembly/A = print_from_menu(printer, H, /obj/item/electronic_assembly/medium/default)
	check("printed an assembly", istype(A), "metal [metal_before] -> [mats.amount(MAT_METAL)]")
	if(!A)
		return
	H.dropItemToGround(A)
	var/obj/item/integrated_circuit/input/button/button = print_from_menu(printer, H, /obj/item/integrated_circuit/input/button)
	H.dropItemToGround(button)
	var/obj/item/integrated_circuit/arithmetic/addition/adder = print_from_menu(printer, H, /obj/item/integrated_circuit/arithmetic/addition)
	H.dropItemToGround(adder)
	var/obj/item/integrated_circuit/memory/memory = print_from_menu(printer, H, /obj/item/integrated_circuit/memory)
	H.dropItemToGround(memory)
	var/obj/item/integrated_circuit/output/text_to_speech/speaker = print_from_menu(printer, H, /obj/item/integrated_circuit/output/text_to_speech)
	H.dropItemToGround(speaker)
	var/obj/item/integrated_circuit/converter/num2text/to_text = print_from_menu(printer, H, /obj/item/integrated_circuit/converter/num2text)
	H.dropItemToGround(to_text)
	check("printed button, adder, memory, speaker, number-to-text", button && adder && memory && speaker && to_text, "metal left [mats.amount(MAT_METAL)]")
	if(!(button && adder && memory && speaker && to_text))
		return

	// Slot them in by hand
	for(var/obj/item/integrated_circuit/IC in list(button, adder, memory, to_text, speaker))
		H.put_in_hands(IC)
		A.attackby(IC, H)
	check("circuits slot into the assembly", length(A.assembly_components) == 5, "[length(A.assembly_components)] inside")

	// Wire: button pulse -> adder compute; adder result -> memory input; adder done -> memory set;
	// memory output -> num2text input; memory on set -> num2text convert; num2text text -> speaker text; num2text done -> speaker
	var/obj/item/integrated_electronics/wirer/wirer = new(spot(4, 4))
	H.put_in_hands(wirer)
	var/list/wires = list(
		list(button.activators[1], adder.activators[1]),
		list(adder.outputs[1], memory.inputs[1]),
		list(adder.activators[2], memory.activators[1]),
		list(memory.outputs[1], to_text.inputs[1]),
		list(memory.activators[2], to_text.activators[1]),
		list(to_text.outputs[1], speaker.inputs[1]),
		list(to_text.activators[2], speaker.activators[1]))
	var/wired = 0
	for(var/list/pair in wires)
		var/datum/integrated_io/from = pair[1]
		var/datum/integrated_io/into = pair[2]
		wirer.wire(from, H)
		wirer.wire(into, H)
		if(into in from.linked)
			wired++
	check("the wirer connects pins", wired == length(wires), "[wired]/[length(wires)] wires")
	H.dropItemToGround(wirer)

	// Constants in the adder's inputs: what the debugger would write (its prompt needs a client)
	var/datum/integrated_io/in_a = adder.inputs[1]
	var/datum/integrated_io/in_b = adder.inputs[2]
	in_a.write_data_to_pin(2)
	in_b.write_data_to_pin(3)

	// Power and close
	var/obj/item/stock_parts/cell/high/cell = new(spot(4, 4))
	H.put_in_hands(cell)
	A.attackby(cell, H)
	check("a power cell slots in", A.battery == cell)
	var/obj/item/screwdriver/screwdriver = new(spot(4, 4))
	H.put_in_hands(screwdriver)
	A.screwdriver_act(H, screwdriver)
	check("the panel screws shut", !A.opened)
	H.dropItemToGround(screwdriver)

	// Press the button
	H.put_in_hands(A)
	A.attack_self(H)
	sleep(5)
	check("button -> adder -> memory: 2 + 3 stored", memory.get_pin_data(IC_OUTPUT, 1) == 5, "memory holds [memory.get_pin_data(IC_OUTPUT, 1)]")
	check("text-to-speech said it to someone nearby", heard_line("5"), "heard: [heard.len ? jointext(heard, " | ") : "nothing"]")
	check("the press drew power", cell.charge < cell.maxcharge, "[cell.charge]/[cell.maxcharge]")

	// The analyzer's save string, printed again through Load Program
	var/save = SScircuit.save_electronic_assembly(A)
	check("assembly saves to a string", istext(save) && length(save) > 20, "[length(save)] chars")
	var/list/program = SScircuit.validate_electronic_assembly(save)
	check("the save validates", islist(program), "[islist(program) ? "metal cost [program["metal_cost"]], complexity [program["complexity"]]/[program["max_complexity"]]" : program]")
	if(!islist(program))
		return
	CONFIG_SET(flag/ic_printing, TRUE)
	printer.program = program
	usr = H
	H.dropItemToGround(A)
	var/turf/printer_turf = get_turf(printer)
	var/list/before = list()
	for(var/obj/item/electronic_assembly/old in printer_turf)
		before += old
	printer.Topic("print=print", list("print" = "print"))
	var/wait_until = world.time + 3 MINUTES + 10 SECONDS
	var/obj/item/electronic_assembly/copy
	while(!copy && world.time < wait_until)
		sleep(1 SECONDS)
		for(var/obj/item/electronic_assembly/new_one in printer_turf)
			if(!(new_one in before))
				copy = new_one
	check("Load Program prints a copy (slow clone)", copy, "after [round((world.time - (wait_until - 3 MINUTES - 10 SECONDS)) / 10)] s")
	if(!copy)
		return
	var/obj/item/integrated_circuit/memory/copy_memory = locate() in copy.assembly_components
	var/obj/item/integrated_circuit/input/button/copy_button = locate() in copy.assembly_components
	var/obj/item/stock_parts/cell/high/cell2 = new(spot(4, 4))
	H.put_in_hands(cell2)
	copy.attackby(cell2, H)
	heard.Cut()
	copy_button.ask_for_input(H)
	sleep(5)
	var/copy_holds = copy_memory ? copy_memory.get_pin_data(IC_OUTPUT, 1) : "no memory chip"
	check("the copy works the same", copy_holds == 5 && heard_line("5"), "memory [copy_holds], heard [jointext(heard, " | ")]")

	// Hostile mobs see an armed assembly
	var/obj/item/electronic_assembly/armed = new /obj/item/electronic_assembly/medium/gun(spot(8, 8))
	var/obj/item/integrated_circuit/manipulation/weapon_firing/gun_circuit = new(armed)
	armed.add_component(gun_circuit)
	check("an armed assembly is a hostile-mob target", (armed in GLOB.hostile_machines))
	qdel(armed)
	check("and stops being one when destroyed", !(armed in GLOB.hostile_machines))
	UnregisterSignal(listener, COMSIG_MOVABLE_HEAR)

/// Every circuit type: in its own assembly with an endless cell, every input fed, every input pulse fired, saved,
/// validated, reloaded, its window built. A circuit that errors is listed with where.
/// Each one runs in its own proc: an error caught in the same proc as a for-in loop leaves BYOND's loop walking
/// whatever list the error was thrown from (the first run swept the examiner's pin names after it broke).
/datum/circuit_selftest/proc/sweep_all_circuits()
	var/mob/living/carbon/human/H = make_human(spot(10, 10), "Sweep Tester")
	var/turf/bench = spot(10, 9)
	var/list/broken = list()
	var/list/paths = subtypesof(/obj/item/integrated_circuit)
	var/swept = 0
	for(var/i in 1 to length(paths))
		var/path = paths[i]
		var/obj/item/integrated_circuit/proto = path
		if(!(initial(proto.spawn_flags) & (IC_SPAWN_DEFAULT | IC_SPAWN_RESEARCH)))
			continue // abstract parents and admin-only types: not in the printer
		swept++
		var/problem = sweep_one(path, H, bench)
		if(problem)
			broken += problem
		for(var/atom/movable/leftover in range(3, bench))
			if(!ismob(leftover) && !isturf(leftover))
				qdel(leftover)
	check("every circuit builds, takes input, pulses, saves and reloads", !length(broken), "[swept] circuits, [length(broken)] with errors")
	for(var/line in broken)
		note(line)

/datum/circuit_selftest/proc/sweep_one(path, mob/living/carbon/human/H, turf/bench)
	var/where = "build"
	var/obj/item/electronic_assembly/A
	try
		A = new /obj/item/electronic_assembly/drone/default(bench)
		A.allowed_circuit_action_flags = IC_ACTION_MOVEMENT | IC_ACTION_COMBAT | IC_ACTION_LONG_RANGE
		A.max_components = 1000
		A.max_complexity = 1000
		A.battery = new /obj/item/stock_parts/cell/infinite(A)
		var/obj/item/integrated_circuit/IC = new path(A)
		A.add_component(IC)
		where = "inputs"
		for(var/datum/integrated_io/pin in IC.inputs)
			pin.write_data_to_pin(sample_value(pin, H))
		where = "pulses"
		for(var/datum/integrated_io/activate/pulse in IC.activators)
			if(istype(pulse, /datum/integrated_io/activate/out))
				continue
			usr = null // nothing prompts a player mid-sweep
			IC.check_then_do_work(pulse.ord, TRUE)
		where = "save"
		var/save = SScircuit.save_electronic_assembly(A)
		var/list/program = SScircuit.validate_electronic_assembly(save)
		if(!islist(program))
			. = "[path]: save doesn't validate ([program])"
		else
			where = "reload"
			var/obj/item/electronic_assembly/reloaded = SScircuit.load_electronic_assembly(bench, program)
			if(!(locate(path) in reloaded.assembly_components))
				. = "[path]: reloaded copy lost it"
			qdel(reloaded)
		where = "window"
		A.opened = TRUE
		A.ui_interact(H)
		IC.ui_interact(H)
		if(!istext(json_encode(A.ui_data(H))))
			. = "[path]: the assembly window's data doesn't encode"
		var/list/node = IC.ui_node_data()
		var/pins = length(node["inputs"]) + length(node["outputs"]) + length(node["pulse_in"]) + length(node["pulse_out"])
		if(pins != length(IC.inputs) + length(IC.outputs) + length(IC.activators))
			. = "[path]: the graph shows [pins] pins of [length(IC.inputs) + length(IC.outputs) + length(IC.activators)]"
	catch(var/exception/e)
		. = "[path] ([where]): [e] at [e.file]:[e.line]"
	if(A && !QDELETED(A))
		qdel(A)

/// A microphone wired to a text-to-speech circuit repeats what's said next to it
/datum/circuit_selftest/proc/microphone_check()
	var/mob/living/carbon/human/talker = make_human(spot(3, 10), "Talker")
	var/mob/living/carbon/human/listener = make_human(spot(5, 10), "Listener")
	heard.Cut()
	RegisterSignal(listener, COMSIG_MOVABLE_HEAR, PROC_REF(on_hear))
	talker.say("just checking")
	sleep(2)
	var/plain = 0
	for(var/line in heard)
		if(findtext(line, "just checking"))
			plain++
	check("plain speech is heard once", plain == 1, "heard: [jointext(heard, " | ")]")
	heard.Cut()
	var/obj/item/electronic_assembly/medium/default/A = new(spot(4, 10))
	A.battery = new /obj/item/stock_parts/cell/high(A)
	var/obj/item/integrated_circuit/input/microphone/mic = new(A)
	A.add_component(mic)
	var/obj/item/integrated_circuit/output/text_to_speech/tts = new(A)
	A.add_component(tts)
	var/datum/integrated_io/heard_text = mic.outputs[2]
	var/datum/integrated_io/say_text = tts.inputs[1]
	heard_text.connect_pin(say_text)
	var/datum/integrated_io/heard_pulse = mic.activators[1]
	var/datum/integrated_io/say_pulse = tts.activators[1]
	heard_pulse.connect_pin(say_pulse)
	talker.say("testing the parrot")
	sleep(2)
	var/repeats = 0
	for(var/line in heard)
		if(findtext(line, "testing the parrot") && findtext(line, "electronic"))
			repeats++
	check("a microphone in an assembly hears, and the speaker repeats it", repeats >= 1, "heard: [jointext(heard, " | ")]")
	qdel(A)
	UnregisterSignal(listener, COMSIG_MOVABLE_HEAR)

/datum/circuit_selftest/proc/sample_value(datum/integrated_io/pin, mob/living/carbon/human/H)
	if(istype(pin, /datum/integrated_io/number) || istype(pin, /datum/integrated_io/index))
		return 1
	if(istype(pin, /datum/integrated_io/boolean))
		return TRUE
	if(istype(pin, /datum/integrated_io/dir))
		return NORTH
	if(istype(pin, /datum/integrated_io/color))
		return "#FF0000"
	if(istype(pin, /datum/integrated_io/char))
		return "a"
	if(istype(pin, /datum/integrated_io/string))
		return "test"
	if(istype(pin, /datum/integrated_io/ref))
		return WEAKREF(H)
	if(istype(pin, /datum/integrated_io/lists))
		return list(1, 2, 3)
	if(istype(pin, /datum/integrated_io/selfref))
		return null
	return 1

// The tgui windows (circuits_tgui.dm), driven through ui_act as their buttons do: a stub window that says interactive
// stands in for a real one (nobody connects to this world)

/datum/tgui/circuit_stub/New()
	status = UI_INTERACTIVE

/datum/circuit_selftest/proc/act(datum/D, mob/user, action, list/params = list())
	var/datum/tgui/circuit_stub/stub = new
	usr = user
	return D.ui_act(action, params, stub, GLOB.default_state)

/datum/circuit_selftest/proc/hold(mob/living/carbon/human/H, obj/item/I)
	var/obj/item/old = H.get_active_held_item()
	if(old && old != I)
		H.dropItemToGround(old)
	if(I && H.get_active_held_item() != I)
		H.put_in_active_hand(I)

/datum/circuit_selftest/proc/window_path()
	var/mob/living/carbon/human/H = make_human(spot(4, 7), "Window Tester")
	var/obj/item/integrated_circuit_printer/printer = new(spot(5, 7))
	var/obj/item/stack/sheet/metal/sheets = new(spot(4, 7), 50)
	hold(H, sheets)
	printer.attackby(sheets, H)
	hold(H, null)

	// Printer window: the shop data, pictures, and printing from it
	var/list/static_data = printer.ui_static_data(H)
	var/list/categories = static_data["categories"]
	var/items = 0
	var/pictured = 0
	var/datum/asset/spritesheet/sheet = get_asset_datum(/datum/asset/spritesheet/circuits)
	var/research_path
	for(var/list/cat in categories)
		for(var/list/item in cat["items"])
			items++
			if(sheet.sprites[item["icon"]])
				pictured++
			if(item["research"] && !research_path)
				research_path = item["path"]
	check("printer window lists the parts with pictures", items > 100 && pictured > items * 0.9, "[length(categories)] categories, [items] parts, [pictured] pictured")
	check("printer window data encodes", istext(json_encode(printer.ui_data(H))))
	var/obj/item/electronic_assembly/A
	var/datum/component/material_container/mats = printer.GetComponent(/datum/component/material_container)
	var/metal_was = mats.amount(MAT_METAL)
	var/acted = act(printer, H, "build", list("path" = "[/obj/item/electronic_assembly/medium/default]"))
	A = locate() in H.held_items
	if(!A)
		A = locate() in range(1, printer)
	check("Print from the printer window", istype(A), "ui_act [acted], metal [metal_was] -> [mats.amount(MAT_METAL)], adjacent [H.Adjacent(printer)], can use [H.canUseTopic(printer, BE_CLOSE)], printable [printer.can_print_type(/obj/item/electronic_assembly/medium/default)]")
	if(!A)
		return
	H.dropItemToGround(A)
	var/obj/item/stock_parts/cell/high/cell = new(spot(4, 7))
	A.battery = cell
	cell.forceMove(A)
	var/turf/T = get_turf(printer)
	var/count_before = length(T.contents) + length(H.held_items - null)
	if(research_path)
		act(printer, H, "build", list("path" = research_path))
	act(printer, H, "build", list("path" = "[/obj/item/gun/energy/laser]"))
	check("the printer won't print research parts without the disk, or things it doesn't list", length(T.contents) + length(H.held_items - null) == count_before && !(locate(/obj/item/gun/energy/laser) in range(1, printer)), "research part [research_path]")

	// Parts in by hand
	var/obj/item/integrated_circuit/input/button/button = new(spot(4, 7))
	var/obj/item/integrated_circuit/arithmetic/addition/adder = new(spot(4, 7))
	var/obj/item/integrated_circuit/memory/memory = new(spot(4, 7))
	for(var/obj/item/integrated_circuit/IC in list(button, adder, memory))
		hold(H, IC)
		A.attackby(IC, H)
	check("parts slot in", length(A.assembly_components) == 3)
	var/list/data = A.ui_data(H)
	check("assembly window lists the parts as nodes", length(data["components"]) == 3 && istext(json_encode(data)), "[length(data["components"])] nodes")
	check("no tool: the window says look only", data["tool"]["kind"] == "none")

	// Tool rules: no tool, nothing set
	var/datum/integrated_io/in_a = adder.inputs[1]
	var/datum/integrated_io/in_b = adder.inputs[2]
	act(A, H, "set", list("ref" = REF(adder), "pin" = REF(in_a), "type" = "number", "value" = "2"))
	check("no tool, no data written", isnull(in_a.data), "[in_a.data]")

	// Multitool: wire button -> adder by clicking two dots, set numbers typed in the window
	var/obj/item/multitool/multitool = new(spot(4, 7))
	hold(H, multitool)
	data = A.ui_data(H)
	check("the window sees the multitool", data["tool"]["kind"] == "multitool")
	var/datum/integrated_io/press = button.activators[1]
	var/datum/integrated_io/compute = adder.activators[1]
	act(A, H, "wire", list("ref" = REF(button), "pin" = REF(press)))
	data = A.ui_data(H)
	check("first dot: the multitool holds that pin", multitool.selected_io == press && data["tool"]["selected"] == REF(press))
	act(A, H, "wire", list("ref" = REF(adder), "pin" = REF(compute)))
	check("second dot: wired", (compute in press.linked) && !multitool.selected_io)
	act(A, H, "set", list("ref" = REF(adder), "pin" = REF(in_a), "type" = "number", "value" = "2"))
	act(A, H, "set", list("ref" = REF(adder), "pin" = REF(in_b), "type" = "number", "value" = "3"))
	check("numbers typed in the window", in_a.data == 2 && in_b.data == 3, "[in_a.data], [in_b.data]")
	var/datum/integrated_io/result = adder.outputs[1]
	var/datum/integrated_io/mem_in = memory.inputs[1]
	act(A, H, "wire", list("ref" = REF(adder), "pin" = REF(result)))
	act(A, H, "wire", list("ref" = REF(memory), "pin" = REF(mem_in)))
	act(A, H, "wire", list("ref" = REF(adder), "pin" = REF(adder.activators[2])))
	act(A, H, "wire", list("ref" = REF(memory), "pin" = REF(memory.activators[1])))
	act(A, H, "data", list("ref" = REF(adder), "pin" = REF(compute))) // a pulse pin's bolt pulses it
	sleep(2)
	check("pulse from the window: 2 + 3 stored", memory.get_pin_data(IC_OUTPUT, 1) == 5, "memory holds [memory.get_pin_data(IC_OUTPUT, 1)]")
	act(A, H, "set", list("ref" = REF(memory), "pin" = REF(mem_in), "type" = "string", "value" = "hi <b>there</b>"))
	check("text typed into an any pin, escaped", mem_in.data == html_encode("hi <b>there</b>"), "[mem_in.data]")
	act(A, H, "set", list("ref" = REF(memory), "pin" = REF(mem_in), "type" = "null"))
	check("null typed into an any pin", isnull(mem_in.data))
	act(A, H, "unwire", list("ref" = REF(button), "pin" = REF(press), "link" = REF(compute)))
	check("a wire clicked: cut", !(compute in press.linked))
	act(A, H, "wire", list("ref" = REF(button), "pin" = REF(press)))
	act(A, H, "cancel_wire", list("ref" = REF(button)))
	check("Cancel lets go of the held pin", !multitool.selected_io)

	// A list pin edited in the window
	var/obj/item/integrated_circuit/lister
	var/datum/integrated_io/lists/list_pin
	for(var/path in SScircuit.cached_components)
		var/obj/item/integrated_circuit/proto = SScircuit.cached_components[path]
		if(!(proto.spawn_flags & IC_SPAWN_DEFAULT))
			continue
		for(var/datum/integrated_io/lists/L in proto.inputs)
			lister = path
			break
		if(lister)
			break
	if(lister)
		var/obj/item/integrated_circuit/LC = new lister(A)
		A.add_component(LC)
		for(var/datum/integrated_io/lists/L in LC.inputs)
			list_pin = L
			break
		act(A, H, "list_add", list("ref" = REF(LC), "pin" = REF(list_pin), "type" = "number", "value" = "5"))
		act(A, H, "list_add", list("ref" = REF(LC), "pin" = REF(list_pin), "type" = "string", "value" = "x"))
		act(A, H, "list_swap", list("ref" = REF(LC), "pin" = REF(list_pin), "pos" = "2", "other" = "1"))
		act(A, H, "list_edit", list("ref" = REF(LC), "pin" = REF(list_pin), "pos" = "2", "type" = "number", "value" = "7"))
		var/list/L1 = list_pin.data
		check("list pin: add, swap, edit", L1.len == 2 && L1[1] == "x" && L1[2] == 7, "[json_encode(L1)]")
		act(A, H, "list_remove", list("ref" = REF(LC), "pin" = REF(list_pin), "pos" = "1"))
		check("list pin: remove", L1.len == 1 && L1[1] == 7, "[json_encode(L1)]")
		act(A, H, "list_clear", list("ref" = REF(LC), "pin" = REF(list_pin)))
		check("list pin: clear", !L1.len)
	else
		check("a printable circuit with a list input", FALSE)

	// Debugger: a value clicked writes its memory
	var/obj/item/integrated_electronics/debugger/debugger = new(spot(4, 7))
	debugger.data_to_write = 9
	hold(H, debugger)
	act(A, H, "data", list("ref" = REF(adder), "pin" = REF(in_a)))
	check("debugger writes its memory to a clicked value", in_a.data == 9, "[in_a.data]")
	data = A.ui_data(H)
	check("the window sees the debugger", data["tool"]["kind"] == "debugger")

	// Wirer: dots wire, a wire cuts only in unwire mode
	var/obj/item/integrated_electronics/wirer/wirer = new(spot(4, 7))
	hold(H, wirer)
	act(A, H, "wire", list("ref" = REF(button), "pin" = REF(press)))
	act(A, H, "wire", list("ref" = REF(adder), "pin" = REF(compute)))
	check("wirer: two dots wire", compute in press.linked)
	act(A, H, "unwire", list("ref" = REF(button), "pin" = REF(press), "link" = REF(compute)))
	check("wirer in wire mode doesn't cut", compute in press.linked)
	wirer.attack_self(H) // to unwire
	act(A, H, "unwire", list("ref" = REF(button), "pin" = REF(press), "link" = REF(compute)))
	check("wirer in unwire mode cuts", !(compute in press.linked))

	// Layout, order, names, remove
	act(A, H, "move", list("ref" = REF(adder), "x" = "120", "y" = "60"))
	check("a dragged chip keeps its place", adder.graph_x == 120 && adder.graph_y == 60)
	act(A, H, "arrange", list("layout" = "[REF(button)],10,20;[REF(memory)],400,30;junk"))
	check("Arrange stores every chip's place", button.graph_x == 10 && button.graph_y == 20 && memory.graph_x == 400)
	var/pos_before = A.assembly_components.Find(button)
	act(A, H, "order", list("ref" = REF(button), "dir" = "down"))
	check("parts move down the order", A.assembly_components.Find(button) == pos_before + 1)
	act(A, H, "rename", list("name" = "Doorbell"))
	check("assembly renamed in the window", A.name == "Doorbell", A.name)
	act(A, H, "rename_component", list("ref" = REF(adder), "name" = "Sum"))
	check("part renamed in the window", adder.displayed_name == "Sum", adder.displayed_name)
	hold(H, null)
	act(A, H, "remove", list("ref" = REF(memory)))
	check("a part removed from the window", !(memory in A.assembly_components))
	act(A, H, "remove_cell")
	check("the cell removed from the window", !A.battery)

	// A loose circuit gets a one-chip window
	hold(H, multitool)
	var/list/loose = memory.ui_data(H)
	check("a loose circuit's window has one chip", loose["loose"] && length(loose["components"]) == 1)
	act(memory, H, "set", list("ref" = REF(memory), "pin" = REF(mem_in), "type" = "number", "value" = "4"))
	check("a loose circuit's pin set from its window", mem_in.data == 4, "[mem_in.data]")

	// Load Program from the window
	CONFIG_SET(flag/ic_printing, TRUE)
	var/save = SScircuit.save_electronic_assembly(A)
	act(printer, H, "load", list("code" = save))
	var/list/pdata = printer.ui_data(H)
	check("Load Program from the window", islist(printer.program) && pdata["program"], "[length(save)] chars")
	act(printer, H, "unload")
	check("Unload", !printer.program)
	act(printer, H, "load", list("code" = "not a program"))
	check("junk code isn't loaded", !printer.program)

	// The analyzer's code window
	var/datum/circuit_code_view/V = new("test", save)
	var/list/vdata = V.ui_static_data(H)
	check("code window carries the code", vdata["code"] == save)
	qdel(V)
	var/list/outline = circuit_outline(A)
	var/list/outline_parts = outline["parts"]
	var/list/first_values = outline_parts.len ? outline_parts[1]["values"] : list()
	var/typed = 0
	for(var/list/part in outline_parts)
		typed += length(part["values"])
	check("the code window's outline lists the parts, typed values and wires", outline_parts.len == length(A.assembly_components) && typed > 0 && istext(json_encode(outline)), "[outline_parts.len] parts, [typed] typed values ([length(first_values)] on the first), [length(outline["wires"])] wires")
	qdel(A)
	qdel(printer)

#undef CIRCUIT_CHECK_DIR
