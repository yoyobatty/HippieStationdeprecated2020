/*
 * hippie_prof.dll: a sampling profiler for BYOND, cheap enough to leave on all round.
 *
 * BYOND's own profiler (world.Profile) times every proc call and adds ~255 ns to each. This one does two things instead:
 *  - the game's thread: a hook on byondcore's exec_proc (every proc run, and every resume after a sleep) pushes the proc's
 *    id onto a shadow stack and pops it afterwards. Nothing else: no clock, no queue, no allocation.
 *  - a thread of its own: reads that stack about every millisecond and adds the time since its last look to the proc on
 *    top (self) and to every proc on the stack once (total). When no proc is running it's put down to BYOND itself: the
 *    server tick, sending the map, or waiting. The last ~65 s of samples are kept, so after a freeze the procs that held
 *    the server can be named: the sampler kept counting while the game stood still.
 * The stack is read without stopping the game's thread, so a sample can catch it mid-push: a proc id one call stale, never a
 * bad one (ids are checked against the proc table). A runtime error that unwinds past the hook leaves the depth high until
 * the next hooked frame below it returns, which puts it back.
 *
 * Where exec_proc, server_tick, send_maps and the string, misc and proc tables are in byondcore.dll comes from byond-tracy
 * (BSD, (c) 2022 anon; ParadiseSS13 fork's offsets/windows.h) for 516.1666; for 516.1688 they were found from 1666's by
 * matching code (tools/hippie_prof/find_offsets.py). An unknown build is refused, not guessed at.
 *
 * Exports (call_ext string procs): start, stop, dump [clear], recent <ms>, status. Results are JSON.
 * Build: tools/hippie_prof/build.bat (32-bit, like BYOND).
 */
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define EXPORT __declspec(dllexport)

/* byond types (from byond-tracy) */
struct object {
	union { unsigned padding; unsigned char type; };
	union { unsigned i; float f; };
};
struct string {
	char *data;
	unsigned id;
	struct string *left;
	struct string *right;
	unsigned refcount;
	unsigned unk0;
	unsigned len;
};
struct proc {
	unsigned procdef;
	/* more we don't use */
};

typedef struct object (__cdecl *exec_proc_fn)(struct proc *);
typedef int (__stdcall *server_tick_fn)(void);
typedef void (__cdecl *send_maps_fn)(void);
typedef int (*get_build_fn)(void);

struct build_offsets {
	int build;
	unsigned strings, strings_len, miscs, miscs_len, procdefs, procdefs_len, procdef_desc, exec_proc, server_tick, send_maps, prologues;
};
static const struct build_offsets known_builds[] = {
	{1666, 0x0042CA18, 0x0042CA1C, 0x0042CA2C, 0x0042CA30, 0x0042CA3C, 0x0042CA40, 0x001C002C, 0x0013D6D0, 0x002287E0, 0x001DA860, 0x00050606},
	{1688, 0x00430BF0, 0x00430BF4, 0x00430C00, 0x00430C04, 0x00430C10, 0x00430C14, 0x001C002C, 0x0013E750, 0x00229950, 0x001DB7B0, 0x00050606},
};

/* what BYOND has, once found */
static struct string ***byond_strings;
static unsigned *byond_strings_len;
static char **byond_procdefs;
static unsigned *byond_procdefs_len;
static unsigned procdef_size, procdef_path;
static exec_proc_fn orig_exec_proc;
static server_tick_fn orig_server_tick;
static send_maps_fn orig_send_maps;
static int hooked;
static int byond_build;

/* the shadow stack: written by the game's thread only */
#define STACK_MAX 1024
static volatile unsigned shadow[STACK_MAX];
static volatile int depth;
/* what BYOND is doing when no proc is: 0 waiting, 1 server tick, 2 sending the map */
static volatile int phase;
enum { PHASE_IDLE, PHASE_TICK, PHASE_MAPS, PHASES };
static const char *const phase_names[PHASES] = {"(idle: between ticks)", "(BYOND: server tick, outside procs)", "(BYOND: sending the map)"};

/* the sampler's figures: microseconds */
static unsigned proc_count;
static unsigned long long *self_us, *total_us;
static unsigned *seen_stamp, stamp;
static unsigned long long phase_us[PHASES];
static unsigned long long samples, sampled_us;
static volatile int sampling;
static HANDLE sampler_thread;
static LARGE_INTEGER qpf;
static CRITICAL_SECTION figures_lock;

/* the last ~65 s of samples, for freezes */
#define RING 65536
struct sample { long long at_us; unsigned top; unsigned dt_us; };
static struct sample ring[RING];
static volatile unsigned ring_pos;

static char *result;

/* ---- hooks: the game's thread ---- */

static struct object __cdecl hook_exec_proc(struct proc *p) {
	int d = depth;
	if(d < STACK_MAX)
		shadow[d] = p->procdef;
	depth = d + 1;
	struct object r = orig_exec_proc(p);
	depth = d;
	return r;
}

static int __stdcall hook_server_tick(void) {
	phase = PHASE_TICK;
	int r = orig_server_tick();
	phase = PHASE_IDLE;
	return r;
}

static void __cdecl hook_send_maps(void) {
	int before = phase;
	phase = PHASE_MAPS;
	orig_send_maps();
	phase = before;
}

/* ---- the sampler: its own thread ---- */

static long long now_us(void) {
	LARGE_INTEGER t;
	QueryPerformanceCounter(&t);
	return (long long)(t.QuadPart * 1000000 / qpf.QuadPart);
}

static DWORD WINAPI sampler(LPVOID unused) {
	(void)unused;
	SetThreadPriority(GetCurrentThread(), THREAD_PRIORITY_HIGHEST);
	HANDLE timer = CreateWaitableTimerExW(NULL, NULL, 0x00000002 /* CREATE_WAITABLE_TIMER_HIGH_RESOLUTION */, TIMER_ALL_ACCESS);
	long long last = now_us();
	while(sampling) {
		if(timer) {
			LARGE_INTEGER due;
			due.QuadPart = -10000; /* 1 ms */
			SetWaitableTimer(timer, &due, 0, NULL, NULL, FALSE);
			WaitForSingleObject(timer, 5);
		} else {
			Sleep(1);
		}
		long long t = now_us();
		unsigned dt = (unsigned)(t - last);
		last = t;
		if(dt > 1000000)
			dt = 1000000; /* the machine slept */
		int d = depth;
		if(d > STACK_MAX)
			d = STACK_MAX;
		unsigned top = 0xFFFFFFFFu;
		EnterCriticalSection(&figures_lock);
		if(d <= 0) {
			int ph = phase;
			phase_us[ph >= 0 && ph < PHASES ? ph : 0] += dt;
		} else {
			top = shadow[d - 1];
			if(top < proc_count)
				self_us[top] += dt;
			stamp++;
			for(int i = 0; i < d; i++) {
				unsigned id = shadow[i];
				if(id < proc_count && seen_stamp[id] != stamp) {
					seen_stamp[id] = stamp;
					total_us[id] += dt;
				}
			}
		}
		samples++;
		sampled_us += dt;
		LeaveCriticalSection(&figures_lock);
		unsigned pos = ring_pos;
		ring[pos % RING].at_us = t;
		ring[pos % RING].top = top;
		ring[pos % RING].dt_us = dt;
		ring_pos = pos + 1;
	}
	if(timer)
		CloseHandle(timer);
	return 0;
}

/* ---- finding BYOND ---- */

static void *trampolines;

/* Overwrite the first `size` bytes of `target` (whole instructions) with a jump to `detour`; returns the original's start */
static void *install_hook(void *target, void *detour, unsigned size, unsigned char *tramp) {
	memcpy(tramp, target, size);
	tramp[size] = 0xE9;
	*(int *)(tramp + size + 1) = (int)((char *)target + size - (char *)(tramp + size + 5));
	DWORD old;
	if(!VirtualProtect(target, size, PAGE_EXECUTE_READWRITE, &old))
		return NULL;
	unsigned char *t = (unsigned char *)target;
	t[0] = 0xE9;
	*(int *)(t + 1) = (int)((char *)detour - (char *)(t + 5));
	for(unsigned i = 5; i < size; i++)
		t[i] = 0x90;
	VirtualProtect(target, size, old, &old);
	FlushInstructionCache(GetCurrentProcess(), target, size);
	return tramp;
}

static const char *find_byond(void) {
	HMODULE core = GetModuleHandleA("byondcore.dll");
	if(!core)
		return "byondcore.dll not loaded";
	get_build_fn get_build = (get_build_fn)GetProcAddress(core, "?GetByondBuild@ByondLib@@QAEJXZ");
	if(!get_build)
		return "GetByondBuild not found";
	byond_build = get_build();
	const struct build_offsets *o = NULL;
	for(unsigned i = 0; i < sizeof(known_builds) / sizeof(known_builds[0]); i++)
		if(known_builds[i].build == byond_build)
			o = &known_builds[i];
	if(!o)
		return "unsupported BYOND build";
	char *base = (char *)core;
	byond_strings = (struct string ***)(base + o->strings);
	byond_strings_len = (unsigned *)(base + o->strings_len);
	byond_procdefs = (char **)(base + o->procdefs);
	byond_procdefs_len = (unsigned *)(base + o->procdefs_len);
	procdef_size = o->procdef_desc & 0xFF;
	procdef_path = (o->procdef_desc >> 8) & 0xFF;
	/* sanity before touching any code: the tables must look like tables */
	if(*byond_procdefs_len == 0 || *byond_procdefs_len > 2000000 || *byond_strings_len == 0 || *byond_strings_len > 50000000 || !*byond_procdefs || !*byond_strings)
		return "BYOND's tables don't look right for this build: not hooking";
	trampolines = VirtualAlloc(NULL, 4096, MEM_COMMIT | MEM_RESERVE, PAGE_EXECUTE_READWRITE);
	if(!trampolines)
		return "no memory for trampolines";
	unsigned char *tr = (unsigned char *)trampolines;
	orig_exec_proc = (exec_proc_fn)install_hook(base + o->exec_proc, (void *)hook_exec_proc, (o->prologues >> 0) & 0xFF, tr);
	orig_server_tick = (server_tick_fn)install_hook(base + o->server_tick, (void *)hook_server_tick, (o->prologues >> 8) & 0xFF, tr + 64);
	orig_send_maps = (send_maps_fn)install_hook(base + o->send_maps, (void *)hook_send_maps, (o->prologues >> 16) & 0xFF, tr + 128);
	if(!orig_exec_proc || !orig_server_tick || !orig_send_maps)
		return "couldn't hook";
	/* byondcore jumps into this DLL from now on: it must never be unloaded (BYOND unloads call_ext DLLs at world close) */
	HMODULE self;
	GetModuleHandleExA(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_PIN, (LPCSTR)hook_exec_proc, &self);
	hooked = 1;
	return NULL;
}

static const char *proc_name(unsigned id) {
	if(id >= *byond_procdefs_len)
		return "?";
	char *pd = *byond_procdefs + id * procdef_size;
	unsigned sid = *(unsigned *)(pd + procdef_path);
	if(sid >= *byond_strings_len)
		return "?";
	struct string *s = (*byond_strings)[sid];
	return s && s->data ? s->data : "?";
}

/* ---- output ---- */

struct buf { char *p; size_t len, cap; };
static void put(struct buf *b, const char *s) {
	size_t n = strlen(s);
	if(b->len + n + 1 > b->cap) {
		b->cap = (b->len + n + 1) * 2 + 4096;
		b->p = (char *)realloc(b->p, b->cap);
	}
	memcpy(b->p + b->len, s, n + 1);
	b->len += n;
}
static void put_name(struct buf *b, const char *s) {
	char tmp[8];
	put(b, "\"");
	for(; *s; s++) {
		if(*s == '"' || *s == '\\') {
			tmp[0] = '\\'; tmp[1] = *s; tmp[2] = 0;
			put(b, tmp);
		} else if((unsigned char)*s < 0x20) {
			put(b, " ");
		} else {
			tmp[0] = *s; tmp[1] = 0;
			put(b, tmp);
		}
	}
	put(b, "\"");
}
static const char *finish(struct buf *b) {
	free(result);
	result = b->p;
	return result ? result : "";
}

static void reset_figures(void) {
	memset(self_us, 0, sizeof(*self_us) * proc_count);
	memset(total_us, 0, sizeof(*total_us) * proc_count);
	memset(phase_us, 0, sizeof(phase_us));
	samples = 0;
	sampled_us = 0;
}

/* start: hooks BYOND (once) and starts the sampler. Returns "ok <build> <procs>" or why not */
EXPORT const char *start(int n, char **v) {
	(void)n; (void)v;
	static char msg[256];
	if(!hooked) {
		QueryPerformanceFrequency(&qpf);
		InitializeCriticalSection(&figures_lock);
		const char *err = find_byond();
		if(err) {
			snprintf(msg, sizeof msg, "error: %s (BYOND build %d)", err, byond_build);
			return msg;
		}
		proc_count = *byond_procdefs_len;
		self_us = (unsigned long long *)calloc(proc_count, sizeof(*self_us));
		total_us = (unsigned long long *)calloc(proc_count, sizeof(*total_us));
		seen_stamp = (unsigned *)calloc(proc_count, sizeof(*seen_stamp));
	}
	if(!sampling) {
		sampling = 1;
		sampler_thread = CreateThread(NULL, 0, sampler, NULL, 0, NULL);
	}
	snprintf(msg, sizeof msg, "ok %d %u", byond_build, proc_count);
	return msg;
}

/* stop: stops the sampler; the hooks stay (they cost a push and a pop) */
EXPORT const char *stop(int n, char **v) {
	(void)n; (void)v;
	if(sampling) {
		sampling = 0;
		WaitForSingleObject(sampler_thread, 1000);
		CloseHandle(sampler_thread);
	}
	return "ok";
}

static int cmp_self(const void *a, const void *b) {
	unsigned x = *(const unsigned *)a, y = *(const unsigned *)b;
	return self_us[y] > self_us[x] ? 1 : (self_us[y] < self_us[x] ? -1 : 0);
}

/* dump [clear]: every proc with time, like world.Profile(json) - name, self, total (seconds), samples - plus BYOND's own parts
   under names in brackets. "clear" starts the figures afresh. */
EXPORT const char *dump(int n, char **v) {
	struct buf b = {0};
	if(!hooked)
		return "[]";
	EnterCriticalSection(&figures_lock);
	unsigned *ids = (unsigned *)malloc(sizeof(unsigned) * proc_count);
	unsigned count = 0;
	for(unsigned i = 0; i < proc_count; i++)
		if(total_us[i])
			ids[count++] = i;
	qsort(ids, count, sizeof(unsigned), cmp_self);
	char num[160];
	put(&b, "[");
	for(int ph = 0; ph < PHASES; ph++) {
		put(&b, ph ? "," : "");
		put(&b, "{\"name\":");
		put_name(&b, phase_names[ph]);
		snprintf(num, sizeof num, ",\"self\":%.6f,\"total\":%.6f}", phase_us[ph] / 1e6, phase_us[ph] / 1e6);
		put(&b, num);
	}
	for(unsigned k = 0; k < count; k++) {
		unsigned i = ids[k];
		put(&b, ",{\"name\":");
		put_name(&b, proc_name(i));
		snprintf(num, sizeof num, ",\"self\":%.6f,\"total\":%.6f}", self_us[i] / 1e6, total_us[i] / 1e6);
		put(&b, num);
	}
	put(&b, "]");
	free(ids);
	if(n >= 1 && v && v[0] && !strcmp(v[0], "clear"))
		reset_figures();
	LeaveCriticalSection(&figures_lock);
	return finish(&b);
}

/* recent <ms>: the procs on top of the stack in the last <ms> of real time, most first, from the ring: what held the server
   in a freeze that's just ended */
EXPORT const char *recent(int n, char **v) {
	struct buf b = {0};
	if(!hooked)
		return "[]";
	long long window = (n >= 1 && v && v[0]) ? atoll(v[0]) * 1000 : 30000000;
	long long since = now_us() - window;
	unsigned long long *us = (unsigned long long *)calloc(proc_count + PHASES, sizeof(*us));
	unsigned end = ring_pos;
	unsigned first = end > RING ? end - RING : 0;
	for(unsigned p = end; p > first; p--) {
		struct sample *s = &ring[(p - 1) % RING];
		if(s->at_us < since)
			break;
		us[s->top < proc_count ? s->top : proc_count] += s->dt_us;
	}
	char num[96];
	put(&b, "[");
	int first_out = 1;
	for(int k = 0; k < 10; k++) {
		unsigned best = 0xFFFFFFFFu;
		unsigned long long best_us = 0;
		for(unsigned i = 0; i <= proc_count; i++)
			if(us[i] > best_us) {
				best_us = us[i];
				best = i;
			}
		if(best == 0xFFFFFFFFu)
			break;
		put(&b, first_out ? "{\"name\":" : ",{\"name\":");
		first_out = 0;
		put_name(&b, best < proc_count ? proc_name(best) : "(BYOND, outside procs)");
		snprintf(num, sizeof num, ",\"self\":%.6f}", best_us / 1e6);
		put(&b, num);
		us[best] = 0;
	}
	put(&b, "]");
	free(us);
	return finish(&b);
}

/* status: what it's done */
EXPORT const char *status(int n, char **v) {
	(void)n; (void)v;
	static char msg[256];
	snprintf(msg, sizeof msg, "{\"hooked\":%d,\"sampling\":%d,\"build\":%d,\"procs\":%u,\"samples\":%llu,\"seconds\":%.3f,\"depth\":%d}",
		hooked, (int)sampling, byond_build, proc_count, samples, sampled_us / 1e6, (int)depth);
	return msg;
}
