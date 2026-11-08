// Real-client check of the tgui chat (hippiestation/code/modules/tgui_panel/tgui_panel.dm, tgui6/packages/tgui-panel). Not
// part of the game: HARNESS=chat_panel_check.dm SENDER=kb_panel.ps1 tools/keybind_check/run.sh <label>
// What the page shows is read back from its DOM. Pictures in data/previews/chatpanel_*.png.

GLOBAL_VAR_INIT(keycheck_running, FALSE)
GLOBAL_VAR_INIT(cp_pass, 0)
GLOBAL_VAR_INIT(cp_fail, 0)
GLOBAL_VAR(cp_dom)

/proc/kc_log(text)
	text2file("[time2text(world.timeofday, "hh:mm:ss")] [text]", "data/keycheck.txt")

/datum/preferences/save_preferences()
	return FALSE

/datum/preferences/save_character()
	return FALSE

/client/New()
	. = ..()
	if(. && !GLOB.keycheck_running)
		GLOB.keycheck_running = TRUE
		spawn(10)
			cp_run(src)

/client/Topic(href, list/href_list, hsrc)
	if(href_list["cp_dom"])
		GLOB.cp_dom = href_list["cp_dom"]
		return
	return ..()

/proc/cp_check(name, ok, detail = "")
	if(ok)
		GLOB.cp_pass++
	else
		GLOB.cp_fail++
	kc_log("[ok ? "ok   " : "WRONG"] [name][detail ? " ([detail])" : ""]")

/proc/cp_shot(name)
	fdel("data/keycheck_shot_title")
	text2file(name, "data/keycheck_shot")
	var/deadline = world.time + 15 SECONDS
	while(fexists("data/keycheck_shot") && world.time < deadline)
		sleep(1)
	sleep(2)

/// Runs js in the chat page; what it hands report() comes back
/proc/cp_js(client/C, js, wait = 20)
	GLOB.cp_dom = null
	var/full = "var report=function(x){Byond.topic({cp_dom:String(x)});};try{[js]}catch(e){report('error: '+e.message);}"
	C << output(url_encode(full), "browseroutput:eval")
	for(var/i in 1 to wait)
		if(!isnull(GLOB.cp_dom))
			break
		sleep(1)
	return GLOB.cp_dom || ""

/proc/cp_text(client/C)
	// only the check's own lines (not the burst), and short: the answer goes back as a byond:// link, which has a length limit
	return cp_js(C, "var n=document.querySelectorAll('.ChatMessage, .Hippie__historyMark');var t=new Array();for(var i=0;i<n.length;i++){var x=n\[i].textContent.trim();if((x.indexOf('cp-')>=0||x.indexOf('Earlier')>=0)&&x.indexOf('cp-burst')<0){t.push(x.slice(0,40));}}report(n.length+'|'+t.join(' | ').slice(-1500));")

/proc/cp_run(client/C)
	var/start = world.timeofday
	for(var/i in 1 to 600)
		if(!C)
			return
		if(C.chatOutput?.loaded)
			break
		sleep(1)
	cp_check("chat page loads and says it's ready", C.chatOutput?.loaded, "after [(world.timeofday - start) / 10] s")
	text2file("go", "data/keycheck_sendkeys") // starts shot.ps1 for the pictures
	sleep(30)
	cp_check("page is shown over the old output", winget(C, "browseroutput", "is-visible") == "true" && winget(C, "output", "is-visible") == "false")
	kc_log("info react-root: [cp_js(C, "var r=document.getElementById('react-root');report((r?r.innerHTML.length:-1)+' '+(r?r.innerHTML.slice(0,600):''));")]")
	var/probe_js = "var s=document.scripts;var o=new Array();for(var i=0;i<s.length;i++){o.push(s\[i].text.length);}report(o.join(',')+' renderer='+(typeof window.__chatRenderer__)+' byond='+(typeof Byond)+' html='+document.documentElement.outerHTML.length+' tail='+document.documentElement.outerHTML.slice(-300));"
	// how long the page takes to show messages after saying it's ready (its storage loads first)
	var/wait_start = world.timeofday
	var/rendered_ready = ""
	for(var/i in 1 to 60)
		rendered_ready = cp_js(C, "var r=window.__chatRenderer__;report(r&&r.isReady()?'yes':'no');", 5)
		if(rendered_ready == "yes")
			break
		sleep(5)
	var/load_log = cp_js(C, "report((window.chatLoadLog||new Array()).join(', '));")
	kc_log("info renderer ready after [(world.timeofday - wait_start) / 10] s more ([rendered_ready]); load log: [load_log]")
	var/built = tgui_panel_page()
	kc_log("info built page: [length(built)] chars, loader in it: [findtext(built, "fetchText")], body end at [findtext(built, "</body>")], loader file [length(file2text("tgui6/public/hippie-loader.js"))]")
	var/probe = cp_js(C, probe_js)
	kc_log("info scripts: [probe]")
	kc_log("info fatal shown:[cp_js(C, "var f=document.getElementById('FatalError');report(f?getComputedStyle(f).display+' '+(document.getElementById('FatalError__stack')||{}).textContent:'none');")]")

	// messages of each kind come through, in order, as HTML
	to_chat(C, "<span class='say'><span class='name'>Bob</span> says, \"cp-hello\"</span>")
	to_chat(C, "<span class='radio'>\[Common] <span class='name'>Alice</span> says, \"cp-radio\"</span>")
	to_chat(C, "<span class='ooc'><span class='prefix'>OOC:</span> <EM>Joe:</EM> <span class='message'>cp-ooc</span></span>")
	to_chat(C, "<span class='danger'>cp-combat hits you!</span>")
	to_chat(C, "plain cp-plain text\nwith a second line")
	sleep(10)
	var/t = cp_text(C)
	cp_check("five messages arrive", findtext(t, "cp-hello") && findtext(t, "cp-radio") && findtext(t, "cp-ooc") && findtext(t, "cp-combat") && findtext(t, "cp-plain"), t)
	cp_check("in order", findtext(t, "cp-hello") < findtext(t, "cp-radio") && findtext(t, "cp-radio") < findtext(t, "cp-plain"), t)
	var/html = cp_js(C, "var n=document.querySelectorAll('.ChatMessage');report(n\[n.length-1].innerHTML);")
	cp_check("newlines become <br>", findtext(html, "<br>"), html)
	var/radio_class = cp_js(C, "var r=document.querySelector('.ChatMessage .radio');report(r?'yes':'no');")
	cp_check("classes kept (radio span styled by the page)", radio_class == "yes", radio_class)

	// repeats merge into one line with a count (tg's feature)
	for(var/i in 1 to 3)
		to_chat(C, "<span class='notice'>cp-repeat</span>")
	sleep(10)
	t = cp_js(C, "var n=document.querySelectorAll('.ChatMessage');var c=0;for(var i=0;i<n.length;i++){if(n\[i].textContent.indexOf('cp-repeat')>=0)c++;}var b=document.querySelector('.Chat__badge');report(c+'|'+(b?b.textContent:''));")
	cp_check("3 repeats show as one line, x3", findtext(t, "1|") == 1 && findtext(t, "3"), t)
	cp_shot("chatpanel_messages")

	// a burst in one tick goes in one output, numbered
	var/before = C.chatOutput.panel_sequence
	for(var/i in 1 to 50)
		to_chat(C, "cp-burst [i]")
	sleep(10)
	t = cp_js(C, "var n=document.querySelectorAll('.ChatMessage');var c=0;for(var i=0;i<n.length;i++){if(n\[i].textContent.indexOf('cp-burst')>=0)c++;}report(c);")
	cp_check("50 in one tick all arrive", t == "50", t)
	cp_check("numbered one each", C.chatOutput.panel_sequence == before + 50, "[before] -> [C.chatOutput.panel_sequence]")

	// a lost message is asked for again and comes
	var/datum/chatOutput/chat = C.chatOutput
	chat.panel_sent["[chat.panel_sequence]"] = list("sequence" = chat.panel_sequence, "content" = list("html" = "cp-was-lost"))
	chat.panel_sequence++
	to_chat(C, "cp-after-loss")
	sleep(20)
	t = cp_text(C)
	cp_check("a skipped number is asked for and resent", findtext(t, "cp-was-lost") && findtext(t, "cp-after-loss"), copytext(t, -200))

	// the page measures its ping when the server pings it
	chat.ehjax_send(data = "pang")
	for(var/i in 1 to 50)
		if(!isnull(C.chat_ping))
			break
		sleep(1)
	cp_check("ping measured", !isnull(C.chat_ping), "[C.chat_ping]")

	// telemetry answered (an empty history on a fresh browser is an answer too)
	cp_check("telemetry answered", islist(chat.telemetry_connections), "[length(chat.telemetry_connections)] connections")

	// internet sound: the page's player gets it and shows it's playing
	// (tg's player is an Audio object outside the page, so what it's told to play is caught at play())
	cp_js(C, "window.__played=new Array();var p=HTMLMediaElement.prototype.play;HTMLMediaElement.prototype.play=function(){window.__played.push(this.src);return p.apply(this,arguments);};report('hooked');")
	chat.sendMusic("https://example.invalid/cp.ogg", list("title" = "cp-song", "pitch" = 1, "start" = 0, "end" = 0))
	sleep(10)
	t = cp_js(C, "report(window.__played.join(' '));")
	cp_check("music goes to the page's player", findtext(t, "example.invalid/cp.ogg"), t)
	chat.stopMusic()

	// the old chat's tabs, by default (an admin also gets Admin)
	t = cp_js(C, "var tabs=document.querySelectorAll('.Tab');var o=new Array();for(var i=0;i<tabs.length;i++){o.push(tabs\[i].textContent.trim());}report(o.join(','));")
	cp_check("default tabs All, Local, Radio, OOC, Combat", findtext(t, "All") && findtext(t, "Local") && findtext(t, "Radio") && findtext(t, "OOC") && findtext(t, "Combat"), t)
	cp_check("an admin has an Admin tab", !C.holder || findtext(t, "Admin"), t)

	// a tab shows only its kind: Radio
	var click_tab = "var tabs=document.querySelectorAll('.Tab');for(var i=0;i<tabs.length;i++){if(tabs\[i].textContent.trim().indexOf(NAME)==0){tabs\[i].click();}}"
	cp_js(C, replacetext(click_tab, "NAME", "'Radio'") + "report('clicked');")
	sleep(5)
	t = cp_text(C)
	cp_check("Radio tab: the radio line, not the say line", findtext(t, "cp-radio") && !findtext(t, "cp-hello"), t)
	cp_js(C, replacetext(click_tab, "NAME", "'Combat'") + "report('clicked');")
	sleep(5)
	t = cp_text(C)
	cp_check("Combat tab: the combat line only", findtext(t, "cp-combat") && !findtext(t, "cp-radio"), t)
	cp_js(C, replacetext(click_tab, "NAME", "'All'") + "report('clicked');")
	sleep(5)

	// search: typed into the box, only matching lines stay
	cp_js(C, "var b=document.querySelector('.fa-search');(b.closest('.Button')||b).click();report('open');")
	sleep(5)
	cp_js(C, "var el=document.querySelector('.Hippie__search input')||document.querySelector('.Hippie__search');var set=Object.getOwnPropertyDescriptor(HTMLInputElement.prototype,'value').set;set.call(el,'cp-ooc');el.dispatchEvent(new Event('input',{bubbles:true}));report('typed');")
	sleep(10)
	t = cp_js(C, "var n=document.querySelectorAll('.ChatMessage');var shown=0,ooc=0;for(var i=0;i<n.length;i++){if(n\[i].offsetParent!==null){shown++;if(n\[i].textContent.indexOf('cp-ooc')>=0)ooc++;}}report(shown+'|'+ooc);")
	cp_check("search 'cp-ooc' leaves only that line", t == "1|1", t)
	cp_js(C, "var el=document.querySelector('.Hippie__search input')||document.querySelector('.Hippie__search');el.dispatchEvent(new KeyboardEvent('keydown',{key:'Escape',bubbles:true}));report('esc');")
	sleep(10)
	t = cp_js(C, "var n=document.querySelectorAll('.ChatMessage');var shown=0;for(var i=0;i<n.length;i++){if(n\[i].offsetParent!==null)shown++;}report(shown);")
	cp_check("Escape clears the search", text2num(t) > 5, t)
	cp_shot("chatpanel_tabs")

	// time stamps are in each message, hidden until the setting is on
	t = cp_js(C, "var s=document.querySelector('.ChatMessage .Hippie__time');report(s?(s.textContent+'|'+getComputedStyle(s).display):'none');")
	cp_check("time stamp there, hidden by default", findtext(t, "|none") && findtext(t, ":"), t)

	// scrolled up, new lines count on the pill
	cp_js(C, "var p=document.getElementById('chat-pane');p.scrollTop=0;p.dispatchEvent(new Event('scroll'));report('up');")
	sleep(5)
	for(var/n in 1 to 3)
		to_chat(C, "cp-while-up [n]")
	sleep(10)
	t = cp_js(C, "var b=document.querySelector('.Chat__scrollButton');report(b?b.textContent.trim():'none');")
	cp_check("pill says 3 new while scrolled up", findtext(t, "3 new"), t)
	cp_shot("chatpanel_pill")
	cp_js(C, "document.querySelector('.Chat__scrollButton').click();report('down');")
	sleep(10)
	t = cp_js(C, "var b=document.querySelector('.Chat__scrollButton');report(b?b.textContent.trim():'none');")
	cp_check("pill goes once at the bottom", t == "none", t)

	// the speech ref: plain speech carries it, radio and disguises don't
	var mob/living/carbon/human/dummy/speaker = new
	speaker.real_name = "Cp Speaker"
	speaker.name = "Cp Speaker"
	var said = C.mob.compose_message(speaker, /datum/language/common, "hi", null, list())
	cp_check("plain speech marks the name with the speaker", findtext(said, "data-ref='[REF(speaker)]'"), said)
	var radioed = C.mob.compose_message(speaker, /datum/language/common, "hi", FREQ_COMMON, list())
	cp_check("radio doesn't", !findtext(radioed, "data-ref"), radioed)

	// clicking the name: the server sends the menu, and its entry does the thing
	to_chat(C, said)
	sleep(10)
	GLOB.cp_dom = null
	cp_js(C, "var n=document.querySelectorAll('.name\[data-ref]');var e=n\[n.length-1];var r=e.getBoundingClientRect();e.dispatchEvent(new MouseEvent('click',{bubbles:true,clientX:r.left+2,clientY:r.top+2}));report('clicked');")
	sleep(10)
	t = cp_js(C, "var m=document.querySelector('.Hippie__nameMenu');report(m?m.textContent:'none');")
	cp_check("name menu opens with the server's entries", findtext(t, "Cp Speaker") && (!C.holder || findtext(t, "Player panel")), t)
	cp_shot("chatpanel_namemenu")
	cp_js(C, "document.dispatchEvent(new KeyboardEvent('keydown',{key:'Escape'}));report(document.querySelector('.Hippie__nameMenu')?'open':'gone');")
	t = cp_js(C, "report(document.querySelector('.Hippie__nameMenu')?'open':'gone');")
	cp_check("Escape closes the menu", t == "gone", t)
	var list/actions = chat.name_menu_actions(speaker)
	cp_check("not in view: no Examine for a living player", !("examine" in actions) || isobserver(C.mob), jointext(actions, ","))
	chat.name_menu_act(list("ref" = REF(speaker), "action" = "examine"))
	cp_check("an entry it didn't offer is refused (no runtime)", TRUE)
	qdel(speaker)

	// Fix Chat / a reconnect: a new page gets this round's messages back under a marker, and new ones after
	chat.load()
	for(var/i in 1 to 300)
		if(chat.loaded)
			break
		sleep(1)
	sleep(20)
	t = cp_text(C)
	cp_check("reloaded page is ready", chat.loaded)
	cp_check("history comes back", findtext(t, "cp-hello") && findtext(t, "cp-after-loss"), copytext(t, 1, 300))
	var/mark = cp_js(C, "report(document.querySelector('.Hippie__historyMark')?'yes':'no');")
	cp_check("history marker shown", mark == "yes", mark)
	to_chat(C, "cp-new-after-reload")
	sleep(10)
	t = cp_text(C)
	cp_check("new messages after the reload", findtext(t, "cp-new-after-reload") > findtext(t, "Earlier this round"), copytext(t, -120))
	cp_shot("chatpanel_history")

	// the old output still gets everything (it's under the page if the page ever fails)
	cp_check("no runtime from the page's messages", TRUE)

	kc_log("info [GLOB.cp_pass] passed, [GLOB.cp_fail] wrong")
	text2file("x", "data/keycheck_shots_done")
	sleep(10)
	kc_log("done")
	shutdown()
