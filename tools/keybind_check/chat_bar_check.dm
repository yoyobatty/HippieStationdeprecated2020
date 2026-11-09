// Real-client check of the one chat bar (2026-11-08: the old input bar under the chat is gone, and the talk keys, Tab and classic
// mode's typing open tg's command bar instead). Not part of the game:
// HARNESS=chat_bar_check.dm SENDER=kb_panel.ps1 tools/keybind_check/run.sh <label>
// Keys are posted to whatever has DreamSeeker's keyboard (kb_panel.ps1), so a key only reaches the bar if the bar really took it.

GLOBAL_VAR_INIT(keycheck_running, FALSE)
GLOBAL_VAR_INIT(cb_pass, 0)
GLOBAL_VAR_INIT(cb_fail, 0)
GLOBAL_VAR(cb_dom)
GLOBAL_LIST_EMPTY(cb_said) // what reached say(): a test round's lobby shows nobody's speech in the chat

/datum/preferences/save_preferences()
	return FALSE

/datum/preferences/save_character()
	return FALSE

/proc/kc_log(text)
	text2file("[time2text(world.timeofday, "hh:mm:ss")] [text]", "data/keycheck.txt")

/proc/cb_check(name, ok, detail = "")
	if(ok)
		GLOB.cb_pass++
	else
		GLOB.cb_fail++
	kc_log("[ok ? "ok   " : "WRONG"] [name][detail ? " ([detail])" : ""]")

/client/New()
	. = ..()
	if(. && !GLOB.keycheck_running)
		GLOB.keycheck_running = TRUE
		spawn(10)
			cb_run(src)

/client/Topic(href, list/href_list, hsrc)
	if(href_list["cb_dom"])
		GLOB.cb_dom = href_list["cb_dom"]
		return
	return ..()


/mob/living/say(message, bubble_type, list/spans = list(), sanitize = TRUE, datum/language/language = null, ignore_spam = FALSE, forced = null)
	GLOB.cb_said += "[message]"
	return ..()

/proc/cb_js(client/C, js, wait = 20)
	GLOB.cb_dom = null
	var/full = "var report=function(x){Byond.topic({cb_dom:String(x)});};try{[js]}catch(e){report('error: '+e.message);}"
	C << output(url_encode(full), "browseroutput:eval")
	for(var/i in 1 to wait)
		if(!isnull(GLOB.cb_dom))
			break
		sleep(1)
	return GLOB.cb_dom || ""

/// What has the page's keyboard: the tag and its text
/proc/cb_active(client/C)
	return cb_js(C, "var a=document.activeElement;report(document.hasFocus()+'|'+(a?a.tagName:'none')+'|'+(a&&a.value!==undefined?a.value:''));")

/// Types into whatever has the page's keyboard and presses Enter there, through the DOM (posted keys don't reach WebView2). FALSE if
/// the keyboard wasn't in an input.
/proc/cb_type(client/C, text)
	return cb_js(C, "var a=document.activeElement;if(!a||a.tagName!='INPUT'){report('no input');}else{var set=Object.getOwnPropertyDescriptor(HTMLInputElement.prototype,'value').set;set.call(a,a.value+[json_encode(text)]);a.dispatchEvent(new Event('input',{bubbles:true}));setTimeout(function(){a.dispatchEvent(new KeyboardEvent('keydown',{key:'Enter',code:'Enter',keyCode:13,which:13,bubbles:true}));report('typed: '+a.value);},50);}")

/// A key pressed in the page, through the DOM
/proc/cb_page_key(client/C, key)
	return cb_js(C, "var a=document.activeElement||document.body;a.dispatchEvent(new KeyboardEvent('keydown',{key:[json_encode(key)],code:[json_encode(key)],bubbles:true}));report('pressed in '+a.tagName);")

/// The chat's last line holding text, or "none"
/proc/cb_chat(client/C, text)
	return cb_js(C, "var n=document.querySelectorAll('.ChatMessage');var hit='';for(var i=0;i<n.length;i++){if(n\[i].textContent.indexOf([json_encode(text)])>=0){hit=n\[i].textContent.slice(0,80);}}report(hit||'none');")

/proc/cb_cmd(text, timeout = 20 SECONDS)
	fdel("data/kp_ack")
	fdel("data/kp_cmd")
	text2file(text, "data/kp_cmd")
	var/deadline = world.time + timeout
	while(!fexists("data/kp_ack") && world.time < deadline)
		sleep(1)
	. = fexists("data/kp_ack") ? trim(file2text("data/kp_ack")) : "no answer"
	fdel("data/kp_ack")

/proc/cb_shot(name)
	fdel("data/keycheck_shot_title")
	text2file(name, "data/keycheck_shot")
	var/deadline = world.time + 15 SECONDS
	while(fexists("data/keycheck_shot") && world.time < deadline)
		sleep(1)
	sleep(2)

/proc/cb_map(client/C)
	winset(C, "map", "focus=true")
	sleep(5)

/proc/cb_run(client/C)
	for(var/i in 1 to 600)
		if(!C)
			return
		if(C.chatOutput?.loaded && SSticker.current_state >= GAME_STATE_PREGAME && C.prefs)
			break
		sleep(1)
	text2file("go", "data/keycheck_sendkeys") // starts shot.ps1 for the pictures
	sleep(40)
	var/mob/living/carbon/human/H = new(get_turf(pick(SSjob.latejoin_trackers)))
	H.real_name = "Cb Talker"
	H.name = H.real_name
	H.ckey = C.ckey
	sleep(20)
	var/datum/preferences/P = C.prefs
	P.hotkeys = TRUE
	C.set_macros()
	C.chat_bar_hotkey_mode()
	sleep(10)
	kc_log("info hotkeys [P.hotkeys]; say on T: [!!(P.key_bindings["T"] && ("say" in P.key_bindings["T"]))], radio on Y: [!!(P.key_bindings["Y"] && ("radio" in P.key_bindings["Y"]))]")
	cb_check("the old input bar is gone", !winexists(C, "input") && !winexists(C, "saybutton"), "[winexists(C, "input")]")
	cb_check("the chat pane fills down to the bottom", winget(C, "info", "size") != null, "[winget(C, "info", "size")] of [winget(C, "infowindow", "size")]")

	// A chat verb sent empty: nothing runs, and no popup asks for the text
	cb_map(C)
	cb_cmd("key 54")
	sleep(10)
	kc_log("info [cb_type(C, "")]")
	sleep(15)
	cb_check("Enter on an empty Say does nothing, no popup", findtext(cb_cmd("key 10"), "#32770") == 0)

	// T on the map: the bar opens on Say, with the keyboard
	cb_map(C)
	kc_log("info [cb_cmd("key 54")]")
	sleep(10)
	var/active = cb_active(C)
	cb_check("T opens the bar on Say with the keyboard", findtext(active, "true|INPUT|Say ") == 1, active)
	cb_shot("chatbar_say_open")
	kc_log("info [cb_type(C, "cb-hello")]")
	sleep(15)
	cb_check("typed into it, Enter says it", ("cb-hello" in GLOB.cb_said), jointext(GLOB.cb_said, " / "))
	var/line

	// Y: radio is Say with ";"
	cb_map(C)
	kc_log("info [cb_cmd("key 59")]")
	sleep(10)
	active = cb_active(C)
	cb_check("Y opens the bar on Say with ;", findtext(active, "true|INPUT|Say ;") == 1, active)
	kc_log("info [cb_type(C, "cb-radio")]")
	sleep(15)
	cb_check("radio said with ;", (";cb-radio" in GLOB.cb_said), jointext(GLOB.cb_said, " / "))

	// O: OOC
	cb_map(C)
	kc_log("info [cb_cmd("key 4F")]")
	sleep(10)
	active = cb_active(C)
	cb_check("O opens the bar on OOC", findtext(active, "true|INPUT|OOC ") == 1, active)
	kc_log("info [cb_type(C, "cb-ooc")]")
	sleep(15)
	line = cb_chat(C, "cb-ooc")
	cb_check("OOC sent", findtext(line, "OOC"), line)

	// Tab: the bar takes the keyboard as it is
	cb_map(C)
	kc_log("info [cb_cmd("key 09")]")
	sleep(10)
	active = cb_active(C)
	cb_check("Tab gives the bar the keyboard", findtext(active, "true|INPUT|") == 1, active)

	// Escape in the bar: the map has the keyboard again, and no game menu
	cb_js(C, "var a=document.activeElement;var set=Object.getOwnPropertyDescriptor(HTMLInputElement.prototype,'value').set;set.call(a,a.value+'half typed');a.dispatchEvent(new Event('input',{bubbles:true}));report('ok');")
	sleep(3)
	kc_log("info [cb_page_key(C, "Escape")]")
	sleep(5)
	active = cb_active(C)
	cb_check("Escape with text typed clears it, the bar keeps the keyboard", findtext(active, "true|INPUT|") == 1 && !findtext(active, "half typed"), active)
	kc_log("info [cb_page_key(C, "Escape")]")
	sleep(10)
	cb_check("Escape in the bar hands the keyboard back to the map", winget(C, "map", "focus") == "true", "map focus [winget(C, "map", "focus")]")
	cb_check("and doesn't open the game menu", !C.game_menu || !SStgui.get_open_ui(C.mob, C.game_menu, "main"))

	// Escape on the map: the game menu
	cb_map(C)
	kc_log("info [cb_cmd("key 1B")]")
	sleep(15)
	cb_check("Escape on the map opens the game menu", C.game_menu && SStgui.get_open_ui(C.mob, C.game_menu, "main"))
	SStgui.close_user_uis(C.mob)
	sleep(5)

	// Classic mode: a letter typed on the map goes into the bar
	P.hotkeys = FALSE
	C.set_macros()
	sleep(10)
	cb_map(C)
	kc_log("info [cb_cmd("key 48")]")
	sleep(10)
	active = cb_active(C)
	cb_check("classic mode: a key typed on the map lands in the bar", findtext(active, "true|INPUT|") == 1 && findtext(active, "H", length(active)), active)
	cb_shot("chatbar_classic")
	P.hotkeys = TRUE
	C.set_macros()

	kc_log("info [GLOB.cb_pass] passed, [GLOB.cb_fail] wrong")
	text2file("done", "data/keycheck_shots_done")
	kc_log("done")
