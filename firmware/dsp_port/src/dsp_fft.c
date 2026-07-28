/* dsp_fft.c — radix-2 complex FFT + helpers. See dsp_fft.h. */
#include "dsp_fft.h"

#include <math.h>
#include <stdlib.h>
#include <stddef.h>

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

/* In-place iterative radix-2 DIT FFT. n must be a power of two.
 * sign = -1 for forward, +1 for inverse (inverse is NOT scaled by 1/n here;
 * callers that need the inverse scale it themselves). */
void dsp_fft(double *re, double *im, int n, int sign) {
    /* bit-reversal permutation */
    for (int i = 1, j = 0; i < n; i++) {
        int bit = n >> 1;
        for (; j & bit; bit >>= 1) j ^= bit;
        j ^= bit;
        if (i < j) {
            double tr = re[i]; re[i] = re[j]; re[j] = tr;
            double ti = im[i]; im[i] = im[j]; im[j] = ti;
        }
    }
    for (int len = 2; len <= n; len <<= 1) {
        double ang = sign * 2.0 * M_PI / (double)len;
        double wr = cos(ang), wi = sin(ang);
        for (int i = 0; i < n; i += len) {
            double cr = 1.0, ci = 0.0;
            for (int k = 0; k < len / 2; k++) {
                int a = i + k, b = i + k + len / 2;
                double xr = re[b] * cr - im[b] * ci;
                double xi = re[b] * ci + im[b] * cr;
                re[b] = re[a] - xr;
                im[b] = im[a] - xi;
                re[a] += xr;
                im[a] += xi;
                double ncr = cr * wr - ci * wi;
                ci = cr * wi + ci * wr;
                cr = ncr;
            }
        }
    }
}

void dsp_rfft_mag(const double *x, int m, int nfft, double *mag) {
    double *re = (double *)calloc((size_t)nfft, sizeof(double));
    double *im = (double *)calloc((size_t)nfft, sizeof(double));
    if (!re || !im) { free(re); free(im); return; }
    for (int i = 0; i < m; i++) re[i] = x[i];   /* zero-padded */
    dsp_fft(re, im, nfft, -1);
    int nb = nfft / 2 + 1;
    for (int k = 0; k < nb; k++) {
        mag[k] = sqrt(re[k] * re[k] + im[k] * im[k]);
    }
    free(re); free(im);
}

void dsp_autocorr(const double *x, int n, int nfft, double *ac) {
    double *re = (double *)calloc((size_t)nfft, sizeof(double));
    double *im = (double *)calloc((size_t)nfft, sizeof(double));
    if (!re || !im) { free(re); free(im); return; }
    for (int i = 0; i < n; i++) re[i] = x[i];   /* zero-padded */
    dsp_fft(re, im, nfft, -1);                   /* F = fft(x) */
    /* power spectrum F * conj(F) = |F|^2 (real, imag 0) */
    for (int k = 0; k < nfft; k++) {
        double p = re[k] * re[k] + im[k] * im[k];
        re[k] = p;
        im[k] = 0.0;
    }
    dsp_fft(re, im, nfft, +1);                   /* inverse (unscaled) */
    /* numpy irfft scales by 1/nfft */
    for (int i = 0; i < n; i++) ac[i] = re[i] / (double)nfft;
    free(re); free(im);
}
