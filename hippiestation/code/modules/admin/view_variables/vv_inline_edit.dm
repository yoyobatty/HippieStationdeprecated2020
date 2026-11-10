// View Variables: editing in the page, in place of E / C / M. Click a value and an editor opens in its row with a field that
// fits it: a number or text box, the flags as checkboxes, the eight directions for dir, a type path box; Enter applies, Esc
// closes. Its type list changes what's put in (a number, text, a type path, null, the default, the marked datum, or "Other"
// for BYOND's old prompts: references, new atoms, lists, icons, files). "All <type>" applies it to every thing of exactly
// that type. A reference or list's value opens it, as before; "edit" by the row (shown on hover) edits it instead, next to
// "watch". The user picked this over E/C/M, with mass edits reaching the exact type only, 2026-11-07.

/// Vars holding a list of access numbers: shown with the name each stands for
GLOBAL_LIST_INIT(vv_access_lists, list("req_access", "req_one_access", "access", "accesses"))

/// An access number's name, station or CentCom
/proc/vv_access_name(access)
	return get_access_desc(access) || get_centcom_access_desc(access) || "?"

/// The flag names a number var's bits stand for (name = bit), for the page: tg's table, which goes by the var's name alone
/// (code/_globalvars/bitfields.dm), then the ones it hasn't got. Those are flags only on some types, so they go by type too: a
/// machine's stat is flags, a mob's is its state, and an alien's heat_protection is a fraction.
/proc/vv_bitfield(var_name, datum/D)
	if(GLOB.bitfields[var_name])
		return GLOB.bitfields[var_name]
	if(isitem(D))
		switch(var_name)
			if("slot_flags")
				var/static/list/slots = list("ITEM_SLOT_OCLOTHING" = ITEM_SLOT_OCLOTHING, "ITEM_SLOT_ICLOTHING" = ITEM_SLOT_ICLOTHING, "ITEM_SLOT_GLOVES" = ITEM_SLOT_GLOVES,
					"ITEM_SLOT_EYES" = ITEM_SLOT_EYES, "ITEM_SLOT_EARS" = ITEM_SLOT_EARS, "ITEM_SLOT_MASK" = ITEM_SLOT_MASK, "ITEM_SLOT_HEAD" = ITEM_SLOT_HEAD,
					"ITEM_SLOT_FEET" = ITEM_SLOT_FEET, "ITEM_SLOT_ID" = ITEM_SLOT_ID, "ITEM_SLOT_BELT" = ITEM_SLOT_BELT, "ITEM_SLOT_BACK" = ITEM_SLOT_BACK,
					"ITEM_SLOT_DEX_STORAGE" = ITEM_SLOT_DEX_STORAGE, "ITEM_SLOT_NECK" = ITEM_SLOT_NECK, "ITEM_SLOT_HANDS" = ITEM_SLOT_HANDS,
					"ITEM_SLOT_BACKPACK" = ITEM_SLOT_BACKPACK, "ITEM_SLOT_SUITSTORE" = ITEM_SLOT_SUITSTORE, "ITEM_SLOT_LPOCKET" = ITEM_SLOT_LPOCKET,
					"ITEM_SLOT_RPOCKET" = ITEM_SLOT_RPOCKET, "ITEM_SLOT_HANDCUFFED" = ITEM_SLOT_HANDCUFFED, "ITEM_SLOT_LEGCUFFED" = ITEM_SLOT_LEGCUFFED)
				return slots
			if("body_parts_covered", "heat_protection", "cold_protection")
				var/static/list/parts = list("HEAD" = HEAD, "CHEST" = CHEST, "GROIN" = GROIN, "LEG_LEFT" = LEG_LEFT, "LEG_RIGHT" = LEG_RIGHT,
					"FOOT_LEFT" = FOOT_LEFT, "FOOT_RIGHT" = FOOT_RIGHT, "ARM_LEFT" = ARM_LEFT, "ARM_RIGHT" = ARM_RIGHT, "HAND_LEFT" = HAND_LEFT,
					"HAND_RIGHT" = HAND_RIGHT, "NECK" = NECK)
				return parts
			if("flags_inv", "visor_flags_inv")
				var/static/list/hides = list("HIDEGLOVES" = HIDEGLOVES, "HIDESUITSTORAGE" = HIDESUITSTORAGE, "HIDEJUMPSUIT" = HIDEJUMPSUIT,
					"HIDESHOES" = HIDESHOES, "HIDEMASK" = HIDEMASK, "HIDEEARS" = HIDEEARS, "HIDEEYES" = HIDEEYES, "HIDEFACE" = HIDEFACE,
					"HIDEHAIR" = HIDEHAIR, "HIDEFACIALHAIR" = HIDEFACIALHAIR, "HIDENECK" = HIDENECK)
				return hides
			if("flags_cover", "visor_flags_cover")
				var/static/list/covers = list("GLASSESCOVERSEYES" = GLASSESCOVERSEYES, "MASKCOVERSEYES" = MASKCOVERSEYES, "HEADCOVERSEYES" = HEADCOVERSEYES,
					"MASKCOVERSMOUTH" = MASKCOVERSMOUTH, "HEADCOVERSMOUTH" = HEADCOVERSMOUTH)
				return covers
			if("visor_flags")
				return GLOB.bitfields["clothing_flags"]
	if(ismob(D) && var_name == "status_flags")
		var/static/list/status = list("CANSTUN" = CANSTUN, "CANKNOCKDOWN" = CANKNOCKDOWN, "CANUNCONSCIOUS" = CANUNCONSCIOUS, "CANPUSH" = CANPUSH, "GODMODE" = GODMODE)
		return status
	if(istype(D, /obj/machinery) && var_name == "stat")
		var/static/list/machine_stat = list("BROKEN" = BROKEN, "NOPOWER" = NOPOWER, "MAINT" = MAINT, "EMPED" = EMPED)
		return machine_stat
	if(istype(D, /datum/reagents) && var_name == "flags")
		var/static/list/reagent_flags = list("INJECTABLE" = INJECTABLE, "DRAWABLE" = DRAWABLE, "REFILLABLE" = REFILLABLE, "DRAINABLE" = DRAINABLE,
			"TRANSPARENT" = TRANSPARENT, "AMOUNT_VISIBLE" = AMOUNT_VISIBLE, "NO_REACT" = NO_REACT)
		return reagent_flags
	return null

/// What kind of value a var holds, for the page's editor
/proc/vv_value_kind(var_name, value, datum/D)
	if(isnull(value))
		return "null"
	if(isnum(value))
		return vv_bitfield(var_name, D) ? "bitfield" : "num"
	if(istext(value))
		return findtext(value, "\n") ? "message" : "text"
	if(ispath(value))
		return "path"
	if(islist(value))
		return "list"
	if(istype(value, /datum) || istype(value, /client))
		return "ref"
	return "other" // icons, files, matrices and BYOND's own types

/// A datum's var as a row: its marks, name, value (clickable to edit when it's plain), and the hover actions
/proc/vv_row_html(name, value, datum/D, sanitize = TRUE)
	var/safe_name = sanitize ? html_encode(name) : name
	var/kind = vv_value_kind(name, value, D)
	var/list/marks = vv_var_marks(D, name)
	var/list/attrs = list("id='vvar_[name]'", "data-var='[name]'", "data-kind='[kind]'")
	var/value_html
	switch(kind)
		if("null")
			value_html = "<span class='value vvv'>null</span>"
		if("num")
			attrs += "data-raw=\"[value]\""
			value_html = "<span class='value vvv'>[value]</span>"
			if(name == "dir" && value)
				value_html += " <font size='1'>[dir2text(value) || "?"]</font>"
		if("bitfield")
			var/list/bits = vv_bitfield(name, D)
			attrs += "data-raw=\"[value]\""
			attrs += "data-bits=\"[html_encode(json_encode(bits))]\""
			var/list/flags = list()
			var/known = 0
			for(var/flag in bits)
				known |= bits[flag]
				if(value & bits[flag])
					flags += flag
			if(value & ~known)
				flags += "[value & ~known]" //bits nothing here has a name for, as a number
			value_html = "<span class='vvv'>[flags.len ? html_encode(jointext(flags, ", ")) : "none"]</span> <font size='1'>[value]</font>"
		if("text", "message")
			attrs += "data-raw=\"[html_encode(value)]\""
			value_html = "<span class='value vvv'>\"[sanitize ? html_encode(value) : value]\"</span>"
			if(findtext(name, "access_txt"))
				var/list/names = list()
				for(var/n in splittext(value, ";"))
					if(text2num(n))
						names += vv_access_name(text2num(n))
				if(names.len)
					value_html += " <font size='1'>[html_encode(jointext(names, ", "))]</font>"
		if("path")
			attrs += "data-raw=\"[value]\""
			value_html = "<span class='value vvv'>[value]</span>"
		if("ref")
			var/datum/DV = value
			var/shown = isatom(DV) ? DV:name : ("[DV]" != "[DV.type]" ? "[DV]" : null) // an atom's name: "[DV]" would say "The box"
			var/label = shown ? "[shown] [REF(DV)]" : REF(DV)
			value_html = "<a href='?_src_=vars;[HrefToken()];Vars=[REF(DV)]'>[html_encode(label)]</a> <font size='1'>[DV.type]</font>"
		if("list")
			var/list/L = value
			value_html = "<a href='?_src_=vars;[HrefToken()];Vars=[REF(L)]'>/list ([L.len])</a>"
			if(L.len > 0 && (name in GLOB.vv_access_lists))
				var/list/items = list() //an access list's numbers, with the name each stands for
				for(var/i in 1 to L.len)
					items += "<li>[i] = <span class='value'>[html_encode("[L[i]]")]</span> <font size='1'>[isnum(L[i]) ? html_encode(vv_access_name(L[i])) : ""]</font></li>"
				value_html += "<ul>[items.Join()]</ul>"
			else if(L.len > 0 && !(name == "underlays" || name == "overlays" || L.len > (IS_NORMAL_LIST(L) ? VV_NORMAL_LIST_NO_EXPAND_THRESHOLD : VV_SPECIAL_LIST_NO_EXPAND_THRESHOLD)))
				var/list/items = list()
				for(var/i in 1 to L.len)
					var/key = L[i]
					var/val
					if(IS_NORMAL_LIST(L) && !isnum(key))
						val = L[key]
					if(isnull(val))
						val = key
						key = i
					items += debug_variable(key, val, 1, sanitize = sanitize)
				value_html += "<ul>[items.Join()]</ul>"
		else
			// icons, files and matrices: the old row's way of showing them, edited through the old prompts
			var/old = debug_variable(name, value, 1, null, sanitize)
			var/eq = findtext(old, " = ")
			value_html = eq ? "<span class='vvv'>[copytext(old, eq + 3, length(old) - 4)]</span>" : old
	var/watch = "<a href='?_src_=vars;[HrefToken()];vvwatch=1;[VV_HK_TARGET]=[REF(D)];[VV_HK_VARNAME]=[name]'>watch</a>"
	return "<li [attrs.Join(" ")][marks[1]]>[marks[2]]<span class='vvn'>[safe_name]</span> = [value_html] <span class='vva'><a href='#' class='vve_open'>edit</a> &middot; [watch]</span></li>"

/// The page's editor: styles, and the script that opens it in a row and sends what's picked
/proc/vv_editor_head(datum/D, client/C)
	var/marked = C?.holder?.marked_datum
	return {"
		<style>
			li .vva { visibility: hidden; font-size: 7pt; margin-left: 6px; }
			li:hover .vva { visibility: visible; }
			.vvv { cursor: pointer; }
			.vvv:hover { background-color: #ffffcc; }
			.vve { margin: 3px 0 5px 12px; padding: 4px 6px; border: 1px solid #cccccc; background-color: #f6f6f6; font-size: 8pt; }
			.vve input\[type=text\], .vve textarea { width: 70%; font-family: "Courier New", monospace; font-size: 8pt; }
			.vve .vvc td { padding: 0; }
			.vve .vvc button { width: 30px; font-size: 7pt; }
			.vve .vvc button.on { font-weight: bold; background-color: #ffe08a; }
			.vve label { margin-right: 8px; white-space: nowrap; }
		</style>
		<script type='text/javascript'>
			var vv_target = '[REF(D)]';
			var vv_token = '[HrefToken()]';
			var vv_type = '[D.type]';
			var vv_marked = [json_encode(marked ? "[marked]" : "")];
			var vv_dirs = \[\['NW', 9\], \['N', 1\], \['NE', 5\], \['W', 8\], \['', 0\], \['E', 4\], \['SW', 10\], \['S', 2\], \['SE', 6\]\];

			function vv_send(name, cls, value, mass) {
				location.href = vv_link('?_src_=vars;' + vv_token + ';vvset=1;target=' + vv_target + ';targetvar=' + encodeURIComponent(name)
					+ ';vvclass=' + cls + ';vvvalue=' + encodeURIComponent(value) + (mass ? ';vvmass=1' : ''), false);
			}
			function vv_close_editors() {
				var open = document.querySelectorAll('.vve');
				for (var i = 0; i < open.length; i++) open\[i\].parentNode.removeChild(open\[i\]);
			}
			function vv_open(li) {
				if (li.querySelector('.vve')) return;
				vv_close_editors();
				var name = li.getAttribute('data-var');
				var kind = li.getAttribute('data-kind');
				var raw = li.getAttribute('data-raw');
				var ed = document.createElement('div');
				ed.className = 'vve';
				var field = null;
				var get = null;
				var cls = { num: 'num', bitfield: 'num', text: 'text', message: 'text', path: 'path' }\[kind\] || 'text';
				if (kind == 'bitfield') {
					var bits = JSON.parse(li.getAttribute('data-bits'));
					var value = parseInt(raw, 10) || 0;
					field = document.createElement('div');
					for (var flag in bits) {
						var label = document.createElement('label');
						var box = document.createElement('input');
						box.type = 'checkbox';
						box.value = bits\[flag\];
						box.checked = (value & bits\[flag\]) != 0;
						label.appendChild(box);
						label.appendChild(document.createTextNode(flag));
						field.appendChild(label);
					}
					get = function () { var n = 0; var boxes = field.querySelectorAll('input'); for (var j = 0; j < boxes.length; j++) if (boxes\[j\].checked) n |= parseInt(boxes\[j\].value, 10); return String(n); };
				} else if (name == 'dir' && kind == 'num') {
					var current = parseInt(raw, 10);
					var picked = current;
					field = document.createElement('table');
					field.className = 'vvc';
					for (var r = 0; r < 3; r++) {
						var tr = field.insertRow(-1);
						for (var c = 0; c < 3; c++) {
							var d = vv_dirs\[r * 3 + c\];
							var td = tr.insertCell(-1);
							if (!d\[1\]) continue;
							var b = document.createElement('button');
							b.textContent = d\[0\];
							b.setAttribute('data-dir', d\[1\]);
							if (d\[1\] == current) b.className = 'on';
							b.onclick = function () { vv_send(name, 'num', this.getAttribute('data-dir'), mass.checked); return false; };
							td.appendChild(b);
						}
					}
					get = function () { return String(picked); };
				} else {
					field = document.createElement(kind == 'message' ? 'textarea' : 'input');
					if (kind != 'message') field.type = 'text';
					field.value = (raw === null) ? '' : raw;
					get = function () { return field.value; };
				}
				ed.appendChild(field);
				var row = document.createElement('div');
				var type = document.createElement('select');
				var kinds = \[\['num', 'Number'\], \['text', 'Text'\], \['path', 'Type path'\], \['null', 'null'\], \['default', 'Default'\]\];
				if (vv_marked) kinds.push(\['marked', 'Marked: ' + vv_marked\]);
				kinds.push(\['other', 'Other...'\]);
				for (var k = 0; k < kinds.length; k++) {
					var o = document.createElement('option');
					o.value = kinds\[k\]\[0\];
					o.textContent = kinds\[k\]\[1\];
					if (kinds\[k\]\[0\] == cls) o.selected = true;
					type.appendChild(o);
				}
				row.appendChild(document.createTextNode('as '));
				row.appendChild(type);
				var massLabel = document.createElement('label');
				var mass = document.createElement('input');
				mass.type = 'checkbox';
				massLabel.appendChild(mass);
				massLabel.appendChild(document.createTextNode(' all ' + vv_type));
				row.appendChild(document.createTextNode(' '));
				row.appendChild(massLabel);
				var apply = document.createElement('button');
				apply.textContent = 'Set';
				var cancel = document.createElement('button');
				cancel.textContent = 'Cancel';
				row.appendChild(apply);
				row.appendChild(cancel);
				ed.appendChild(row);
				function go() {
					var t = type.value;
					if (t == 'other') { location.href = vv_link('?_src_=vars;' + vv_token + ';datumchange=1;target=' + vv_target + ';targetvar=' + encodeURIComponent(name), false); return; }
					vv_send(name, t, (t == 'null' || t == 'default' || t == 'marked') ? '' : get(), mass.checked);
				}
				apply.onclick = function () { go(); return false; };
				cancel.onclick = function () { vv_close_editors(); return false; };
				ed.onkeydown = function (e) {
					if (e.keyCode == 27) { vv_close_editors(); return false; }
					if (e.keyCode == 13 && !(kind == 'message' && e.shiftKey)) { go(); return false; }
					return true;
				};
				li.appendChild(ed);
				if (ed.scrollIntoView) ed.scrollIntoView({ block: 'nearest' });
				if (field.focus) { field.focus(); if (field.select) field.select(); }
			}
			document.addEventListener('click', function (e) {
				var el = e.target;
				while (el && el.nodeType == 1 && !(el.className && (String(el.className).indexOf('vvv') != -1 || String(el.className).indexOf('vve_open') != -1))) el = el.parentNode;
				if (!el || el.nodeType != 1) return;
				var li = el;
				while (li && li.tagName != 'LI') li = li.parentNode;
				if (!li || !li.getAttribute('data-var')) return;
				e.preventDefault();
				vv_open(li);
			}, false);
		</script>
	"}

/// Sets a var from the page's editor: what was typed, as the chosen type, on this thing or every thing of exactly its type
/client/proc/vv_inline_set(datum/D, var_name, class, text, mass)
	if(!istype(D) || !(var_name in D.vars) || !D.can_vv_get(var_name) || !vv_varname_lockcheck(var_name))
		return FALSE
	var/value
	switch(class)
		if("num")
			value = text2num(text)
			if(isnull(value))
				to_chat(src, "<span class='warning'>\"[html_encode(text)]\" isn't a number.</span>", confidential = TRUE)
				return FALSE
		if("text")
			value = text
		if("path")
			value = text2path(trim(text))
			if(!value)
				to_chat(src, "<span class='warning'>No type [html_encode(text)].</span>", confidential = TRUE)
				return FALSE
		if("null")
			value = null
		if("default")
			value = initial(D.vars[var_name])
		if("marked")
			value = holder?.marked_datum
			if(!value)
				to_chat(src, "<span class='warning'>Nothing's marked.</span>", confidential = TRUE)
				return FALSE
		else
			return FALSE
	var/old = D.vars[var_name]
	if(mass)
		return vv_inline_mass(D, var_name, value, class == "text")
	var/set_value = class == "text" ? vv_text_substitute(D, value) : value
	if(D.vv_edit_var(var_name, set_value) == FALSE)
		to_chat(src, "<span class='warning'>Your edit was rejected by the object.</span>", confidential = TRUE)
		return FALSE
	vv_note_edit(D, var_name, old, src)
	vv_log_change(D, var_name, old, set_value, "modified")
	return TRUE

/// "[varname]" in text is that var of the thing, as the old editor did
/client/proc/vv_text_substitute(datum/D, text)
	for(var/V in vv_parse_text(D, text))
		text = replacetext(text, "\[[V]]", "[D.vars[V]]")
	return text

/// Every thing of exactly D's type gets the value
/client/proc/vv_inline_mass(datum/D, var_name, value, is_text)
	var/list/items = get_all_of_type(D.type, FALSE)
	var/accepted = 0
	var/rejected = 0
	for(var/datum/thing as anything in items)
		if(QDELETED(thing) || !(var_name in thing.vars))
			continue
		var/old = thing.vars[var_name]
		if(thing.vv_edit_var(var_name, is_text ? vv_text_substitute(thing, value) : value) != FALSE)
			accepted++
			if(thing == D)
				vv_note_edit(D, var_name, old, src)
		else
			rejected++
		CHECK_TICK
	log_world("### MassVarEdit by [key_name(src)]: [D.type] (exact type) [var_name]=[value] ([accepted] changed, [rejected] rejected)")
	log_admin("[key_name(src)] mass modified every [D.type]'s [var_name] to [html_encode("[value]")] ([accepted] objects modified)")
	message_admins("[key_name_admin(src)] mass modified every [D.type]'s [var_name] to [value] ([accepted] objects modified)")
	to_chat(src, "<span class='notice'>[accepted] [D.type] changed[rejected ? ", [rejected] rejected the edit" : ""].</span>", confidential = TRUE)
	return accepted > 0
