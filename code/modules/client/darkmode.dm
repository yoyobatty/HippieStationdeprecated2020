//Darkmode preference by Kmc2000//

/*
This lets you switch chat themes by using winset and CSS loading, you must relog to see this change (or rebuild your browseroutput datum)

Things to note:
If you change ANYTHING in hippiestation/interface/skin.dmf you need to change it here: GLOB.skin_theme lists every control with a colour.
The skin itself is written dark, so that's what a new player sees, and the chat starts dark to match.

How this works:
I've added a function to browseroutput.js which registers a cookie for darkmode and swaps the chat accordingly. You can find the button to do this under the "cog" icon next to the ping button (top right of chat)
This then swaps the window theme automatically

Thanks to spacemaniac and mcdonald for help with the JS side of this.

*/

#define SKIN_BUTTON "#2c2f33"
#define SKIN_BUTTON_TEXT "#c8d2dc"

/// Control -> params dark -> params light, every one of them.
GLOBAL_LIST_INIT(skin_theme, list(
	//Main windows
	"mainwindow" = list(list("background-color" = COLOR_DARKMODE_DARKBACKGROUND), list("background-color" = "none")),
	"split" = list(list("background-color" = COLOR_DARKMODE_DARKBACKGROUND), list("background-color" = "none")),
	"mapwindow" = list(list("background-color" = COLOR_DARKMODE_DARKBACKGROUND), list("background-color" = "none")),
	"status_bar" = list(list("background-color" = COLOR_DARKMODE_DARKBACKGROUND, "text-color" = "#e6e6e6"), list("background-color" = "none", "text-color" = "#000000")),
	"infowindow" = list(list("background-color" = COLOR_DARKMODE_BACKGROUND, "text-color" = COLOR_DARKMODE_TEXT), list("background-color" = "none", "text-color" = "#000000")),
	"info" = list(list("background-color" = COLOR_DARKMODE_BACKGROUND, "text-color" = COLOR_DARKMODE_TEXT), list("background-color" = "none", "text-color" = "#000000")),
	"outputwindow" = list(list("background-color" = COLOR_DARKMODE_BACKGROUND, "text-color" = COLOR_DARKMODE_TEXT), list("background-color" = "none", "text-color" = "#000000")),
	"browseroutput" = list(list("background-color" = COLOR_DARKMODE_BACKGROUND, "text-color" = COLOR_DARKMODE_TEXT), list("background-color" = "none", "text-color" = "#000000")),
	"output" = list(list("background-color" = COLOR_DARKMODE_DARKBACKGROUND, "text-color" = COLOR_DARKMODE_TEXT), list("background-color" = "none", "text-color" = "#000000")),
	"asset_cache_browser" = list(list("background-color" = COLOR_DARKMODE_BACKGROUND, "text-color" = COLOR_DARKMODE_TEXT), list("background-color" = "none", "text-color" = "#000000")),
	"tooltip" = list(list("background-color" = COLOR_DARKMODE_BACKGROUND, "text-color" = COLOR_DARKMODE_TEXT), list("background-color" = "none", "text-color" = "#000000")),
	//Status and verb tabs
	"statwindow" = list(list("background-color" = COLOR_DARKMODE_DARKBACKGROUND, "text-color" = COLOR_DARKMODE_TEXT), list("background-color" = "none", "text-color" = "#000000")),
	"statbrowser" = list(list("background-color" = COLOR_DARKMODE_BACKGROUND), list("background-color" = "#FFFFFF")), //the HTML stat panel; its page is themed with set_theme
	//Buttons
	"options" = list(list("background-color" = SKIN_BUTTON, "text-color" = SKIN_BUTTON_TEXT), list("background-color" = "none", "text-color" = "#000000")),
	"display" = list(list("background-color" = SKIN_BUTTON, "text-color" = SKIN_BUTTON_TEXT), list("background-color" = "none", "text-color" = "#000000")),
	"fullscreen-toggle" = list(list("background-color" = SKIN_BUTTON, "text-color" = SKIN_BUTTON_TEXT), list("background-color" = "none", "text-color" = "#000000")),
	"reconnect" = list(list("background-color" = SKIN_BUTTON, "text-color" = SKIN_BUTTON_TEXT), list("background-color" = "none", "text-color" = "#000000")),
	"changelog" = list(list("background-color" = SKIN_BUTTON, "text-color" = SKIN_BUTTON_TEXT), list("background-color" = "none", "text-color" = "#000000")),
	"rules" = list(list("background-color" = SKIN_BUTTON, "text-color" = SKIN_BUTTON_TEXT), list("background-color" = "none", "text-color" = "#000000")),
	"wiki" = list(list("background-color" = SKIN_BUTTON, "text-color" = SKIN_BUTTON_TEXT), list("background-color" = "none", "text-color" = "#000000")),
	"forum" = list(list("background-color" = SKIN_BUTTON, "text-color" = SKIN_BUTTON_TEXT), list("background-color" = "none", "text-color" = "#000000")),
	"github" = list(list("background-color" = SKIN_BUTTON, "text-color" = SKIN_BUTTON_TEXT), list("background-color" = "none", "text-color" = "#000000")),
	"report-issue" = list(list("background-color" = "#4a2222", "text-color" = SKIN_BUTTON_TEXT), list("background-color" = "none", "text-color" = "#000000")),
	"statbus" = list(list("background-color" = SKIN_BUTTON, "text-color" = SKIN_BUTTON_TEXT), list("background-color" = "none", "text-color" = "#000000")), // hippie - statbus
	// hippie -- the Say, OOC and Me buttons went with the old input bar
))

#undef SKIN_BUTTON
#undef SKIN_BUTTON_TEXT

/// Every control in one go, so the window changes once rather than a piece at a time. The chat bar stays as it is: its colours are
/// what say whether it has the keyboard, on either theme (COLOR_INPUT_ENABLED).
/client/proc/set_skin_theme(dark)
	dark_theme = dark
	var/list/changes = list()
	for(var/control in GLOB.skin_theme)
		var/list/params = GLOB.skin_theme[control][dark ? 1 : 2]
		for(var/param in params)
			changes["[control].[param]"] = params[param]
	winset(src, null, list2params(changes))
	stat_panel?.send_message("set_theme", dark ? "dark" : "light") //hippie: the HTML stat panel's page

/client/proc/force_white_theme() //There's no way round it. We're essentially changing the skin by hand. It's painful but it works, and is the way Lummox suggested.
	set_skin_theme(FALSE)

/client/proc/force_dark_theme() //Inversely, if theyre using white theme and want to swap to the superior dark theme, let's get WINSET() ing
	set_skin_theme(TRUE)
