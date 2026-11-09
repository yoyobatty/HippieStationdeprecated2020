// Included last by a side build (see preview.py): writes every atom type's starting icon data, then quits without booting the game.
/world/New()
	var/out = "data/icon_merge/types.txt"
	fdel(out)
	var/list/lines = list()
	for(var/path in typesof(/atom))
		var/atom/A = path
		var/line = "[path]\t[initial(A.icon)]\t[initial(A.icon_state)]\t" // 4th column was the retired icon_hippie
		if(ispath(path, /obj/item))
			var/obj/item/I = path
			line += "\t[initial(I.item_state)]\t[initial(I.alternate_worn_icon)]\t[initial(I.lefthand_file)]\t[initial(I.righthand_file)]"
		lines += line
	text2file(lines.Join("\n"), out)
	shutdown()
