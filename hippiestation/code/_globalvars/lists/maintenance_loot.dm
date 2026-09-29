// Maintenance loot, in tiers - after tgstation's (code/_globalvars/lists/maintenance_loot.dm at 89e3432): a spawner picks a
// tier by weight, then a category in it, then an item. Most of what turns up is trash or common gear, useful things now and
// then, something really good rarely, and once in a long while something strange. Only items this codebase has, plus
// hippie's own and the worn gear (hippiestation/code/game/objects/items/worn_gear.dm).
//
// How to balance: keep each category's items about as strong as each other, then tune the tier weights until the average
// find feels right. Loot should be worth more the harder it is to get to, or an assistant just sweeps maint for free gear.
//
// Weights nest: a list inside a list is picked as a whole, then picked from (pick_weight_recursive()).

/// Out of 10,000: trash and common make up 90% of finds, useful items 9%, really good ones 1%, strange ones 0.01%
#define MAINT_TRASH_WEIGHT 4500
#define MAINT_COMMON_WEIGHT 4500
#define MAINT_UNCOMMON_WEIGHT 900
#define MAINT_RARITY_WEIGHT 99
#define MAINT_ODDITY_WEIGHT 1
/// A holiday's loot (add_holiday_maint_loot()) makes up about a quarter of finds while it lasts, as on tg
#define MAINT_HOLIDAY_WEIGHT 3500

GLOBAL_LIST_INIT(maintenance_loot, build_maintenance_loot())

/proc/build_maintenance_loot()
	var/list/trash = list( // junk: useless, or only good for crafting and ghetto chemistry
		list(
			/obj/item/trash/can = 1,
			/obj/item/trash/candy = 1,
			/obj/item/trash/cheesie = 1,
			/obj/item/trash/chips = 1,
			/obj/item/trash/pistachios = 1,
			/obj/item/trash/popcorn = 1,
			/obj/item/trash/raisins = 1,
			/obj/item/trash/sosjerky = 1,
			/obj/item/trash/candle = 1,
			/obj/item/cigbutt = 2,
			/obj/item/c_tube = 1,
			/obj/item/disk/data = 1,
			/obj/item/folder/yellow = 1,
			/obj/item/paper = 1,
			/obj/item/paper/crumpled = 2,
			/obj/item/pen = 1,
			/obj/item/poster/random_contraband = 1,
			/obj/item/poster/random_official = 1,
			/obj/item/stack/sheet/cardboard = 2,
			/obj/item/shard = 1,
			/obj/item/light/bulb = 1,
			/obj/item/light/tube = 1,
			/obj/item/reagent_containers/glass/rag = 2,
			/obj/item/storage/box = 2,
			/obj/item/storage/box/cups = 1,
			/obj/item/clothing/head/cone = 3,
			/obj/item/brick = 4,
			/obj/item/stack/rods/ten = 4,
			) = 8,
		list( // tier 1 stock parts
			/obj/item/stock_parts/capacitor = 1,
			/obj/item/stock_parts/matter_bin = 1,
			/obj/item/stock_parts/micro_laser = 1,
			/obj/item/stock_parts/scanning_module = 1,
			/obj/item/stock_parts/manipulator = 1,
			) = 1,
		)

	var/list/common = list( // common: basic items
		list( // tools
			/obj/item/screwdriver = 3,
			/obj/item/wrench = 3,
			/obj/item/crowbar = 2,
			/obj/item/crowbar/red = 1,
			/obj/item/wirecutters = 2,
			/obj/item/weldingtool = 3,
			/obj/item/t_scanner = 3,
			/obj/item/analyzer = 2,
			/obj/item/multitool = 2,
			/obj/item/flashlight = 3,
			/obj/item/flashlight/pen = 1,
			/obj/item/geiger_counter = 2,
			/obj/item/airlock_painter = 1,
			/obj/item/hand_labeler = 1,
			) = 8,
		list( // worn gear: it works, mostly
			/obj/item/wrench/rusty = 2,
			/obj/item/crowbar/rusty = 2,
			/obj/item/screwdriver/bent = 2,
			/obj/item/wirecutters/dull = 2,
			/obj/item/multitool/cracked = 1,
			/obj/item/weldingtool/rusty = 2,
			/obj/item/stock_parts/cell/worn = 2,
			/obj/item/tank/internals/emergency_oxygen/scuffed = 2,
			/obj/item/flashlight/flickering = 2,
			/obj/item/reagent_containers/pill/expired = 2,
			/obj/item/storage/toolbox/mechanical/dented = 1,
			/obj/item/clothing/gloves/color/fyellow/old = 2,
			) = 6,
		list( // equipment
			/obj/item/clothing/mask/gas = 6,
			/obj/item/clothing/mask/breath = 2,
			/obj/item/clothing/glasses/meson = 2,
			/obj/item/clothing/head/hardhat = 1,
			/obj/item/clothing/head/hardhat/red = 1,
			/obj/item/clothing/head/welding = 1,
			/obj/item/clothing/suit/hazardvest = 1,
			/obj/item/clothing/gloves/color/fyellow = 1,
			/obj/effect/spawner/lootdrop/gloves = 3,
			/obj/item/clothing/head/that = 1,
			/obj/item/clothing/head/ushanka = 1,
			/obj/item/clothing/shoes/laceup = 1,
			/obj/item/clothing/under/rank/vice = 1,
			/obj/item/clothing/under/hippie/cosby = 1,
			/obj/item/radio/off = 2,
			/obj/item/radio/headset = 1,
			/obj/item/tank/internals/emergency_oxygen = 2,
			/obj/item/extinguisher = 4,
			) = 8,
		list( // construction and crafting
			/obj/item/stack/cable_coil = 2,
			/obj/item/stack/cable_coil/five = 3,
			/obj/item/stack/rods/twentyfive = 1,
			/obj/item/stack/sheet/metal/twenty = 1,
			/obj/item/stack/sheet/rglass = 1,
			/obj/item/stack/ducttape = 3,
			/obj/item/storage/box/lights/mixed = 2,
			/obj/item/assembly/prox_sensor = 2,
			/obj/item/assembly/timer = 2,
			/obj/item/assembly/igniter = 2,
			/obj/item/assembly/signaler = 2,
			/obj/item/assembly/infra = 1,
			/obj/item/assembly/mousetrap = 2,
			/obj/item/assembly/health = 1,
			/obj/item/rack_parts = 1,
			/obj/item/stack/wrapping_paper = 1,
			/obj/item/book/manual/wiki/engineering_construction = 1,
			/obj/item/book/manual/wiki/engineering_hacking = 1,
			) = 8,
		list( // medical
			/obj/item/stack/medical/bruise_pack = 2,
			/obj/item/reagent_containers/syringe = 2,
			/obj/item/reagent_containers/pill/floorpill = 1,
			/obj/item/bodybag = 1,
			/obj/item/reagent_containers/spray/pestspray = 1,
			) = 4,
		list( // food and smokes
			/obj/item/storage/box/donkpockets = 1,
			/obj/item/reagent_containers/food/snacks/grown/citrus/orange = 1,
			/obj/item/storage/fancy/cigarettes/dromedaryco = 1,
			/obj/item/storage/box/matches = 1,
			) = 4,
		list( // misc
			/obj/item/coin/silver = 1,
			/obj/item/stack/spacecash/c10 = 2,
			/obj/item/toy/eightball = 1,
			/obj/item/storage/secure/briefcase = 2,
			/obj/item/storage/wallet/random = 1,
			/obj/item/camera = 1,
			/obj/item/flashlight/flare = 2,
			/obj/effect/spawner/lootdrop/glowstick = 2,
			/obj/item/vending_refill/cola = 1,
			/obj/item/grenade/smokebomb = 1,
			) = 6,
		)

	var/list/uncommon = list( // uncommon: useful items
		list( // tools
			/obj/item/hatchet = 1,
			/obj/item/weldingtool/largetank = 1,
			/obj/item/restraints/handcuffs/cable = 1,
			/obj/item/restraints/legcuffs/bola = 1,
			/obj/item/pen/fountain = 1,
			/obj/item/storage/belt/utility = 2,
			/obj/item/storage/toolbox/mechanical = 1,
			/obj/item/storage/toolbox/artistic = 1,
			) = 8,
		list( // equipment
			/obj/item/clothing/ears/earmuffs = 1,
			/obj/item/clothing/glasses/hud/diagnostic = 1,
			/obj/item/clothing/glasses/hud/health = 1,
			/obj/item/clothing/glasses/welding = 1,
			/obj/item/clothing/glasses/sunglasses = 1,
			/obj/item/clothing/gloves/color/black = 1,
			/obj/item/clothing/head/helmet/old = 1,
			/obj/item/clothing/suit/armor/vest/old = 1,
			/obj/item/clothing/mask/muzzle = 1,
			/obj/item/storage/belt/medical = 1,
			) = 8,
		list( // strange objects
			/obj/item/relic = 1,
			) = 6,
		list( // construction and crafting
			/obj/item/beacon = 1,
			/obj/item/stack/sheet/mineral/wood/fifty = 1,
			/obj/item/stack/sheet/mineral/plasma = 1,
			/obj/item/stock_parts/cell = 2,
			/obj/item/stock_parts/cell/high = 1,
			/obj/item/weaponcrafting/receiver = 2,
			/obj/item/storage/box/clown = 1,
			) = 8,
		list( // medical and chemicals
			/obj/item/storage/box/hug/medical = 1,
			/obj/item/reagent_containers/hypospray/medipen = 1,
			/obj/item/reagent_containers/spray = 1,
			/obj/item/watertank = 1,
			/obj/item/watertank/janitor = 1,
			) = 6,
		list( // music
			/obj/item/instrument/accordion = 5,
			/obj/item/instrument/eguitar = 5,
			/obj/item/instrument/glockenspiel = 5,
			/obj/item/instrument/guitar = 5,
			/obj/item/instrument/harmonica = 5,
			/obj/item/instrument/recorder = 5,
			/obj/item/instrument/saxophone = 5,
			/obj/item/instrument/trombone = 5,
			/obj/item/instrument/trumpet = 5,
			/obj/item/instrument/violin = 5,
			/obj/item/instrument/bikehorn = 2,
			/obj/item/instrument/violin/golden = 2,
			) = 2,
		list( // fakeouts - looks like the good stuff
			/obj/item/clothing/shoes/jackboots = 1,
			/obj/item/dice/d20 = 1,
			/obj/item/coin/twoheaded = 1,
			) = 1,
		)

	var/list/rarity = list( // rare: really good items
		list( // tools
			/obj/item/assembly/flash/memorizer = 1,
			/obj/item/flashlight/flashdark = 1,
			/obj/item/restraints/handcuffs = 1,
			/obj/item/throwing_star = 1,
			/obj/item/weldingtool/hugetank = 1,
			) = 1,
		list( // equipment
			/obj/item/clothing/glasses/hud/security = 1,
			/obj/item/clothing/gloves/color/yellow = 1,
			/obj/item/storage/belt/military/assault = 1,
			/obj/item/storage/belt/security = 1,
			) = 1,
		list( // paint
			/obj/item/paint/anycolor = 1,
			/obj/item/paint/black = 1,
			/obj/item/paint/blue = 1,
			/obj/item/paint/green = 1,
			/obj/item/paint/paint_remover = 1,
			/obj/item/paint/red = 1,
			/obj/item/paint/violet = 1,
			/obj/item/paint/white = 1,
			/obj/item/paint/yellow = 1,
			) = 1,
		list( // misc
			/obj/item/disk/nuclear/fake = 1,
			/obj/item/toy/crayon/spraycan = 1,
			/obj/item/storage/belt/fannypack = 1,
			) = 1,
		)

	var/list/oddity = list( // oddity: strange or crazy items, about one a round at most
		/obj/effect/rune/teleport = 1,
		/obj/item/clothing/head/helmet/abductor = 1,
		/obj/item/clothing/shoes/jackboots/fast = 1,
		/obj/item/clothing/suit/armor/reactive/table = 1,
		/obj/item/shadowcloak = 1,
		list(
			/obj/item/instrument/saxophone/spectral = 1,
			/obj/item/instrument/trombone/spectral = 1,
			/obj/item/instrument/trumpet/spectral = 1,
			) = 1,
		)

	. = list()
	.[trash] = MAINT_TRASH_WEIGHT
	.[common] = MAINT_COMMON_WEIGHT
	.[uncommon] = MAINT_UNCOMMON_WEIGHT
	.[rarity] = MAINT_RARITY_WEIGHT
	.[oddity] = MAINT_ODDITY_WEIGHT

/// Adds a holiday's items to maintenance loot as their own tier, so they actually turn up (see MAINT_HOLIDAY_WEIGHT)
/proc/add_holiday_maint_loot(list/items)
	GLOB.maintenance_loot[items] = MAINT_HOLIDAY_WEIGHT

/// pickweight() through nested lists: when the pick is itself a list, pick from that, and so on down to an item
/proc/pick_weight_recursive(list/L)
	var/picked = pickweight(L)
	while(islist(picked))
		picked = pickweight(picked)
	return picked

#undef MAINT_TRASH_WEIGHT
#undef MAINT_COMMON_WEIGHT
#undef MAINT_UNCOMMON_WEIGHT
#undef MAINT_RARITY_WEIGHT
#undef MAINT_ODDITY_WEIGHT
