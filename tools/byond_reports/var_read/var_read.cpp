// What Byondapi costs to read one var from each of many turfs, in ns a read. var_read.dm calls these. build.bat makes var_read.dll.
#include "byondapi.h"
#include <windows.h>
#include <vector>

static double ns_since(LARGE_INTEGER start) {
	LARGE_INTEGER now, frequency;
	QueryPerformanceCounter(&now);
	QueryPerformanceFrequency(&frequency);
	return (double)(now.QuadPart - start.QuadPart) * 1000000000.0 / (double)frequency.QuadPart;
}

static CByondValue number(double value) {
	CByondValue result;
	ByondValue_Clear(&result);
	ByondValue_SetNum(&result, (float)value);
	return result;
}

static bool read_turfs(CByondValue const *list, std::vector<CByondValue> &turfs) {
	u4c length = 0;
	Byond_ReadList(list, nullptr, &length);
	if (!length) return false;
	turfs.resize(length);
	return Byond_ReadList(list, turfs.data(), &length);
}

// A var on every turf, one Byondapi call each. v[0] the turfs, v[1] the var's name.
extern "C" BYOND_EXPORT CByondValue read_var_each(u4c n, CByondValue v[]) {
	std::vector<CByondValue> turfs;
	if (n != 2 || !read_turfs(&v[0], turfs)) return number(-1);
	char name[64];
	u4c length = sizeof(name);
	if (!Byond_ToString(&v[1], name, &length)) return number(-2);
	u4c id = Byond_GetStrId(name);
	float total = 0;
	LARGE_INTEGER start;
	QueryPerformanceCounter(&start);
	for (size_t i = 0; i < turfs.size(); i++) {
		CByondValue out;
		if (!Byond_ReadVarByStrId(&turfs[i], id, &out)) return number(-3);
		total += ByondValue_GetNum(&out);
	}
	double ns = ns_since(start) / turfs.size();
	return total > 0 ? number(ns) : number(-4);
}

// The whole list in one call: what a read costs when it's a single trip across the API. v[0] the turfs.
extern "C" BYOND_EXPORT CByondValue read_list_whole(u4c n, CByondValue v[]) {
	u4c length = 0;
	if (n != 1) return number(-1);
	Byond_ReadList(&v[0], nullptr, &length);
	if (!length) return number(-2);
	std::vector<CByondValue> turfs(length);
	LARGE_INTEGER start;
	QueryPerformanceCounter(&start);
	if (!Byond_ReadList(&v[0], turfs.data(), &length)) return number(-3);
	return number(ns_since(start) / length);
}
