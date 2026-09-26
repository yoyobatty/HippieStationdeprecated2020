// Experimental botany. Some botanists are mad scientists (botany_temperament): once the bay is
// running they take on a project the way players do it on a pre-2020 hydroponics server (the
// "Old guides" part of the tgstation Guide to Hydroponics):
//
//  - get the species: buy it from the MegaSeed Servitor, hacking it for contraband (nettles) if
//    need be, or MUTATE it - plant the parent in a lab tray fed Left 4 Zed (a chance of a new
//    species every time it ripens, nutrimentMutation()) plus unstable mutagen when a chemist
//    obliges (50u guarantees it on this server, hydroponics.dm's hippie applyChemicals());
//  - put the produce through the seed extractor for seeds;
//  - pull genes out onto plant data disks with the DNA manipulator (extracting destroys the donor
//    seed) and splice them into the base crop (gene_modder.dm Topic() "extract"/"insert");
//  - grow the result, harvest it, tell the station about it and leave a few on the Hydroponics
//    counter; keep a few for self-defence (try_botany_weapon(), called from handle_combat()).
//
// Like the tray round, every step is chosen from what the bot and the bay actually have right now
// (botany_project_next_goal()), so it picks up where it left off after any interruption.

#define BOT_PROJECT_KEEP 2 //creations kept for self-defence before any go on the counter
#define BOT_PROJECT_COUNTER_MAX 3 //how many to leave out for people at once
#define BOT_MUTATION_TRAYS 2 //lab trays growing the parent species in parallel

// ---------------------------------------------------------------------------------------------
// Recipes
// ---------------------------------------------------------------------------------------------

/datum/botany_recipe
	var/name
	/// The seed the creation is grown from.
	var/base
	/// list(list(gene, donor seed type)) spliced into the base. gene is a reagent type (a
	/// reagent gene) or a /datum/plant_gene/trait type. Empty for a species that is the creation.
	var/list/genes = list()
	/// "throw" (splashes/stings), "melee" (a weapon to swing), "grenade" (prime, then throw) or
	/// "joke" (not a weapon).
	var/use = "throw"
	/// Said over the radio when the first batch comes in.
	var/announce

/datum/botany_recipe/acid_melons
	name = "acid melons"
	base = /obj/item/seeds/watermelon
	genes = list(list(/datum/reagent/toxin/acid/fluacid, /obj/item/seeds/nettle/death), list(/datum/plant_gene/trait/squash, /obj/item/seeds/tomato))
	announce = "Hydroponics has ACID MELONS. They burst when you throw them. Fluorosulfuric acid. Some on the counter, don't eat them."

/datum/botany_recipe/death_nettles
	name = "death nettles"
	base = /obj/item/seeds/nettle/death
	use = "melee"
	announce = "Got death nettles growing in Hydroponics. Wear gloves if you want one, they're on the counter."

/datum/botany_recipe/combustible_lemons
	name = "combustible lemons"
	base = /obj/item/seeds/firelemon
	use = "grenade"
	announce = "When life gives you lemons... Hydroponics has combustible lemons. Use in hand, then THROW. Counter."

/datum/botany_recipe/pepper_tomatoes
	name = "pepper tomatoes"
	base = /obj/item/seeds/tomato
	genes = list(list(/datum/reagent/consumable/condensedcapsaicin, /obj/item/seeds/chili/ghost))
	announce = "Pepper spray tomatoes, fresh from Hydroponics. Throw one at a clown. Counter."

/datum/botany_recipe/lube_bananas
	name = "lube bananas"
	base = /obj/item/seeds/banana
	genes = list(list(/datum/reagent/lube, /obj/item/seeds/tomato/blue))
	use = "joke"
	announce = "Hydroponics made space lube bananas. Peels on the counter. Honk."

/datum/botany_recipe/mute_apples
	name = "mute apples"
	base = /obj/item/seeds/apple
	genes = list(list(/datum/reagent/toxin/mutetoxin, /obj/item/seeds/banana/mime))
	use = "joke"
	announce = "Hydroponics has apples that shut you up. For the talkative. Counter."

GLOBAL_LIST_INIT(bot_botany_recipes, init_bot_botany_recipes())

/proc/init_bot_botany_recipes()
	. = list()
	for(var/path in subtypesof(/datum/botany_recipe))
		. += new path

/// Species a botanist can only get by mutating another one (the mutatelist it's in).
GLOBAL_LIST_INIT(bot_botany_ancestors, list(
	/obj/item/seeds/nettle/death = /obj/item/seeds/nettle,
	/obj/item/seeds/firelemon = /obj/item/seeds/lemon,
	/obj/item/seeds/chili/ghost = /obj/item/seeds/chili,
	/obj/item/seeds/tomato/blue = /obj/item/seeds/tomato,
	/obj/item/seeds/banana/mime = /obj/item/seeds/banana,
))

/proc/bot_seed_is_experimental(obj/item/seeds/S)
	return copytext(S.name, 1, 13) == "experimental"

/// S is an unmodified packet of exactly this species (a blue tomato is not a tomato).
/proc/bot_seed_is_plain(obj/item/seeds/S, species)
	return S && S.type == species && !bot_seed_is_experimental(S)

/proc/bot_seed_has_gene(obj/item/seeds/S, gene)
	if(ispath(gene, /datum/plant_gene))
		for(var/datum/plant_gene/G in S.genes)
			if(G.type == gene)
				return TRUE
		return FALSE
	for(var/datum/plant_gene/reagent/R in S.genes)
		if(R.reagent_id == gene)
			return TRUE
	return FALSE

/// The gene datum in donor that carries gene.
/proc/bot_seed_find_gene(obj/item/seeds/donor, gene)
	for(var/datum/plant_gene/G in donor.genes)
		if(ispath(gene, /datum/plant_gene))
			if(G.type == gene)
				return G
			continue
		var/datum/plant_gene/reagent/R = G
		if(istype(R) && R.reagent_id == gene)
			return R
	return null

/proc/bot_disk_holds(obj/item/disk/plantgene/D, gene)
	if(!D?.gene)
		return FALSE
	if(ispath(gene, /datum/plant_gene))
		return D.gene.type == gene
	var/datum/plant_gene/reagent/R = D.gene
	return istype(R) && R.reagent_id == gene

/datum/botany_recipe/proc/is_result(obj/item/seeds/S)
	if(!S || S.type != base)
		return FALSE
	for(var/list/G in genes)
		if(!bot_seed_has_gene(S, G[1]))
			return FALSE
	return TRUE

/// Every species this recipe needs at some point - kept out of ordinary planting while it runs.
/datum/botany_recipe/proc/species_needed()
	. = list(base)
	for(var/list/G in genes)
		. |= G[2]
	for(var/S in .)
		var/parent = GLOB.bot_botany_ancestors[S]
		if(parent)
			. |= parent

/// A recipe whose result this produce is, if any.
/proc/bot_botany_recipe_of(obj/item/reagent_containers/food/snacks/grown/G)
	if(!istype(G) || !G.seed)
		return null
	for(var/datum/botany_recipe/R as anything in GLOB.bot_botany_recipes)
		if(R.is_result(G.seed) && (length(R.genes) || R.use != "joke"))
			return R
	return null

// ---------------------------------------------------------------------------------------------
// The project
// ---------------------------------------------------------------------------------------------

/datum/botany_project
	var/datum/botany_recipe/recipe
	/// Lab tray -> the species it should end up growing.
	var/list/lab_trays = list()
	var/asked_for_mutagen = FALSE
	var/shown_off = FALSE
	/// Errands given up on - enough of them and the project is dropped.
	var/failures = 0
	var/started

/datum/botany_project/New(datum/botany_recipe/R)
	. = ..()
	recipe = R
	started = world.time

/datum/bot_brain
	/// "mad scientist" or "farmer", rolled the first time it matters.
	var/botany_temperament
	var/datum/botany_project/botany_project
	var/next_botany_project_time = 0
	var/next_botany_weapon_time = 0

/datum/bot_brain/proc/is_mad_scientist()
	if(!botany_temperament)
		botany_temperament = prob(35) ? "mad scientist" : "farmer"
		if(botany_temperament == "mad scientist")
			next_botany_project_time = world.time + rand(3 MINUTES, 6 MINUTES) //get the farm going first
	return botany_temperament == "mad scientist"

/// Works on the current project, starting one when it's time. TRUE if that gave the bot a goal.
/datum/bot_brain/proc/try_botany_project()
	if(!is_botanist_job() || !is_mad_scientist())
		return FALSE
	if(!botany_project)
		if(world.time < next_botany_project_time)
			return FALSE
		var/datum/botany_recipe/R = pick_botany_recipe()
		if(!R)
			next_botany_project_time = world.time + 5 MINUTES
			return FALSE
		botany_project = new(R)
		bot_log(src, "starting a botany project: [R.name]")
		bot_say(owner, pick("I've got an idea for the trays.", "Time for some science.", "Let's see what these can really do.", "Hold my plant bag."))
	var/datum/bot_goal/G = botany_project_next_goal()
	return G ? assign_goal(G) : FALSE

/datum/bot_brain/proc/pick_botany_recipe()
	var/list/options = list()
	var/can_splice = !!find_dna_manipulator()
	for(var/datum/botany_recipe/R as anything in GLOB.bot_botany_recipes)
		if(length(R.genes) && !can_splice)
			continue
		options += R
	return length(options) ? pick(options) : null

/datum/bot_brain/proc/end_botany_project(success)
	if(!botany_project)
		return
	bot_log(src, "botany project [botany_project.recipe.name] [success ? "done" : "abandoned"]")
	botany_project = null
	next_botany_project_time = world.time + (success ? rand(15 MINUTES, 25 MINUTES) : rand(5 MINUTES, 10 MINUTES))

/datum/bot_brain/proc/is_project_tray(obj/machinery/hydroponics/H)
	return botany_project && (H in botany_project.lab_trays)

/// "mutate" (feed Left 4 Zed, pour mutagen), "grow" (lock the species with Robust Harvest), or
/// null for a tray that isn't part of the project.
/datum/bot_brain/proc/project_tray_role(obj/machinery/hydroponics/H)
	if(!is_project_tray(H) || !H.myseed || H.dead)
		return null
	var/want = botany_project.lab_trays[H]
	return (H.myseed.type == want || bot_seed_is_experimental(H.myseed)) ? "grow" : "mutate"

/// Seeds the project needs are not for ordinary planting.
/datum/bot_brain/proc/is_reserved_seed(obj/item/seeds/S)
	return botany_project && (S.type in botany_project.recipe.species_needed())

/// The next thing to do for the project, or null while waiting on the trays.
/datum/bot_brain/proc/botany_project_next_goal()
	var/datum/botany_project/P = botany_project
	var/datum/botany_recipe/R = P.recipe
	if(P.shown_off)
		end_botany_project(TRUE)
		return null
	forget_lost_lab_trays()
	var/growing = FALSE
	for(var/obj/machinery/hydroponics/H in P.lab_trays)
		if(H.myseed && !H.dead && R.is_result(H.myseed))
			growing = TRUE
	// Show it off once there's some to spare - or when this is all there's going to be. A tree
	// still bearing (a mutation can leave it yielding one or two) is worth another harvest first.
	var/made = length(carried_creations(R))
	if(made && (made > BOT_PROJECT_KEEP || !growing))
		return new /datum/bot_goal/botany_project_errand/show_off_creation()
	if(growing)
		return null //the tray round harvests it
	for(var/obj/item/seeds/S as anything in carried_seeds())
		if(R.is_result(S) && (length(R.genes) || !bot_seed_is_experimental(S)))
			return plant_project_seed_goal(S, R.base)
	if(!length(R.genes))
		return obtain_species_goal(R.base)
	var/obj/machinery/plantgenes/M = find_dna_manipulator()
	if(!M)
		end_botany_project(FALSE)
		return null
	for(var/list/G in R.genes)
		if(carried_disk_with(G[1]))
			continue
		if(!carried_blank_disk())
			return get_disks_goal()
		var/obj/item/seeds/donor = carried_plain_seed(G[2])
		if(donor)
			return new /datum/bot_goal/botany_project_errand/extract_gene(M, donor, G[1])
		return obtain_species_goal(G[2])
	var/obj/item/seeds/base = carried_plain_seed(R.base)
	if(base)
		return new /datum/bot_goal/botany_project_errand/splice_seed(M, base, R)
	return obtain_species_goal(R.base)

/// Gets a packet of species S one way or another. Null while waiting (a tray is mutating).
/datum/bot_brain/proc/obtain_species_goal(species)
	var/datum/botany_project/P = botany_project
	for(var/obj/item/reagent_containers/food/snacks/grown/G in carried_produce())
		if(G.seed && bot_seed_is_plain(G.seed, species))
			return new /datum/bot_goal/botany_project_errand/extract_species(species)
	var/obj/machinery/vending/hydroseeds/V = find_seed_vendor_for(species)
	if(V)
		if(!length(vendor_stock(V, list(species))))
			if(is_botany_supply_blocked("hack"))
				return null
			return new /datum/bot_goal/botany_project_errand/hack_seed_vendor(V)
		return new /datum/bot_goal/botany_project_errand/buy_project_seeds(V, species)
	for(var/obj/machinery/hydroponics/H in P.lab_trays)
		if(H.myseed && !H.dead && H.myseed.type == species)
			return null //ripening - its produce comes back through the extractor
	var/parent = GLOB.bot_botany_ancestors[species]
	if(!parent)
		bot_log(src, "no way to get [species] for [P.recipe.name]")
		end_botany_project(FALSE)
		return null
	var/mutating = 0
	for(var/obj/machinery/hydroponics/H in P.lab_trays)
		if(P.lab_trays[H] != species || !H.myseed || H.dead)
			continue
		if(H.myseed.type == parent || (species in H.myseed.mutatelist))
			mutating++
		else
			return new /datum/bot_goal/botany_project_errand/clear_lab_tray(H) //mutated the wrong way into a dead end
	var/obj/item/seeds/seed = carried_plain_seed(parent)
	if(seed && mutating < BOT_MUTATION_TRAYS)
		return plant_project_seed_goal(seed, species)
	if(mutating)
		if(!P.asked_for_mutagen)
			P.asked_for_mutagen = TRUE
			bot_say(owner, ";Chemistry, could I get 50u of unstable mutagen in Hydroponics? It's for science.")
		var/obj/item/reagent_containers/loose = find_loose_mutagen()
		if(loose && !carried_mutagen())
			return new /datum/bot_goal/botany_project_errand/botany_pickup(loose)
		return null
	return obtain_species_goal(parent)

/// Lab trays that were dug up, destroyed, or taken over by weeds of their own accord.
/datum/bot_brain/proc/forget_lost_lab_trays()
	for(var/obj/machinery/hydroponics/H in botany_project.lab_trays.Copy())
		if(QDELETED(H))
			botany_project.lab_trays -= H

/// Plants S (becoming species `goal` eventually) in a free tray, claiming it for the project.
/datum/bot_brain/proc/plant_project_seed_goal(obj/item/seeds/S, goal)
	var/obj/machinery/hydroponics/H = claim_lab_tray()
	if(!H)
		return null
	return new /datum/bot_goal/botany_project_errand/plant_project_seed(H, S, goal)

/// An empty tray, or one a dead plant can be pulled from; failing that a young ordinary crop to
/// dig up with a spade. Trays already in the project that are empty come first.
/datum/bot_brain/proc/claim_lab_tray()
	var/obj/machinery/hydroponics/best
	var/best_score
	for(var/obj/machinery/hydroponics/H as anything in bot_instances_of(/obj/machinery/hydroponics))
		if(!is_workplace_tray(H))
			continue
		var/score
		if(is_project_tray(H))
			if(H.myseed && !H.dead)
				continue
			score = 0
		else if(!H.myseed || H.dead)
			score = 1
		else if(!H.harvest)
			score = 10 + H.age //dig up the youngest crop
		else
			continue
		score += get_dist(owner, H) / 10
		if(!best || score < best_score)
			best = H
			best_score = score
	return best

// ---------------------------------------------------------------------------------------------
// Carried things
// ---------------------------------------------------------------------------------------------

/datum/bot_brain/proc/carried_plain_seed(species)
	for(var/obj/item/seeds/S as anything in carried_seeds())
		if(bot_seed_is_plain(S, species))
			return S
	return null

/datum/bot_brain/proc/carried_creations(datum/botany_recipe/R)
	. = list()
	for(var/obj/item/reagent_containers/food/snacks/grown/G in owner.GetAllContents())
		if(G.seed && R.is_result(G.seed))
			. += G

/datum/bot_brain/proc/carried_disk_with(gene)
	for(var/obj/item/disk/plantgene/D in owner.GetAllContents())
		if(bot_disk_holds(D, gene))
			return D
	return null

/datum/bot_brain/proc/carried_blank_disk()
	for(var/obj/item/disk/plantgene/D in owner.GetAllContents())
		if(!D.gene && !D.read_only)
			return D
	return null

/// A carried container with enough unstable mutagen in it for a species roll (5u).
/datum/bot_brain/proc/carried_mutagen()
	for(var/obj/item/reagent_containers/C in owner.GetAllContents())
		if(C.reagents?.get_reagent_amount(/datum/reagent/toxin/mutagen) >= 5 && C.is_drainable())
			return C
	return null

/datum/bot_brain/proc/find_loose_mutagen()
	for(var/obj/item/reagent_containers/C as anything in bot_instances_of(/obj/item/reagent_containers/glass))
		if(isturf(C.loc) && botany_in_reach(C) && C.reagents?.get_reagent_amount(/datum/reagent/toxin/mutagen) >= 5)
			return C
	return null

/datum/bot_brain/proc/find_dna_manipulator()
	for(var/obj/machinery/plantgenes/M as anything in bot_instances_of(/obj/machinery/plantgenes))
		if(botany_in_reach(M) && !(M.stat & (BROKEN|NOPOWER)) && !M.panel_open)
			return M
	return null

/// The seed vendor that sells species, stock or contraband.
/datum/bot_brain/proc/find_seed_vendor_for(species)
	for(var/obj/machinery/vending/hydroseeds/V as anything in bot_instances_of(/obj/machinery/vending/hydroseeds))
		if(!botany_in_reach(V) || (V.stat & (BROKEN|NOPOWER)))
			continue
		for(var/datum/data/vending_product/R in V.product_records + V.hidden_records)
			if(R.product_path == species && R.amount > 0)
				return V
	return null

/// The Hydroponics front counter - a table with a windoor on it - or failing that any table in
/// the bay (any table in a Bot Gym arena).
/datum/bot_brain/proc/find_botany_counter()
	var/obj/structure/table/best
	var/best_score
	for(var/obj/structure/table/T as anything in bot_instances_of(/obj/structure/table))
		if(!botany_in_reach(T) || !isturf(T.loc))
			continue
		var/area/A = get_area(T)
		if(!gym_run && !istype(A, /area/hydroponics))
			continue
		var/score = get_dist(owner, T) + ((locate(/obj/machinery/door/window) in T.loc) ? 0 : 100)
		if(!best || score < best_score)
			best = T
			best_score = score
	return best

// ---------------------------------------------------------------------------------------------
// Goals
// ---------------------------------------------------------------------------------------------

/// Things every project errand shares: runs its steps once, doesn't chain on its own - the next
/// round picks the next step.
/datum/bot_goal/botany_project_errand/on_success(datum/bot_brain/bot)
	bot.continue_botany_round()

/datum/bot_goal/botany_project_errand/on_give_up(datum/bot_brain/bot)
	bot.next_botany_check_time = world.time + 30 SECONDS
	var/datum/botany_project/P = bot.botany_project
	if(P && ++P.failures >= 8)
		bot_say(bot.owner, pick("This isn't working.", "Forget it, back to farming.", "Science can wait."))
		bot.end_botany_project(FALSE)

/datum/bot_goal/botany_project_errand/proc/errand(list/steps)
	var/datum/bot_strategy/botany_errand/S = new
	S.steps = steps
	return list(S)

/datum/bot_goal/botany_project_errand/buy_project_seeds
	var/species

/datum/bot_goal/botany_project_errand/buy_project_seeds/New(obj/machinery/vending/V, species)
	. = ..()
	target = V
	src.species = species

/datum/bot_goal/botany_project_errand/buy_project_seeds/get_strategies(datum/bot_brain/bot)
	var/list/buy = list(species)
	for(var/child in GLOB.bot_botany_ancestors)
		if(GLOB.bot_botany_ancestors[child] == species)
			buy += species //a parent for the mutation trays: one packet per tray
			break
	return errand(list(new /datum/bot_step/move_to(), new /datum/bot_step/paced/vend_products(buy)))

/// Picks something up off a table or the floor (a bottle of mutagen someone brought over).
/datum/bot_goal/botany_project_errand/botany_pickup/New(obj/item/I)
	. = ..()
	target = I

/datum/bot_goal/botany_project_errand/botany_pickup/get_strategies(datum/bot_brain/bot)
	return errand(list(new /datum/bot_step/move_to(), new /datum/bot_step/take_target()))

/// Seeds of `species` from its produce in the plant bag.
/datum/bot_goal/botany_project_errand/extract_species
	var/species

/datum/bot_goal/botany_project_errand/extract_species/New(species)
	. = ..()
	src.species = species

/datum/bot_goal/botany_project_errand/extract_species/resolve_target(datum/bot_brain/bot)
	target = bot.find_seed_extractor()

/datum/bot_goal/botany_project_errand/extract_species/get_strategies(datum/bot_brain/bot)
	var/datum/bot_step/paced/extract_seeds/E = new(target, 1)
	E.only_type = species
	return errand(list(new /datum/bot_step/move_to(), E))

/// Takes the box of plant data disks out of a Hydroponics locker (or loose disks off a table).
/datum/bot_brain/proc/get_disks_goal()
	for(var/obj/item/disk/plantgene/D as anything in bot_instances_of(/obj/item/disk/plantgene))
		if(isturf(D.loc) && !D.gene && !D.read_only && botany_in_reach(D))
			return new /datum/bot_goal/botany_project_errand/botany_pickup(D)
	for(var/obj/structure/closet/C as anything in bot_instances_of(/obj/structure/closet))
		if(!botany_in_reach(C) || (C.locked && !C.allowed(owner)))
			continue
		if(locate(/obj/item/storage/box/disks_plantgene) in C)
			return new /datum/bot_goal/botany_project_errand/disks_from_locker(C)
	bot_log(src, "no plant data disks anywhere I can get to")
	end_botany_project(FALSE)
	return null

/datum/bot_goal/botany_project_errand/disks_from_locker/New(obj/structure/closet/C)
	. = ..()
	target = C

/datum/bot_goal/botany_project_errand/disks_from_locker/get_strategies(datum/bot_brain/bot)
	return errand(list(new /datum/bot_step/move_to(), new /datum/bot_step/interact(), new /datum/bot_step/pickup_from_target(/obj/item/storage/box/disks_plantgene)))

/// Plants a project seed in a lab tray - digging out whatever ordinary crop was there first.
/datum/bot_goal/botany_project_errand/plant_project_seed
	var/obj/item/seeds/seed
	var/goal_species

/datum/bot_goal/botany_project_errand/plant_project_seed/New(obj/machinery/hydroponics/H, obj/item/seeds/S, goal_species)
	. = ..()
	target = H
	seed = S
	src.goal_species = goal_species

/datum/bot_goal/botany_project_errand/plant_project_seed/get_strategies(datum/bot_brain/bot)
	var/list/steps = list()
	var/obj/machinery/hydroponics/H = target
	if(H.myseed && !H.dead && !bot.carried_botany_item(/obj/item/shovel/spade))
		steps += new /datum/bot_step/fetch_botany_supply("spade")
	steps += new /datum/bot_step/move_to()
	steps += new /datum/bot_step/paced/plant_project_seed()
	return errand(steps)

/datum/bot_goal/botany_project_errand/plant_project_seed/on_success(datum/bot_brain/bot)
	if(bot.botany_project && !QDELETED(target))
		bot.botany_project.lab_trays[target] = goal_species
	return ..()

/// Fetches one supply by key (see botany_supply_goal()) and carries on either way.
/datum/bot_step/fetch_botany_supply
	var/key
	var/tried = FALSE

/datum/bot_step/fetch_botany_supply/New(key)
	. = ..()
	src.key = key

/datum/bot_step/fetch_botany_supply/execute(datum/bot_brain/bot)
	if(tried)
		return GOAL_STEP_SUCCESS
	tried = TRUE
	var/datum/bot_goal/G = bot.botany_supply_goal(key)
	if(G && bot.suspend_goal_for(G))
		return GOAL_STEP_PENDING
	return GOAL_STEP_SUCCESS

/datum/bot_step/paced/plant_project_seed
	var/digging = FALSE

/datum/bot_step/paced/plant_project_seed/start(datum/bot_brain/bot)
	return bot.owner.Adjacent(bot.current_goal?.target)

/datum/bot_step/paced/plant_project_seed/do_click(datum/bot_brain/bot)
	var/datum/bot_goal/botany_project_errand/plant_project_seed/G = bot.current_goal
	var/obj/machinery/hydroponics/H = G.target
	if(QDELETED(H) || !bot.owner.Adjacent(H) || QDELETED(G.seed) || G.seed.loc == H)
		return FALSE
	if(H.dead)
		bot_log(bot, "pulling the dead [H.myseed?.plantname] out of [H]")
		return bot.use_atom(H)
	if(H.myseed)
		var/obj/item/shovel/spade/S = bot.carried_botany_item(/obj/item/shovel/spade)
		if(!S || digging)
			return FALSE
		digging = TRUE
		bot_log(bot, "digging up the [H.myseed.plantname] in [H] to make room for the project")
		bot.botany_use(S, H) //a five second dig (tray attackby(), use_tool())
		digging = FALSE
		return TRUE
	bot_log(bot, "planting [G.seed] in [H] for the project")
	bot.botany_use(G.seed, H)
	return TRUE

/datum/bot_step/paced/plant_project_seed/finish(datum/bot_brain/bot)
	var/datum/bot_goal/botany_project_errand/plant_project_seed/G = bot.current_goal
	for(var/obj/item/held in bot.owner.held_items)
		if(bot.is_botany_tool(held))
			bot.put_away_botany(held)
	return (G.seed && G.seed.loc == G.target) ? GOAL_STEP_SUCCESS : GOAL_STEP_FAIL

/// A lab tray that mutated into a dead end (a blood tomato when blue was wanted): dig it out.
/datum/bot_goal/botany_project_errand/clear_lab_tray/New(obj/machinery/hydroponics/H)
	. = ..()
	target = H

/datum/bot_goal/botany_project_errand/clear_lab_tray/get_strategies(datum/bot_brain/bot)
	var/list/steps = list()
	if(!bot.carried_botany_item(/obj/item/shovel/spade))
		steps += new /datum/bot_step/fetch_botany_supply("spade")
	steps += new /datum/bot_step/move_to()
	steps += new /datum/bot_step/dig_out_tray()
	return errand(steps)

/datum/bot_step/dig_out_tray/execute(datum/bot_brain/bot)
	var/obj/machinery/hydroponics/H = bot.current_goal?.target
	var/obj/item/shovel/spade/S = bot.carried_botany_item(/obj/item/shovel/spade)
	if(!H || !S || !bot.owner.Adjacent(H))
		return GOAL_STEP_FAIL
	if(H.myseed)
		bot_log(bot, "that [H.myseed.plantname] is no good to me - digging it up")
		bot.botany_use(S, H)
	bot.put_away_botany(S)
	return H.myseed ? GOAL_STEP_FAIL : GOAL_STEP_SUCCESS

// ---------------------------------------------------------------------------------------------
// The DNA manipulator, replicating its Topic() operations (gene_modder.dm) against a real
// seed/disk the bot has put in with its own hands.
// ---------------------------------------------------------------------------------------------

/datum/bot_brain/proc/manipulator_press(obj/machinery/plantgenes/M, action)
	human_pause(M)
	if(QDELETED(M) || !owner.Adjacent(M))
		return FALSE
	owner.face_atom(M)
	telemetry_ui_action(M, action)
	return TRUE

/// Puts a seed or disk into the manipulator from the hand - what its attackby() does, minus the
/// browser window it opens for the user (a bot has no client to show it on).
/datum/bot_brain/proc/manipulator_insert(obj/machinery/plantgenes/M, obj/item/I)
	if(QDELETED(M) || M.operation || !botany_ready(I))
		return FALSE
	human_pause(M)
	if(QDELETED(M) || !owner.Adjacent(M) || owner.get_active_held_item() != I)
		return FALSE
	owner.face_atom(M)
	if(istype(I, /obj/item/seeds))
		if(M.seed || !owner.temporarilyRemoveItemFromInventory(I))
			return FALSE
		M.insert_seed(I)
	else if(istype(I, /obj/item/disk/plantgene))
		if(M.disk || !owner.transferItemToLoc(I, M))
			return FALSE
		M.disk = I
		M.update_genes()
	else
		return FALSE
	telemetry_event("use", list("item" = "[I]", "item_was" = "active_hand", "target" = "[M]", "target_type" = bot_telemetry_short(M.type),
		"dist" = get_dist(owner, M), "harm" = FALSE, "dur" = 0, "ok" = TRUE) + telemetry_target_fields(M))
	bot_log(src, "put [I] into [M]")
	return TRUE

/// Takes the disk out into a hand and puts it away.
/datum/bot_brain/proc/manipulator_eject_disk(obj/machinery/plantgenes/M)
	var/obj/item/disk/plantgene/D = M.disk
	if(!D || M.operation || !manipulator_press(M, "eject disk"))
		return FALSE
	M.disk = null
	M.update_genes()
	if(!owner.put_in_hands(D))
		D.forceMove(M.drop_location())
		return FALSE
	put_away_botany(D)
	return TRUE

/// Ejects the loaded seed onto the machine's tile. Takes it if it's ours to take.
/datum/bot_brain/proc/manipulator_eject_seed(obj/machinery/plantgenes/M, take = TRUE)
	var/obj/item/seeds/S = M.seed
	if(!S || M.operation || !manipulator_press(M, "eject seed"))
		return null
	S.forceMove(M.drop_location())
	M.seed = null
	M.update_genes()
	M.update_icon()
	if(take)
		take_botany_item(S)
	return S

/// Pulls one gene out of the loaded seed onto the loaded disk - the seed is used up.
/datum/bot_goal/botany_project_errand/extract_gene
	var/obj/item/seeds/donor
	var/gene

/datum/bot_goal/botany_project_errand/extract_gene/New(obj/machinery/plantgenes/M, obj/item/seeds/donor, gene)
	. = ..()
	target = M
	src.donor = donor
	src.gene = gene

/datum/bot_goal/botany_project_errand/extract_gene/get_strategies(datum/bot_brain/bot)
	return errand(list(new /datum/bot_step/move_to(), new /datum/bot_step/paced/extract_gene()))

/datum/bot_step/paced/extract_gene
	var/done = FALSE

/datum/bot_step/paced/extract_gene/start(datum/bot_brain/bot)
	done = FALSE
	return bot.owner.Adjacent(bot.current_goal?.target)

/datum/bot_step/paced/extract_gene/do_click(datum/bot_brain/bot)
	var/datum/bot_goal/botany_project_errand/extract_gene/G = bot.current_goal
	var/obj/machinery/plantgenes/M = G.target
	if(QDELETED(M) || !bot.owner.Adjacent(M))
		return FALSE
	if(done)
		return M.disk ? bot.manipulator_eject_disk(M) : FALSE
	if(M.seed && M.seed != G.donor)
		return !!bot.manipulator_eject_seed(M, take = FALSE) //somebody else's - out it comes
	if(!M.seed)
		if(QDELETED(G.donor))
			return FALSE
		return bot.manipulator_insert(M, G.donor)
	var/obj/item/disk/plantgene/D = M.disk
	if(!D || D.gene || D.read_only)
		if(D)
			return bot.manipulator_eject_disk(M)
		var/obj/item/disk/plantgene/blank = bot.carried_blank_disk()
		if(!blank)
			return FALSE
		return bot.manipulator_insert(M, blank)
	var/datum/plant_gene/source = bot_seed_find_gene(M.seed, G.gene)
	if(!source || !bot.manipulator_press(M, "extract [source.get_name()]"))
		return FALSE
	// Topic() "extract": the disk takes the gene, the seed is destroyed.
	D.gene = source
	D.update_name()
	qdel(M.seed)
	M.seed = null
	M.update_icon()
	M.update_genes()
	bot_log(bot, "extracted [source.get_name()] onto a disk")
	done = TRUE
	return TRUE

/datum/bot_step/paced/extract_gene/finish(datum/bot_brain/bot)
	var/datum/bot_goal/botany_project_errand/extract_gene/G = bot.current_goal
	return bot.carried_disk_with(G.gene) ? GOAL_STEP_SUCCESS : GOAL_STEP_FAIL

/// Splices every disk the recipe needs into the base seed, then takes the result out.
/datum/bot_goal/botany_project_errand/splice_seed
	var/obj/item/seeds/base
	var/datum/botany_recipe/recipe

/datum/bot_goal/botany_project_errand/splice_seed/New(obj/machinery/plantgenes/M, obj/item/seeds/base, datum/botany_recipe/R)
	. = ..()
	target = M
	src.base = base
	recipe = R

/datum/bot_goal/botany_project_errand/splice_seed/get_strategies(datum/bot_brain/bot)
	return errand(list(new /datum/bot_step/move_to(), new /datum/bot_step/paced/splice_seed()))

/datum/bot_step/paced/splice_seed
	max_clicks = 20

/datum/bot_step/paced/splice_seed/start(datum/bot_brain/bot)
	return bot.owner.Adjacent(bot.current_goal?.target)

/datum/bot_step/paced/splice_seed/do_click(datum/bot_brain/bot)
	var/datum/bot_goal/botany_project_errand/splice_seed/G = bot.current_goal
	var/obj/machinery/plantgenes/M = G.target
	if(QDELETED(M) || !bot.owner.Adjacent(M))
		return FALSE
	if(M.seed && M.seed != G.base)
		return !!bot.manipulator_eject_seed(M, take = FALSE)
	if(!M.seed)
		if(QDELETED(G.base) || G.recipe.is_result(G.base))
			return FALSE //spliced and taken back out - done
		return bot.manipulator_insert(M, G.base)
	if(G.recipe.is_result(M.seed))
		if(M.disk)
			return bot.manipulator_eject_disk(M)
		bot_log(bot, "spliced [M.seed] - [G.recipe.name] in the making")
		return !!bot.manipulator_eject_seed(M)
	for(var/list/need in G.recipe.genes)
		if(bot_seed_has_gene(M.seed, need[1]))
			continue
		if(!bot_disk_holds(M.disk, need[1]))
			if(M.disk)
				return bot.manipulator_eject_disk(M)
			var/obj/item/disk/plantgene/D = bot.carried_disk_with(need[1])
			return D ? bot.manipulator_insert(M, D) : FALSE
		if(!M.disk.gene.can_add(M.seed) || !bot.manipulator_press(M, "insert [M.disk.gene.get_name()]"))
			return FALSE
		// Topic() "insert" (confirmed): the seed gets a copy of the disk's gene.
		M.seed.genes += M.disk.gene.Copy()
		if(istype(M.disk.gene, /datum/plant_gene/reagent))
			M.seed.reagents_from_genes()
		M.disk.gene.apply_vars(M.seed)
		M.repaint_seed()
		M.update_genes()
		bot_log(bot, "inserted [M.disk.gene.get_name()] into [M.seed]")
		return TRUE
	return FALSE

/datum/bot_step/paced/splice_seed/finish(datum/bot_brain/bot)
	var/datum/bot_goal/botany_project_errand/splice_seed/G = bot.current_goal
	for(var/obj/item/seeds/S as anything in bot.carried_seeds())
		if(G.recipe.is_result(S))
			return GOAL_STEP_SUCCESS
	return GOAL_STEP_FAIL

// ---------------------------------------------------------------------------------------------
// Hacking the MegaSeed Servitor for contraband seeds
// ---------------------------------------------------------------------------------------------

/// Screwdriver the panel open, then pulse the wires one at a time with a multitool, watching the
/// status lights (datums/wires/vending.dm get_status()) for the green contraband light - undoing
/// anything else a pulse set off, and waiting out the shock if the orange light comes on.
/datum/bot_goal/botany_project_errand/hack_seed_vendor/New(obj/machinery/vending/V)
	. = ..()
	target = V

/datum/bot_goal/botany_project_errand/hack_seed_vendor/get_strategies(datum/bot_brain/bot)
	var/list/steps = list()
	if(!bot.find_carried_tool(/obj/item/screwdriver))
		steps += new /datum/bot_step/fetch_tool(/obj/item/screwdriver)
	if(!bot.find_carried_tool(/obj/item/multitool))
		steps += new /datum/bot_step/fetch_tool(/obj/item/multitool)
	steps += new /datum/bot_step/move_to()
	steps += new /datum/bot_step/paced/hack_vendor()
	return errand(steps)

/datum/bot_goal/botany_project_errand/hack_seed_vendor/on_give_up(datum/bot_brain/bot)
	LAZYSET(bot.botany_supply_blocked, "hack", world.time + 3 MINUTES)
	return ..()

/datum/bot_step/fetch_tool
	var/tool_type
	var/tried = FALSE

/datum/bot_step/fetch_tool/New(tool_type)
	. = ..()
	src.tool_type = tool_type

/datum/bot_step/fetch_tool/execute(datum/bot_brain/bot)
	if(bot.find_carried_tool(tool_type))
		return GOAL_STEP_SUCCESS
	if(tried)
		return GOAL_STEP_FAIL
	tried = TRUE
	if(bot.suspend_goal_for(new /datum/bot_goal/acquire_tool(tool_type)))
		return GOAL_STEP_PENDING
	return GOAL_STEP_FAIL

/datum/bot_step/paced/hack_vendor
	max_clicks = 60
	var/list/untried
	/// Colors whose pulse flipped something that should be flipped back.
	var/list/to_undo
	var/closing = FALSE
	var/waited = FALSE

/datum/bot_step/paced/hack_vendor/start(datum/bot_brain/bot)
	var/obj/machinery/vending/V = bot.current_goal?.target
	if(!istype(V) || !bot.owner.Adjacent(V))
		return FALSE
	untried = shuffle(V.wires.colors.Copy())
	to_undo = list()
	closing = FALSE
	return TRUE

/datum/bot_step/paced/hack_vendor/do_click(datum/bot_brain/bot)
	var/obj/machinery/vending/V = bot.current_goal?.target
	if(QDELETED(V) || !bot.owner.Adjacent(V))
		return FALSE
	if(closing)
		return FALSE
	var/obj/item/screwdriver/S = bot.find_carried_tool(/obj/item/screwdriver)
	if(!V.panel_open)
		if(V.extended_inventory || !S)
			return FALSE
		bot_log(bot, "unscrewing the panel on [V]")
		return bot.use_tool_on(S, V)
	if(V.seconds_electrified > 0)
		// The orange light's on: touching it now means a shock. Wait for it, like anyone would.
		if(!waited)
			bot_log(bot, "the shock light's on - waiting for it to go off")
		waited = TRUE
		bot.idle_fidget()
		wait_for = 1 SECONDS
		return TRUE
	waited = FALSE
	var/obj/item/multitool/MT = bot.find_carried_tool(/obj/item/multitool)
	if(!MT)
		return FALSE
	if(length(to_undo))
		var/undo = to_undo[1]
		to_undo.Cut(1, 2)
		return pulse(bot, V, MT, undo)
	if(V.extended_inventory)
		closing = TRUE
		bot_log(bot, "[V] is hacked - screwing the panel back on")
		if(S)
			bot.use_tool_on(S, V)
		return TRUE
	if(!length(untried))
		return FALSE
	var/color = untried[1]
	untried.Cut(1, 2)
	var/before_throw = V.shoot_inventory
	var/before_scan = V.scan_id
	var/before_voice = V.shut_up
	if(!pulse(bot, V, MT, color))
		return FALSE
	if(V.shoot_inventory != before_throw || V.scan_id != before_scan || V.shut_up != before_voice)
		to_undo += color //the red/yellow/speaker light changed - put it back
	return TRUE

/// One multitool pulse on a wire - the wire panel's ui_act("pulse") (_wires.dm).
/datum/bot_step/paced/hack_vendor/proc/pulse(datum/bot_brain/bot, obj/machinery/vending/V, obj/item/multitool/MT, color)
	if(!bot.ready_in_hand(MT))
		return FALSE
	bot.human_pause(V)
	if(QDELETED(V) || !bot.owner.Adjacent(V))
		return FALSE
	bot.owner.face_atom(V)
	if(!V.wires.interactable(bot.owner)) //shocks whoever touches an electrified machine
		return FALSE
	bot.telemetry_ui_action(V, "pulse [color] wire")
	MT.play_tool_sound(V, 20)
	V.wires.pulse_color(color, bot.owner)
	bot_log_verbose(bot, "pulsed [color] on [V]: [jointext(V.wires.get_status(), " ")]")
	return TRUE

/datum/bot_step/paced/hack_vendor/finish(datum/bot_brain/bot)
	var/obj/machinery/vending/V = bot.current_goal?.target
	for(var/obj/item/held in bot.owner.held_items)
		if(bot.is_tool_or_toolbox(held))
			bot.stow_or_drop(held)
	if(!QDELETED(V) && V.extended_inventory)
		bot_log(bot, "hacked [V] - contraband seeds unlocked")
		return GOAL_STEP_SUCCESS
	return GOAL_STEP_FAIL

// ---------------------------------------------------------------------------------------------
// Showing it off
// ---------------------------------------------------------------------------------------------

/// Tells the station, then leaves a few on the counter - keeping BOT_PROJECT_KEEP back.
/datum/bot_goal/botany_project_errand/show_off_creation/resolve_target(datum/bot_brain/bot)
	target = bot.find_botany_counter() || bot.owner

/datum/bot_goal/botany_project_errand/show_off_creation/get_strategies(datum/bot_brain/bot)
	if(target == bot.owner)
		return errand(list(new /datum/bot_step/paced/show_off()))
	return errand(list(new /datum/bot_step/move_to(), new /datum/bot_step/paced/show_off()))

/datum/bot_step/paced/show_off
	var/announced = FALSE
	/// How many to hold on to: BOT_PROJECT_KEEP, or all but one when that's all there is.
	var/keep = BOT_PROJECT_KEEP

/datum/bot_step/paced/show_off/start(datum/bot_brain/bot)
	if(!bot.botany_project)
		return FALSE
	var/made = length(bot.carried_creations(bot.botany_project.recipe))
	keep = min(BOT_PROJECT_KEEP, made - 1)
	announced = made < 2 //just the one: keep it, nothing to announce
	return TRUE

/datum/bot_step/paced/show_off/do_click(datum/bot_brain/bot)
	var/datum/botany_project/P = bot.botany_project
	if(!P)
		return FALSE
	if(!announced)
		announced = TRUE
		bot_say(bot.owner, ";[P.recipe.announce]")
		return TRUE
	var/obj/structure/table/T = bot.current_goal?.target
	if(!istype(T) || !bot.owner.Adjacent(T))
		return FALSE
	var/on_counter = 0
	for(var/obj/item/reagent_containers/food/snacks/grown/G in T.loc)
		if(G.seed && P.recipe.is_result(G.seed))
			on_counter++
	var/list/mine = bot.carried_creations(P.recipe)
	if(length(mine) <= keep || on_counter >= BOT_PROJECT_COUNTER_MAX)
		return FALSE
	var/obj/item/I = mine[1]
	bot_log(bot, "leaving [I] on [T] for anyone who wants one")
	return bot.use_item_on(I, T)

/datum/bot_step/paced/show_off/finish(datum/bot_brain/bot)
	if(bot.botany_project)
		bot.botany_project.shown_off = TRUE
	for(var/obj/item/held in bot.owner.held_items)
		if(bot.is_botany_tool(held))
			bot.put_away_botany(held)
	return GOAL_STEP_SUCCESS

// ---------------------------------------------------------------------------------------------
// Self-defence
// ---------------------------------------------------------------------------------------------

/// A botanist under attack reaches for what it grew: swings a death nettle up close, throws an
/// acid melon or pepper tomato from a few tiles off, primes and lobs a combustible lemon from
/// further away. Called from handle_combat(); TRUE if it did something this tick.
/datum/bot_brain/proc/try_botany_weapon(mob/living/target)
	if(!is_botanist_job() || world.time < next_botany_weapon_time || QDELETED(target) || owner.incapacitated())
		return FALSE
	var/dist = get_dist(owner, target)
	var/obj/item/best
	var/best_use
	for(var/obj/item/reagent_containers/food/snacks/grown/G in owner.GetAllContents())
		var/datum/botany_recipe/R = bot_botany_recipe_of(G)
		if(!R || R.use == "joke")
			continue
		if(R.use == "melee" && dist <= 1 && G.force > 0)
			best = G
			best_use = "melee"
			break
		if(R.use == "throw" && dist >= 2 && dist <= 6)
			best = G
			best_use = "throw"
		else if(R.use == "grenade" && dist >= 3 && dist <= 6 && !best)
			best = G
			best_use = "grenade"
	if(!best || (best_use != "melee" && !(target in view(7, owner))))
		return FALSE
	if(!ready_in_hand(best))
		return FALSE
	owner.face_atom(target)
	if(best_use == "melee")
		owner.a_intent = INTENT_HARM
		best.melee_attack_chain(owner, target)
		owner.changeNext_move(CLICK_CD_MELEE)
		next_botany_weapon_time = world.time + CLICK_CD_MELEE
		bot_log(src, "hitting [target] with [best]")
		return TRUE
	if(best_use == "grenade")
		best.attack_self(owner) //prime it (throw mode comes on with it)
	human_pause(target)
	if(QDELETED(best) || !(best in owner.held_items))
		return FALSE
	owner.throw_item(target)
	owner.changeNext_move(CLICK_CD_RANGE)
	next_botany_weapon_time = world.time + rand(15, 30)
	bot_log(src, "threw [best] at [target]")
	telemetry_event("botany_weapon", list("item" = "[best]", "use" = best_use, "target" = "[target]", "dist" = dist))
	return TRUE

#undef BOT_PROJECT_KEEP
#undef BOT_PROJECT_COUNTER_MAX
#undef BOT_MUTATION_TRAYS

// ---------------------------------------------------------------------------------------------
// Admin
// ---------------------------------------------------------------------------------------------

/client/proc/admin_bot_botany_project()
	set name = "Start Bot Botany Project"
	set category = "Fun"
	set desc = "Makes a botanist bot a mad scientist and starts a plant project right now, optionally with mutagen and sped-up trays."

	if(!check_rights(R_FUN))
		return
	var/list/bots = list()
	for(var/datum/bot_brain/B as anything in GLOB.bot_brains)
		if(!QDELETED(B.owner) && B.owner.stat != DEAD && B.is_botanist_job() && !B.gym_run)
			bots["[B.owner.real_name] ([get_area_name(B.owner)])"] = B
	if(!length(bots))
		to_chat(usr, "<span class='warning'>No living botanist bots - spawn one with Spawn Bot Crew Member (Botanist) first.</span>")
		return
	var/choice = input(usr, "Which botanist?", "Bot Botany Project") as null|anything in bots
	var/datum/bot_brain/brain = bots[choice]
	if(!brain)
		return
	var/list/recipes = list("Random" = null)
	for(var/datum/botany_recipe/R as anything in GLOB.bot_botany_recipes)
		recipes[R.name] = R
	var/recipe_name = input(usr, "Which project?", "Bot Botany Project") as null|anything in recipes
	if(!recipe_name || QDELETED(brain))
		return
	var/datum/botany_recipe/recipe = recipes[recipe_name] || pick(GLOB.bot_botany_recipes)
	if(alert(usr, "Hand them a large beaker of 60u unstable mutagen? (Otherwise they mutate the slow way, with Left 4 Zed - about a 1 in 8 chance per harvest.)", "Bot Botany Project", "Yes", "No") == "Yes")
		var/obj/item/reagent_containers/glass/beaker/large/B = new(get_turf(brain.owner))
		B.reagents.add_reagent(/datum/reagent/toxin/mutagen, 60)
		if(!brain.owner.equip_to_slot_if_possible(B, ITEM_SLOT_BACKPACK, FALSE, TRUE))
			brain.owner.put_in_hands(B)
	if(alert(usr, "Speed up the Hydroponics trays tenfold (a growth cycle every 2s instead of 20s)? Debug only - affects every tray in the bay.", "Bot Botany Project", "Yes", "No") == "Yes")
		for(var/obj/machinery/hydroponics/H as anything in bot_instances_of(/obj/machinery/hydroponics))
			if(istype(get_area(H), /area/hydroponics) && !istype(get_area(H), /area/hydroponics/garden))
				H.cycledelay = 20
	if(QDELETED(brain))
		return
	brain.botany_temperament = "mad scientist"
	brain.end_botany_project(FALSE)
	brain.botany_project = new(recipe)
	brain.next_botany_check_time = world.time
	message_admins("[key_name_admin(usr)] started a [recipe.name] botany project for [ADMIN_LOOKUPFLW(brain.owner)].")
	log_admin("[key_name(usr)] started a [recipe.name] botany project for [key_name(brain.owner)].")
