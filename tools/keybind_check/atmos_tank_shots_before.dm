// The "before" build for atmos_tank_shots.dm: tg's own atmos_control.dm and the window bundle from HEAD (see atmos_tank_shots.dm).
// run.sh's EXCLUDE takes Hippie's atmos_control.dm out; this puts tg's back.

#include "code\game\machinery\computer\atmos_control.dm"
#include "tools\keybind_check\atmos_tank_shots.dm"

// What admin_reports_tgui.dm reads of the new file, so the old one compiles beside it
/obj/machinery/computer/atmos_control/tank/var/chamber_id
/obj/machinery/computer/atmos_control/tank/proc/find_sensor()
	return null
/obj/machinery/air_sensor/proc/get_inlet()
	return null
/obj/machinery/air_sensor/proc/get_outlet()
	return null
/proc/atmos_chamber_name(chamber_id)
	return "[chamber_id]"

// The window bundle as it was, under an address of its own so the browser's cache can't hand it to the after run
/datum/controller/subsystem/tgui/PreInit()
	. = ..()
	basehtml = replacetextEx(basehtml, "tgui.bundle.js?v=[md5('tgui-next/packages/tgui/public/tgui.bundle.js')]", "tgui.bundle.js?v=old[md5('data/previews/atmos_old/tgui.bundle.js')]")
	basehtml = replacetextEx(basehtml, "tgui.bundle.css?v=[md5('tgui-next/packages/tgui/public/tgui.bundle.css')]", "tgui.bundle.css?v=old[md5('data/previews/atmos_old/tgui.bundle.css')]")

/datum/asset/simple/tgui
	assets = list(
		"tgui.css"	= 'tgui/assets/tgui.css',
		"tgui.js"	= 'tgui/assets/tgui.js',
		"tgui-main.html" = 'tgui-next/packages/tgui/public/tgui-main.html',
		"tgui-fallback.html" = 'tgui-next/packages/tgui/public/tgui-fallback.html',
		"tgui.bundle.js" = 'data/previews/atmos_old/tgui.bundle.js',
		"tgui.bundle.css" = 'data/previews/atmos_old/tgui.bundle.css',
		"shim-html5shiv.js" = 'tgui-next/packages/tgui/public/shim-html5shiv.js',
		"shim-ie8.js" = 'tgui-next/packages/tgui/public/shim-ie8.js',
		"shim-dom4.js" = 'tgui-next/packages/tgui/public/shim-dom4.js',
		"shim-css-om.js" = 'tgui-next/packages/tgui/public/shim-css-om.js',
	)
