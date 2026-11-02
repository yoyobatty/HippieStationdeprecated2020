GLOBAL_LIST_EMPTY(classic_keybinding_list_by_key)
GLOBAL_LIST_EMPTY(hotkey_keybinding_list_by_key)
GLOBAL_LIST_EMPTY(keybindings_by_name)

// This is a mapping from JS keys to Byond - ref: https://keycode.info/
// Hippie: BYOND's browser is Chromium since 516, which names keys differently from Internet Explorer: both are here.
GLOBAL_LIST_INIT(_kbMap, list(
	"UP" = "North",
	"RIGHT" = "East",
	"DOWN" = "South",
	"LEFT" = "West",
	"ARROWUP" = "North",
	"ARROWRIGHT" = "East",
	"ARROWDOWN" = "South",
	"ARROWLEFT" = "West",
	"INSERT" = "Insert",
	"HOME" = "Northwest",
	"PAGEUP" = "Northeast",
	"DEL" = "Delete",
	"DELETE" = "Delete",
	"END" = "Southwest",
	"PAGEDOWN" = "Southeast",
	"CLEAR" = "Center",
	"SPACEBAR" = "Space",
	" " = "Space",
	"ALT" = "Alt",
	"ALTGRAPH" = "Alt",
	"SHIFT" = "Shift",
	"CONTROL" = "Ctrl",
	"ENTER" = "Return",
	"BACKSPACE" = "Back",
	"TAB" = "Tab",
	"PAUSE" = "Pause",
	"CONTEXTMENU" = "Apps",
	"APPS" = "Apps",
	"PRINTSCREEN" = "Snapshot",
	// What the old capture window saved for the numpad's operators, for fix_browser_key_names()
	"Numpad " = "Add",
	"Numpad-" = "Subtract",
	"Numpad*" = "Multiply",
	"Numpad/" = "Divide",
	"Numpad." = "Decimal",
	))

/// The keys whose name depends on what else is held. Shift+1 is "!" to a browser, and to BYOND it's Shift and 1: e.code is the
/// key itself, whatever it would type. A numpad key is a different key to BYOND from the one with the same symbol.
GLOBAL_LIST_INIT(_kbCodeMap, list(
	"Digit0" = "0", "Digit1" = "1", "Digit2" = "2", "Digit3" = "3", "Digit4" = "4",
	"Digit5" = "5", "Digit6" = "6", "Digit7" = "7", "Digit8" = "8", "Digit9" = "9",
	"Numpad0" = "Numpad0", "Numpad1" = "Numpad1", "Numpad2" = "Numpad2", "Numpad3" = "Numpad3", "Numpad4" = "Numpad4",
	"Numpad5" = "Numpad5", "Numpad6" = "Numpad6", "Numpad7" = "Numpad7", "Numpad8" = "Numpad8", "Numpad9" = "Numpad9",
	"NumpadAdd" = "Add", "NumpadSubtract" = "Subtract", "NumpadMultiply" = "Multiply", "NumpadDivide" = "Divide", "NumpadDecimal" = "Decimal",
	"Minus" = "-", "Equal" = "=", "BracketLeft" = "\[", "BracketRight" = "]", "Backslash" = "\\", "Semicolon" = ";",
	"Quote" = "'", "Backquote" = "`", "Comma" = ",", "Period" = ".", "Slash" = "/",
	))

/// What BYOND's macros call the key a browser reported. Letters go by what they type, for the layouts that aren't QWERTY.
/proc/byond_key_name(key, code)
	var/upper = uppertext(key)
	if(length(key) == 1 && upper != lowertext(key))
		return upper
	return GLOB._kbMap[upper] || GLOB._kbCodeMap[code] || upper
