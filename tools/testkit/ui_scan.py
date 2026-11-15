#!/usr/bin/env python3
"""What every type's ui_act() answers to, read out of the DM: the actions (the strings its switch tests) and the param keys it
reads. The UI fuzzer (fuzz_ui) presses each one with junk. Hippie's redefinitions (hippiestation/code) are read after tg's and
add to them, as ..() would.

  python tools/testkit/ui_scan.py [match]      prints the cases as JSON
"""
import json
import os
import re
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
PROC_RE = re.compile(r"^(/[\w/]+?)/(?:proc/)?ui_act\(")
ACTION_RE = re.compile(r'(?:if\s*\(\s*|action\s*==\s*|\(\s*action\s*==\s*)"([\w\- ]+)"')
SWITCH_CASE_RE = re.compile(r'^\s+if\s*\(\s*"([\w\- ]+)"(?:\s*,\s*"([\w\- ]+)")*\s*\)')
PARAM_RE = re.compile(r'params\s*\[\s*"([\w\-]+)"\s*\]')


def dm_files():
	for top in ("code", "hippiestation/code"):
		for folder, _, files in os.walk(os.path.join(ROOT, top)):
			for f in files:
				if f.endswith(".dm"):
					yield os.path.join(folder, f)


def scan():
	cases = {}
	for path in dm_files():
		try:
			with open(path, encoding="utf-8", errors="replace") as f:
				lines = f.read().splitlines()
		except OSError:
			continue
		i = 0
		while i < len(lines):
			m = PROC_RE.match(lines[i])
			if not m:
				i += 1
				continue
			type_path = m.group(1)
			j = i + 1
			body = []
			while j < len(lines) and (not lines[j] or lines[j][0] in "\t "):
				body.append(lines[j])
				j += 1
			text = "\n".join(body)
			actions = set()
			for line in body:
				sm = SWITCH_CASE_RE.match(line)
				if sm:
					actions.update(re.findall(r'"([\w\- ]+)"', line))
			actions.update(a for a in ACTION_RE.findall(text) if a not in ("ui", "main"))
			keys = set(PARAM_RE.findall(text))
			values = set(re.findall(r'"([\w\- ]{1,24})"', text)) - keys
			if actions:
				case = cases.setdefault(type_path, {"type": type_path, "actions": set(), "keys": set(), "values": set(), "file": os.path.relpath(path, ROOT)})
				case["actions"] |= actions
				case["keys"] |= keys
				case["values"] |= values
			i = j
	out = []
	for c in cases.values():
		out.append({"type": c["type"], "actions": sorted(c["actions"]), "keys": sorted(c["keys"]), "values": sorted(c["values"])[:40], "file": c["file"]})
	return sorted(out, key=lambda c: c["type"])


# Types that end the round, wreck the station or wait on a person forever: not pressed
SKIP = ("/datum", "/mob", "/obj/machinery/nuclearbomb", "/obj/machinery/computer/shuttle", "/obj/machinery/computer/emergency_shuttle",
	"/obj/machinery/computer/communications", "/obj/machinery/doomsday", "/obj/machinery/power/supermatter", "/obj/singularity",
	"/obj/machinery/computer/bsa", "/obj/machinery/syndicatebomb", "/obj/effect", "/client", "/atom", "/obj/machinery/gravity_generator")


def cases_for(match=None, include_skipped=False):
	found = []
	for c in scan():
		if match and match not in c["type"]:
			continue
		if not include_skipped and any(c["type"] == s or c["type"].startswith(s + "/") for s in SKIP):
			continue
		if not c["type"].startswith("/obj"):
			continue
		found.append(c)
	return found


if __name__ == "__main__":
	print(json.dumps(cases_for(sys.argv[1] if len(sys.argv) > 1 else None), indent=1))
