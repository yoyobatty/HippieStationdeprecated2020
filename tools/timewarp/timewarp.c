// timewarp.dll - fast-forward for the BYOND server (Dream Daemon), for headless test runs.
//
// BYOND has no fixed-step or time-scale switch. A tick always advances world.time by
// world.tick_lag, and the server then waits out the rest of the tick in real time. That wait is
// a one-shot winmm timer (timeSetEvent) which TimeLib re-arms after each tick's work, and its
// idea of "now" comes from _ftime64. This library replaces both in byondcore.dll's import table:
// the timer fires at once (or after a shortened wait, when a speed cap is set) and the wait that
// was skipped is added to the clock.
//
// The game still runs one ordinary tick per tick: same tick_lag, same order of events, and
// world.tick_usage still measures the real CPU time the tick took. Only the idle time between
// ticks is removed, so the speed-up is however idle the server was.
//
// Loaded from DM with call_ext() - see hippiestation/code/modules/admin/timewarp.dm. 32-bit, like
// BYOND. Build: tools/timewarp/build.bat (needs Visual Studio's x86 compiler); the result goes in
// the repository root next to rust_g.dll. Found against BYOND 516.1688: if a later build changes
// how TimeLib waits, timewarp_speed() reports it can't find the imports and the run stays real time.

#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <mmsystem.h>
#include <sys/timeb.h>
#include <time.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define MAX_ALARMS 8
/// Our timer ids carry this bit so timeKillEvent can tell them from winmm's own.
#define OUR_ID 0x10000

static CRITICAL_SECTION lock;
static int installed;
static LARGE_INTEGER qpf;
static LONGLONG qpc0;
/// Wall clock at install, microseconds since 1970.
static LONGLONG wall0_us;
/// Time skipped so far. Virtual now = real now + offset_us.
static LONGLONG offset_us;
/// 1 = real time (timers pass through to winmm), 0 = no cap, N = at most N times real time.
static double speed = 1;
/// Real and virtual time when the current speed was set; the cap is measured from here.
static LONGLONG cap_real0_us, cap_virt0_us;
static LONGLONG alarms_fired;

static struct alarm {
	int armed;
	UINT id;
	LPTIMECALLBACK cb;
	DWORD_PTR user;
	LONGLONG due_virt_us;
} alarms[MAX_ALARMS];
static UINT next_id = 16;
static HANDLE wake;

static MMRESULT (WINAPI *real_timeSetEvent)(UINT, UINT, LPTIMECALLBACK, DWORD_PTR, UINT);
static MMRESULT (WINAPI *real_timeKillEvent)(UINT);
static void (__cdecl *real_ftime64)(struct __timeb64 *);
static __time64_t (__cdecl *real_time64)(__time64_t *);

/// Real microseconds since install.
static LONGLONG real_us(void) {
	LARGE_INTEGER t;
	QueryPerformanceCounter(&t);
	return (LONGLONG)((double)(t.QuadPart - qpc0) * 1000000.0 / (double)qpf.QuadPart);
}

static LONGLONG virt_us(void) {
	EnterCriticalSection(&lock);
	LONGLONG v = real_us() + offset_us;
	LeaveCriticalSection(&lock);
	return v;
}

// ---------------------------------------------------------------------------------------------
// The clock
// ---------------------------------------------------------------------------------------------

static void __cdecl hook_ftime64(struct __timeb64 *tb) {
	real_ftime64(tb); //for the timezone fields
	LONGLONG v = wall0_us + virt_us();
	tb->time = v / 1000000;
	tb->millitm = (unsigned short)((v / 1000) % 1000);
}

static __time64_t __cdecl hook_time64(__time64_t *out) {
	__time64_t v = (wall0_us + virt_us()) / 1000000;
	if (out)
		*out = v;
	return v;
}

// ---------------------------------------------------------------------------------------------
// The tick timer
// ---------------------------------------------------------------------------------------------

/// Fires each alarm as soon as the speed cap allows, moving the clock on to the alarm's due time.
static DWORD WINAPI alarm_thread(LPVOID unused) {
	for (;;) {
		EnterCriticalSection(&lock);
		struct alarm *next = NULL;
		for (int i = 0; i < MAX_ALARMS; i++)
			if (alarms[i].armed && (!next || alarms[i].due_virt_us < next->due_virt_us))
				next = &alarms[i];
		if (!next) {
			LeaveCriticalSection(&lock);
			WaitForSingleObject(wake, INFINITE);
			continue;
		}
		LONGLONG now = real_us();
		LONGLONG fire_at = now;
		if (speed > 0) {
			LONGLONG capped = cap_real0_us + (LONGLONG)((double)(next->due_virt_us - cap_virt0_us) / speed);
			if (capped > fire_at)
				fire_at = capped;
		}
		LONGLONG natural = next->due_virt_us - offset_us; //when it would fire with nothing skipped
		if (fire_at > natural)
			fire_at = natural;
		if (fire_at > now) {
			LeaveCriticalSection(&lock);
			LONGLONG wait_us = fire_at - now;
			if (wait_us >= 2000)
				WaitForSingleObject(wake, (DWORD)(wait_us / 1000) - 1); //woken early if the alarm is killed or replaced
			else
				SwitchToThread();
			continue;
		}
		if (next->due_virt_us - now > offset_us)
			offset_us = next->due_virt_us - now;
		struct alarm fired = *next;
		next->armed = 0;
		alarms_fired++;
		LeaveCriticalSection(&lock);
		fired.cb(fired.id, 0, fired.user, 0, 0);
	}
}

static MMRESULT WINAPI hook_timeSetEvent(UINT delay, UINT resolution, LPTIMECALLBACK cb, DWORD_PTR user, UINT flags) {
	// BYOND's tick alarm is a plain one-shot function callback (flags 0). Anything else is not ours to fake.
	if (flags != 0 || !cb)
		return real_timeSetEvent(delay, resolution, cb, user, flags);
	EnterCriticalSection(&lock);
	struct alarm *slot = NULL;
	if (speed != 1) {
		for (int i = 0; i < MAX_ALARMS; i++)
			if (!alarms[i].armed) {
				slot = &alarms[i];
				break;
			}
	}
	if (!slot) {
		LeaveCriticalSection(&lock);
		return real_timeSetEvent(delay, resolution, cb, user, flags);
	}
	slot->id = OUR_ID | next_id;
	next_id = next_id >= 0xFFF0 ? 16 : next_id + 16;
	slot->cb = cb;
	slot->user = user;
	slot->due_virt_us = real_us() + offset_us + (LONGLONG)delay * 1000;
	slot->armed = 1;
	UINT id = slot->id;
	LeaveCriticalSection(&lock);
	SetEvent(wake);
	return id;
}

static MMRESULT WINAPI hook_timeKillEvent(UINT id) {
	if (!(id & OUR_ID))
		return real_timeKillEvent(id);
	EnterCriticalSection(&lock);
	for (int i = 0; i < MAX_ALARMS; i++)
		if (alarms[i].armed && alarms[i].id == id)
			alarms[i].armed = 0;
	LeaveCriticalSection(&lock);
	SetEvent(wake);
	return TIMERR_NOERROR;
}

// ---------------------------------------------------------------------------------------------
// Installing
// ---------------------------------------------------------------------------------------------

/// The import table slot of mod that holds fn, or NULL.
static void **import_slot(HMODULE mod, const char *fn) {
	BYTE *base = (BYTE *)mod;
	IMAGE_NT_HEADERS *nt = (IMAGE_NT_HEADERS *)(base + ((IMAGE_DOS_HEADER *)base)->e_lfanew);
	IMAGE_DATA_DIRECTORY dir = nt->OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_IMPORT];
	if (!dir.VirtualAddress)
		return NULL;
	for (IMAGE_IMPORT_DESCRIPTOR *d = (IMAGE_IMPORT_DESCRIPTOR *)(base + dir.VirtualAddress); d->Name; d++) {
		IMAGE_THUNK_DATA *names = (IMAGE_THUNK_DATA *)(base + (d->OriginalFirstThunk ? d->OriginalFirstThunk : d->FirstThunk));
		IMAGE_THUNK_DATA *slots = (IMAGE_THUNK_DATA *)(base + d->FirstThunk);
		for (; names->u1.AddressOfData; names++, slots++) {
			if (IMAGE_SNAP_BY_ORDINAL(names->u1.Ordinal))
				continue;
			if (!strcmp((char *)((IMAGE_IMPORT_BY_NAME *)(base + names->u1.AddressOfData))->Name, fn))
				return (void **)&slots->u1.Function;
		}
	}
	return NULL;
}

static void patch(void **slot, void *replacement) {
	DWORD old;
	VirtualProtect(slot, sizeof(void *), PAGE_READWRITE, &old);
	*slot = replacement;
	VirtualProtect(slot, sizeof(void *), old, &old);
}

static const char *install(void) {
	HMODULE core = GetModuleHandleA("byondcore.dll");
	if (!core)
		return "error: byondcore.dll is not loaded";
	void **set = import_slot(core, "timeSetEvent");
	void **kill = import_slot(core, "timeKillEvent");
	void **ftime = import_slot(core, "_ftime64");
	void **time = import_slot(core, "_time64");
	if (!set || !kill || !ftime || !time)
		return "error: this BYOND build doesn't import the timer functions timewarp replaces";

	// BYOND unloads call_ext() libraries when the world closes but goes on calling the timer; stay loaded.
	HMODULE self;
	GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_PIN | GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS, (LPCWSTR)&install, &self);

	// Windows 11 ignores timeBeginPeriod() for windowless processes unless told otherwise, which
	// would round capped waits up to 15.6ms.
	PROCESS_POWER_THROTTLING_STATE throttle = { PROCESS_POWER_THROTTLING_CURRENT_VERSION, PROCESS_POWER_THROTTLING_IGNORE_TIMER_RESOLUTION, 0 };
	SetProcessInformation(GetCurrentProcess(), ProcessPowerThrottling, &throttle, sizeof(throttle));
	timeBeginPeriod(1);

	InitializeCriticalSection(&lock);
	wake = CreateEventW(NULL, FALSE, FALSE, NULL);
	QueryPerformanceFrequency(&qpf);
	LARGE_INTEGER t;
	QueryPerformanceCounter(&t);
	qpc0 = t.QuadPart;
	real_ftime64 = *ftime;
	real_time64 = *time;
	real_timeSetEvent = *set;
	real_timeKillEvent = *kill;
	struct __timeb64 tb;
	real_ftime64(&tb);
	wall0_us = tb.time * 1000000 + (LONGLONG)tb.millitm * 1000;
	if (!CreateThread(NULL, 0, alarm_thread, NULL, 0, NULL))
		return "error: couldn't start the alarm thread";

	patch(ftime, hook_ftime64);
	patch(time, hook_time64);
	patch(kill, hook_timeKillEvent);
	patch(set, hook_timeSetEvent);
	installed = 1;
	return NULL;
}

// ---------------------------------------------------------------------------------------------
// call_ext() entry points
// ---------------------------------------------------------------------------------------------

static char reply[160];

/// timewarp_speed(speed): 1 = real time, 0 = as fast as the CPU allows, N = at most N times real time.
__declspec(dllexport) const char *timewarp_speed(int argc, char **argv) {
	double wanted = argc > 0 ? atof(argv[0]) : 0;
	if (wanted < 0)
		return "error: speed must be 0 (no cap) or a multiple of real time";
	if (!installed) {
		const char *problem = install();
		if (problem)
			return problem;
	}
	EnterCriticalSection(&lock);
	speed = wanted;
	cap_real0_us = real_us();
	cap_virt0_us = cap_real0_us + offset_us;
	LeaveCriticalSection(&lock);
	SetEvent(wake);
	return "ok";
}

/// timewarp_clock(): "<real ms> <game ms> <ticks fired early>" since timewarp was installed.
__declspec(dllexport) const char *timewarp_clock(int argc, char **argv) {
	if (!installed)
		return "0 0 0";
	EnterCriticalSection(&lock);
	LONGLONG real = real_us();
	LONGLONG virt = real + offset_us;
	LONGLONG fired = alarms_fired;
	LeaveCriticalSection(&lock);
	_snprintf(reply, sizeof(reply) - 1, "%.3f %.3f %lld", real / 1000.0, virt / 1000.0, fired);
	return reply;
}
