/* Prototype: byondcore 516.1688 puts a sleeping proc into its wake queue with one memmove of the shorter side.

   The queue is a sorted array of proc pointers (wake time at +8C), live between a head and an end index with room at
   both ends: array 42E410, head 42D918, end 42D91C, capacity 42D920. 16D7B0 inserts after the last entry with the
   same or an earlier time. When there is room in front it always moves the front part down with rep movs, however
   long it is; otherwise it moves the back part up one element per loop pass. With 20,000 sleepers that is ~10 us.

   This keeps the same array and the same order (so every reader of the queue is untouched), moves whichever part
   is shorter, with memmove, and leaves the "no room at either end" case (growing the array) to the engine.

   inject.py <pid> sleep_queue.dll thread_install | thread_stats | thread_uninstall */
#include <windows.h>
#include <stdio.h>
#include <string.h>

typedef unsigned u32;

#define RVA_INSERT 0x16D7B0
#define RVA_HEAD 0x42D918
#define RVA_END 0x42D91C
#define RVA_CAP 0x42D920
#define RVA_ARRAY 0x42E410
#define WAKE(p) (*(int *)((unsigned char *)(p) + 0x8C))

static unsigned char *core, *tramp;
static const unsigned char PROLOGUE[6] = {0x55, 0x8B, 0xEC, 0x83, 0xEC, 0x10};
static char out[256];
static unsigned long long n_insert, n_front, n_back, n_engine, n_moved, n_recenter;
static void (__cdecl *orig_insert)(void *);

static void __cdecl my_insert(void *p) {
    u32 *head = (u32 *)(core + RVA_HEAD), *end = (u32 *)(core + RVA_END), cap = *(u32 *)(core + RVA_CAP);
    void **a = *(void ***)(core + RVA_ARRAY);
    u32 lo = *head, hi = *end, pos;
    int t = WAKE(p);
    n_insert++;
    /* full (the engine grows the array), or short enough that the engine's own moves are as cheap */
    if ((*head == 0 && *end >= cap) || *end - *head < 256) { n_engine++; orig_insert(p); return; }
    while (lo < hi) {  /* first entry waking later than p, the same test as the engine */
        u32 mid = (lo + hi) >> 1;
        if (WAKE(a[mid]) - t <= 0) lo = mid + 1; else hi = mid;
    }
    pos = lo;
    if (*head == 0 && *end < cap && *end - pos > 64) {
        /* no room in front and a long back part: move everything to the middle of the free space once, so later
           inserts near the front (short sleeps) move only the few entries before them */
        u32 g = (cap - *end + 1) / 2;
        memmove(a + g, a, *end * sizeof *a);
        n_moved += *end;
        *head = g; *end += g; pos += g;
        n_recenter++;
    }
    if (*head &&(*end >= cap || pos - *head <= *end - pos)) {
        /* front part [head, pos) down one; p goes at pos - 1 */
        memmove(a + *head - 1, a + *head, (pos - *head) * sizeof *a);
        n_moved += pos - *head;
        (*head)--;
        a[pos - 1] = p;
        n_front++;
    } else {
        /* back part [pos, end) up one; p goes at pos */
        memmove(a + pos + 1, a + pos, (*end - pos) * sizeof *a);
        n_moved += *end - pos;
        (*end)++;
        a[pos] = p;
        n_back++;
    }
}

static void write_bytes(unsigned char *at, const void *b, unsigned n) {
    DWORD old;
    VirtualProtect(at, n, PAGE_EXECUTE_READWRITE, &old);
    memcpy(at, b, n);
    VirtualProtect(at, n, old, &old);
    FlushInstructionCache(GetCurrentProcess(), at, n);
}

__declspec(dllexport) const char *install(int argc, const char **argv) {
    unsigned char jmp[6];
    (void)argc; (void)argv;
    core = (unsigned char *)GetModuleHandleA("byondcore.dll");
    if (!core) return "no byondcore.dll";
    if (core[RVA_INSERT] == 0xE9) return "already installed";
    if (memcmp(core + RVA_INSERT, PROLOGUE, 6)) return "not the 516.1688 code this was written for";
    if (!tramp) {
        tramp = (unsigned char *)VirtualAlloc(0, 16, MEM_COMMIT | MEM_RESERVE, PAGE_EXECUTE_READWRITE);
        memcpy(tramp, PROLOGUE, 6);
        tramp[6] = 0xE9; *(int *)(tramp + 7) = (int)((core + RVA_INSERT + 6) - (tramp + 11));
        FlushInstructionCache(GetCurrentProcess(), tramp, 11);
    }
    orig_insert = (void *)tramp;
    jmp[0] = 0xE9; *(int *)(jmp + 1) = (int)((unsigned char *)my_insert - (core + RVA_INSERT + 5)); jmp[5] = 0x90;
    write_bytes(core + RVA_INSERT, jmp, 6);
    return "installed";
}

__declspec(dllexport) const char *uninstall(int argc, const char **argv) {
    (void)argc; (void)argv;
    if (!core || core[RVA_INSERT] != 0xE9) return "not installed";
    write_bytes(core + RVA_INSERT, PROLOGUE, 6);
    return "uninstalled";
}

__declspec(dllexport) const char *stats(int argc, const char **argv) {
    (void)argc; (void)argv;
    sprintf(out, "inserts %llu: front %llu, back %llu, engine (grow or short) %llu, recentred %llu; %.1f entries moved each", n_insert, n_front,
            n_back, n_engine, n_recenter, n_insert ? (double)n_moved / n_insert : 0.0);
    return out;
}

__declspec(dllexport) DWORD WINAPI thread_install(LPVOID p) { (void)p; return (DWORD)install(0, 0); }
__declspec(dllexport) DWORD WINAPI thread_uninstall(LPVOID p) { (void)p; return (DWORD)uninstall(0, 0); }
__declspec(dllexport) DWORD WINAPI thread_stats(LPVOID p) { (void)p; return (DWORD)stats(0, 0); }
