// Real-client check of the href fixes (2026-11-12). Not part of the game: tools/keybind_check/run_href_check.sh <label>
// Results in data/hrefcheck_<label>.txt.
//
// The chat: a line with a picture and two kinds of game link (they must still work), raw HTML sent straight to the chat (the
// page must run none of it) and HTML through a ticket (the server must send it as text). Then Topic()s forged by this client
// at things that aren't theirs: a borg's law switches, a pAI's software, mech equipment, a Ripley's hold, a borer, someone
// else's tgui window. Each forged one must do nothing and the owner's own must still work. Last, the stat panel's cap.

GLOBAL_VAR_INIT(xc_running, FALSE)
GLOBAL_LIST_EMPTY(xc_hits)
GLOBAL_VAR(xc_dom)
GLOBAL_VAR_INIT(xc_pass, 0)
GLOBAL_VAR_INIT(xc_fail, 0)

/proc/xc_log(text)
	text2file("[time2text(world.timeofday, "hh:mm:ss")] [text]", "data/hrefcheck.txt")

/proc/xc_check(name, ok, detail = "")
	if(ok)
		GLOB.xc_pass++
	else
		GLOB.xc_fail++
	xc_log("[ok ? "ok   " : "WRONG"] [name][detail ? " ([detail])" : ""]")

// The client may come in as the user's own key: nothing of theirs is written
/datum/preferences/save_preferences()
	return FALSE

/datum/preferences/save_character()
	return FALSE

/client/New()
	GLOB.player_history_dir = "data/hrefcheck_history/" // the test ticket goes in the player's history: not their real one
	. = ..()
	if(. && !GLOB.xc_running)
		GLOB.xc_running = TRUE
		spawn(10)
			xc_run(src)

/client/Topic(href, list/href_list, hsrc)
	if(href_list["xss_probe"])
		GLOB.xc_hits |= "script:[href_list["xss_probe"]]"
		return
	if(href_list["link_probe"])
		GLOB.xc_hits |= "link:[href_list["link_probe"]]"
		return
	if(href_list["xc_dom"])
		GLOB.xc_dom = href_list["xc_dom"]
		return
	return ..()

/// Runs js in the chat page; what it hands report() comes back. No square brackets in it unescaped: DM reads them.
/proc/xc_js(client/C, js, wait = 30)
	GLOB.xc_dom = null
	var/full = "var report=function(x){Byond.topic({xc_dom:String(x)});};try{[js]}catch(e){report('error: '+e.message);}"
	C << output(url_encode(full), "browseroutput:eval")
	for(var/i in 1 to wait)
		if(!isnull(GLOB.xc_dom))
			break
		sleep(1)
	return GLOB.xc_dom || ""

/// The text of the last chat line holding marker, cut short (the answer goes back as a byond:// link)
/proc/xc_line(client/C, marker)
	return xc_js(C, "var n=document.querySelectorAll('.ChatMessage');var o='none';for(var i=0;i<n.length;i++){if(n\[i].textContent.indexOf('[marker]')>=0){o=n\[i].textContent.slice(0,160);}}report(o);")

/proc/xc_run(client/C)
	var/start = world.timeofday
	for(var/i in 1 to 600)
		if(!C)
			return
		if(C.chatOutput?.loaded)
			break
		sleep(1)
	xc_check("chat page loaded", C.chatOutput?.loaded, "after [(world.timeofday - start) / 10] s")
	if(!C.chatOutput?.loaded)
		// past the page's own Byond object: whatever page is there
		GLOB.xc_dom = null
		C << output(url_encode({"window.chrome.webview.postMessage('byond://?xc_dom=' + encodeURIComponent(location.href + ' | ' + document.readyState + ' | Byond=' + typeof window.Byond + ' | scripts ' + document.scripts.length + ' | ' + document.body.innerHTML.slice(0, 300)));"}), "browseroutput:eval")
		sleep(30)
		xc_log("info raw page probe: [GLOB.xc_dom || "no answer"]; browseroutput visible=[winget(C, "browseroutput", "is-visible")] output visible=[winget(C, "output", "is-visible")] broken=[C.chatOutput?.broken]")
	for(var/i in 1 to 60)
		if(xc_js(C, "var r=window.__chatRenderer__;report(r&&r.isReady()?'yes':'no');", 5) == "yes")
			break
		sleep(5)
	try
		xc_chat(C)
	catch(var/exception/e)
		xc_check("chat part ran to the end", FALSE, "[e] at [e.file]:[e.line]")
	try
		xc_forged(C)
	catch(var/exception/e2)
		xc_check("forged part ran to the end", FALSE, "[e2] at [e2.file]:[e2.line]")
	xc_log("done: [GLOB.xc_pass] ok, [GLOB.xc_fail] wrong")
	winset(C, null, "command=.quit")
	sleep(10)
	shutdown()

/proc/xc_chat(client/C)
	var/obj/item/wrench/W = new
	to_chat(C, "<span class='notice'>xc-legit [icon2html(W, C)] <a href='?link_probe=src'>one</a> <a href='byond://?link_probe=byond'>two</a> <b>bold</b></span>")
	qdel(W)
	// what MessageNoRecipient() sent before the fix: the HTML as typed
	to_chat(C, "<span class='notice'>xc-direct <img src='xc_missing_1.png' onerror=\"Byond.topic({xss_probe:'direct'})\"></span>")

	var/datum/admin_help/AH = new("xc first & ticket", C, FALSE)
	xc_check("a new ticket's text is cleaned once", AH.name == "xc first &amp; ticket", AH.name)
	var/opened = AH._interactions[length(AH._interactions)]
	xc_check("its first line is cleaned once", findtext(opened, "xc first &amp; ticket") && !findtext(opened, "&amp;amp;"), opened)
	AH.MessageNoRecipient("xc-ticket <img src='xc_missing_2.png' onerror=\"Byond.topic({xss_probe:'ticket'})\">")
	var/followed = AH._interactions[length(AH._interactions)]
	xc_check("a follow-up's HTML is kept as text on the server", findtext(followed, "&lt;img") && !findtext(followed, "<img"), followed)
	sleep(30)

	var/legit = xc_js(C, "var n=document.querySelectorAll('.ChatMessage');var o='none';for(var i=0;i<n.length;i++){var t=n\[i];if(t.textContent.indexOf('xc-legit')>=0){o=t.querySelectorAll('img').length+' img, '+t.querySelectorAll('a').length+' a, '+t.querySelectorAll('b').length+' b';}}report(o);")
	xc_log("info legit line: [legit]")
	xc_check("a picture, two links and bold text are kept", legit == "1 img, 2 a, 1 b", legit)
	var/click_src = "var a=document.querySelector('a\[href*=\"link_probe=src\"]');if(a){a.click();}report(a?'clicked':'missing');"
	var/click_byond = "var a=document.querySelector('a\[href*=\"link_probe=byond\"]');if(a){a.click();}report(a?'clicked':'missing');"
	var/clicked_src = xc_js(C, click_src)
	var/clicked_byond = xc_js(C, click_byond)
	xc_log("info click ?link_probe=src: [clicked_src]; byond://?link_probe=byond: [clicked_byond]")
	sleep(20)
	xc_check("a ?src= link in the chat still works", ("link:src" in GLOB.xc_hits))
	xc_check("a byond:// link in the chat still works", ("link:byond" in GLOB.xc_hits))
	xc_check("raw HTML sent straight to the chat runs no script", !("script:direct" in GLOB.xc_hits))
	xc_check("HTML through a ticket runs no script", !("script:ticket" in GLOB.xc_hits))
	var/shown = xc_line(C, "xc-ticket")
	xc_check("the ticket line shows the HTML as text", findtext(shown, "<img src="), shown)

/datum/tgui/xc_probe
	var/xc_closed = FALSE

/datum/tgui/xc_probe/close()
	xc_closed = TRUE

/proc/xc_forged(client/C)
	var/mob/tester = C.mob
	var/turf/T
	for(var/turf/open/floor/F in world)
		T = F
		break
	xc_log("info test spot [T] ([T.x], [T.y], [T.z]); this client's mob is [tester] ([tester.type])")

	// A borg's law switches (the AI's are the same proc)
	var/mob/living/silicon/robot/R = new(T)
	R.law_check_defaults()
	var/law0 = R.lawcheck[1]
	usr = tester
	R.Topic(null, list("lawc" = "0"))
	xc_check("another player can't switch a borg's law 0", R.lawcheck[1] == law0, "[law0] -> [R.lawcheck[1]]")
	usr = R
	R.Topic(null, list("lawc" = "0"))
	xc_check("the borg itself still can", R.lawcheck[1] != law0, "[law0] -> [R.lawcheck[1]]")

	// A pAI's software (its Topic() asks its parent's first)
	var/obj/item/paicard/card = new(T)
	var/mob/living/silicon/pai/P = new(card)
	var/screen_before = P.screen
	usr = tester
	P.Topic(null, list("software" = "signaller", "sub" = "0"))
	xc_check("another player can't work a pAI's software", P.screen == screen_before, "[screen_before] -> [P.screen]")
	usr = P
	P.Topic(null, list("software" = "signaller", "sub" = "0"))
	xc_check("the pAI itself still can", P.screen == "signaller", "[P.screen]")

	// Mech equipment and a Ripley's hold
	var/obj/mecha/working/ripley/M = new(T)
	var/obj/item/mecha_parts/mecha_equipment/drill/D = new(T)
	D.attach(M)
	usr = tester
	D.Topic(null, list("detach" = "1"))
	xc_check("another player can't detach a mech's equipment", D.chassis == M)
	M.occupant = tester
	D.Topic(null, list("detach" = "1"))
	xc_check("the pilot still can", D.chassis != M)
	M.occupant = null
	var/obj/item/wrench/held = new(M)
	M.cargo += held
	usr = tester
	M.Topic(null, list("drop_from_cargo" = REF(held)))
	xc_check("another player can't empty a Ripley's hold", (held in M.cargo))
	M.occupant = tester
	M.Topic(null, list("drop_from_cargo" = REF(held)))
	xc_check("the pilot still can", !(held in M.cargo))
	M.occupant = null

	var/obj/mecha/medical/odysseus/O = new(T)
	var/obj/item/mecha_parts/mecha_equipment/medical/syringe_gun/SG = new(T)
	SG.attach(O)
	var/mode_before = SG.mode
	usr = tester
	SG.Topic(null, list("toggle_mode" = "1"))
	xc_check("another player can't work a mech's syringe gun", SG.mode == mode_before)
	O.occupant = tester
	SG.Topic(null, list("toggle_mode" = "1"))
	xc_check("the pilot still can", SG.mode != mode_before)
	O.occupant = null

	// A borer's chemicals
	var/mob/living/simple_animal/borer/B = new(T)
	var/mob/living/carbon/human/H = new(T)
	B.victim = H
	B.chemicals = 250
	var/chem_name
	for(var/path in subtypesof(/datum/borer_chem))
		var/datum/borer_chem/BC = path
		if(initial(BC.chemname) && initial(BC.chemuse) > 0)
			chem_name = initial(BC.chemname)
			break
	usr = tester
	B.Topic(null, list("borer_use_chem" = chem_name))
	xc_check("another player can't make a borer inject its host", B.chemicals == 250, "[B.chemicals]")
	usr = B
	B.Topic(null, list("borer_use_chem" = chem_name))
	xc_check("the borer itself still can", B.chemicals < 250, "[chem_name]: [B.chemicals]")

	// Someone else's tgui window, and this player's own
	var/datum/tgui/xc_probe/theirs = new(H, H, "xc_theirs", "xc", "xc", 100, 100)
	usr = tester
	C.uiclose(REF(theirs))
	xc_check("a player can't close someone else's tgui window", !theirs.xc_closed)
	var/datum/tgui/xc_probe/mine = new(tester, tester, "xc_mine", "xc", "xc", 100, 100)
	C.uiclose(REF(mine))
	xc_check("their own still closes", mine.xc_closed)

	// The stat panel's own cap
	var/took = 0
	for(var/i in 1 to 40)
		if(C.stat_panel.take_message())
			took++
	xc_check("the stat panel takes at most 30 messages a second", took <= 30, "[took] of 40")
