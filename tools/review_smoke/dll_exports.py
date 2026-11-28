#!/usr/bin/env python3
"""Lists a Windows DLL's exported functions, or compares two DLLs' exports (what one has that the other doesn't).

  python tools/review_smoke/dll_exports.py hippie_lighting.dll
  python tools/review_smoke/dll_exports.py hippie_lighting.dll data/review_smoke/hippie_lighting_old15a.dll

Used by review_smoke.py's sprites_old step to check that the DLL it loads really lacks the texture exports. Needs pefile.
"""
import sys

import pefile


def exports(path):
	pe = pefile.PE(path, fast_load=True)
	pe.parse_data_directories(directories=[pefile.DIRECTORY_ENTRY["IMAGE_DIRECTORY_ENTRY_EXPORT"]])
	if not hasattr(pe, "DIRECTORY_ENTRY_EXPORT"):
		return set()
	return {e.name.decode() for e in pe.DIRECTORY_ENTRY_EXPORT.symbols if e.name}


def main():
	if len(sys.argv) == 2:
		for name in sorted(exports(sys.argv[1])):
			print(name)
	elif len(sys.argv) == 3:
		a, b = exports(sys.argv[1]), exports(sys.argv[2])
		print("only in %s: %s" % (sys.argv[1], " ".join(sorted(a - b)) or "-"))
		print("only in %s: %s" % (sys.argv[2], " ".join(sorted(b - a)) or "-"))
	else:
		print(__doc__)
		sys.exit(2)


if __name__ == "__main__":
	main()
