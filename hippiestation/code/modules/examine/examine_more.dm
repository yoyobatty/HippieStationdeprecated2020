// Examine-more, as on tg: examining the same thing again within EXAMINE_MORE_WINDOW takes a closer look - examine_more()
// instead of examine(). Anything with more to show hints at it on the normal examine, so players find out it exists.
// Things add to it by overriding examine_more(), or with examine_lore for background reading.
/client
	/// REF of each atom this client examined in the last couple of seconds -> world.time they examined it
	var/list/recent_examines

/obj
	/// Background reading shown when you take a closer look (examine it twice)
	var/examine_lore

/// What a mob sees examining A: a closer look if they examined it a moment ago, the normal examine otherwise
/mob/proc/examine_or_look_closer(atom/A)
	var/ref_to_atom = REF(A)
	var/examined_at = LAZYACCESS(client?.recent_examines, ref_to_atom)
	if(examined_at && world.time - examined_at < EXAMINE_MORE_WINDOW)
		LAZYREMOVE(client.recent_examines, ref_to_atom) // a third examine is a normal one again
		var/list/closer = A.examine_more(src)
		if(!length(closer))
			return list("<span class='notice'><i>You examine [A] closer, but find nothing of interest...</i></span>")
		return list("<span class='notice'><i>You take a closer look at [A]...</i></span>") + closer
	var/list/result = A.examine(src)
	if(length(A.examine_more(src)))
		result += "<span class='notice'><i>Examine it again to take a closer look.</i></span>"
	if(client)
		LAZYSET(client.recent_examines, ref_to_atom, world.time)
		addtimer(CALLBACK(src, PROC_REF(clear_from_recent_examines), ref_to_atom), EXAMINE_MORE_WINDOW * 2)
	return result

/mob/proc/clear_from_recent_examines(ref_to_clear)
	if(client)
		LAZYREMOVE(client.recent_examines, ref_to_clear)

/// What a closer look shows, beyond the normal examine. Keep it free of side effects: the normal examine calls it too,
/// to decide whether to hint that there's more.
/atom/proc/examine_more(mob/user)
	. = list()
	SEND_SIGNAL(src, COMSIG_PARENT_EXAMINE_MORE, user, .)

/obj/examine_more(mob/user)
	. = ..()
	if(examine_lore)
		. += "<i>[examine_lore]</i>"

// Machines: with the maintenance panel open you can see what parts are inside, and their tiers
/obj/machinery/examine_more(mob/user)
	. = ..()
	if(panel_open && length(component_parts))
		. += display_parts(user)

// ID cards: the how-to lines live here rather than on every examine of the card
/obj/item/card/id/examine_more(mob/user)
	. = ..()
	if(!registered_account)
		. += "<span class='info'>There is no registered account linked to this card. Alt-Click to add one.</span>"
		return
	. += "<span class='info'>Alt-Click the ID to pull money from the linked account in the form of holochips.</span>"
	. += "<span class='info'>You can insert credits into the linked account by pressing holochips, cash, or coins against the ID.</span>"
	if(registered_account.account_holder == user.real_name)
		. += "<span class='boldnotice'>If you lose this ID card, you can reclaim your account by Alt-Clicking a blank ID card while holding it and entering your account ID number.</span>"

// Weapon lore, from tgstation 5ae4e2897540e1ed0f49e4751fb41d1895ea700c (/datum/element/examine_lore). tg calls the Mosin
// the Sakhno; the names are swapped back here.
/obj/item/gun/energy/laser
	examine_lore = "The NT Type 5 Heat Delivery System (sometimes referred to as the HDS-5 in promotional material) is what truly put Nanotrasen head and shoulders above most weapon manufacturers in the modern era. All modern energy weaponry offered by the company have the success of the Type 5 to thank for setting the standard for energy-based weapon platforms.<br><br>Adopted as the standard infantry firearm for Nanotrasen military forces, as well as private security lethal armaments, few can deny the weapon's reliability, and at an affordable price!<br><br>However, the weapon platform still possesses many of the vulnerabilities of previous energy-based weaponry. Onboard power supplies cannot be adequately shielded from external electromagnetic pulses that might interfere with the weapon's functionality without also severely jeopardizing thermal distribution into the weapon's heatsink. The Type 4, which never saw wider adoption, remains a haunting example to Nanotrasen's weapons division as to the consequences when a HDS is unable to expel thermal buildup safely.<br><br>Certainly, the Melted Veterans of Galpha 5 advocacy group will never let them forget it."

/obj/item/gun/energy/laser/retro
	examine_lore = "The NT Type 1 Heat Delivery System (sometimes referred to as the HDS-1 in older weapon catalogs) was a weapon that marked the beginning of a new era of firearm development.<br><br>Invented in the think-tank laboratories of Nanotrasen's weapon development team towards the end of the 24th century, the Type 1 found itself adopted broadly by various factions and military entities vying for control over the frontier once it hit the market. One hallmark of those who stood successful in these conflicts was the adoption of the Type 1 as a standard infantry weapon. The logistics required to maintain the operational peak of the HDS-1 allowed most quartermasters to merely dump a half dozen of the weapons into the hands of bloodythirsty marines, knowing full well the weapons were rugged enough to survive most anything thrown at them, only needing a recharging station with a power supply to become operational again once they ran empty.<br><br>So many of these weapons exist today that even modern conflicts may see more usage of the HDS-1 than the updated and equally reliable HDS5 employed by Nanotrasen's modern combat forces. Nanotrasen, despite their best efforts, still have not managed to encourage potential customers to swap for the new model despite a generous exchange discount."

/obj/item/gun/energy/laser/captain
	examine_lore = "For a brief period, Nanotrasen produced a series of custom-made Type 4 laser guns for a select group of clients, primarily composed of wealthy starship captains, politicians, and military leaders looking to demonstrate prestige before the common folk.<br><br>The Type 4 was a commercial failure, but this particular variant earned its own infamy, linked to narratives of crazed despots using it to put down political rivals and dissidents, as well as tales of mad generals marching ahead of their forces, this weapon brandished and running hot in an outstretched arm, pointed towards any moving target they could find on the battlefield.<br><br>Copies of this firearm are now prohibited within TerraGov space, and any captured are quickly decommissioned.This is largely why Nanotrasen <b>insists</b> that any examples held by ranking officers be kept under lock and key. All records of the schematics surrounding this variant of the Type 4 were seized and destroyed, and the creator behind it was detained in a maximum security TerraGov sanitorium. When they found her again, she appeared to have smeared the walls in her own blood, claiming that 'She' was coming, and that she had paid dearly for the knowledge of how to make the weapon.<br><br>Even the microfusion breeder cell housed inside the weapon is practically a lost technology, and Nanotrasen have been unable to reverse engineer the devices exact means of functionality.<br><br>The Syndicate are obviously just as interested in exactly how this weapon is capable of self-perpetuation, hence why the collective seem hell-bent on capturing them whenever possible. Maybe keep this somewhere safe. Or don't."

/obj/item/gun/energy/xray
	examine_lore = "The NT Type 6 Heat Delivery System (sometimes referred to as the HDS6 in research notes) is a breakthrough in the development of man-portable directed energy weaponry.<br><br>Very little is known about the Type 6, as it is a relatively new experimental weapon only accessible to Nanotrasen security forces. Somehow, Nanotrasen has found a means to 'slip' the energy beams produced by the Type 6 through unintended targets, only impacting once it has made contact with a pre-designated target by the weapon's user. It appears to be unable to slip past organic matter reliably, which hampers its potential for eliminating friendly-fire. However, inorganic targets are left unscathed unless the weapon is directed towards firing upon the object. This makes the weapon exceptional for asset recovery, defense of entrenched positions, and assaults on defensive structures. <br><br>Nanotrasen claims that this phenomenon is achieved 'through the power of X-rays'. Most critics have highlighted that this is total nonsense. Some claim that Nanotrasen has discovered a yet-unknown state of matter that the company is exploiting for weapons development and manufacturing. The most conspiratorially minded of Nanotrasen's critics have even gone as far as to claim it is 'proof of ectoplasm as the sixth element,' perhaps even allowing the weapon to operate through supernatural means: perhaps even powered by the 'spirits of the damned'.<br><br>Whatever the truth may be, the weapon seems to function as advertized, and is even more energy efficient than the Type 5. Nanotrasen expects full commercial rollout sometime in the next quarter."

/obj/item/gun/ballistic/automatic/pistol/m1911
	examine_lore = "The Colt M1911, created by John Moses Browning centuries ago, is the primordial ancestor of modern automatic firearms. Somehow, to this day, there are still officers who refuse to utilize anything that isn't chambered in 'God's Caliber'.<br><br>Few want to tell any of these people that .45 ACP has struggled to puncture modern ballistic plating for almost five centuries.<br><br>You are VERY confident that this particular example was lathed this decade. Most M1911's seen in the wild today are recreations of the weapon made with modern alloyed metals and manufactoring techniques, mass produced for the consumer market. This does not stop fraudsters from claiming that their weapon is a 'family heirloom' that has saved them from various conflicts that they insist they participated in."

/obj/item/gun/ballistic/automatic/sniper_rifle
	examine_lore = "Modern arms and armor technology has come a long way since man's first strides into space, from high-throughput directed energy weaponry to advanced energy shielding and everything in between. Such advancements in technology, then, should have put the role of the anti-materiel rifle to rest, as other solutions to the armor problems it solves would have become more accessible - in theory, anyway.<br><br>In practice, the problem with advanced armor is that it's expensive and/or heavy - both of which are constraints that limit the usage of such defensive solutions, especially on smaller targets such as station-ready exosuits or human-scale MODsuits.<br><br>These constraints gave the anti-materiel rifle concept a new lease on life, which Scarborough Arms is happy to provide to prospective buyers."

/obj/item/gun/ballistic/rifle/boltaction
	examine_lore = "The Mosin Nagant's origins are closely tied to the Mosin Concern, one of the Third Soviet Union's state-ran weapons manufacturing concerns before the Union's collapse in the February Revolution, and subsequently one of the Spinward Stellar Coalition's favored industrial concerns.<br><br>Designed to be easily manufactured with the tooling and equipment that the nascent TSU had on-hand, and with enough reliability and stopping power for all sorts of purposes, from hunting to home defense, the Mosin became a mainstay for Soviet citizens since 2440... and, subsequently, a mainstay when those citizens became conspirators and combatants against dictatorship.<br><br>Even to this day, though, Mosins in various conditions and states of modification end up all around the Spinward Sector. Many are manufactured or refurbished with new internals, with reliability to match their history, while others are from stockpiles of surplus or salvage, scavenged and refurbished time and time again... which typically isn't great for reliability."

// Subtypes that are a different gun in all but name
/obj/item/gun/energy/laser/bluetag
	examine_lore = null

/obj/item/gun/energy/laser/redtag
	examine_lore = null

/obj/item/gun/energy/laser/practice
	examine_lore = null

/obj/item/gun/energy/laser/scatter
	examine_lore = null

/obj/item/gun/energy/laser/cyborg
	examine_lore = null

/obj/item/gun/energy/laser/mounted
	examine_lore = null

/obj/item/gun/energy/laser/instakill
	examine_lore = null

/obj/item/gun/energy/laser/makeshiftlasrifle
	examine_lore = null

/obj/item/gun/energy/laser/captain/scattershot
	examine_lore = null

/obj/item/gun/ballistic/rifle/boltaction/enchanted
	examine_lore = null
