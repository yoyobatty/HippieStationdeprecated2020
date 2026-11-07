// The cell timer, the keycard authentication device and the scanner gate redone (tgui-next BrigTimer.js,
// KeycardAuth.js, ScannerGate.js): sizes for the new layouts, and the scanner gate's lock kept by the gate itself.

/obj/machinery/door_timer
	ui_x = 360
	ui_y = 262

/obj/machinery/keycard_auth
	ui_x = 380
	ui_y = 262

/obj/machinery/scanner_gate
	ui_x = 470
	ui_y = 340

/// The old window only hid its controls while the gate was locked; the gate took a new mode from anybody who sent one
/obj/machinery/scanner_gate/ui_act(action, params)
	if(locked && action != "toggle_lock")
		return
	return ..()
