/* dsp_pairs.c — Stage 03 implementation. See dsp_pairs.h.
 *
 * Correctness-first host port. Direct DFT (O(n^2)) for the score spectrum —
 * matches numpy.fft magnitudes closely enough that the well-separated ranking
 * (see score gaps in the reference) reproduces the same selected pairs. The
 * on-device version will replace the DFT with ESP-DSP and cache pairs.
 */
#include "dsp_pairs.h"
#include "dsp_fft.h"

#include <math.h>
#include <stdlib.h>

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

/* median of |denom| across packets, to skip near-null denominators (Python
 * skips a candidate whose median denom amplitude < 1e-3). */
static int cmp_double(const void *a, const void *b) {
    double da = *(const double *)a, db = *(const double *)b;
    return (da < db) ? -1 : (da > db) ? 1 : 0;
}

static double median_amp_col(const float *H, int n, int s, int col, double *scratch) {
    for (int r = 0; r < n; r++) {
        double re = (double)H[(size_t)r * s * 2 + (size_t)col * 2 + 0];
        double im = (double)H[(size_t)r * s * 2 + (size_t)col * 2 + 1];
        scratch[r] = sqrt(re * re + im * im);
    }
    qsort(scratch, (size_t)n, sizeof(double), cmp_double);
    if (n & 1) return scratch[n / 2];
    return 0.5 * (scratch[n / 2 - 1] + scratch[n / 2]);
}

/* pair_snr — SNR proxy for one candidate: real-part of the CSCR ratio,
 * zero-meaned, magnitude spectrum via the fast radix-2 FFT (zero-padded to
 * `nfft`), scored as peak-in-band / mean-magnitude.
 *
 * The original scored an exact n-point DFT (O(n^2)); on the ESP32-S3 (no
 * hardware double FPU) that took ~7.7 min for 3000 candidates. This uses the
 * O(n log n) FFT instead. Zero-padding to a power of two shifts the bin grid
 * slightly, so the absolute scores differ from the exact-DFT version, but the
 * ranking (which pairs are best) is what selection uses and it is preserved —
 * re-verified against the golden. `mag` is caller scratch >= nfft/2+1 doubles;
 * `xm` is caller scratch >= n doubles. */
static double pair_snr(const double *xr, int n, double low_hz, double high_hz,
                       double rate, int nfft, double *xm, double *mag) {
    if (n < 16) return 0.0;
    double mean = 0.0;
    for (int k = 0; k < n; k++) mean += xr[k];
    mean /= n;
    double var = 0.0;
    for (int k = 0; k < n; k++) { double d = xr[k] - mean; var += d * d; }
    if (sqrt(var / n) < 1e-9) return 0.0;

    for (int k = 0; k < n; k++) xm[k] = xr[k] - mean;
    dsp_rfft_mag(xm, n, nfft, mag);   /* |rFFT| over nfft bins, bins 0..nfft/2 */

    int nb = nfft / 2 + 1;
    double df = rate / (double)nfft;
    double sum_mag = 0.0, peak_in_band = 0.0;
    for (int k = 0; k < nb; k++) {
        sum_mag += mag[k];
        double f = (double)k * df;
        if (f >= low_hz && f <= high_hz && mag[k] > peak_in_band) peak_in_band = mag[k];
    }
    double mean_mag = sum_mag / (double)nb + 1e-12;
    if (peak_in_band <= 0.0) return 0.0;
    return peak_in_band / mean_mag;
}

static int next_pow2_i(int v) { int p = 1; while (p < v) p <<= 1; return p; }

typedef struct { double score; int i; int j; int order; } scored_t;

/* sort: score descending; ties keep original candidate order (stable) —
 * matches Python list.sort(key=score, reverse=True) on an in-order list. */
static int cmp_scored(const void *a, const void *b) {
    const scored_t *x = (const scored_t *)a, *y = (const scored_t *)b;
    if (x->score > y->score) return -1;
    if (x->score < y->score) return 1;
    return (x->order < y->order) ? -1 : (x->order > y->order) ? 1 : 0;
}

int dsp_select_pairs(const float *H, int n, int s, int num_pairs,
                     double low_hz, double high_hz, double rate,
                     int *out_i, int *out_j) {
    if (s < 4 || n < 16) return 0;

    int nfft = next_pow2_i(n);
    double *scratch = (double *)malloc((size_t)n * sizeof(double));
    double *xr = (double *)malloc((size_t)n * sizeof(double));
    double *xm = (double *)malloc((size_t)n * sizeof(double));
    double *mag = (double *)malloc((size_t)(nfft / 2 + 1) * sizeof(double));
    scored_t *scored = (scored_t *)malloc(
        (size_t)DSP_PAIRS_MAX_CANDIDATES * sizeof(scored_t));
    if (!scratch || !xr || !xm || !mag || !scored) {
        free(scratch); free(xr); free(xm); free(mag); free(scored);
        return 0;
    }

    /* Precompute median |col| once per column (reused as denom test). */
    double *col_med = (double *)malloc((size_t)s * sizeof(double));
    for (int c = 0; c < s; c++) col_med[c] = median_amp_col(H, n, s, c, scratch);

    int cand = 0;   /* candidate counter (i-outer, j-inner), capped */
    int nscored = 0;
    for (int i = 0; i < s && cand < DSP_PAIRS_MAX_CANDIDATES; i++) {
        for (int j = 0; j < s; j++) {
            if (i == j) continue;
            if (cand >= DSP_PAIRS_MAX_CANDIDATES) break;
            int order = cand;   /* candidate-generation order for stable ties */
            cand++;

            if (col_med[j] < 1e-3) continue;  /* skip near-null denom */

            /* CSCR real part: Re( H[:,i] / H[:,j] ) with the same eps guard.
             * (a+bi)/(c+di) = ((ac+bd) + (bc-ad)i)/(c^2+d^2). */
            for (int r = 0; r < n; r++) {
                double a = (double)H[(size_t)r * s * 2 + (size_t)i * 2 + 0];
                double b = (double)H[(size_t)r * s * 2 + (size_t)i * 2 + 1];
                double c = (double)H[(size_t)r * s * 2 + (size_t)j * 2 + 0];
                double d = (double)H[(size_t)r * s * 2 + (size_t)j * 2 + 1];
                double den = c * c + d * d;
                if (sqrt(den) < 1e-6) { c = 1e-6; d = 0.0; den = 1e-12; }
                xr[r] = (a * c + b * d) / den;   /* real part only */
            }

            double sc = pair_snr(xr, n, low_hz, high_hz, rate, nfft, xm, mag);
            if (sc > 0.0) {
                scored[nscored].score = sc;
                scored[nscored].i = i;
                scored[nscored].j = j;
                scored[nscored].order = order;
                nscored++;
            }
        }
    }

    qsort(scored, (size_t)nscored, sizeof(scored_t), cmp_scored);

    int out = (num_pairs < nscored) ? num_pairs : nscored;
    for (int k = 0; k < out; k++) {
        out_i[k] = scored[k].i;
        out_j[k] = scored[k].j;
    }

    free(scratch); free(xr); free(xm); free(mag); free(scored); free(col_med);
    return out;
}
