// Old browse() windows with a real client. BYOND 516's browser decides what a page is from how it starts: a bare bit of HTML that
// starts with a tag it doesn't know (<TT>, <ol>, <pre>) or with words comes up as raw code, as the safe's keypad did. Those windows
// now go out in HTML_SKELETON() (code/__DEFINES/html_assistant.dm). This opens a few of them the way a player does and asks each
// page what it is. Not part of the game: HARNESS=browse_check.dm SENDER=shot.ps1 tools/keybind_check/run.sh <label>
// Pictures land in data/previews/popup_browse_*.png; the verdicts in data/keycheck.txt.

GLOBAL_VAR_INIT(keycheck_running, FALSE)
GLOBAL_LIST_EMPTY(bc_expect) //label -> TRUE if the page should be HTML

/datum/preferences/save_preferences()
	return FALSE

/datum/preferences/save_character()
	return FALSE

/proc/kc_log(text)
	text2file(text, "data/keycheck.txt")

/client/New()
	. = ..()
	if(. && !GLOB.keycheck_running)
		GLOB.keycheck_running = TRUE
		spawn(50)
			browse_check_run(src)

/client/Topic(href, href_list, hsrc)
	if(href_list["probe"])
		var/label = href_list["probe"]
		var/said = href_list["value"]
		var/html = findtext(said, "text/html") == 1
		kc_log("[html == GLOB.bc_expect[label] ? "PASS" : "FAIL"] [label]: [said]")
		GLOB.bc_expect -= label
		return
	return ..()

/proc/bc_shot(name)
	text2file(name, "data/keycheck_shot")
	var/deadline = world.time + 15 SECONDS
	while(fexists("data/keycheck_shot") && world.time < deadline)
		sleep(1)
	sleep(2)

/// The window on screen where a picture can be had of it, the page asked what it is, a picture, and the window shut.
/proc/bc_look(client/C, window, label, html = TRUE)
	GLOB.bc_expect[label] = html
	sleep(15)
	if(winget(C, window, "is-visible") != "true")
		kc_log("FAIL [label]: no window [window]")
		GLOB.bc_expect -= label
		return
	winset(C, window, "size=520x420;pos=1700,300")
	sleep(10)
	var/js = {"window.chrome.webview.postMessage('byond://?probe=[label]&value=' + encodeURIComponent(document.contentType + ' | anchors ' + document.getElementsByTagName('a').length + ' | ' + (document.body ? document.body.innerText.replace(/\\s+/g, ' ').slice(0, 80) : 'no body')));"}
	C << output(url_encode(js), "[window].browser:eval")
	sleep(10)
	bc_shot("popup_browse_[label]")
	C << browse(null, "window=[window]")
	sleep(5)
	if(GLOB.bc_expect[label] != null)
		kc_log("FAIL [label]: the page never answered")
		GLOB.bc_expect -= label

/proc/browse_check_run(client/C)
	fdel("data/keycheck_shot")
	fdel("data/keycheck_shots_done")
	text2file("go", "data/keycheck_sendkeys") //starts shot.ps1
	GLOB.master_mode = "extended"
	SSticker.start_immediately = TRUE
	var/wait_for_round = world.time + 3 MINUTES
	while(SSticker.current_state < GAME_STATE_PLAYING && world.time < wait_for_round)
		sleep(1 SECONDS)
	sleep(3 SECONDS)
	var/turf/home = get_turf(pick(SSjob.latejoin_trackers))
	var/mob/living/carbon/human/H = new(home)
	H.mind_initialize()
	H.equipOutfit(/datum/outfit/job/assistant)
	H.ckey = C.ckey
	sleep(3 SECONDS)
	kc_log("round state [SSticker.current_state], mob [C.mob]")

	// What it was about: a bare fragment, and the same in the page round it.
	var/fragment = "<TT><B>A safe</B><BR>\n\nLock Status: LOCKED<HR>\n>*****<BR>\n<A href='#'>1</A>-<A href='#'>2</A>-<A href='#'>3</A><BR>\n</TT>"
	C << browse(fragment, "window=bc_fragment;size=520x420")
	bc_look(C, "bc_fragment", "bare_fragment", FALSE)
	C << browse(HTML_SKELETON(fragment), "window=bc_skeleton;size=520x420")
	bc_look(C, "bc_skeleton", "skeleton")

	// Real windows, opened the way a player does.
	var/obj/item/storage/secure/safe/S = new(home)
	S.attack_self(H)
	sleep(15)
	// Its buttons, pressed on the page itself: the link has to come back to the safe.
	C << output(url_encode("document.getElementsByTagName('a')\[0\].click();"), "caselock.browser:eval")
	sleep(10)
	kc_log("[S.code == "1" ? "PASS" : "FAIL"] the keypad's 1 reaches the safe (code now [S.code])")
	S.attack_self(H)
	bc_look(C, "caselock", "secure_safe")
	var/obj/machinery/power/port_gen/pacman/P = new(home)
	P.anchored = TRUE //its panel only opens wrenched down
	P.ui_interact(H)
	bc_look(C, "port_gen", "pacman")
	var/obj/item/clipboard/board = new(home)
	board.attack_self(H)
	bc_look(C, "clipboard", "clipboard")
	var/obj/item/folder/F = new(home)
	new /obj/item/paper(F)
	F.attack_self(H)
	bc_look(C, "folder", "folder")
	var/obj/item/assembly/signaler/signaler = new(home)
	signaler.ui_interact(H)
	bc_look(C, "radio", "signaler")
	var/obj/machinery/pipedispenser/dispenser = new(home)
	dispenser.ui_interact(H)
	bc_look(C, "pipedispenser", "pipe_dispenser")
	var/mob/living/carbon/monkey/M = new(home)
	M.show_inv(H)
	bc_look(C, "mob[REF(M)]", "monkey_strip_panel")
	var/obj/structure/noticeboard/board2 = new(home)
	board2.ui_interact(H)
	bc_look(C, "noticeboard", "noticeboard")

	text2file("done", "data/keycheck_shots_done")
	sleep(5)
	kc_log("done")
	winset(C, null, "command=.quit")
	sleep(5)
	del(world)
