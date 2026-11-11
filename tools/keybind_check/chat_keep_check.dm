// Real-client check: what's typed in the chat bar stays there when the mob's verbs change (round-13.09.35: being stripped in a cell,
// every item with verbs of its own taken off sent the bar a fresh verb list, and each one wiped the message being typed).
// Not part of the game: HARNESS=chat_keep_check.dm SENDER=kb_panel.ps1 MAP=testbench tools/keybind_check/run.sh chatkeep
// Uses chat_bar_check.dm's way in: keys posted by kb_panel.ps1, the page read and typed into through browseroutput:eval.

GLOBAL_VAR_INIT(keycheck_running, FALSE)
GLOBAL_VAR_INIT(ck_pass, 0)
GLOBAL_VAR_INIT(ck_fail, 0)
GLOBAL_VAR(ck_dom)
GLOBAL_LIST_EMPTY(ck_said)

/datum/preferences/save_preferences()
	return FALSE

/datum/preferences/save_character()
	return FALSE

/proc/kc_log(text)
	text2file("[time2text(world.timeofday, "hh:mm:ss")] [text]", "data/keycheck.txt")

/proc/ck_check(name, ok, detail = "")
	if(ok)
		GLOB.ck_pass++
	else
		GLOB.ck_fail++
	kc_log("[ok ? "ok   " : "WRONG"] [name][detail ? " ([detail])" : ""]")

/client/New()
	. = ..()
	if(. && !GLOB.keycheck_running)
		GLOB.keycheck_running = TRUE
		spawn(10)
			ck_run(src)

/client/Topic(href, list/href_list, hsrc)
	if(href_list["ck_dom"])
		GLOB.ck_dom = href_list["ck_dom"]
		return
	return ..()

/mob/living/say(message, bubble_type, list/spans = list(), sanitize = TRUE, datum/language/language = null, ignore_spam = FALSE, forced = null)
	GLOB.ck_said += "[message]"
	return ..()

/proc/ck_js(client/C, js, wait = 20)
	GLOB.ck_dom = null
	var/full = "var report=function(x){setTimeout(function(){Byond.topic({ck_dom:String(x)});},0);};try{[js]}catch(e){report('error: '+e.message);}"
	C << output(url_encode(full), "browseroutput:eval")
	for(var/i in 1 to wait)
		if(!isnull(GLOB.ck_dom))
			break
		sleep(1)
	return GLOB.ck_dom || ""

/// The chat bar's text: the focused input's, else every input on the page
/proc/ck_bar(client/C)
	return ck_js(C, "var a=document.activeElement;var v=new Array();document.querySelectorAll('input').forEach(function(i){v.push((i===a?'*':'')+(i.placeholder||i.className||'input')+'='+i.value);});report('<'+v.join('> <')+'>');")

/// Typed into the focused input, no Enter
/proc/ck_type(client/C, text)
	return ck_js(C, "var a=document.activeElement;if(!a||a.tagName!='INPUT'){report('no input');}else{var set=Object.getOwnPropertyDescriptor(HTMLInputElement.prototype,'value').set;set.call(a,a.value+[json_encode(text)]);a.dispatchEvent(new Event('input',{bubbles:true}));setTimeout(function(){report(a.value);},50);}")

/proc/ck_enter(client/C)
	return ck_js(C, "var a=document.activeElement;if(!a||a.tagName!='INPUT'){report('no input');}else{a.dispatchEvent(new KeyboardEvent('keydown',{key:'Enter',code:'Enter',keyCode:13,which:13,bubbles:true}));report('sent');}")

/proc/ck_cmd(text, timeout = 20 SECONDS)
	fdel("data/kp_ack")
	fdel("data/kp_cmd")
	text2file(text, "data/kp_cmd")
	var/deadline = world.time + timeout
	while(!fexists("data/kp_ack") && world.time < deadline)
		sleep(1)
	. = fexists("data/kp_ack") ? trim(file2text("data/kp_ack")) : "no answer"
	fdel("data/kp_ack")

/proc/ck_run(client/C)
	for(var/i in 1 to 600)
		if(!C)
			return
		if(C.chatOutput?.loaded && SSticker.current_state >= GAME_STATE_PREGAME && C.prefs)
			break
		sleep(1)
	text2file("go", "data/keycheck_sendkeys") // starts kb_panel.ps1
	sleep(40)
	var/mob/living/carbon/human/H = new(get_turf(pick(SSjob.latejoin_trackers)))
	H.real_name = "Ck Talker"
	H.name = H.real_name
	H.equipOutfit(/datum/outfit/job/assistant)
	H.ckey = C.ckey
	sleep(20)
	var/datum/preferences/P = C.prefs
	P.hotkeys = TRUE
	C.set_macros()
	C.chat_bar_hotkey_mode()
	sleep(10)

	// The bar opened on Say with T, a message typed and not sent
	winset(C, "map", "focus=true")
	sleep(5)
	kc_log("info T: [ck_cmd("key 54")]")
	sleep(10)
	kc_log("info typed: [ck_type(C, "hold on a sec")]")
	sleep(5)
	var/before = ck_bar(C)
	ck_check("the message is in the bar", findtext(before, "hold on a sec"), "read: [before]")

	// A fresh verb list, as every verb change sends (command_bar.dm /client/init_verbs())
	C.chatOutput.send_command_bar_verbs()
	sleep(10)
	var/after_send = ck_bar(C)
	ck_check("still there after a fresh verb list", findtext(after_send, "hold on a sec"), "read: [after_send]")

	// Being stripped: things with verbs of their own come off one after another, and the stat panel sends the bar each new list
	for(var/obj/item/I in list(H.ears, H.wear_id, H.belt, H.back, H.shoes))
		H.dropItemToGround(I, TRUE)
		C.init_verbs()
		sleep(5)
	var/after_strip = ck_bar(C)
	ck_check("still there after being stripped", findtext(after_strip, "hold on a sec"), "read: [after_strip]")

	// And it still goes when sent
	kc_log("info enter: [ck_enter(C)]")
	sleep(15)
	ck_check("sent as Say", ("hold on a sec" in GLOB.ck_said), GLOB.ck_said.Join(" / "))

	// An empty bar is still set up afresh: Say ready to type into
	sleep(5)
	C.chatOutput.send_command_bar_verbs()
	sleep(10)
	var/empty = ck_bar(C)
	ck_check("an empty bar is still on Say", findtext(empty, "Say"), "read: [empty]")

	kc_log("[GLOB.ck_pass] ok, [GLOB.ck_fail] wrong")
	text2file("done", "data/keycheck_shots_done")
	sleep(5)
	kc_log("done")
	winset(C, null, "command=.quit")
	sleep(5)
	del(world)
