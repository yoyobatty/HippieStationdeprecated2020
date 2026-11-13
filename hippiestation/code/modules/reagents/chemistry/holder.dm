/// Reactions in one handle_reactions() call before it stops: a few is a long chain
#define CHEM_REACTION_PASSES 100
/// handle_reactions() inside handle_reactions() on the same holder (a reaction's product added reacts at once): a few is a long chain
#define CHEM_REACTION_NESTING 20

/// Whether reagent_state_check() could do anything: a gas below its boiling point, a solid above its melting point, a liquid either way.
/// Otherwise it's sure to do nothing, and handle_reactions() would ask it of every reagent on every pass.
#define STATE_MAY_CHANGE(R) (R.reagent_state == GAS ? chem_temp < R.boiling_point : (R.reagent_state == SOLID ? chem_temp > R.melting_point : (R.reagent_state != LIQUID || chem_temp > R.boiling_point || chem_temp < R.melting_point)))

/datum/reagents
	var/chem_pressure = 0
	var/chem_radioactivity = 0
	var/chem_bluespaced = FALSE
	var/chem_centrifuged = FALSE
	var/next_react = 0
	/// How deep handle_reactions() is in itself this tick (react_depth_time): see handle_reactions()
	var/react_depth = 0
	var/react_depth_time = -1
	/// The tick its reactions were stopped in, for not settling: nothing more reacts in it that tick
	var/react_stopped_time = -1

/proc/get_random_toxin_reagent_id()	// Returns a random toxin reagent ID minus blacklisted reagents
	var/static/list/random_reagents = list()
	if(!random_reagents.len)
		for(var/thing  in subtypesof(/datum/reagent/toxin))
			var/datum/reagent/RT = thing
			if(initial(RT.can_synth))
				random_reagents += RT.type
	var/picked_reagent = pick(random_reagents)
	return picked_reagent

/// Two recipes that make each other's ingredient react back and forth for ever: each product added reacts at once, one call inside
/// another, until BYOND's recursion limit throws (2026-11-11, tools/mob_storm SCENARIO=chemloop). So the nesting stops at
/// CHEM_REACTION_NESTING and each call's own loop at CHEM_REACTION_PASSES, and once either is reached nothing in the holder reacts again
/// that tick (each level's loop going on would start the levels under it afresh: the caps multiplied). Ordinary chemistry nests a few
/// deep and is exactly as it was (tools/chem_check's 400 mixtures, the same results). The counts start afresh each tick, so a runtime
/// can't leave them stuck.
/datum/reagents/proc/handle_reactions()
	// Heated or cooled away from room temperature: drifts back towards the air around it (reagent_heat.dm)
	if(!(datum_flags & DF_ISPROCESSING) && (chem_temp > T20C + REAGENT_DRIFT_START || chem_temp < T20C - REAGENT_DRIFT_START))
		start_drift()
	if(react_stopped_time == world.time)
		return 0
	if(react_depth_time != world.time)
		react_depth = 0
		react_depth_time = world.time
	if(react_depth >= CHEM_REACTION_NESTING)
		react_stopped_time = world.time
		chem_reaction_loop_stopped(my_atom)
		return 0
	react_depth++
	. = handle_reactions_now()
	react_depth--

/datum/reagents/proc/handle_reactions_now()
	if(!QDELETED(src))	//don't call the proc if the container doesn't exist
		var/list/cached_reagents = reagent_list
		var/list/cached_reactions = GLOB.chemical_reactions_list
		var/datum/cached_my_atom = my_atom
		if(flags & NO_REACT)
			return //Yup, no reactions here. No siree.

		var/reaction_occurred = 0
		var/turf/T = get_turf(cached_my_atom)
		// Nothing new can happen (react_shortcut() below): the states checked as one pass would, and done
		if(react_shortcut())
			for(var/datum/reagent/R as anything in cached_reagents)
				if(STATE_MAY_CHANGE(R))
					reagent_state_check(R, cached_my_atom, T)
			update_total()
			return 0
		stable_amounts = null
		// What's in it by type, as has_reagent() and get_reagent_amount() read it (the first of a type, rounded to CHEMICAL_QUANTISATION_LEVEL),
		// made once and again after each reaction (the only thing in here that changes the amounts) instead of both of them going down
		// the whole list for every reagent of every recipe tried. A chem dispenser EMP'd by a tesla zap splashes a dozen chemicals onto
		// 29 tiles' piles one after another, each reacted in turn: 1.4 s of 1.9 s in 24 of them was has_reagent(), get_reagent_amount()
		// and this proc's own loop (2026-11-08). The same recipes tried in the same order, with the same answers.
		var/list/amounts
		// Two recipes that make each other's ingredients would react back and forth here for ever, in one tick, and the server with them:
		// a few passes is a long chain, so it stops at CHEM_REACTION_PASSES and the next call carries on (2026-11-11)
		var/passes = 0
		do
			if(++passes > CHEM_REACTION_PASSES || react_stopped_time == world.time)
				break
			reaction_occurred = 0
			for(var/reagent in cached_reagents)
				var/datum/reagent/R = reagent
				if(STATE_MAY_CHANGE(R))
					reagent_state_check(R, cached_my_atom, T)

				if(!amounts)
					amounts = list()
					for(var/datum/reagent/present as anything in cached_reagents)
						if(isnull(amounts[present.type]))
							amounts[present.type] = round(present.volume, CHEMICAL_QUANTISATION_LEVEL)
				for(var/reaction in cached_reactions[R.type]) // Was a big list but now it should be smaller since we filtered it with our reagent id
					if(!reaction)
						continue

					var/datum/chemical_reaction/C = reaction
					var/list/cached_required_reagents = C.required_reagents
					var/total_required_reagents = cached_required_reagents.len
					var/total_matching_reagents = 0
					var/multiplier = null // min() of each required reagent's amount over what's required: as min(multipliers) was
					for(var/B in cached_required_reagents)
						var/needed = cached_required_reagents[B]
						var/have = amounts[B]
						if(isnull(have) || (needed && have < needed)) //!has_reagent(B, needed)
							break
						total_matching_reagents++
						var/times = round(have / needed)
						multiplier = isnull(multiplier) ? times : min(multiplier, times)
					// Most recipes tried are missing something: on to the next before the rest is read. The one thing below that acts
					// whether the recipe matches or not is the stop for recipes that don't happen in a mob, so that still happens here.
					if(total_matching_reagents != total_required_reagents)
						if(isliving(cached_my_atom) && !C.mob_react)
							return
						continue
					var/list/cached_required_catalysts = C.required_catalysts
					var/total_required_catalysts = cached_required_catalysts.len
					var/total_matching_catalysts= 0
					var/matching_container = 0
					var/matching_other = 0
					var/required_temp = C.required_temp
					var/is_cold_recipe = C.is_cold_recipe
					var/meets_temp_requirement = 0
					var/centrifuge_recipe = C.centrifuge_recipe
					var/pressure_required = C.pressure_required
					var/radioactivity_required = C.radioactivity_required
					var/bluespace_recipe = C.bluespace_recipe
					var/list/cached_results = C.results

					for(var/B in cached_required_catalysts)
						var/needed = cached_required_catalysts[B]
						var/have = amounts[B]
						if(isnull(have) || (needed && have < needed))
							break
						total_matching_catalysts++
					if(cached_my_atom)
						if(!C.required_container)
							matching_container = 1

						else
							if(cached_my_atom.type == C.required_container)
								matching_container = 1
						if (isliving(cached_my_atom) && !C.mob_react) //Makes it so certain chemical reactions don't occur in mobs
							return
						if(!C.required_other)
							matching_other = 1

						else if(istype(cached_my_atom, /obj/item/slime_extract))
							var/obj/item/slime_extract/M = cached_my_atom

							if(M.Uses > 0) // added a limit to slime cores -- Muskets requested this
								matching_other = 1
					else
						if(!C.required_container)
							matching_container = 1
						if(!C.required_other)
							matching_other = 1

					if(required_temp == 0 || (is_cold_recipe && chem_temp <= required_temp) || (!is_cold_recipe && chem_temp >= required_temp))
						meets_temp_requirement = 1

					if(centrifuge_recipe == TRUE)
						if(!chem_centrifuged)
							continue

					if(bluespace_recipe == TRUE)
						if(!chem_bluespaced)
							continue

					if(total_matching_reagents == total_required_reagents && total_matching_catalysts == total_required_catalysts && matching_container && matching_other && meets_temp_requirement && chem_pressure >= pressure_required && chem_radioactivity >= radioactivity_required)
						amounts = null // it's changing: read again before the next recipe
						for(var/B in cached_required_reagents)
							remove_reagent(B, (multiplier * cached_required_reagents[B]), safety = 1)

						for(var/P in C.results)
							SSblackbox.record_feedback("tally", "chemical_reaction", 1, "[P]|[cached_results[P]*multiplier]")
							multiplier = max(multiplier, 1) //this shouldnt happen ...
							add_reagent(P, cached_results[P]*multiplier, null, chem_temp)

						var/list/seen = viewers(4, get_turf(my_atom))
						var/iconhtml = icon2html(cached_my_atom, seen)
						if(cached_my_atom)
							if(!ismob(cached_my_atom)) // No bubbling mobs
								if(C.mix_sound)
									playsound(get_turf(cached_my_atom), C.mix_sound, 80, 1)

								for(var/mob/M in seen)
									to_chat(M, "<span class='notice'>[iconhtml] [C.mix_message]</span>")

							if(istype(cached_my_atom, /obj/item/slime_extract))
								var/obj/item/slime_extract/ME2 = my_atom
								ME2.Uses--
								if(ME2.Uses <= 0) // give the notification that the slime core is dead
									for(var/mob/M in seen)
										to_chat(M, "<span class='notice'>[iconhtml] \The [my_atom]'s power is consumed in the reaction.</span>")
										ME2.name = "used slime extract"
										ME2.desc = "This extract has been used up."

						C.on_reaction(src, multiplier)
						reaction_occurred = 1
						break

		while(reaction_occurred)
		if(passes > CHEM_REACTION_PASSES || react_stopped_time == world.time)
			react_stopped_time = world.time
			chem_reaction_loop_stopped(cached_my_atom)
		else
			note_stable(amounts) // only when nothing was left to react
		update_total()
		return 0

/// A container whose reactions didn't settle in CHEM_REACTION_PASSES: logged, at most once a minute
/proc/chem_reaction_loop_stopped(atom/where)
	var/static/next_log = 0
	if(world.time < next_log)
		return
	next_log = world.time + 1 MINUTES
	var/list/what = list()
	for(var/datum/reagent/R as anything in where?.reagents?.reagent_list)
		what += "[R.type] [round(R.volume, 0.1)]"
	log_game("CHEM: reactions in [where] ([where?.type]) at [AREACOORD(where)] still going after [CHEM_REACTION_PASSES] in a row or [CHEM_REACTION_NESTING] deep, stopped for now: [jointext(what, ", ")]")

/datum/reagents
	/// What was in it, by type (rounded as the recipes read it), when it last had nothing left to react, and what else the recipes go by
	/// then; null when unknown. See react_shortcut().
	var/list/stable_amounts
	var/stable_temp
	var/stable_pressure
	var/stable_radioactivity
	var/stable_bluespaced
	var/stable_centrifuged
	var/datum/stable_atom

/// Its state of matter by the temperature (a GAS turns LIQUID below its boiling point, and so on), as each pass of handle_reactions() does
/// for each reagent, with the messages
/datum/reagents/proc/reagent_state_check(datum/reagent/R, datum/cached_my_atom, turf/T)
	switch(R.reagent_state)//evaluating state of matter
		if(GAS)
			if(chem_temp < R.boiling_point)
				R.reagent_state = LIQUID
				if(!is_type_in_typecache(cached_my_atom, GLOB.no_reagent_message_typecache) && SSticker.HasRoundStarted())
					for(var/mob/M in viewers(3, T))
						to_chat(M, ("<span class='notice'>[icon2html(cached_my_atom, viewers(cached_my_atom))] The vapour condenses into a liquid!</span>"))

		if(SOLID)
			if(chem_temp > R.melting_point)
				R.reagent_state = LIQUID
				if(!is_type_in_typecache(cached_my_atom, GLOB.no_reagent_message_typecache) && SSticker.HasRoundStarted())
					for(var/mob/M in viewers(3, T))
						to_chat(M, ("<span class='notice'>[icon2html(cached_my_atom, viewers(cached_my_atom))] The solid chemicals melt into a liquid!</span>"))
						//for(var/i = 1; i <= cached_reagents.len; i++)
						//	message_admins("[cached_reagents[i]] melted into liquid of atom [my_atom] located in [my_atom.loc]")
						///For debug purposes, feel free to uncomment in future. (YoYoBatty)

		if(LIQUID)
			if(!is_type_in_typecache(R, GLOB.statechange_reagent_blacklist)) //Reagent states are interchangeable, so one blacklist to rule them all.
				if(chem_temp > R.boiling_point && !is_type_in_typecache(R, GLOB.vaporchange_reagent_blacklist))
					R.reagent_state = GAS
					if(!is_type_in_typecache(cached_my_atom, GLOB.no_reagent_message_typecache) && SSticker.HasRoundStarted())
						for(var/mob/M in viewers(4, T))
							to_chat(M, ("<span class='notice'>[icon2html(cached_my_atom, viewers(cached_my_atom))] The solution rapidly boils into a vapour!</span>"))

				else if(chem_temp < R.melting_point && !is_type_in_typecache(R, GLOB.solidchange_reagent_blacklist))
					R.reagent_state = SOLID
					if(!is_type_in_typecache(cached_my_atom, GLOB.no_reagent_message_typecache) && SSticker.HasRoundStarted())
						for(var/mob/M in viewers(3, T))
							to_chat(M, ("<span class='notice'>[icon2html(cached_my_atom, viewers(cached_my_atom))] The solution solidifies!</span>"))

/// handle_reactions() found nothing to react: what it went by, for react_shortcut()
/datum/reagents/proc/note_stable(list/amounts)
	if(!amounts || isliving(my_atom) || istype(my_atom, /obj/item/slime_extract))
		stable_amounts = null
		return
	stable_amounts = amounts
	stable_temp = chem_temp
	stable_pressure = chem_pressure
	stable_radioactivity = chem_radioactivity
	stable_bluespaced = chem_bluespaced
	stable_centrifuged = chem_centrifuged
	stable_atom = my_atom

/// TRUE when it's known that handle_reactions() would find nothing to react. When it last found nothing, and since then the container and
/// the other things recipes go by are the same, a recipe can only happen now if it needs something there's more of than then (nothing a
/// recipe needs has less of it than it had, and every other recipe failed then), or the temperature's changed and it has one. So only
/// those are tried, as handle_reactions() tries them; if any would happen, the whole thing is done as before, so it's the same reaction
/// that happens, the same way. Splashes add
/// a dozen chemicals one after another to piles that already hold twenty-odd, each add reacted: every recipe of every one tried each time,
/// 160 ms an EMP'd chem dispenser where a tesla kept hitting it (tools/chem_check SAME=1, 2026-11-08). Not in a mob or a slime extract,
/// whose recipes have more to them (mob_react stops the whole proc; an extract's uses run out).
/datum/reagents/proc/react_shortcut()
	var/list/before = stable_amounts
	if(!before || chem_pressure != stable_pressure || chem_radioactivity != stable_radioactivity \
		|| chem_bluespaced != stable_bluespaced || chem_centrifuged != stable_centrifuged || my_atom != stable_atom || (my_atom && QDELETED(my_atom)))
		return FALSE
	var/list/amounts = list()
	for(var/datum/reagent/present as anything in reagent_list)
		if(isnull(amounts[present.type]))
			amounts[present.type] = round(present.volume, CHEMICAL_QUANTISATION_LEVEL)
	var/list/involving = GLOB.reactions_involving || build_reactions_involving()
	var/list/hot_cold_by_first = GLOB.reactions_temp_by_first
	// A temperature change only matters to a recipe whose temperature lies between the two: piles take each chemical at room temperature
	// and drift a little with each one
	var/temp_changed = FALSE
	if(chem_temp != stable_temp)
		var/low = min(chem_temp, stable_temp)
		var/high = max(chem_temp, stable_temp)
		for(var/threshold in GLOB.reaction_temp_thresholds)
			if(threshold >= low && threshold <= high)
				temp_changed = TRUE
				break
	// What to try, and whether that's less than handle_reactions() would try (every recipe under every reagent there): a reagent that goes
	// into hundreds of recipes (ethanol, in the drinks) isn't worth it
	var/list/to_try = list()
	var/trying = 0
	var/whole = 0
	var/list/by_first = GLOB.chemical_reactions_list
	for(var/type in amounts)
		whole += length(by_first[type])
		var/had = before[type]
		var/list/tried
		if(isnull(had) || amounts[type] > had)
			tried = involving[type]
		else if(temp_changed)
			tried = hot_cold_by_first[type] // each once, under its first reagent, as handle_reactions() lists them
		if(length(tried))
			to_try += list(tried)
			trying += length(tried)
	if(trying >= whole)
		return FALSE
	for(var/list/tried as anything in to_try)
		for(var/datum/chemical_reaction/C as anything in tried)
			var/list/required = C.required_reagents
			var/missing = FALSE
			for(var/B in required) // the reagents first, here: nearly every recipe tried fails on them
				var/needed = required[B]
				var/have = amounts[B]
				if(isnull(have) || (needed && have < needed))
					missing = TRUE
					break
			if(!missing && reaction_possible(C, amounts))
				return FALSE
	stable_amounts = amounts
	stable_temp = chem_temp
	return TRUE

/// Each recipe handle_reactions() can try, by every reagent it needs, catalysts too; those with a temperature to them by their first reagent;
/// and every temperature a recipe has
GLOBAL_LIST(reactions_involving)
GLOBAL_LIST(reactions_temp_by_first)
GLOBAL_LIST(reaction_temp_thresholds)

/proc/build_reactions_involving()
	var/list/index = list()
	var/list/temp_index = list()
	var/list/thresholds = list()
	for(var/first in GLOB.chemical_reactions_list)
		for(var/datum/chemical_reaction/C as anything in GLOB.chemical_reactions_list[first])
			if(!C)
				continue
			for(var/type in C.required_reagents | C.required_catalysts)
				if(!index[type])
					index[type] = list()
				index[type] |= C
			if(C.required_temp)
				if(!temp_index[first])
					temp_index[first] = list()
				temp_index[first] |= C
				thresholds |= C.required_temp
	GLOB.reactions_temp_by_first = temp_index
	GLOB.reaction_temp_thresholds = thresholds
	GLOB.reactions_involving = index
	return index

/// Whether handle_reactions() would set this recipe off, with these amounts, outside a mob or a slime extract
/datum/reagents/proc/reaction_possible(datum/chemical_reaction/C, list/amounts)
	for(var/B in C.required_reagents)
		var/needed = C.required_reagents[B]
		var/have = amounts[B]
		if(isnull(have) || (needed && have < needed))
			return FALSE
	for(var/B in C.required_catalysts)
		var/needed = C.required_catalysts[B]
		var/have = amounts[B]
		if(isnull(have) || (needed && have < needed))
			return FALSE
	if(C.required_container && (!my_atom || my_atom.type != C.required_container))
		return FALSE
	if(C.required_other)
		return FALSE
	var/required_temp = C.required_temp
	if(!(required_temp == 0 || (C.is_cold_recipe && chem_temp <= required_temp) || (!C.is_cold_recipe && chem_temp >= required_temp)))
		return FALSE
	if(C.centrifuge_recipe == TRUE && !chem_centrifuged)
		return FALSE
	if(C.bluespace_recipe == TRUE && !chem_bluespaced)
		return FALSE
	return chem_pressure >= C.pressure_required && chem_radioactivity >= C.radioactivity_required

/datum/reagents/reaction(atom/A, method = TOUCH, volume_modifier = 1, show_message = 1, special_modifier = 1)
	var/datum/cached_my_atom = my_atom
	// Smoke reacts with its tile and with every object on it each tick, and each of those changed the reagents' state onto the same
	// tile again: a chempile, solid lump or vapour per object (a cloud over a pile of 400 things made 400 a tick). Its reagents
	// change state once a tick now, on the first call that tick for the tile or a thing on it (foam, VAPOR, already stopped after
	// its first reagent, below)
	var/react_type
	if(isliving(A))
		react_type = "LIVING"
		if(method == INGEST)
			var/mob/living/L = A
			L.taste(src)
	else if(isturf(A))
		react_type = "TURF"
	else if(isobj(A))
		react_type = "OBJ"
	else
		return
	var/smoke_state_change = react_type != "LIVING" && method != VAPOR && istype(cached_my_atom, /obj/effect/particle_effect) && world.time >= next_react
	if(smoke_state_change)
		next_react = world.time + 1
	var/list/cached_reagents = reagent_list
	for(var/reagent in cached_reagents)
		var/datum/reagent/R = reagent
		switch(react_type)
			if("LIVING")
				var/touch_protection = 0
				if(method == VAPOR)
					var/mob/living/L = A
					touch_protection = L.get_permeability_protection()
				R.reaction_mob(A, method, R.volume * volume_modifier, show_message, touch_protection)
			if("TURF")
				if(R.reagent_state != SOLID)
					R.reaction_turf(A, R.volume * volume_modifier, show_message)
				if(smoke_state_change || world.time >= next_react)
					R.handle_state_change(A, R.volume * special_modifier, cached_my_atom)
					if(method == VAPOR)
						next_react = world.time + 1
			if("OBJ")
				if(R.reagent_state != SOLID)
					R.reaction_obj(A, R.volume * volume_modifier, show_message)
				if(smoke_state_change || world.time >= next_react)
					R.handle_state_change(get_turf(A), R.volume * special_modifier, cached_my_atom)
					if(method == VAPOR)
						next_react = world.time + 1

#undef STATE_MAY_CHANGE
