// View Variables in one window: a reference clicked in a VV page opens in that same window, with Back and Forward, instead of a
// window per datum (shift-click still opens a new one). The page tells the server which window a link came from (the vvwin
// param, added by the page's own script to every VV link), so none of the many places that write VV links had to change.
// Also here: where a thing is (the chain of what it's in, and who's carrying it) for the header, and putting a var's row
// back in place after it's edited. The user asked for VV's concept improved, not its look, 2026-11-07.

/// A client's VV windows: window id = /datum/vv_window
/client/var/list/vv_windows
/client/var/vv_window_count = 0

#define VV_HISTORY_MAX 30

/datum/vv_window
	var/id
	/// What it's shown, oldest first: each list(ref text, weakref or null for a list)
	var/list/history = list()
	/// Where in history it is
	var/index = 0

/datum/vv_window/proc/current_ref()
	if(index < 1 || index > history.len)
		return null
	var/list/entry = history[index]
	return entry[1]

/// The datum (or list) an entry stands for, if it's still the same one
/datum/vv_window/proc/resolve(list/entry)
	var/datum/weakref/W = entry[2]
	if(W)
		return W.resolve()
	return locate(entry[1]) // a list: no weakrefs for those

/datum/vv_window/proc/push(datum/D)
	if(index < history.len)
		history.Cut(index + 1) // a new page drops what was ahead
	history += list(list(REF(D), islist(D) ? null : WEAKREF(D)))
	if(history.len > VV_HISTORY_MAX)
		history.Cut(1, 2)
	index = history.len

/// Opens a VV window, or shows D in one the client already has (window_id), or in the one already showing D
/client/proc/vv_window_for(datum/D, window_id)
	LAZYINITLIST(vv_windows)
	for(var/id in vv_windows.Copy())
		if(!winexists(src, id))
			vv_windows -= id
	var/datum/vv_window/W = window_id && vv_windows[window_id]
	if(W)
		return W
	var/ref = REF(D)
	for(var/id in vv_windows) // already open on it: that one
		var/datum/vv_window/open = vv_windows[id]
		if(open.current_ref() == ref)
			return open
	W = new
	W.id = "vv[++vv_window_count]"
	W.owner = src
	vv_windows[W.id] = W
	return W

/// Back or forward in a window's history, skipping things that are gone
/client/proc/vv_step(window_id, step)
	var/datum/vv_window/W = LAZYACCESS(vv_windows, window_id)
	if(!W)
		return
	var/at = W.index + step
	while(at >= 1 && at <= W.history.len)
		var/datum/D = W.resolve(W.history[at])
		if(D)
			W.index = at
			vv_show(D, window_id, FALSE)
			return
		W.history.Cut(at, at + 1) // gone: off the history
		if(step < 0)
			W.index--
			at--
	to_chat(src, "<span class='notice'>Nothing [step < 0 ? "before" : "after"] that in this window.</span>", confidential = TRUE)

/// The windows showing D now
/client/proc/vv_windows_showing(datum/D)
	. = list()
	var/ref = REF(D)
	for(var/id in vv_windows)
		var/datum/vv_window/W = vv_windows[id]
		if(W.current_ref() == ref)
			. += id

/// Back and Forward for the page's header: links, or greyed text when there's nowhere to go
/proc/vv_nav_links(datum/vv_window/W)
	var/back = W.index > 1 ? "<a href='?_src_=vars;[HrefToken()];vvback=1'>&lt; Back</a>" : "<font color='#999999'>&lt; Back</font>"
	var/forward = W.index < W.history.len ? "<a href='?_src_=vars;[HrefToken()];vvforward=1'>Forward &gt;</a>" : "<font color='#999999'>Forward &gt;</font>"
	return "<font size='1'>[back] | [forward]</font>"

/// The page's script for window links: every VV link says which window it came from; shift-click asks for a new window
/proc/vv_window_script(window_id)
	return {"
			var vv_window = '[window_id]';
			function vv_link(href, fresh) {
				if (href.indexOf('_src_=vars') == -1) return href;
				return href + ';vvwin=' + vv_window + (fresh ? ';vvnew=1' : '');
			}
			document.addEventListener('click', function(e) {
				var a = e.target;
				while (a && a.tagName != 'A') a = a.parentNode;
				if (!a || !a.getAttribute('href')) return;
				var href = a.getAttribute('href');
				if (href.indexOf('_src_=vars') == -1) return;
				e.preventDefault();
				location.href = vv_link(href, e.shiftKey);
			}, true);
			// one var's row, after it's edited: name, then the row's html
			function vv_row(what) {
				var idx = what.indexOf(':');
				var id = 'vvar_' + what.substr(0, idx);
				var old = document.getElementById(id);
				if (!old) return;
				var holder = document.createElement('ol');
				holder.innerHTML = what.substr(idx + 1);
				var row = holder.firstChild;
				if (!row) return;
				for (var i = 0; i < complete_list.length; i++) {
					if (complete_list\[i\] === old) complete_list\[i\] = row;
				}
				old.parentNode.replaceChild(row, old);
			}
	"}

/// Where an atom is: what it's in, out to the turf and area, and who's carrying it. Links open each in VV.
/proc/vv_where(atom/A)
	if(!istype(A) || isarea(A))
		return ""
	if(isturf(A))
		var/area/turf_area = get_area(A)
		return "<br><font size='1'>[turf_area ? "<a href='?_src_=vars;[HrefToken()];Vars=[REF(turf_area)]'>[html_encode(turf_area.name)]</a> " : ""]([A.x], [A.y], [A.z]) [ADMIN_JMP(A)] (<a href='?_src_=holder;[HrefToken()];adminfindtile=[REF(A)]'>Everything here</a>)</font>"
	if(!A.loc)
		return "<br><font size='1'>Nowhere (in nullspace)</font>"
	var/list/chain = list()
	var/mob/carrier
	var/atom/at = A.loc
	var/steps = 0
	while(at && !isturf(at) && steps++ < 20)
		if(!carrier && ismob(at))
			carrier = at
		chain.Insert(1, "<a href='?_src_=vars;[HrefToken()];Vars=[REF(at)]'>[html_encode(at.name)]</a>") // the name: "[at]" would say "The box"
		at = at.loc
	var/turf/T = get_turf(A)
	var/list/out = list()
	if(T)
		var/area/turf_area = get_area(T)
		if(turf_area)
			out += "<a href='?_src_=vars;[HrefToken()];Vars=[REF(turf_area)]'>[html_encode(turf_area.name)]</a>"
		out += "<a href='?_src_=vars;[HrefToken()];Vars=[REF(T)]'>([T.x], [T.y], [T.z])</a>"
	out += chain
	. = "<br><font size='1'>In: [out.Join(" &gt; ")][T ? " [ADMIN_JMP(T)]" : ""]</font>"
	if(carrier)
		. += "<br><font size='1'>Carried by: <a href='?_src_=vars;[HrefToken()];Vars=[REF(carrier)]'>[html_encode(carrier.name)]</a>[carrier.ckey ? " ([carrier.ckey])" : ""] [ADMIN_FLW(carrier)]</font>"
	. += vv_touched_by(A)

/// Who's touched it: the admin-only hidden prints (every player's first and last touch), for investigating
/proc/vv_touched_by(atom/A)
	var/datum/component/forensics/F = A.GetComponent(/datum/component/forensics)
	var/list/prints = F?.hiddenprints
	if(!length(prints))
		return A.fingerprintslast ? "<br><font size='1'>Last touched by [html_encode(A.fingerprintslast)]</font>" : ""
	var/list/rows = list()
	for(var/key in prints)
		rows += "[html_encode(key)]: [html_encode(prints[key])]"
		if(rows.len >= 6)
			rows += "and [prints.len - 6] more"
			break
	return "<br><details><summary><font size='1'>Touched by [prints.len] player[prints.len == 1 ? "" : "s"][A.fingerprintslast ? ", last [html_encode(A.fingerprintslast)]" : ""]</font></summary><font size='1'>[rows.Join("<br>")]</font></details>"

/// Puts an edited var's row back with its new value, in every window of this client showing D
/client/proc/vv_refresh_var(datum/D, var_name)
	if(!istype(D) || !(var_name in D.vars) || !D.can_vv_get(var_name))
		return
	var/row = D.vv_get_var(var_name)
	for(var/id in vv_windows_showing(D))
		src << output(url_encode("[var_name]:[row]"), "[id].browser:vv_row")

#undef VV_HISTORY_MAX
