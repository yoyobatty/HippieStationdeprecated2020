// View Variables: watching vars live. (W) by a var puts it in a Watching box at the top of the page, which the server fills in
// again every second (SSprocessing) while the window shows that thing: health going down, a bot's current goal, loc as
// something walks. (W) again, or the box's own x, stops it; so does going to another page, closing the window or the
// thing being deleted. The user asked for VV's concept improved, 2026-11-07.

/datum/vv_window/var/list/watching
/datum/vv_window/var/client/owner

/// The window closed (onclose(), .windowclose): nothing left to send to
/datum/vv_window/Topic(href, list/href_list)
	if(href_list["close"])
		watching = null
		owner?.vv_windows -= id
		return
	return ..()

/// Tells the window datum when the window's closed (as datum/browser does: the window has to be there first)
/client/proc/vv_setup_onclose(datum/vv_window/W)
	for(var/i in 1 to 10)
		if(winexists(src, W.id))
			onclose(mob, W.id, W)
			return
		sleep(1)

GLOBAL_DATUM_INIT(vv_watcher, /datum/vv_watcher, new)

/datum/vv_watcher
	/// The windows with something watched
	var/list/windows = list()
	var/next_prune = 0
	var/pruning = FALSE

/datum/vv_watcher/proc/add(datum/vv_window/W)
	windows |= W
	START_PROCESSING(SSprocessing, src)

/datum/vv_watcher/process()
	for(var/datum/vv_window/W as anything in windows)
		var/client/C = W.owner
		if(!C || !length(W.watching) || LAZYACCESS(C.vv_windows, W.id) != W)
			windows -= W
			continue
		C << output(url_encode(vv_watch_json(W)), "[W.id].browser:vv_watch")
		if(!W.resolve(W.history[W.index])) // deleted: said once, then stopped
			W.watching = null
	if(!windows.len)
		return PROCESS_KILL
	if(world.time >= next_prune && !pruning)
		next_prune = world.time + 3 SECONDS
		INVOKE_ASYNC(src, PROC_REF(prune))

/// A window closed some way that didn't say so (browse(null) runs no on-close): asking the client sleeps, so not in process()
/datum/vv_watcher/proc/prune()
	pruning = TRUE
	for(var/datum/vv_window/W as anything in windows.Copy())
		var/client/C = W.owner
		if(!C || !winexists(C, W.id) || winget(C, W.id, "is-visible") == "false")
			W.watching = null
			windows -= W
			C?.vv_windows -= W.id
	pruning = FALSE

/// The watched vars' values now, for the page
/proc/vv_watch_json(datum/vv_window/W)
	var/datum/D = W.resolve(W.history[W.index])
	if(!D)
		return json_encode(list("gone" = TRUE))
	var/list/rows = list()
	for(var/var_name in W.watching)
		if(!(var_name in D.vars) || !D.can_vv_get(var_name))
			continue
		rows += list(list(var_name, vv_watch_value(D.vars[var_name])))
	return json_encode(list("rows" = rows, "time" = DisplayTimeText(world.time - SSticker.round_start_time)))

/proc/vv_watch_value(value)
	if(isnull(value))
		return "null"
	if(istext(value))
		return length(value) > 100 ? "\"[copytext(value, 1, 98)]...\"" : "\"[value]\""
	if(islist(value))
		var/list/L = value
		return "/list ([L.len])"
	if(istype(value, /datum))
		var/datum/DV = value
		return isatom(DV) ? "[DV:name] ([DV.type])" : "[DV.type]"
	return "[value]"

/// (W): watch the var, or stop
/client/proc/vv_toggle_watch(datum/D, var_name, window_id)
	var/datum/vv_window/W = LAZYACCESS(vv_windows, window_id)
	if(!W || W.current_ref() != REF(D) || !(var_name in D.vars))
		return
	W.owner = src
	if(var_name in W.watching)
		W.watching -= var_name
	else
		LAZYADD(W.watching, var_name)
		GLOB.vv_watcher.add(W)
	src << output(url_encode(vv_watch_json(W)), "[W.id].browser:vv_watch")

/// The page's box and the script that fills it
/proc/vv_watch_html(datum/vv_window/W)
	return {"
		<div id='vv_watch' style='display:none'><hr><font size='1'><b>Watching</b> <span id='vv_watch_time'></span></font><ul id='vv_watch_rows'></ul></div>
		<script type='text/javascript'>
			function vv_watch(json) {
				var data = JSON.parse(json);
				var box = document.getElementById('vv_watch');
				var list = document.getElementById('vv_watch_rows');
				while (list.firstChild) list.removeChild(list.firstChild);
				if (data.gone) {
					box.style.display = '';
					list.innerHTML = '<li><font color="red">Deleted.</font></li>';
					return;
				}
				if (!data.rows || !data.rows.length) {
					box.style.display = 'none';
					return;
				}
				box.style.display = '';
				document.getElementById('vv_watch_time').textContent = data.time ? '(round time ' + data.time + ')' : '';
				for (var i = 0; i < data.rows.length; i++) {
					var li = document.createElement('li');
					var stop = document.createElement('a');
					stop.textContent = 'x';
					stop.href = document.getElementById('vvar_' + data.rows\[i\]\[0\]).querySelector('a\[href*=vvwatch\]').getAttribute('href');
					li.appendChild(document.createTextNode('('));
					li.appendChild(stop);
					li.appendChild(document.createTextNode(') ' + data.rows\[i\]\[0\] + ' = '));
					var value = document.createElement('span');
					value.className = 'value';
					value.textContent = data.rows\[i\]\[1\];
					li.appendChild(value);
					list.appendChild(li);
				}
			}
			[length(W.watching) ? "vv_watch([json_encode(vv_watch_json(W))]);" : ""]
		</script>
	"}
