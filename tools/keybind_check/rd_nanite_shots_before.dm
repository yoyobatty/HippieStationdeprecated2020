// The "before" build for rd_nanite_shots.dm: HEAD's rdconsole_tgui.dm and HEAD's window bundle (see rd_nanite_shots.dm).

#include "data\previews\rd_old\rdconsole_tgui.dm"
#include "tools\keybind_check\rd_nanite_shots.dm"

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
