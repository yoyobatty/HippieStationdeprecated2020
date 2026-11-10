// hippie -- The Captain's display case opens to the Captain's ID. tg made it CentCom's on purpose (ACCESS_CENT_SPECOPS, "slightly
// harder for caps to grab their gun roundstart"), so a Captain swiping their card at their own case was told "Access denied" and
// had to break the glass. The user, playing Captain, 2026-11-10: it should open.
/obj/structure/displaycase/captain
	req_access = list(ACCESS_CAPTAIN)
