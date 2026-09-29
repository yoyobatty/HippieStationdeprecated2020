/obj/item/card/id/admin
	name = "Admin ID"
	desc = "Magic card that opens everything."
	icon_state = "fingerprint1"
	registered_name = null
	assignment = "General"

/obj/item/card/id/admin/Initialize()
	. = ..()
	access = get_all_accesses()+get_all_centcom_access()+get_all_syndicate_access()+get_ert_access("commander")
	// A bank account of its own, so it can pay at vending machines and cargo like anyone's ID (crew get theirs when their
	// job equips them). In godmode it never runs out (/datum/bank_account/proc/is_godmode_funded()).
	registered_account = new /datum/bank_account/admin(registered_name || "Admin", SSjob.GetJob("Assistant"))
	registered_account.bank_cards += src

/// The Admin ID's account: listed with the crew's (so Give Money finds it), but off the payroll
/datum/bank_account/admin

/datum/bank_account/admin/payday(amt_of_paychecks, free = FALSE)
	return FALSE

/proc/spawntestdummy(var/mob/usr)
	SSblackbox.record_feedback("tally", "admin_secrets_fun_used", 1, "TD")
	message_admins("[key_name_admin(usr)] spawned himself as a Test Dummy.")
	var/turf/T = get_turf(usr)
	var/mob/living/carbon/human/dummy/D = new /mob/living/carbon/human/dummy(T)
	D.set_admin_godmode(TRUE) // dummies are born with GODMODE, but not the immunities that go with it
	D.unascend_animation()
	usr.client.cmd_assume_direct_control(D)
	D.equip_to_slot_or_del(new /obj/item/clothing/under/color/black(D), ITEM_SLOT_ICLOTHING)
	D.equip_to_slot_or_del(new /obj/item/clothing/shoes/sneakers/black(D), ITEM_SLOT_FEET)
	D.equip_to_slot_or_del(new /obj/item/card/id/admin(D), ITEM_SLOT_ID)
	D.equip_to_slot_or_del(new /obj/item/radio/headset/heads/captain(D), ITEM_SLOT_EARS)
	D.equip_to_slot_or_del(new /obj/item/storage/backpack/satchel(D), ITEM_SLOT_BACK)
	D.equip_to_slot_or_del(new /obj/item/storage/box/engineer(D.back), ITEM_SLOT_BACKPACK)
	D.name = "Admin"
	D.real_name = "Admin"
	var/newname = ""
	newname = copytext(sanitize(input(D, "Before you step out as an embodied god, what name do you wish for?", "Choose your name.", "Admin") as null|text),1,MAX_NAME_LEN)
	if (!newname)
		newname = "Admin"
	D.name = newname
	D.real_name = newname
	var/obj/item/card/id/admin/card = D.wear_id
	if(istype(card))
		card.registered_name = newname
		card.update_label()
		card.registered_account?.account_holder = newname
