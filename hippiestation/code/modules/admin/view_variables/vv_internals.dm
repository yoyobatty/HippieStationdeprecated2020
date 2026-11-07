// View Variables: the internals, the part of a datum the var list shows only as raw lists. Its components, the signals it
// listens to and who listens to its signals, its timers with what they'll call and when, traits and where they come from,
// status effects, cooldowns, the subsystems processing it and its garbage collection state. Collapsed, with a count of each
// on the summary line, and open or shut as the admin last left it. The user asked for VV's concept improved, 2026-11-07.

/proc/vv_link(datum/D, text)
	if(!D)
		return "null"
	return "<a href='?_src_=vars;[HrefToken()];Vars=[REF(D)]'>[html_encode(text || "[D.type]")]</a>"

/proc/vv_name_of(datum/D)
	if(isatom(D))
		var/atom/A = D
		return "[A.name] ([A.type])"
	return "[D.type]"

/proc/vv_internals(datum/D)
	var/list/sections = list()
	var/list/summary = list()

	// Components
	var/list/rows = list()
	var/list/seen = list() // a component is filed under its type and its parent types too
	for(var/key in D.datum_components)
		var/entry = D.datum_components[key]
		for(var/datum/component/C in (islist(entry) ? entry : list(entry)))
			if(seen[C])
				continue
			seen[C] = TRUE
			rows += vv_link(C, "[C.type]")
	if(rows.len)
		summary += "[rows.len] component[rows.len == 1 ? "" : "s"]"
		sections += "<b>Components</b><br>[rows.Join("<br>")]"

	// Signals it listens to: on what, and the proc that runs
	rows = list()
	for(var/datum/target as anything in D.signal_procs)
		var/list/procs = D.signal_procs[target]
		for(var/sig in procs)
			rows += "[html_encode(sig)] on [target == D ? "itself" : vv_link(target, vv_name_of(target))] &rarr; [html_encode("[procs[sig]]")]"
	if(rows.len)
		summary += "listens to [rows.len] signal[rows.len == 1 ? "" : "s"]"
		sections += "<b>Listens to</b><br>[rows.Join("<br>")]"

	// Who listens to its signals
	rows = list()
	var/listeners = 0
	for(var/sig in D.comp_lookup)
		var/list/who = D.comp_lookup[sig]
		var/list/links = list()
		for(var/datum/L in (islist(who) ? who : list(who)))
			links += L == D ? "itself" : vv_link(L, vv_name_of(L))
			listeners++
		rows += "[html_encode(sig)]: [links.Join(", ")]"
	if(rows.len)
		summary += "[listeners] listener[listeners == 1 ? "" : "s"]"
		sections += "<b>Listened to by</b><br>[rows.Join("<br>")]"

	// Timers
	rows = list()
	for(var/datum/timedevent/T as anything in D.active_timers)
		var/datum/callback/CB = T.callBack
		var/what = CB ? "[CB.delegate]" : "?"
		var/left = round((T.timeToRun - world.time) / 10, 0.1)
		rows += "[vv_link(T, html_encode(what))] in [left] s[T.flags & TIMER_LOOP ? ", every [T.wait / 10] s" : ""][CB && CB.object != D && CB.object != GLOBAL_PROC ? " on [vv_link(CB.object, vv_name_of(CB.object))]" : ""]"
	if(rows.len)
		summary += "[rows.len] timer[rows.len == 1 ? "" : "s"]"
		sections += "<b>Timers</b><br>[rows.Join("<br>")]"

	// Traits, with their sources
	rows = list()
	for(var/trait in D.status_traits)
		var/list/sources = D.status_traits[trait]
		rows += "[html_encode(trait)] <font size='1'>([html_encode(jointext(sources, ", "))])</font>"
	if(rows.len)
		summary += "[rows.len] trait[rows.len == 1 ? "" : "s"]"
		sections += "<b>Traits</b><br>[rows.Join("<br>")]"

	// Status effects
	if(isliving(D))
		var/mob/living/L = D
		rows = list()
		for(var/datum/status_effect/S as anything in L.status_effects)
			rows += vv_link(S, "[S.id || S.type]")
		if(rows.len)
			summary += "[rows.len] status effect[rows.len == 1 ? "" : "s"]"
			sections += "<b>Status effects</b><br>[rows.Join("<br>")]"

	// Cooldowns
	rows = list()
	for(var/index in D.cooldowns)
		rows += html_encode("[index]")
	if(rows.len)
		summary += "[rows.len] cooldown[rows.len == 1 ? "" : "s"]"
		sections += "<b>Cooldowns</b><br>[rows.Join(", ")]"

	// Processed by
	rows = list()
	for(var/datum/controller/subsystem/SS as anything in Master.subsystems)
		if(!("processing" in SS.vars))
			continue
		var/list/processing = SS.vars["processing"]
		if(islist(processing) && (D in processing))
			rows += vv_link(SS, SS.name)
	if(rows.len)
		summary += "processed by [rows.Join(", ")]"
	else if(D.datum_flags & DF_ISPROCESSING)
		summary += "flagged as processing, but in no subsystem's list"

	// Garbage collection
	var/list/gc = list()
	if(D.gc_destroyed)
		gc += "<font color='red'>deleted [round((world.time - D.gc_destroyed) / 10)] s ago, still here</font>"
	if(D.weak_reference)
		gc += "has a weakref"
	if(D.tag)
		gc += "tag [html_encode(D.tag)]"
	if(gc.len)
		sections += "<b>Deletion</b><br>[gc.Join("<br>")]"

	if(!sections.len && !summary.len)
		return "<font size='1'>Internals: none</font><hr>"
	return {"<details id='vv_internals' ontoggle="document.cookie='vv_internals_open=' + (this.open ? 1 : 0) + ';path=/'">
		<summary><font size='1'><b>Internals:</b> [summary.Join(", ") || "see below"]</font></summary>
		<font size='1'>[sections.Join("<br><br>")]</font>
	</details>
	<script type='text/javascript'>if (document.cookie.indexOf('vv_internals_open=1') != -1) document.getElementById('vv_internals').open = true;</script>
	<hr>"}
