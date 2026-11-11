// hippie -- the tgui window pool. A tgui window used to be a new browse() popup each time: BYOND made the window (60-90 ms the first
// time an object's window opened), the page loaded and ran the 1.4 MB bundle (70-110 ms), and asked for its data with tgui:initialize,
// a round trip to the server. Measured open to first paint with a real client, 2026-11-11 (tools/keybind_check/tgui_open_bench.dm):
// 165-194 ms for an object's first window, 59-120 ms after.
//
// Now each client keeps a hidden window with the page already loaded (winclone() makes a window that stays hidden; a browse() popup
// can't be made hidden). open() hands a UI to it in one message (hippieMount in tgui-next/packages/tgui/index.js: config, data and
// any style sheets the object adds to the head), the page draws it, centres the window on the game window and shows it. close() hides
// the window and keeps it for the next UI. A UI that opens while no window is ready, or with its own browser control, opens the old
// way. The page of a UI with no tgui-next route is taken over by old tgui for good, so that window is thrown away when it closes.
// A window is only used again once its page says it's ready: shutting a window with its title bar's X (no fancy frills) leaves its
// page blank, so it never says so and is thrown away. A UI whose page never says it was mounted reopens the old way.
// GLOB.tgui_pool_enabled (world param tgui-pool=0) turns it off.

#define TGUI_POOL_LOADING 1
#define TGUI_POOL_READY 2
#define TGUI_POOL_IN_USE 3
/// old tgui took the page over: thrown away when its UI closes
#define TGUI_POOL_SPENT 4
/// its UI has closed: waiting for the page to say it's empty and ready
#define TGUI_POOL_RELEASING 5
/// Hidden windows kept loaded for the next UI
#define TGUI_POOL_SPARES 1
/// Windows kept for reuse once their UI has closed
#define TGUI_POOL_KEEP 2
/// Windows a client can have at once; past this a UI opens the old way
#define TGUI_POOL_MAX 8
/// A window whose page hasn't said it's loaded by then is thrown away
#define TGUI_POOL_LOAD_TIMEOUT (30 SECONDS)
/// A page that hasn't answered a mount or a release by then is dead: its window is thrown away
#define TGUI_POOL_ANSWER_TIMEOUT (5 SECONDS)
/// What a UI gets as its window id once its pooled window is taken from it, so nothing it does later reaches that window
#define TGUI_POOL_GONE "tguipool_gone"

GLOBAL_VAR_INIT(tgui_pool_enabled, world.params["tgui-pool"] != "0")
/// Numbers the windows over the whole server run: a client that reconnects may still have the last connection's windows
GLOBAL_VAR_INIT(tgui_pool_count, 0)

/client/var/datum/tgui_pool/tgui_pool

/datum/tgui_pool
	var/client/owner
	var/list/datum/tgui_pool_window/windows = list()

/datum/tgui_pool/New(client/owner)
	src.owner = owner

/datum/tgui_pool_window
	var/datum/tgui_pool/pool
	/// The window; fixed width, since focus_hears_keys() goes by what the focused control's id starts with
	var/id
	var/browser_id
	var/state = TGUI_POOL_LOADING
	var/datum/tgui/ui
	/// A UI was handed to it and the page hasn't said it has it yet
	var/mount_pending = FALSE
	/// When the last UI was handed to it
	var/mount_sent_at = 0

/// Makes windows until there are TGUI_POOL_SPARES loaded or loading
/datum/tgui_pool/proc/warm()
	if(!owner)
		return
	var/spares = 0
	for(var/datum/tgui_pool_window/W as anything in windows)
		if(W.state == TGUI_POOL_READY || W.state == TGUI_POOL_LOADING || W.state == TGUI_POOL_RELEASING)
			spares++
	while(spares < TGUI_POOL_SPARES && length(windows) < TGUI_POOL_MAX)
		make_window()
		spares++

/datum/tgui_pool/proc/make_window()
	var/datum/tgui_pool_window/W = new
	W.pool = src
	W.id = "tguipool[copytext("000000[++GLOB.tgui_pool_count]", -6)]"
	W.browser_id = "[W.id]_browser"
	windows += W
	var/datum/asset/assets = get_asset_datum(/datum/asset/group/tgui)
	assets.send(owner)
	winclone(owner, "window", W.id)
	winset(owner, W.id, "size=400x400;titlebar=false;can-resize=false;can-minimize=false;statusbar=false")
	winset(owner, W.browser_id, "parent=[W.id];type=browser;pos=0,0;size=400x400;anchor1=0,0;anchor2=100,100")
	var/html = replacetextEx(SStgui.basehtml, "data-pool=\"\"", "data-pool=\"[W.id]\"")
	html = replacetextEx(html, "\[ref]", "")
	html = replacetextEx(html, "\[style]", "nanotrasen")
	owner << browse(html, "window=[W.browser_id]")
	addtimer(CALLBACK(src, PROC_REF(load_timeout), W), TGUI_POOL_LOAD_TIMEOUT)

/datum/tgui_pool/proc/load_timeout(datum/tgui_pool_window/W)
	if(W.state == TGUI_POOL_LOADING && (W in windows))
		log_tgui("[owner] ([owner?.ckey]): pooled window [W.id] never loaded, thrown away")
		destroy(W)

/datum/tgui_pool/proc/find(id)
	for(var/datum/tgui_pool_window/W as anything in windows)
		if(W.id == id)
			return W

/// What a pooled page sends: ready (its bundle has run, or it has let its UI go), mounted (it has its UI) or spent (old tgui took it)
/datum/tgui_pool/proc/on_message(list/href_list)
	var/datum/tgui_pool_window/W = find(href_list["tgui_pool"])
	if(!W)
		return
	if(href_list["ready"] && (W.state == TGUI_POOL_LOADING || W.state == TGUI_POOL_RELEASING))
		W.state = TGUI_POOL_READY
	else if(href_list["mounted"])
		W.mount_pending = FALSE
	else if(href_list["spent"] && W.state == TGUI_POOL_IN_USE)
		W.state = TGUI_POOL_SPENT

/// The page never said it had its UI: the window is thrown away and the UI opens the old way
/datum/tgui_pool/proc/mount_timeout(datum/tgui_pool_window/W, datum/tgui/ui)
	if(!W.mount_pending || W.ui != ui || !(W in windows) || QDELETED(ui) || world.time - W.mount_sent_at < TGUI_POOL_ANSWER_TIMEOUT)
		return
	log_tgui("[owner] ([owner?.ckey]): pooled window [W.id] never took [ui.title], opened the old way")
	destroy(W)
	warm()
	ui.window_id = ui.own_window_id
	ui.window_output_target = null
	ui.initialized = FALSE
	ui.open()

/// The page never said it let its UI go (a title bar's X leaves it blank): thrown away
/datum/tgui_pool/proc/release_timeout(datum/tgui_pool_window/W)
	if(W.state != TGUI_POOL_RELEASING || !(W in windows))
		return
	destroy(W)
	warm()

/// A ready window for this UI, or null when there's none (it opens the old way, and a spare is made for next time)
/datum/tgui_pool/proc/acquire(datum/tgui/ui)
	var/datum/tgui_pool_window/found
	for(var/datum/tgui_pool_window/W as anything in windows)
		if(W.state == TGUI_POOL_READY)
			found = W
			break
	if(found)
		found.state = TGUI_POOL_IN_USE
		found.ui = ui
	warm()
	return found

/// Its UI has closed: hidden, emptied and kept, or thrown away
/datum/tgui_pool/proc/release(datum/tgui_pool_window/W)
	if(W.ui)
		W.ui.pool_window = null
		W.ui.window_id = TGUI_POOL_GONE
		W.ui.window_output_target = TGUI_POOL_GONE
		W.ui = null
	if(!owner)
		return
	winset(owner, W.id, "is-visible=false;on-close=")
	var/kept = 0
	for(var/datum/tgui_pool_window/other as anything in windows)
		if(other.state == TGUI_POOL_READY || other.state == TGUI_POOL_RELEASING)
			kept++
	if(W.state == TGUI_POOL_SPENT || kept >= TGUI_POOL_KEEP)
		destroy(W)
		warm()
		return
	W.state = TGUI_POOL_RELEASING
	owner << output("", "[W.browser_id]:hippieRelease")
	addtimer(CALLBACK(src, PROC_REF(release_timeout), W), TGUI_POOL_ANSWER_TIMEOUT)

/// For code that remembered a window id to close by hand (the lobby's): TRUE if it was a pooled window, now released
/datum/tgui_pool/proc/release_id(id)
	var/datum/tgui_pool_window/W = find(id)
	if(!W)
		return FALSE
	if(W.state == TGUI_POOL_IN_USE || W.state == TGUI_POOL_SPENT)
		release(W)
	return TRUE

/datum/tgui_pool/proc/destroy(datum/tgui_pool_window/W)
	windows -= W
	if(W.ui)
		W.ui.pool_window = null
		W.ui.window_id = TGUI_POOL_GONE
		W.ui.window_output_target = TGUI_POOL_GONE
		W.ui = null
	if(owner)
		winset(owner, W.id, "parent=none")

/client/Topic(href, href_list, hsrc)
	if(href_list["tgui_pool"])
		tgui_pool?.on_message(href_list)
		return
	return ..()

/datum/tgui
	/// The pooled window this UI is in, if it's in one
	var/datum/tgui_pool_window/pool_window
	/// It has been opened once: a UI that first opened the old way stays in its own window
	var/opened_before = FALSE
	/// The window id tg gave it, for when it has to open the old way after all
	var/own_window_id

/datum/tgui/New(mob/user, datum/src_object, ui_key, interface, title, width = 0, height = 0, datum/tgui/master_ui = null, datum/ui_state/state = GLOB.default_state, browser_id = null)
	. = ..()
	own_window_id = window_id

/datum/tgui/open()
	if(pool_window)
		open_pooled()
		return
	if(opened_before || custom_browser_id || !GLOB.tgui_pool_enabled || !user.client)
		opened_before = TRUE
		return ..()
	opened_before = TRUE
	update_status(push = FALSE)
	if(status < UI_UPDATE)
		return
	var/client/C = user.client
	if(!C.tgui_pool)
		C.tgui_pool = new(C)
	pool_window = C.tgui_pool.acquire(src)
	if(!pool_window)
		return ..()
	open_pooled()

/// Hands this UI to its pooled window: the window's look, then the UI in one message
/datum/tgui/proc/open_pooled()
	var/client/C = user.client
	if(!C)
		return
	update_status(push = FALSE)
	if(status < UI_UPDATE)
		return
	window_id = pool_window.id
	window_output_target = pool_window.browser_id
	if(!initial_data)
		initial_data = src_object.ui_data(user)
	if(!initial_static_data)
		initial_static_data = src_object.ui_static_data(user)
	var/fancy = C.prefs.tgui_fancy
	var/list/look = list(
		"size" = "[width || 400]x[height || 500]",
		"titlebar" = fancy ? "false" : "true",
		"can-resize" = fancy ? "false" : "true",
		"can-close" = no_close ? "false" : "true",
		"title" = title,
		// NOTE: Intentional \ref usage; tgui datums can't/shouldn't be tagged, so this is an effective unwrap
		"on-close" = "uiclose \ref[src]",
	)
	winset(C, window_id, list2params(look))
	// The object's own head html (its sprite sheet's style sheet), which a page that's already loaded adds to its head
	var/head = src_object.ui_base_html("<!--customheadhtml-->")
	if(head == "<!--customheadhtml-->")
		head = null
	C << output(url_encode("{\"head\":[json_encode(head)],\"state\":[get_json(initial_data, initial_static_data)]}"), "[window_output_target]:hippieMount")
	initialized = TRUE
	pool_window.mount_pending = TRUE
	pool_window.mount_sent_at = world.time
	addtimer(CALLBACK(pool_window.pool, TYPE_PROC_REF(/datum/tgui_pool, mount_timeout), pool_window, src), TGUI_POOL_ANSWER_TIMEOUT)
	SStgui.on_open(src)

/datum/tgui/close()
	if(!pool_window)
		return ..()
	var/datum/tgui_pool_window/W = pool_window
	W.pool.release(W)
	// the rest of tg's close(), which starts by closing the window with browse(null)
	src_object.ui_close(user)
	SStgui.on_close(src)
	for(var/datum/tgui/child in children)
		child.close()
	children.Cut()
	state = null
	master_ui = null
	qdel(src)

#undef TGUI_POOL_LOADING
#undef TGUI_POOL_READY
#undef TGUI_POOL_IN_USE
#undef TGUI_POOL_SPENT
#undef TGUI_POOL_RELEASING
#undef TGUI_POOL_SPARES
#undef TGUI_POOL_KEEP
#undef TGUI_POOL_MAX
#undef TGUI_POOL_LOAD_TIMEOUT
#undef TGUI_POOL_ANSWER_TIMEOUT
#undef TGUI_POOL_GONE
