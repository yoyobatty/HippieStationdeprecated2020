/* Prototype: byondcore 516.1688's var read with a cache in front of its two binary searches.

   Reading obj.var (rva 2030D0, and its silent twin 2031F0) does:
     1. 202500(type, ref): the object's override list {entries, u16 count}, 16-byte entries (+4 var id, +8 Value),
        sorted by id. A binary search; found -> that Value.
     2. not found: the object's type id (162790 + 24CBC0), then 213470(type id, var id, &Value): a binary search of
        the type's default table (16-byte entries counted in dwords: +0 var id, +8 type byte, +0C value).
     3. not found there: 213370 (global/static vars), then a warning and null.
   Both searches get a direct-mapped cache of the index last found for (list, var id). A cached index is used only if
   the entry there still holds that var id, and ids are unique in a list, so a stale or colliding entry is a miss, never
   a wrong answer. Misses do the same binary search as the engine. Nothing is cached for "absent".

   inject.py <pid> var_cache.dll thread_install | thread_stats | thread_uninstall */
#include <windows.h>
#include <stdio.h>
#include <string.h>

typedef unsigned long long u64;
typedef unsigned u32;

#define RVA_READ 0x2030D0
#define RVA_READ_SILENT 0x2031F0
#define RVA_TYPE_DEFAULT 0x213470
#define RVA_OVERRIDES 0x202500
#define RVA_TYPE_OF 0x162790
#define RVA_GLOBAL 0x213370
#define RVA_ID_ENTRY 0x226D20
#define RVA_TYPE_NAME_ID 0x2232E0
#define RVA_WARN 0x135300
#define RVA_WARN_FMT 0x3B6534
#define RVA_WARN_LEVEL 0x4326C8
#define RVA_NULL_VALUE 0x3BAAF8
#define RVA_GLOBAL_VALUES 0x430C9C
#define RVA_TYPES 0x430BC8
#define RVA_TYPE_COUNT 0x430BCC
#define RVA_TABLES 0x430C00
#define RVA_TABLE_COUNT 0x430C04

typedef struct { u32 *entries; unsigned short count; } Overrides;
typedef struct { unsigned short count; unsigned short pad; u32 pad2; u32 *entries; } TypeTable;

static unsigned char *core;
static unsigned char saved[3][5];
static const u32 HOOKED[3] = {RVA_READ, RVA_READ_SILENT, RVA_TYPE_DEFAULT};
static char out[512];

#define CBITS 16
static u32 ocache[1 << CBITS], tcache[1 << CBITS];
static u64 n_read, n_ohit, n_osearch_found, n_omiss, n_thit, n_tsearch_found, n_tmiss, n_global;

static Overrides *(__cdecl *overrides_of)(u32 type, u32 ref);
static u64 (__cdecl *type_of)(u32 type, u32 ref);
static char (__cdecl *global_var)(u32 tid, u32 var, u32 *idx, unsigned char *flags);
static u32 **(__cdecl *id_entry)(u32 id);
static u32 (__cdecl *type_name_id)(u32 type, u32 ref);
static void (__cdecl *warn)(const char *fmt, ...);

static __forceinline u32 slot(const void *list, u32 var) {
    return (((u32)list >> 3) * 0x9E3779B1u ^ var * 0x85EBCA6Bu) >> (32 - CBITS);
}

static __forceinline u64 value_at(const u32 *p) { return ((u64)p[1] << 32) | p[0]; }

/* 213470's contract: the type's default for var, written to out (type byte, then value), true if the type has it */
static char __cdecl type_default(u32 tid, u32 var, unsigned char *outv) {
    TypeTable *t; u32 *e, n, lo, hi, k, s, rec;
    if (tid >= *(u32 *)(core + RVA_TYPE_COUNT) || tid == 0xFFFF) return 0;
    rec = *(u32 *)(core + RVA_TYPES) + tid * 0x98;
    if (!rec) return 0;
    k = *(u32 *)(rec + 0x78);
    if (k >= *(u32 *)(core + RVA_TABLE_COUNT)) return 0;
    t = ((TypeTable **)*(u32 *)(core + RVA_TABLES))[k];
    if (!t) return 0;
    e = t->entries; n = t->count;
    s = slot(t, var);
    k = tcache[s];
    if (k < n && e[k] == var) { n_thit++; goto found; }
    lo = 0; hi = n;
    while (lo < hi) {  /* indexes in dwords, 4 per entry, as the engine does it */
        k = ((lo + hi) >> 1) & 0xFFFC;
        if (e[k] == var) { tcache[s] = k; n_tsearch_found++; goto found; }
        if (e[k] < var) lo = k + 4; else hi = k;
    }
    n_tmiss++;
    return 0;
found:
    outv[0] = (unsigned char)e[k + 2];
    *(u32 *)(outv + 4) = e[k + 3];
    return 1;
}

static __forceinline int override_value(u32 type, u32 ref, u32 var, u64 *v) {
    Overrides *o = overrides_of(type, ref);
    u32 *e, n, lo, hi, mid, s, i;
    if (!o || !(n = o->count)) return 0;
    e = o->entries;
    s = slot(e, var);
    i = ocache[s];
    if (i < n && e[i * 4 + 1] == var) { n_ohit++; *v = value_at(e + i * 4 + 2); return 1; }
    lo = 0; hi = n;
    while (lo < hi) {
        mid = (lo + hi) >> 1;
        if (e[mid * 4 + 1] == var) { ocache[s] = mid; n_osearch_found++; *v = value_at(e + mid * 4 + 2); return 1; }
        if (e[mid * 4 + 1] < var) lo = mid + 1; else hi = mid;
    }
    return 0;
}

static __forceinline u64 read_var(u32 type, u32 ref, u32 var, int loud) {
    u64 v, t; u32 tid, idx; unsigned char d[8], flags;
    n_read++;
    var &= 0xFFFFFF;
    if (override_value(type, ref, var, &v)) return v;
    n_omiss++;
    t = type_of(type, ref);
    tid = (unsigned char)t == 9 ? (u32)(t >> 32) : 0xFFFF;
    if (type_default(tid, var, d)) return ((u64)*(u32 *)(d + 4) << 32) | d[0];
    n_global++;
    t = type_of(type, ref);
    tid = (unsigned char)t == 9 ? (u32)(t >> 32) : 0xFFFF;
    if (global_var(tid, var, &idx, &flags) && (flags & 1))
        return value_at(*(u32 **)(core + RVA_GLOBAL_VALUES) + idx * 2);
    if (loud && *(u32 *)(core + RVA_WARN_LEVEL) >= 0x137) {
        const char *vname = (const char *)*id_entry(var);
        const char *tname = (const char *)*id_entry(type_name_id(type, ref));
        warn((const char *)(core + RVA_WARN_FMT), tname, vname);
    }
    return value_at((u32 *)(core + RVA_NULL_VALUE));
}

static u64 __cdecl read_loud(u32 type, u32 ref, u32 var) { return read_var(type, ref, var, 1); }
static u64 __cdecl read_silent(u32 type, u32 ref, u32 var) { return read_var(type, ref, var, 0); }

static void write_jmp(u32 rva, void *to) {
    DWORD old; unsigned char *at = core + rva;
    VirtualProtect(at, 5, PAGE_EXECUTE_READWRITE, &old);
    at[0] = 0xE9; *(int *)(at + 1) = (int)((unsigned char *)to - (at + 5));
    VirtualProtect(at, 5, old, &old);
    FlushInstructionCache(GetCurrentProcess(), at, 5);
}

static void put_back(u32 rva, const unsigned char *bytes) {
    DWORD old; unsigned char *at = core + rva;
    VirtualProtect(at, 5, PAGE_EXECUTE_READWRITE, &old);
    memcpy(at, bytes, 5);
    VirtualProtect(at, 5, old, &old);
    FlushInstructionCache(GetCurrentProcess(), at, 5);
}

__declspec(dllexport) const char *install(int argc, const char **argv) {
    static const unsigned char want[3][5] = {{0x55, 0x8B, 0xEC, 0x83, 0xEC}, {0x55, 0x8B, 0xEC, 0x83, 0xEC},
                                             {0x55, 0x8B, 0xEC, 0x51, 0x8B}};
    int i;
    (void)argc; (void)argv;
    core = (unsigned char *)GetModuleHandleA("byondcore.dll");
    if (!core) return "no byondcore.dll";
    if (core[RVA_READ] == 0xE9) return "already installed";
    for (i = 0; i < 3; i++)
        if (memcmp(core + HOOKED[i], want[i], 5)) return "not the 516.1688 code this was written for";
    overrides_of = (void *)(core + RVA_OVERRIDES);
    type_of = (void *)(core + RVA_TYPE_OF);
    global_var = (void *)(core + RVA_GLOBAL);
    id_entry = (void *)(core + RVA_ID_ENTRY);
    type_name_id = (void *)(core + RVA_TYPE_NAME_ID);
    warn = (void *)(core + RVA_WARN);
    for (i = 0; i < 3; i++) memcpy(saved[i], core + HOOKED[i], 5);
    memset(ocache, 0xFF, sizeof ocache);
    memset(tcache, 0xFF, sizeof tcache);
    write_jmp(RVA_TYPE_DEFAULT, (void *)type_default);
    write_jmp(RVA_READ_SILENT, (void *)read_silent);
    write_jmp(RVA_READ, (void *)read_loud);
    return "installed";
}

__declspec(dllexport) const char *uninstall(int argc, const char **argv) {
    int i;
    (void)argc; (void)argv;
    if (!core || core[RVA_READ] != 0xE9) return "not installed";
    for (i = 0; i < 3; i++) put_back(HOOKED[i], saved[i]);
    return "uninstalled";
}

__declspec(dllexport) const char *stats(int argc, const char **argv) {
    (void)argc; (void)argv;
    sprintf(out, "reads %llu: override cache hit %llu, found by search %llu, not overridden %llu; type cache hit %llu, "
            "found by search %llu, not in type %llu; global path %llu",
            n_read, n_ohit, n_osearch_found, n_omiss, n_thit, n_tsearch_found, n_tmiss, n_global);
    return out;
}

__declspec(dllexport) DWORD WINAPI thread_install(LPVOID p) { (void)p; return (DWORD)install(0, 0); }
__declspec(dllexport) DWORD WINAPI thread_uninstall(LPVOID p) { (void)p; return (DWORD)uninstall(0, 0); }
__declspec(dllexport) DWORD WINAPI thread_stats(LPVOID p) { (void)p; return (DWORD)stats(0, 0); }
