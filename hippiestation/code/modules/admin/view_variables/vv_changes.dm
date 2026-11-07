// View Variables: what's been changed. A var whose plain value (number, text, path, file or null) isn't its compile-time
// default is marked, with a link to put the default back; one an admin edited is marked too, with an undo that puts back
// what it was before the edit. Checkboxes by the search box show only those. References and lists aren't compared: those
// are set as the game runs, so nearly every one would be marked. The user asked for VV's concept improved, 2026-11-07.

/// Admin edits made through VV, var name = list of list(the value before, who, world.time), oldest first. A datum value is kept
/// as a weakref, so an undo record never keeps anything alive.
/datum/var/list/vv_edits

#define VV_EDITS_KEPT 10

/// Vars that are the game's running state, not a setting: never compared with their default
GLOBAL_LIST_INIT(vv_uncompared_vars, list(
	"loc" = TRUE, "x" = TRUE, "y" = TRUE, "z" = TRUE, "contents" = TRUE, "locs" = TRUE, "vars" = TRUE, "verbs" = TRUE,
	"type" = TRUE, "parent_type" = TRUE, "tag" = TRUE, "overlays" = TRUE, "underlays" = TRUE, "vis_contents" = TRUE,
	"vis_locs" = TRUE, "appearance" = TRUE, "transform" = TRUE, "vv_edits" = TRUE, "datum_flags" = TRUE, "gc_destroyed" = TRUE,
	"signal_enabled" = TRUE, "weak_reference" = TRUE, "bound_x" = TRUE, "bound_y" = TRUE, "step_x" = TRUE, "step_y" = TRUE,
	"filters" = TRUE, "pixloc" = TRUE, "flags_1" = TRUE, // filters and pixloc are BYOND's own; flags_1 picks up INITIALIZED_1 and such
))

/// Whether a var's plain value isn't its default
/proc/vv_var_changed(datum/D, var_name)
	if(GLOB.vv_uncompared_vars[var_name] || !(var_name in D.vars))
		return FALSE
	var/value = D.vars[var_name]
	var/default = initial(D.vars[var_name])
	if(islist(value) || islist(default) || istype(value, /datum) || istype(default, /datum))
		return FALSE
	if(isnum(value) && isnum(default))
		if(var_name == "obj_integrity" && value == D.vars["max_integrity"]) // set to max_integrity as it's made: only damage is news
			return FALSE
		return abs(value - default) > 0.00001
	if(var_name == "icon" && ("icon_hippie" in D.vars) && value == D.vars["icon_hippie"]) // Hippie's own sprite swapped in as it's made
		return FALSE
	return value != default

/// The li's attributes and the marks after a var's edit links
/proc/vv_var_marks(datum/D, var_name)
	var/edited = length(LAZYACCESS(D.vv_edits, var_name))
	var/changed = vv_var_changed(D, var_name)
	if(!edited && !changed)
		return list("", "")
	var/list/marks = list()
	if(edited)
		var/list/last = D.vv_edits[var_name][edited]
		marks += "<font size='1' color='red' title='[html_encode("was [vv_short_value(last[1])], by [last[2]]")]'>edited (<a href='?_src_=vars;[HrefToken()];vvundo=1;[VV_HK_TARGET]=[REF(D)];[VV_HK_VARNAME]=[var_name]'>undo</a>)</font>"
	if(changed)
		marks += "<font size='1' color='#8a6d00' title='[html_encode("default: [vv_short_value(initial(D.vars[var_name]))]")]'>changed (<a href='?_src_=vars;[HrefToken()];vvdefault=1;[VV_HK_TARGET]=[REF(D)];[VV_HK_VARNAME]=[var_name]'>default</a>)</font>"
	return list("[edited ? " data-edited='1'" : ""][changed ? " data-changed='1'" : ""]", "[marks.Join(" ")] ")

/proc/vv_short_value(value)
	if(isnull(value))
		return "null"
	if(istype(value, /datum/weakref))
		var/datum/weakref/W = value
		value = W.resolve()
		if(!value)
			return "(something since deleted)"
	var/text = istext(value) ? "\"[value]\"" : "[value]"
	return length(text) > 60 ? "[copytext(text, 1, 58)]..." : text

/// Notes an admin's edit: what the var was before it, for undo
/proc/vv_note_edit(datum/D, var_name, old_value, client/by)
	if(!istype(D))
		return
	LAZYINITLIST(D.vv_edits)
	LAZYINITLIST(D.vv_edits[var_name])
	var/list/history = D.vv_edits[var_name]
	history += list(list(istype(old_value, /datum) ? WEAKREF(old_value) : old_value, by ? by.key : "?", world.time))
	if(history.len > VV_EDITS_KEPT)
		history.Cut(1, 2)

/// Puts a var back to what it was before the last VV edit
/client/proc/vv_undo_var(datum/D, var_name)
	var/list/history = LAZYACCESS(D?.vv_edits, var_name)
	if(!length(history))
		to_chat(src, "<span class='notice'>No edit of [var_name] to undo.</span>", confidential = TRUE)
		return FALSE
	var/list/last = history[history.len]
	var/value = last[1]
	if(istype(value, /datum/weakref))
		var/datum/weakref/W = value
		value = W.resolve()
		if(!value)
			to_chat(src, "<span class='warning'>What [var_name] held before has been deleted since.</span>", confidential = TRUE)
			return FALSE
	var/was = D.vars[var_name]
	if(D.vv_edit_var(var_name, value) == FALSE)
		to_chat(src, "<span class='warning'>The undo was rejected by the object.</span>", confidential = TRUE)
		return FALSE
	history.Cut(history.len)
	if(!history.len)
		D.vv_edits -= var_name
	vv_log_change(D, var_name, was, value, "undid the last edit of")
	return TRUE

/// Puts a var back to its compile-time default (undoable like an edit)
/client/proc/vv_restore_default(datum/D, var_name)
	if(!istype(D) || !(var_name in D.vars) || !vv_varname_lockcheck(var_name))
		return FALSE
	var/was = D.vars[var_name]
	var/default = initial(D.vars[var_name])
	if(D.vv_edit_var(var_name, default) == FALSE)
		to_chat(src, "<span class='warning'>Your edit was rejected by the object.</span>", confidential = TRUE)
		return FALSE
	vv_note_edit(D, var_name, was, src)
	vv_log_change(D, var_name, was, default, "restored the default of")
	return TRUE

/client/proc/vv_log_change(datum/D, var_name, old_value, new_value, what)
	vv_update_display(D, "varedited", VV_MSG_EDITED)
	log_world("### VarEdit by [key_name(src)]: [D.type] [var_name]=[old_value] => [new_value] ([what])")
	log_admin("[key_name(src)] [what] [D]'s [var_name]: [html_encode("[old_value]")] to [html_encode("[new_value]")]")
	var/msg = "[key_name_admin(src)] [what] [D]'s [var_name]: [old_value] to [new_value]"
	message_admins(msg)
	admin_ticket_log(D, msg)

/// How many vars are edited and changed, for the page's header
/proc/vv_change_counts(datum/D)
	var/edited = 0
	var/changed = 0
	for(var/var_name in D.vars)
		if(length(LAZYACCESS(D.vv_edits, var_name)))
			edited++
		if(vv_var_changed(D, var_name))
			changed++
	return "<br><font size='1'>[edited] edited, [changed] changed from default</font>"

#undef VV_EDITS_KEPT
