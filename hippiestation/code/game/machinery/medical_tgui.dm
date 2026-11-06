// Medical windows redone (tgui-next Cryo.js, CrewConsole.js, OperatingComputer.js): the cryo cell's beaker in its reagents'
// colours, as chemistry's windows draw them (chemistry_tgui.dm). The crew monitor and operating computer need nothing new.

/obj/machinery/atmospherics/components/unary/cryo_cell/ui_data(mob/user)
	. = ..()
	.["beakerContents"] = beaker ? tgui_reagent_list(beaker.reagents) : list()
	.["beakerColor"] = beaker ? tgui_reagent_mix_color(beaker.reagents) : null
	.["beakerVolume"] = beaker ? beaker.reagents.total_volume : 0
	.["beakerMaxVolume"] = beaker ? beaker.volume : 0
