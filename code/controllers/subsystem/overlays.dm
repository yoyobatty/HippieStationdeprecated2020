// hippie -- overlays go onto the atom at once, as on tg since 2021, instead of waiting in a queue for the next tick.
// The queue showed changes a tick late, needed COMPILE_OVERLAYS by hand before reading an atom's look (getFlatIcon gave blank
// bodies), and its copy_overlays dropped adds queued earlier in the same tick. "Priority" overlays (blood, fire, acid, c4,
// a gun's knife and light) still survive a plain cut_overlays()/cut_overlay() and stay drawn above the others.
SUBSYSTEM_DEF(overlays)
	name = "Overlay"
	flags = SS_NO_FIRE|SS_NO_INIT

	var/list/stats
	var/list/overlay_icon_state_caches
	var/list/overlay_icon_cache

/datum/controller/subsystem/overlays/PreInit()
	overlay_icon_state_caches = list()
	overlay_icon_cache = list()
	stats = list()

/datum/controller/subsystem/overlays/Shutdown()
	if(length(stats)) // only with OVERLAY_STATS defined below
		text2file(render_stats(stats), "[GLOB.log_directory]/overlay.log")

/datum/controller/subsystem/overlays/Recover()
	overlay_icon_state_caches = SSoverlays.overlay_icon_state_caches
	overlay_icon_cache = SSoverlays.overlay_icon_cache
	stats = SSoverlays.stats

/proc/iconstate2appearance(icon, iconstate)
	var/static/image/stringbro = new()
	var/list/icon_states_cache = SSoverlays.overlay_icon_state_caches
	var/list/cached_icon = icon_states_cache[icon]
	if (cached_icon)
		var/cached_appearance = cached_icon["[iconstate]"]
		if (cached_appearance)
			return cached_appearance
	stringbro.icon = icon
	stringbro.icon_state = iconstate
	if (!cached_icon) //not using the macro to save an associated lookup
		cached_icon = list()
		icon_states_cache[icon] = cached_icon
	var/cached_appearance = stringbro.appearance
	cached_icon["[iconstate]"] = cached_appearance
	return cached_appearance

/proc/icon2appearance(icon)
	var/static/image/iconbro = new()
	var/list/icon_cache = SSoverlays.overlay_icon_cache
	. = icon_cache[icon]
	if (!.)
		iconbro.icon = icon
		. = iconbro.appearance
		icon_cache[icon] = .

/atom/proc/build_appearance_list(old_overlays)
	var/static/image/appearance_bro = new()
	var/list/new_overlays = list()
	if (!islist(old_overlays))
		old_overlays = list(old_overlays)
	for (var/overlay in old_overlays)
		if(!overlay)
			continue
		if (istext(overlay))
			new_overlays += iconstate2appearance(icon, overlay)
		else if(isicon(overlay))
			new_overlays += icon2appearance(overlay)
		else
			appearance_bro.appearance = overlay //this works for images and atoms too!
			// hippie -- BYOND stores every overlay with dir 0 (it follows its parent's), so one given any other dir is not
			// the same appearance as the stored copy: |= added it again and "in" never found it. Copying the source's dir
			// here (as this used to) made every image or mutable_appearance overlay pile up when re-added.
			appearance_bro.dir = 0
			new_overlays += appearance_bro.appearance
	return new_overlays

//#define OVERLAY_STATS // uncomment to time every overlay change into overlay.log / "Display overlay Log"; about 13% slower on a full regenerate_icons()
#ifdef OVERLAY_STATS
#define OVERLAY_STAT_START STAT_START_STOPWATCH
#define OVERLAY_STAT_LOG STAT_STOP_STOPWATCH; STAT_LOG_ENTRY(SSoverlays.stats, type)
#else
#define OVERLAY_STAT_START
#define OVERLAY_STAT_LOG
#endif

/// After the atom's overlays change: alternate appearances that copy them, and the demo recorder
#define POST_OVERLAY_CHANGE(changed_on) \
	if(changed_on.alternate_appearances){\
		for(var/I in changed_on.alternate_appearances){\
			var/datum/atom_hud/alternate_appearance/AA = changed_on.alternate_appearances[I];\
			if(AA.transfer_overlays){\
				AA.copy_overlays(changed_on, TRUE);\
			}\
		}\
	}\
	if(!SSdemo.disabled){\
		if(isturf(changed_on)){SSdemo.mark_turf(changed_on);}\
		else if(isobj(changed_on) || ismob(changed_on)){SSdemo.mark_dirty(changed_on);}\
	}

/// Removes every overlay but the priority ones (all of them with priority = TRUE)
/atom/proc/cut_overlays(priority = FALSE)
	if(priority)
		LAZYCLEARLIST(priority_overlays)
	if(!length(overlays))
		return
	var/list/kept = priority_overlays
	if(length(kept) == length(overlays))
		var/only_kept = TRUE
		for(var/overlay in overlays)
			if(!(overlay in kept))
				only_kept = FALSE
				break
		if(only_kept)
			return // only the priority ones are on, nothing to cut
	OVERLAY_STAT_START
	if(length(kept))
		overlays = kept
	else
		overlays.Cut()
	POST_OVERLAY_CHANGE(src)
	OVERLAY_STAT_LOG

/// Removes these overlays; a priority one only goes when priority = TRUE
/atom/proc/cut_overlay(list/remove, priority = FALSE)
	if(!remove)
		return
	var/list/built = build_appearance_list(remove)
	if(!length(built))
		return
	var/list/kept = priority_overlays
	if(length(kept))
		if(priority)
			kept -= built
			if(!length(kept))
				priority_overlays = null
		else
			built -= kept
			if(!length(built))
				return
	var/before = length(overlays)
	if(!before)
		return
	OVERLAY_STAT_START
	overlays -= built
	if(length(overlays) != before)
		POST_OVERLAY_CHANGE(src)
	OVERLAY_STAT_LOG

/// Adds these overlays (once each); priority ones survive cut_overlays() and are kept drawn above the rest
/atom/proc/add_overlay(list/add, priority = FALSE)
	if(!add)
		return
	var/list/built = build_appearance_list(add)
	if(!length(built))
		return
	OVERLAY_STAT_START
	if(priority)
		LAZYINITLIST(priority_overlays)
		priority_overlays |= built
		overlays |= built
	else
		var/list/kept = priority_overlays
		if(length(kept))
			var/list/combined = overlays.Copy()
			combined -= kept
			combined |= built
			combined |= kept
			overlays = combined
		else
			overlays |= built
	POST_OVERLAY_CHANGE(src)
	OVERLAY_STAT_LOG

/// Copies another atom's overlays onto this one, replacing this one's own (not its priority ones) with cut_old
/atom/proc/copy_overlays(atom/other, cut_old)
	if(!other)
		if(cut_old)
			cut_overlays()
		return
	var/list/cached_other = other.overlays.Copy()
	OVERLAY_STAT_START
	if(cut_old)
		var/list/kept = priority_overlays
		if(length(kept))
			cached_other -= kept
			cached_other |= kept
		overlays = cached_other
	else if(length(cached_other))
		overlays |= cached_other
	else
		return
	POST_OVERLAY_CHANGE(src)
	OVERLAY_STAT_LOG

#undef POST_OVERLAY_CHANGE
#undef OVERLAY_STAT_START
#undef OVERLAY_STAT_LOG

//TODO: Better solution for these?
/image/proc/add_overlay(x)
	overlays |= x

/image/proc/cut_overlay(x)
	overlays -= x

/image/proc/cut_overlays(x)
	overlays.Cut()

/image/proc/copy_overlays(atom/other, cut_old)
	if(!other)
		if(cut_old)
			cut_overlays()
		return

	var/list/cached_other = other.overlays.Copy()
	if(cached_other)
		if(cut_old || !overlays.len)
			overlays = cached_other
		else
			overlays |= cached_other
	else if(cut_old)
		cut_overlays()
