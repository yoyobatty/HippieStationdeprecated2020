/* Exhaustive check of numfmt_core.h against the CRT: every 32-bit float from 1e-5 to 2e6 (both signs, plus 0 and
   specials) through g6() and sprintf("%.6g"); every int in +-2^24 through put_int() and sprintf("%d").
   numfmt_check.exe -> prints mismatches (first 20), counts, and the fallback rate. */
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include "numfmt_core.h"

int main(void) {
    float lo = 1e-5f, hi = 2e6f;
    unsigned a, b; long long u, ua, ub;
    long long bad = 0, fallback = 0, total = 0, badint = 0;
    memcpy(&a, &lo, 4); memcpy(&b, &hi, 4); ua = a; ub = b;
#pragma omp parallel for reduction(+:bad, fallback, total) schedule(dynamic, 65536)
    for (u = ua; u <= ub; u++) {
        for (int sign = 0; sign < 2; sign++) {
            unsigned bits = (unsigned)u | (sign ? 0x80000000u : 0); float f; char x[64], y[64];
            memcpy(&f, &bits, 4);
            total++;
            if (!g6((double)f, x)) { fallback++; continue; }
            sprintf(y, "%.6g", (double)f);
            if (strcmp(x, y)) {
#pragma omp critical
                { if (bad < 20) printf("float %.9g: mine %s crt %s\n", (double)f, x, y); }
                bad++;
            }
        }
    }
    {
        static const float sp[] = {0.0f, -0.0f, 1.0f / 0.0f, -1.0f / 0.0f};
        for (int i = 0; i < 4; i++) {
            char x[64], y[64]; int ok = g6((double)sp[i], x);
            sprintf(y, "%.6g", (double)sp[i]);
            if (ok && strcmp(x, y)) { printf("special: mine %s crt %s\n", x, y); bad++; }
        }
        float nan = sp[2] - sp[2]; char x[64];
        if (g6((double)nan, x)) { printf("nan not left to sprintf\n"); bad++; }
    }
    for (int v = -(1 << 24); v <= (1 << 24); v++) {
        char x[16], y[16];
        put_int(x, v); sprintf(y, "%d", v);
        if (strcmp(x, y)) { if (badint < 20) printf("int %d: mine %s crt %s\n", v, x, y); badint++; }
    }
    printf("floats %lld: %lld differ, %lld left to sprintf (%.3f%%); ints %d: %lld differ\n",
           total, bad, fallback, 100.0 * fallback / total, (1 << 25) + 1, badint);
    return bad || badint;
}
