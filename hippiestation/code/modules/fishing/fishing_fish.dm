// Fish: what comes up on the hook, and the fillets that come out of it. Paradise's fish items came with its fish tanks, which
// aren't here, so the pool and sea fish are made here too (their sprites are Paradise's, fish_items.dmi).

// ---- Caught fish

/// Remembers how big a caught fish is, who caught it and where
/datum/component/caught_fish
	/// How long the fish is, in cm
	var/length_cm
	/// Is it big for its kind? Big ones give an extra fillet
	var/big
	/// Name of whoever caught it
	var/angler
	/// Name of the kind of spot it came out of
	var/spot_name

/datum/component/caught_fish/Initialize(length_cm, big, angler, spot_name)
	if(!isitem(parent))
		return COMPONENT_INCOMPATIBLE
	src.length_cm = length_cm
	src.big = big
	src.angler = angler
	src.spot_name = spot_name

/datum/component/caught_fish/RegisterWithParent()
	RegisterSignal(parent, COMSIG_PARENT_EXAMINE, PROC_REF(on_examine))

/datum/component/caught_fish/UnregisterFromParent()
	UnregisterSignal(parent, COMSIG_PARENT_EXAMINE)

/datum/component/caught_fish/proc/on_examine(datum/source, mob/user, list/examine_list)
	SIGNAL_HANDLER // COMSIG_PARENT_EXAMINE
	examine_list += "<span class='notice'>It's [length_cm] cm long. [angler] caught it in [spot_name].</span>"

// ---- Fish

/obj/item/fish
	name = "fish"
	desc = "A generic fish."
	icon = 'hippiestation/icons/obj/fish_items.dmi'
	icon_state = "fish"
	throwforce = 1
	w_class = WEIGHT_CLASS_SMALL
	throw_speed = 3
	force = 1
	attack_verb = list("slapped", "humiliated", "hit", "rubbed")
	hitsound = 'sound/effects/snap.ogg'
	/// What cleaning it with something sharp gives, null for a fish too small to clean
	var/fillet_type = /obj/item/reagent_containers/food/snacks/fish_fillet
	/// How many fillets it gives. A big one gives one more
	var/fillet_amount = 1

/obj/item/fish/examine(mob/user)
	. = ..()
	if(fillet_type)
		. += "<span class='notice'>Something sharp would clean and gut it.</span>"

/obj/item/fish/attackby(obj/item/I, mob/living/user, params)
	if(!fillet_type || !I.is_sharp())
		return ..()
	var/amount = fillet_amount
	var/datum/component/caught_fish/info = GetComponent(/datum/component/caught_fish)
	if(info?.big)
		amount++
	to_chat(user, "<span class='notice'>You carefully clean and gut \the [src.name].</span>")
	for(var/i in 1 to amount)
		new fillet_type(get_turf(src))
	qdel(src)
	return TRUE

/obj/item/fish/goldfish
	name = "goldfish"
	desc = "A goldfish, just like the one you never won at the county fair."
	icon_state = "goldfish"
	fillet_type = null

/obj/item/fish/feederfish
	name = "feeder fish"
	desc = "A tiny feeder fish. Live bait, if you're fishing for something bigger."
	icon_state = "feederfish"
	w_class = WEIGHT_CLASS_TINY
	fillet_type = null

/obj/item/fish/shrimp
	name = "shrimp"
	desc = "A little grey shrimp. Live bait, if you're fishing for something bigger."
	icon_state = "shrimp"
	w_class = WEIGHT_CLASS_TINY
	fillet_type = null

/obj/item/fish/glofish
	name = "glofish"
	desc = "A small bio-luminescent fish. Not very bright, but at least it's pretty!"
	icon_state = "glofish"
	fillet_type = null

/obj/item/fish/glofish/Initialize(mapload)
	. = ..()
	set_light(2, 1, "#99FF66")

/obj/item/fish/electric_eel
	name = "electric eel"
	desc = "An eel capable of producing a mild electric shock. Luckily it's rather weak out of water."
	icon_state = "electric_eel"
	fillet_amount = 2

/obj/item/fish/shark
	name = "shark"
	desc = "Warning: Keep away from tornadoes."
	icon_state = "shark"
	hitsound = 'sound/weapons/bite.ogg'
	force = 3
	fillet_amount = 4

/obj/item/fish/catfish
	name = "catfish"
	desc = "Apparently, catfish don't purr like you might have expected them to. Such a confusing name!"
	icon_state = "catfish"
	fillet_amount = 2

/obj/item/fish/salmon
	name = "salmon"
	desc = "The second-favorite food of Space Bears, right behind crew members."
	icon_state = "salmon"
	fillet_amount = 2

/obj/item/fish/babycarp
	name = "baby space carp"
	desc = "Substantially smaller than the space carp lurking outside the hull, but still unsettling."
	icon_state = "babycarp"
	hitsound = 'sound/weapons/bite.ogg'
	force = 3
	fillet_type = /obj/item/reagent_containers/food/snacks/carpmeat

/obj/item/fish/clownfish
	name = "clown fish"
	desc = "Even underwater, you cannot escape HONKing."
	icon_state = "clownfish"
	fillet_type = null

/obj/item/fish/clownfish/ComponentInitialize()
	. = ..()
	AddComponent(/datum/component/slippery, 40)

// ---- Wild fish, that only come from fishing

/obj/item/fish/wild
	icon = FISHING_ICON
	fillet_type = /obj/item/reagent_containers/food/snacks/fish_fillet/cave

/obj/item/fish/wild/magma_eel
	name = "magma eel"
	desc = "A long eel with skin like cooling lava. It's still warm to the touch."
	icon_state = "magma_eel"
	fillet_type = /obj/item/reagent_containers/food/snacks/fish_fillet/magma
	fillet_amount = 2

/obj/item/fish/wild/magma_eel/Initialize(mapload)
	. = ..()
	set_light(2, 1, "#FF7B2E")

/obj/item/fish/wild/ash_perch
	name = "ash perch"
	desc = "A stubby grey fish that eats whatever falls into the lava."
	icon_state = "ash_perch"
	fillet_type = /obj/item/reagent_containers/food/snacks/fish_fillet/magma

/obj/item/fish/wild/cinder_crab
	name = "cinder crab"
	desc = "A crab with a shell like a hot coal. Not a fish, but it came up on a hook all the same."
	icon_state = "cinder_crab"
	hitsound = 'sound/weapons/bite.ogg'
	fillet_type = /obj/item/reagent_containers/food/snacks/fish_fillet/magma

/obj/item/fish/wild/plasma_lungfish
	name = "plasma lungfish"
	desc = "It breathes liquid plasma. Nobody is sure how, and it isn't telling."
	icon_state = "plasma_lungfish"
	fillet_type = /obj/item/reagent_containers/food/snacks/fish_fillet/rime
	fillet_amount = 2

/obj/item/fish/wild/rime_pike
	name = "rime pike"
	desc = "All teeth and bad temper, out of a river cold enough to freeze the air."
	icon_state = "rime_pike"
	hitsound = 'sound/weapons/bite.ogg'
	force = 3
	fillet_type = /obj/item/reagent_containers/food/snacks/fish_fillet/rime
	fillet_amount = 2

/obj/item/fish/wild/cave_blindfish
	name = "cave blindfish"
	desc = "It has no eyes, and no need for them at the bottom of a chasm."
	icon_state = "cave_blindfish"

/obj/item/fish/wild/glowmaw_angler
	name = "glowmaw angler"
	desc = "It dangles a little light in front of a very large mouth. It was fishing long before you were."
	icon_state = "glowmaw_angler"
	hitsound = 'sound/weapons/bite.ogg'
	force = 3
	fillet_amount = 2

/obj/item/fish/wild/glowmaw_angler/Initialize(mapload)
	. = ..()
	set_light(2, 1, "#7DF9FF")

/obj/item/fish/wild/void_ray
	name = "void ray"
	desc = "It glides through vacuum on wings a metre across. It looks as surprised to be here as you are."
	icon_state = "void_ray"
	fillet_type = /obj/item/reagent_containers/food/snacks/fish_fillet/void
	fillet_amount = 3

/obj/item/fish/wild/comet_minnow
	name = "comet minnow"
	desc = "A tiny silver fish that leaves a faint trail of frost behind it."
	icon_state = "comet_minnow"
	fillet_type = /obj/item/reagent_containers/food/snacks/fish_fillet/void

// ---- Fillets

/obj/item/reagent_containers/food/snacks/fish_fillet
	name = "fish fillet"
	desc = "A fresh fillet of fish."
	icon = FISHING_ICON
	icon_state = "fillet_cave"
	filling_color = "#E8D7C4"
	bitesize = 6
	list_reagents = list(/datum/reagent/consumable/nutriment = 3, /datum/reagent/consumable/nutriment/vitamin = 2)
	tastes = list("fish" = 1)
	foodtype = MEAT

/obj/item/reagent_containers/food/snacks/fish_fillet/magma
	name = "magma fish fillet"
	desc = "A fillet from something that lived in lava. It never quite cools down."
	icon_state = "fillet_magma"
	filling_color = "#E8601C"
	list_reagents = list(/datum/reagent/consumable/nutriment = 3, /datum/reagent/consumable/nutriment/vitamin = 1, /datum/reagent/consumable/capsaicin = 3)
	tastes = list("smoky fish" = 2, "burning" = 1)

/obj/item/reagent_containers/food/snacks/fish_fillet/rime
	name = "rime fish fillet"
	desc = "A pale blue fillet with frost on it. It numbs your fingers."
	icon_state = "fillet_rime"
	filling_color = "#9FD8F2"
	list_reagents = list(/datum/reagent/consumable/nutriment = 3, /datum/reagent/consumable/nutriment/vitamin = 1, /datum/reagent/consumable/frostoil = 3)
	tastes = list("clean white fish" = 2, "ice" = 1)

/obj/item/reagent_containers/food/snacks/fish_fillet/cave
	name = "cave fish fillet"
	desc = "A soft grey fillet from something that never saw daylight."
	icon_state = "fillet_cave"
	filling_color = "#B9B4A8"
	tastes = list("muddy fish" = 1)

/obj/item/reagent_containers/food/snacks/fish_fillet/void
	name = "void fish fillet"
	desc = "A dark fillet that seems to soak up the light around it. Rich, if you can get past the look."
	icon_state = "fillet_void"
	filling_color = "#3A2E5C"
	list_reagents = list(/datum/reagent/consumable/nutriment = 4, /datum/reagent/consumable/nutriment/vitamin = 2)
	tastes = list("rich fish" = 2, "static" = 1)
