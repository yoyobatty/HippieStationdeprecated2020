/* %.6g and %d without printf, for numbers that came from a 32-bit float. Shared by numfmt.c and numfmt_check.c.
   g6() writes the same text as sprintf("%.6g", x) or returns 0 when the caller must use sprintf: outside
   1e-4 <= |x| < 999999.5 (exponent notation), NaN and infinity, and within 1e-7 of a rounding tie, where the one
   rounding error of the scaling multiply could pick the other side. */
#include <math.h>

static const double P10[] = {1e0, 1e1, 1e2, 1e3, 1e4, 1e5, 1e6, 1e7, 1e8, 1e9, 1e10, 1e11};

static __inline char *put_uint(char *p, unsigned v) {
    char t[12]; int n = 0;
    do { t[n++] = (char)('0' + v % 10); v /= 10; } while (v);
    while (n) *p++ = t[--n];
    return p;
}

static __inline int put_int(char *out, int v) {
    char *p = out;
    if (v < 0) { *p++ = '-'; p = put_uint(p, 0u - (unsigned)v); } else p = put_uint(p, (unsigned)v);
    *p = 0;
    return (int)(p - out);
}

static __inline int g6(double x, char *out) {
    char *p = out, d[6]; double ax, scaled, fr; unsigned n; int e, i, last;
    if (x != x) return 0;
    ax = fabs(x);
    if (ax == 0) { if (signbit(x)) *p++ = '-'; *p++ = '0'; *p = 0; return (int)(p - out); }
    if (!(ax >= 1e-4 && ax < 999999.5)) return 0;
    for (e = 5; e > -5 && ax < (e >= 0 ? P10[e] : 1.0 / P10[-e]); e--) {}
    /* six significant digits: ax scaled into [1e5, 1e6), one rounding error */
    scaled = 5 - e >= 0 ? ax * P10[5 - e] : ax / P10[e - 5];
    n = (unsigned)scaled;
    fr = scaled - n;
    if (fabs(fr - 0.5) < 1e-7) return 0;
    if (fr > 0.5) n++;
    if (n < 100000) return 0;  /* the power search and the scaling disagreed: leave it to sprintf */
    if (n >= 1000000) { n /= 10; e++; if (e >= 6) return 0; }
    for (i = 5; i >= 0; i--) { d[i] = (char)('0' + n % 10); n /= 10; }
    for (last = 5; last > 0 && d[last] == '0' && last > e; last--) {}
    if (x < 0) *p++ = '-';
    if (e < 0) {
        *p++ = '0'; *p++ = '.';
        for (i = -1; i > e; i--) *p++ = '0';
        for (i = 0; i <= last; i++) *p++ = d[i];
    } else {
        for (i = 0; i <= e; i++) *p++ = d[i];
        if (last > e) { *p++ = '.'; for (i = e + 1; i <= last; i++) *p++ = d[i]; }
    }
    *p = 0;
    return (int)(p - out);
}
