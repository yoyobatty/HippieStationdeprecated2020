/* Prototype: byondcore 516.1688 answers "k in L" from the list's index tree when it can.

   17F8B0(key type, key value, container type, container value) is "in". For a list (container type 0x0F) it walks
   every element calling 24CCD0, a bitwise compare (same type byte, same 32-bit value): O(n), 304 us at 300,000.
   A list's associations sit in a red-black tree at list+4 (node: +0 key type, +4 key value, +10 left, +14 right),
   ordered by 24CC60 (type byte, then float order for numbers, else unsigned value). Every key in that tree is also an
   element of the list (in_test.dm checks this under every list operation), so a key found there is "in" the list.
   A hit is taken only when the node's key is bitwise equal to the asked key (the tree treats 0 and -0 as equal, "in"
   doesn't). Anything else, a miss included (the key may be a plain element with no association), runs the engine's
   own code through a trampoline.

   inject.py <pid> in_index.dll thread_install | thread_stats | thread_uninstall */
#include <windows.h>
#include <stdio.h>
#include <string.h>

typedef unsigned u32;
typedef struct Node { u32 ktype, kval, vtype, vval; struct Node *left, *right, *parent; } Node;
typedef struct { u32 *elems; Node *root; u32 pad, length; } List;

#define RVA_IN 0x17F8B0
#define RVA_LIST_OF 0x2044A0
#define LIST_TYPE 0x0F
#define NUM_TYPE 0x2A

static unsigned char *core, *tramp;
static const unsigned char PROLOGUE[6] = {0x55, 0x8B, 0xEC, 0x83, 0xEC, 0x40};
static char out[256];
static unsigned long long n_lists, n_tree_hit, n_scan;
static char (__cdecl *orig_in)(u32, u32, u32, u32);
static List *(__cdecl *list_of)(u32);

/* 24CC60's order: <0 key before node, 0 same, >0 after */
static __forceinline int order(u32 kt, u32 kv, const Node *n) {
    unsigned char a = (unsigned char)kt, b = (unsigned char)n->ktype;
    if (a != b) return a < b ? -1 : 1;
    if (a == NUM_TYPE) {
        float x, y; memcpy(&x, &kv, 4); memcpy(&y, &n->kval, 4);
        if (y > x) return -1;
        if (x > y) return 1;
        return 0;
    }
    if (kv != n->kval) return kv < n->kval ? -1 : 1;
    return 0;
}

static char __cdecl my_in(u32 kt, u32 kv, u32 ct, u32 cv) {
    if ((unsigned char)ct == LIST_TYPE) {
        List *l = list_of(cv);
        n_lists++;
        if (l) {
            Node *n = l->root;
            while (n) {
                int c = order(kt, kv, n);
                if (!c) break;
                n = c < 0 ? n->left : n->right;
            }
            if (n && (unsigned char)n->ktype == (unsigned char)kt && n->kval == kv) { n_tree_hit++; return 1; }
        }
        n_scan++;
    }
    return orig_in(kt, kv, ct, cv);
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
    if (core[RVA_IN] == 0xE9) return "already installed";
    if (memcmp(core + RVA_IN, PROLOGUE, 6)) return "not the 516.1688 code this was written for";
    if (!tramp) {
        /* the six prologue bytes (three whole instructions, no relative addresses), then jmp to entry+6 */
        tramp = (unsigned char *)VirtualAlloc(0, 16, MEM_COMMIT | MEM_RESERVE, PAGE_EXECUTE_READWRITE);
        memcpy(tramp, PROLOGUE, 6);
        tramp[6] = 0xE9; *(int *)(tramp + 7) = (int)((core + RVA_IN + 6) - (tramp + 11));
        FlushInstructionCache(GetCurrentProcess(), tramp, 11);
    }
    orig_in = (void *)tramp;
    list_of = (void *)(core + RVA_LIST_OF);
    jmp[0] = 0xE9; *(int *)(jmp + 1) = (int)((unsigned char *)my_in - (core + RVA_IN + 5)); jmp[5] = 0x90;
    write_bytes(core + RVA_IN, jmp, 6);
    return "installed";
}

__declspec(dllexport) const char *uninstall(int argc, const char **argv) {
    (void)argc; (void)argv;
    if (!core || core[RVA_IN] != 0xE9) return "not installed";
    write_bytes(core + RVA_IN, PROLOGUE, 6);
    return "uninstalled";
}

__declspec(dllexport) const char *stats(int argc, const char **argv) {
    (void)argc; (void)argv;
    sprintf(out, "in on lists %llu: answered from the index %llu, scanned %llu", n_lists, n_tree_hit, n_scan);
    return out;
}

__declspec(dllexport) DWORD WINAPI thread_install(LPVOID p) { (void)p; return (DWORD)install(0, 0); }
__declspec(dllexport) DWORD WINAPI thread_uninstall(LPVOID p) { (void)p; return (DWORD)uninstall(0, 0); }
__declspec(dllexport) DWORD WINAPI thread_stats(LPVOID p) { (void)p; return (DWORD)stats(0, 0); }
