/* Prototype: byondcore 516.1688's runtime string lookup by hash instead of its unbalanced strcmp tree.

   byondcore keeps every runtime string as a node (+0 char*, +4 id, +8 left, +0C right, +10 refcount) in a binary
   tree under a sentinel node, table[0], whose right subtree holds every string. One function (rva 213580) finds a
   string by content: it returns the node or 0, and hands back the link that points (or would point) at it. New
   strings are linked at that link by the caller; a string whose count reaches 0 is found the same way and spliced
   out through the link (a plain BST delete). 213890 rebuilds the whole tree from the string table.

   This replaces both. The tree becomes a chain: sentinel.right -> first, then each node's left -> the next, right
   always 0. Under that shape the engine's own insert (write the link) and delete (splice through the link) keep it a
   chain. A hash map (FNV-1a of the bytes) finds a node, and a doubly-linked list beside the chain gives the link
   that points at it. Nodes the engine appended at the tail are picked up at the start of the next lookup; a delete
   is seen at its lookup (called from the release path, returning the node itself), just before the splice.

   call_ext("string_hash.dll", "install")() / ("uninstall")() / ("stats")(). Only from DM code, which is a point
   where no lookup is in progress. uninstall puts the code back and has the engine rebuild its tree. */
#include <windows.h>
#include <intrin.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct Node { const char *str; unsigned id; struct Node *left, *right; int refcount; } Node;
typedef struct Ent { Node *node; unsigned h; struct Ent *bnext, *prev, *next; } Ent;

#define RVA_FIND 0x213580
#define RVA_REBUILD 0x213890
#define RVA_TABLE 0x430BF0
#define RVA_COUNT 0x430BF4
#define RVA_RELEASE_RET 0x221E89  /* return address of the release path's first lookup */

static unsigned char *core;
static Ent **buckets, *head, *tail, *spare;
static unsigned nbuckets, nents;
static unsigned long long n_find, n_hit, n_new_seen, n_del, n_probe, n_rebuild;
static const unsigned char PROLOGUE[5] = {0x55, 0x8B, 0xEC, 0x6A, 0xFF};
static char out[512];

static Node *sentinel(void) { return (*(Node ***)(core + RVA_TABLE))[0]; }

static unsigned fnv(const char *s) {
    unsigned h = 2166136261u;
    while (*s) h = (h ^ (unsigned char)*s++) * 16777619u;
    return h;
}

static Ent *new_ent(void) {
    Ent *e = spare;
    if (e) spare = e->next; else e = (Ent *)malloc(sizeof(Ent));
    return e;
}

static void grow(void) {
    unsigned n = nbuckets ? nbuckets * 2 : 1u << 20, i;
    Ent **b = (Ent **)calloc(n, sizeof(Ent *));
    for (i = 0; i < nbuckets; i++) {
        Ent *e = buckets[i], *nx;
        for (; e; e = nx) { nx = e->bnext; e->bnext = b[e->h & (n - 1)]; b[e->h & (n - 1)] = e; }
    }
    free(buckets); buckets = b; nbuckets = n;
}

static Ent *lookup(const char *s, unsigned h) {
    Ent *e = buckets[h & (nbuckets - 1)];
    for (; e; e = e->bnext) { n_probe++; if (e->h == h && strcmp(e->node->str, s) == 0) return e; }
    return 0;
}

/* add n at the tail of the list (the chain already has it there) */
static void append(Node *n) {
    Ent *e = new_ent();
    if (nents + 1 > nbuckets / 4 * 3) grow();
    e->node = n; e->h = fnv(n->str);
    e->bnext = buckets[e->h & (nbuckets - 1)]; buckets[e->h & (nbuckets - 1)] = e;
    e->prev = tail; e->next = 0;
    if (tail) tail->next = e; else head = e;
    tail = e; nents++;
}

static void drop(Ent *e) {
    Ent **p = &buckets[e->h & (nbuckets - 1)];
    while (*p != e) p = &(*p)->bnext;
    *p = e->bnext;
    if (e->prev) e->prev->next = e->next; else head = e->next;
    if (e->next) e->next->prev = e->prev; else tail = e->prev;
    nents--; e->next = spare; spare = e;
}

static void clear(void) {
    while (head) drop(head);
}

/* pick up nodes the engine linked at the tail since the last call */
static void catch_up(void) {
    Node *n = tail ? tail->node->left : sentinel()->right;
    for (; n; n = n->left) { append(n); n_new_seen++; }
}

/* the lookup: same contract as 213580 */
static Node *__cdecl find(Node *key, Node ***slot) {
    unsigned h; Ent *e; Node *s = sentinel();
    n_find++;
    catch_up();
    if (!key->str[0] && !s->str[0]) { *slot = 0; return s; }
    h = fnv(key->str);
    e = lookup(key->str, h);
    if (!e) { *slot = tail ? &tail->node->left : &s->right; return 0; }
    n_hit++;
    *slot = e->prev ? &e->prev->node->left : &s->right;
    if (e->node == key && (unsigned char *)_ReturnAddress() == core + RVA_RELEASE_RET) { drop(e); n_del++; }
    return e->node;
}

/* relink every node in order as the chain and rebuild the map. nodes: the live strings to keep, in order. */
static void chain(Node **nodes, unsigned n) {
    unsigned i; Node *s = sentinel();
    clear();
    for (i = 0; i < n; i++) { nodes[i]->left = i + 1 < n ? nodes[i + 1] : 0; nodes[i]->right = 0; }
    s->right = n ? nodes[0] : 0;
    for (i = 0; i < n; i++) append(nodes[i]);
}

/* the rebuild: same job as 213890 (every live, non-empty string in the table, one node per content) */
static void __cdecl rebuild(void) {
    Node **table = *(Node ***)(core + RVA_TABLE);
    unsigned count = *(unsigned *)(core + RVA_COUNT), i, n = 0;
    Node **keep = (Node **)malloc(sizeof(Node *) * (count + 1));
    n_rebuild++;
    clear();
    for (i = 1; i < count; i++) {
        Node *x = table[i];
        if (x && x->str && x->str[0] && !lookup(x->str, fnv(x->str))) { keep[n++] = x; append(x); }
    }
    chain(keep, n);
    free(keep);
}

static int write_jmp(unsigned rva, void *to) {
    DWORD old; unsigned char *at = core + rva;
    if (VirtualProtect(at, 5, PAGE_EXECUTE_READWRITE, &old) == 0) return 0;
    at[0] = 0xE9; *(int *)(at + 1) = (int)((unsigned char *)to - (at + 5));
    VirtualProtect(at, 5, old, &old);
    FlushInstructionCache(GetCurrentProcess(), at, 5);
    return 1;
}

static void put_back(unsigned rva) {
    DWORD old; unsigned char *at = core + rva;
    VirtualProtect(at, 5, PAGE_EXECUTE_READWRITE, &old);
    memcpy(at, PROLOGUE, 5);
    VirtualProtect(at, 5, old, &old);
    FlushInstructionCache(GetCurrentProcess(), at, 5);
}

__declspec(dllexport) const char *install(int argc, const char **argv) {
    unsigned cap = 1 << 16, n = 0, sp = 0, depth_max = 0;
    Node **nodes, **stack; Node *x;
    (void)argc; (void)argv;
    core = (unsigned char *)GetModuleHandleA("byondcore.dll");
    if (!core) return "no byondcore.dll";
    if (core[RVA_FIND] == 0xE9) return "already installed";
    if (memcmp(core + RVA_FIND, PROLOGUE, 5) || memcmp(core + RVA_REBUILD, PROLOGUE, 5))
        return "not the 516.1688 code this was written for";
    /* every node under the sentinel's right link, in order (iterative: the tree can be hundreds deep) */
    nodes = (Node **)malloc(sizeof(Node *) * cap);
    stack = (Node **)malloc(sizeof(Node *) * 65536);
    x = sentinel()->right;
    while (x || sp) {
        while (x) { stack[sp++] = x; if (sp > depth_max) depth_max = sp; x = x->left; }
        x = stack[--sp];
        if (n == cap) { cap *= 2; nodes = (Node **)realloc(nodes, sizeof(Node *) * cap); }
        nodes[n++] = x;
        x = x->right;
    }
    free(stack);
    if (!buckets) grow();
    chain(nodes, n);
    free(nodes);
    write_jmp(RVA_FIND, (void *)find);
    write_jmp(RVA_REBUILD, (void *)rebuild);
    sprintf(out, "installed: %u strings chained, tree was %u deep", n, depth_max);
    return out;
}

__declspec(dllexport) const char *uninstall(int argc, const char **argv) {
    (void)argc; (void)argv;
    if (!core || core[RVA_FIND] != 0xE9) return "not installed";
    put_back(RVA_FIND);
    put_back(RVA_REBUILD);
    clear();
    ((void (__cdecl *)(void))(core + RVA_REBUILD))();
    return "uninstalled: tree rebuilt by the engine";
}

__declspec(dllexport) const char *stats(int argc, const char **argv) {
    (void)argc; (void)argv;
    sprintf(out, "strings %u, buckets %u, lookups %llu (found %llu, %.2f probes each), new seen %llu, deletes %llu, rebuilds %llu",
            nents, nbuckets, n_find, n_hit, n_find ? (double)n_probe / n_find : 0.0, n_new_seen, n_del, n_rebuild);
    return out;
}

/* For inject.py: thread entry points (run while every other thread is suspended away from string code). The exit
   code is the address of the result text. */
__declspec(dllexport) DWORD WINAPI thread_install(LPVOID p) { (void)p; return (DWORD)install(0, 0); }
__declspec(dllexport) DWORD WINAPI thread_uninstall(LPVOID p) { (void)p; return (DWORD)uninstall(0, 0); }
__declspec(dllexport) DWORD WINAPI thread_stats(LPVOID p) { (void)p; return (DWORD)stats(0, 0); }
