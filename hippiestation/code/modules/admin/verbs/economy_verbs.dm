// Admin verbs for the economy and research: give (or take) a player's money, adjust a department budget (cargo's
// credits are the Cargo Budget), and give research points. Negative amounts take away. All logged.

/client/proc/cmd_admin_give_money()
	set category = "Fun"
	set name = "Give Money"
	set desc = "Add money to (or take it from) a crew member's bank account."
	if(!check_rights(R_ADMIN))
		return
	var/list/choices = list()
	for(var/datum/bank_account/account in SSeconomy.bank_accounts)
		choices["[account.account_holder] ([account.account_job?.title || "no job"], #[account.account_id], $[account.account_balance])"] = account
	if(!length(choices))
		to_chat(usr, "<span class='warning'>There are no crew bank accounts yet.</span>", confidential = TRUE)
		return
	var/choice = input(usr, "Whose account?", "Give Money") as null|anything in sortList(choices)
	var/datum/bank_account/account = choices[choice]
	if(!account)
		return
	var/amount = input(usr, "How much? Negative takes money away.", "Give Money", 1000) as null|num
	if(!amount || QDELETED(account))
		return
	admin_adjust_account(account, amount)

/client/proc/cmd_admin_adjust_budget()
	set category = "Fun"
	set name = "Adjust Department Budget"
	set desc = "Add credits to (or take them from) a department budget. Cargo's credits are the Cargo Budget."
	if(!check_rights(R_ADMIN))
		return
	var/list/choices = list()
	for(var/datum/bank_account/department/account in SSeconomy.generated_accounts)
		choices["[account.account_holder] ($[account.account_balance])"] = account
	var/choice = input(usr, "Which budget?", "Adjust Department Budget") as null|anything in sortList(choices)
	var/datum/bank_account/account = choices[choice]
	if(!account)
		return
	var/amount = input(usr, "How much? Negative takes credits away.", "Adjust Department Budget", 5000) as null|num
	if(!amount)
		return
	admin_adjust_account(account, amount)

/client/proc/admin_adjust_account(datum/bank_account/account, amount)
	var/before = account.account_balance
	account._adjust_money(amount) // straight on the balance: no godmode rules, and it bottoms out at 0
	var/msg = "[key_name_admin(usr)] [amount > 0 ? "gave" : "took"] $[abs(amount)] [amount > 0 ? "to" : "from"] [account.account_holder]'s account ($[before] -> $[account.account_balance])"
	message_admins(msg)
	log_admin("[key_name(usr)] [amount > 0 ? "gave" : "took"] $[abs(amount)] [amount > 0 ? "to" : "from"] [account.account_holder]'s account ($[before] -> $[account.account_balance])")
	if(amount > 0)
		account.bank_card_talk("Transfer received: $[amount]. Account now holds $[account.account_balance].")
	SSblackbox.record_feedback("tally", "admin_verb", 1, "Adjust Bank Account")

/client/proc/cmd_admin_give_research_points()
	set category = "Fun"
	set name = "Give Research Points"
	set desc = "Add research points to (or take them from) the station's research."
	if(!check_rights(R_ADMIN))
		return
	var/datum/techweb/web = SSresearch.science_tech
	if(!web)
		return
	var/list/types = TECHWEB_POINT_TYPE_LIST_ASSOCIATIVE_NAMES
	var/list/choices = list("All types" = null)
	for(var/type in types)
		choices["[types[type]] ([round(web.research_points[type])])"] = type
	var/choice = input(usr, "Which points?", "Give Research Points") as null|anything in choices
	if(!choice)
		return
	var/amount = input(usr, "How many? Negative takes points away.", "Give Research Points", 10000) as null|num
	if(!amount)
		return
	var/list/which = choices[choice] ? list(choices[choice]) : types
	for(var/type in which)
		web.research_points[type] = max(0, web.research_points[type] + amount)
	var/msg = "[amount > 0 ? "gave" : "took"] [abs(amount)] [choices[choice] ? types[choices[choice]] : "of every type of"] research points [amount > 0 ? "to" : "from"] the station"
	message_admins("[key_name_admin(usr)] [msg]")
	log_admin("[key_name(usr)] [msg]")
	SSblackbox.record_feedback("tally", "admin_verb", 1, "Give Research Points")
