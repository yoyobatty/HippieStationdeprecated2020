#!/bin/bash
unset __COMPAT_LAYER # with this set, dm.exe leaks two kernel handles for every file it opens until the next reboot
# Every tgui window on the station opened by a crew member, the AI and a cyborg, headless (tools/tgui_preview/tgui_dump.dm), then
# each one rendered through the built bundle in headless Edge (render.py): a picture per window, and the ones that failed.
# Builds its own copy (tguipreview.mdme -> tguipreview.mdme.dmb), so hippiestation.dmb is left alone.
# Usage: tools/tgui_preview/run_tgui_preview.sh            # dump, then render everything
#        NODUMP=1 tools/tgui_preview/run_tgui_preview.sh   # render the last dump again (after a bundle rebuild)
#        ONLY="smes|apc" ...                               # render only interfaces matching this regex
#        MAP=metastation ...                               # another station (default hippiestation)
# Results: data/tgui_preview/results.txt (DM side), data/tgui_preview/render.txt (page side), pictures in data/previews/tgui/
set -u
cd "$(dirname "$0")/../.."
BYOND_BIN="${BYOND_BIN:-/c/Program Files (x86)/BYOND/bin}"
PORT="${PORT:-45393}"
MAP="${MAP:-hippiestation}"

if [ "${NODUMP:-0}" != "1" ]; then
	cp hippiestation.dme tguipreview.mdme
	printf '#include "tools\\tgui_preview\\tgui_dump.dm"\r\n' >> tguipreview.mdme
	echo "Compiling..."
	"$BYOND_BIN/dm.exe" tguipreview.mdme | grep -E "error|warning|dmb -" || true
	if [ ! -f tguipreview.mdme.dmb ]; then echo "Compile failed"; rm -f tguipreview.mdme; exit 1; fi
	rm -rf data/tgui_preview data/logs/tgui_preview_logs
	began=$(date +%s)
	"$BYOND_BIN/dd.exe" tguipreview.mdme.dmb "$PORT" -trusted -invisible -params "tgui-dump=1&log-directory=tgui_preview_logs&bot-map=$MAP" > /dev/null 2>&1 &
	dd=$!
	while kill -0 $dd 2>/dev/null; do
		sleep 2
		[ -f data/tgui_preview/results.txt ] && break
		if [ $(($(date +%s) - began)) -gt 900 ]; then echo "still going after 900 s - stopped"; break; fi
	done
	sleep 1
	kill $dd 2>/dev/null; sleep 1; kill -9 $dd 2>/dev/null
	rm -f tguipreview.mdme tguipreview.mdme.dmb tguipreview.mdme.rsc tguipreview.mdme.int tguipreview.mdme.lk tguipreview.mdme.dyn.rsc tguipreview.mdme.rsc.lk tguipreview.mdme.dyn.rsc.lk
	echo "dump took $(($(date +%s) - began)) s"
	grep -c "^OK" data/tgui_preview/results.txt | sed 's/^/windows opened: /'
	grep "^ERROR" data/tgui_preview/results.txt | head -40
	runtimes=$(grep -c 'runtime error' data/logs/tgui_preview_logs/runtime.log 2>/dev/null)
	echo "runtimes: ${runtimes:-0}"
fi
python -I tools/tgui_preview/render.py "${ONLY:-}"
