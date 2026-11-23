/* Prototype: byondcore 516.1688 links an obj into, and out of, its loc's contents in O(1) instead of O(contents).

   The objs in a loc form a singly linked chain of obj ids: the loc's record holds the first id (1FEE80 returns that
   slot), each obj record holds the next at +48h, 0xFFFF ends it. Obj record: +0 loc type, +4 loc value.
     1EF940 (obj enters a loc) walks the whole chain to append at the end           -> loop at 1EF986
     2149F0 (obj leaves its loc) walks from the start to find the obj's predecessor -> loop at 214A42
   Moving one obj onto and off a turf holding 20,000 objs costs ~230 us that way.

   Both loops are replaced by a jump to a stub here that returns the slot to write, from two caches:
     tail of a loc: used only if that obj is not the one being added, its loc is this loc and its next is 0xFFFF.
       Every obj whose loc is this loc is in the chain, so that obj is the end of it.
     predecessor of an obj: used only if its loc is this loc and its next is this obj.
   A failed check falls back to the same walk as the engine (with the engine's own error exits).

   inject.py <pid> turf_chain.dll thread_install | thread_stats | thread_uninstall */
#include <windows.h>
#include <stdio.h>
#include <string.h>

typedef unsigned u32;
#define END 0xFFFF
#define NEXT(rec) ((u32 *)((unsigned char *)(rec) + 0x48))

#define RVA_APPEND_LOOP 0x1EF986
#define RVA_APPEND_OK 0x1EF9BB
#define RVA_APPEND_BAD 0x1EF9DF
#define RVA_UNLINK_LOOP 0x214A42
#define RVA_UNLINK_FOUND 0x214A75
#define RVA_UNLINK_NONE 0x214B73
#define RVA_OBJS 0x430BA0
#define RVA_OBJ_COUNT 0x430BA4

static const unsigned char APPEND_BYTES[8] = {0x8B, 0x01, 0x57, 0x3D, 0xFF, 0xFF, 0x00, 0x00};
static const unsigned char UNLINK_BYTES[14] = {0x8B, 0x15, 0xA4, 0x0B, 0x43, 0x10, 0x57,
                                               0x8B, 0x3D, 0xA0, 0x0B, 0x43, 0x10, 0x90};

static unsigned char *core;
static u32 *g_count, **g_table;
static void *g_append_ok, *g_append_bad, *g_unlink_found, *g_unlink_none;
static char out[256];
static unsigned long long n_append, n_tail_hit, n_unlink, n_head, n_prev_hit, n_walk_steps;

#define TBITS 16
#define PBITS 20
typedef struct { u32 lt, lv, tail; } Tail;
static Tail tails[1 << TBITS];
static u32 prev_obj[1 << PBITS], prev_of[1 << PBITS];

static __forceinline u32 *rec_of(u32 id) { return id < *g_count ? (*g_table)[id] ? (u32 *)(*g_table)[id] : 0 : 0; }
static __forceinline Tail *tail_entry(u32 lt, u32 lv) {
    return &tails[(((lt & 0xFF) * 0x9E3779B1u) ^ (lv * 0x85EBCA6Bu)) >> (32 - TBITS)];
}
static __forceinline int in_loc(const u32 *rec, u32 lt, u32 lv) {
    return (unsigned char)rec[0] == (unsigned char)lt && rec[1] == lv;
}
static __forceinline void set_prev(u32 obj, u32 p) {
    prev_obj[obj & ((1 << PBITS) - 1)] = obj; prev_of[obj & ((1 << PBITS) - 1)] = p;
}

/* the slot to write obj's id into to append it to the chain at head, or 0 for the engine's error path */
static u32 *__cdecl append_slot(u32 *head, u32 obj, u32 lt, u32 lv) {
    Tail *t = tail_entry(lt, lv);
    u32 *slot = head, e = *head, prev = END, *rec;
    n_append++;
    if (t->lt == lt && t->lv == lv && t->tail != obj && (rec = rec_of(t->tail)) && in_loc(rec, lt, lv) &&
        *NEXT(rec) == END) {
        n_tail_hit++;
        prev = t->tail; slot = NEXT(rec);
    } else {
        while (e != END) {
            if (!(rec = rec_of(e))) return 0;
            n_walk_steps++;
            prev = e; slot = NEXT(rec); e = *slot;
        }
    }
    t->lt = lt; t->lv = lv; t->tail = obj;
    set_prev(obj, prev);
    return slot;
}

/* the slot that points at obj in the chain at head (obj's loc is lt/lv), or 0 if it isn't there */
static u32 *__cdecl unlink_slot(u32 *head, u32 obj, u32 lt, u32 lv) {
    u32 *slot = 0, prev = END, e, *rec, *orec, i = obj & ((1 << PBITS) - 1);
    n_unlink++;
    if (*head == obj) { n_head++; slot = head; }
    else if (prev_obj[i] == obj && prev_of[i] != obj && (rec = rec_of(prev_of[i])) && in_loc(rec, lt, lv) &&
             *NEXT(rec) == obj) {
        n_prev_hit++; prev = prev_of[i]; slot = NEXT(rec);
    } else {
        slot = head; e = *head;
        while (e != obj) {
            if (!(rec = rec_of(e))) return 0;
            n_walk_steps++;
            prev = e; slot = NEXT(rec); e = *slot;
        }
    }
    /* keep the caches right across the unlink: obj's successor gets obj's predecessor; a removed tail hands over */
    if ((orec = rec_of(obj))) {
        u32 nx = *NEXT(orec);
        if (nx != END) set_prev(nx, prev);
        else { Tail *t = tail_entry(lt, lv); if (t->lt == lt && t->lv == lv) t->tail = prev; }
    }
    return slot;
}

/* at 1EF986: ecx = head slot, esi = obj id, [ebp+0Ch]/[ebp+10h] = the new loc */
static __declspec(naked) void append_stub(void) {
    __asm {
        push edi
        push dword ptr [ebp + 10h]
        push dword ptr [ebp + 0Ch]
        push esi
        push ecx
        call append_slot
        add esp, 16
        test eax, eax
        je bad
        mov ecx, eax
        jmp dword ptr [g_append_ok]
    bad:
        jmp dword ptr [g_append_bad]
    }
}

/* at 214A42: ecx = head slot, esi = obj id, ebx = obj record (+0 loc type, +4 loc value) */
static __declspec(naked) void unlink_stub(void) {
    __asm {
        push edi
        push dword ptr [ebx + 4]
        push dword ptr [ebx]
        push esi
        push ecx
        call unlink_slot
        add esp, 16
        test eax, eax
        je none
        mov ecx, eax
        mov edx, dword ptr [g_count]
        mov edx, dword ptr [edx]
        mov edi, dword ptr [g_table]
        mov edi, dword ptr [edi]
        jmp dword ptr [g_unlink_found]
    none:
        jmp dword ptr [g_unlink_none]
    }
}

static void write_bytes(unsigned char *at, const void *b, unsigned n) {
    DWORD old;
    VirtualProtect(at, n, PAGE_EXECUTE_READWRITE, &old);
    memcpy(at, b, n);
    VirtualProtect(at, n, old, &old);
    FlushInstructionCache(GetCurrentProcess(), at, n);
}

static void write_jmp(unsigned rva, void *to, unsigned len) {
    unsigned char b[16]; unsigned i;
    b[0] = 0xE9; *(int *)(b + 1) = (int)((unsigned char *)to - (core + rva + 5));
    for (i = 5; i < len; i++) b[i] = 0x90;
    write_bytes(core + rva, b, len);
}

__declspec(dllexport) const char *install(int argc, const char **argv) {
    unsigned char want[14];
    (void)argc; (void)argv;
    core = (unsigned char *)GetModuleHandleA("byondcore.dll");
    if (!core) return "no byondcore.dll";
    if (core[RVA_APPEND_LOOP] == 0xE9) return "already installed";
    /* the absolute addresses in the unlink loop's bytes follow the module's base */
    memcpy(want, UNLINK_BYTES, 14);
    *(u32 *)(want + 2) = (u32)(core + RVA_OBJ_COUNT);
    *(u32 *)(want + 9) = (u32)(core + RVA_OBJS);
    if (memcmp(core + RVA_APPEND_LOOP, APPEND_BYTES, 8) || memcmp(core + RVA_UNLINK_LOOP, want, 14))
        return "not the 516.1688 code this was written for";
    g_count = (u32 *)(core + RVA_OBJ_COUNT);
    g_table = (u32 **)(core + RVA_OBJS);
    g_append_ok = core + RVA_APPEND_OK; g_append_bad = core + RVA_APPEND_BAD;
    g_unlink_found = core + RVA_UNLINK_FOUND; g_unlink_none = core + RVA_UNLINK_NONE;
    memset(tails, 0, sizeof tails);
    memset(prev_obj, 0xFF, sizeof prev_obj);
    write_jmp(RVA_APPEND_LOOP, (void *)append_stub, 8);
    write_jmp(RVA_UNLINK_LOOP, (void *)unlink_stub, 14);
    return "installed";
}

__declspec(dllexport) const char *uninstall(int argc, const char **argv) {
    unsigned char want[14];
    (void)argc; (void)argv;
    if (!core || core[RVA_APPEND_LOOP] != 0xE9) return "not installed";
    memcpy(want, UNLINK_BYTES, 14);
    *(u32 *)(want + 2) = (u32)(core + RVA_OBJ_COUNT);
    *(u32 *)(want + 9) = (u32)(core + RVA_OBJS);
    write_bytes(core + RVA_APPEND_LOOP, APPEND_BYTES, 8);
    write_bytes(core + RVA_UNLINK_LOOP, want, 14);
    return "uninstalled";
}

__declspec(dllexport) const char *stats(int argc, const char **argv) {
    (void)argc; (void)argv;
    sprintf(out, "appends %llu (tail cached %llu), unlinks %llu (first %llu, predecessor cached %llu), walk steps %llu",
            n_append, n_tail_hit, n_unlink, n_head, n_prev_hit, n_walk_steps);
    return out;
}

__declspec(dllexport) DWORD WINAPI thread_install(LPVOID p) { (void)p; return (DWORD)install(0, 0); }
__declspec(dllexport) DWORD WINAPI thread_uninstall(LPVOID p) { (void)p; return (DWORD)uninstall(0, 0); }
__declspec(dllexport) DWORD WINAPI thread_stats(LPVOID p) { (void)p; return (DWORD)stats(0, 0); }
