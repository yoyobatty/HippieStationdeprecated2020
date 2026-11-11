/// hippie -- tgui's bundle is asked for by an address that carries its own hash. The game window's browser (WebView2, BYOND 516) kept
/// an old tgui.bundle.js in its cache from one connection to the next, at the same address, so after the bundle changed a window could
/// come up with the old page, or blank if its route was new (seen three times in a row of picture runs while moving consoles to tgui,
/// 2026-11-04). Players after an update would have had the same. The asset cache still sends the file under its plain name; the hash
/// is only for the browser's cache.
/datum/controller/subsystem/tgui/PreInit()
	. = ..()
	var/js_hash = md5('tgui-next/packages/tgui/public/tgui.bundle.js')
	var/css_hash = md5('tgui-next/packages/tgui/public/tgui.bundle.css')
	basehtml = replacetextEx(basehtml, "src=\"tgui.bundle.js\"", "src=\"tgui.bundle.js?v=[js_hash]\"")
	basehtml = replacetextEx(basehtml, "href=\"tgui.bundle.css\"", "href=\"tgui.bundle.css?v=[css_hash]\"")

/// hippie -- the MC's strikes against tgui only count blames in a row (Paradise tgui-reliability dfbea371e7). failure_strikes never
/// went down, so two stalls hours apart got it replaced and a third took it offline for 5 minutes, and with it every open window's
/// refresh. A pass through every window means the earlier stalls weren't its doing. Only tgui: the other subsystems keep the
/// 2026-11-07 ruling (third strike off 5 minutes, one more chance, then off until an admin).
/datum/controller/subsystem/tgui/fire(resumed = 0)
	..()
	if(!length(currentrun) && failure_strikes?[type])
		failure_strikes[type] = 0
