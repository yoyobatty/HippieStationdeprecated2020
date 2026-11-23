/* Prototype: byondcore 516.1688 turns numbers into text without printf.

   Three call sites are pointed at this DLL (their rel32 rewritten, nothing else touched):
     108A87  sprintf(buf, "%.6g", x)            number -> text (num2text, text conversion of a number Value)
     1B2A57  printf-append(sb, "%d", i)         "[x]" for a whole number below 2^24
     1B2A79  printf-append(sb, "%.6g", x)       "[x]" for anything else
     1826DE  sprintf(buf, "%.*g", digits, x)    num2text(x, digits): only digits = 6 (the default) is done here
   numfmt_core.h writes the same text as the CRT (numfmt_check.c compares all 630M floats from 1e-5 to 2e6 and all
   ints in +-2^24) and hands anything else back to the engine's own call.

   inject.py <pid> numfmt.dll thread_install | thread_stats | thread_uninstall */
#include <windows.h>
#include <stdio.h>
#include <string.h>
#include "numfmt_core.h"

#define RVA_FMT_G6 0x3AA8AC
#define RVA_SPRINTF 0x1DDB0
#define RVA_PRINTF_APPEND 0x282D70
#define RVA_APPEND 0x281460

typedef struct { unsigned site, target; void *mine; } Site;

static unsigned char *core;
static char out[512];
static unsigned long long n_fast, n_slow;
static int (__cdecl *crt_sprintf)(char *, const char *, ...);
static int (__cdecl *printf_append)(void *, const char *, ...);
static void (__fastcall *append)(void *sb, void *unused, const char *s);

static int __cdecl my_sprintf(char *buf, const char *fmt, double x) {
    if (fmt == (const char *)(core + RVA_FMT_G6)) {
        int n = g6(x, buf);
        if (n) { n_fast++; return n; }
    }
    n_slow++;
    return crt_sprintf(buf, fmt, x);
}

static int __cdecl my_sprintf_digits(char *buf, const char *fmt, int digits, double x) {
    if (digits == 6) {
        int n = g6(x, buf);
        if (n) { n_fast++; return n; }
    }
    n_slow++;
    return crt_sprintf(buf, fmt, digits, x);
}

static int __cdecl my_append_d(void *sb, const char *fmt, int v) {
    char t[16];
    (void)fmt;
    put_int(t, v);
    append(sb, 0, t);
    n_fast++;
    return 0;
}

static int __cdecl my_append_g(void *sb, const char *fmt, double x) {
    char t[32];
    if (g6(x, t)) { append(sb, 0, t); n_fast++; return 0; }
    n_slow++;
    return printf_append(sb, fmt, x);
}

static Site sites[] = {
    {0x108A87, RVA_SPRINTF, (void *)my_sprintf},
    {0x1B2A57, RVA_PRINTF_APPEND, (void *)my_append_d},
    {0x1B2A79, RVA_PRINTF_APPEND, (void *)my_append_g},
    {0x1826DE, RVA_SPRINTF, (void *)my_sprintf_digits},
};
#define NSITES (sizeof sites / sizeof sites[0])

static unsigned char *call_target(unsigned site) {
    unsigned char *at = core + site;
    return at + 5 + *(int *)(at + 1);
}

static void set_call(unsigned site, void *to) {
    DWORD old; unsigned char *at = core + site;
    VirtualProtect(at, 5, PAGE_EXECUTE_READWRITE, &old);
    *(int *)(at + 1) = (int)((unsigned char *)to - (at + 5));
    VirtualProtect(at, 5, old, &old);
    FlushInstructionCache(GetCurrentProcess(), at, 5);
}

__declspec(dllexport) const char *install(int argc, const char **argv) {
    unsigned i;
    (void)argc; (void)argv;
    core = (unsigned char *)GetModuleHandleA("byondcore.dll");
    if (!core) return "no byondcore.dll";
    if (call_target(sites[0].site) == (unsigned char *)sites[0].mine) return "already installed";
    for (i = 0; i < NSITES; i++)
        if (core[sites[i].site] != 0xE8 || call_target(sites[i].site) != core + sites[i].target)
            return "not the 516.1688 code this was written for";
    if (strcmp((const char *)core + RVA_FMT_G6, "%.6g")) return "format string moved";
    crt_sprintf = (void *)(core + RVA_SPRINTF);
    printf_append = (void *)(core + RVA_PRINTF_APPEND);
    append = (void *)(core + RVA_APPEND);
    for (i = 0; i < NSITES; i++) set_call(sites[i].site, sites[i].mine);
    return "installed";
}

__declspec(dllexport) const char *uninstall(int argc, const char **argv) {
    unsigned i;
    (void)argc; (void)argv;
    if (!core || call_target(sites[0].site) != (unsigned char *)sites[0].mine) return "not installed";
    for (i = 0; i < NSITES; i++) set_call(sites[i].site, core + sites[i].target);
    return "uninstalled";
}

__declspec(dllexport) const char *stats(int argc, const char **argv) {
    (void)argc; (void)argv;
    sprintf(out, "formatted %llu here, %llu handed to printf", n_fast, n_slow);
    return out;
}

__declspec(dllexport) DWORD WINAPI thread_install(LPVOID p) { (void)p; return (DWORD)install(0, 0); }
__declspec(dllexport) DWORD WINAPI thread_uninstall(LPVOID p) { (void)p; return (DWORD)uninstall(0, 0); }
__declspec(dllexport) DWORD WINAPI thread_stats(LPVOID p) { (void)p; return (DWORD)stats(0, 0); }
