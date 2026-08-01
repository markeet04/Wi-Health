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
 * FLOAT32 throughout: this is called for every candidate (thousands), and the
 * ESP32-S3 does double in SOFTWARE but float in HARDWARE, so double scoring
 * took ~80 s on-device. Float is ~10-40x faster and only the ranking of scores
 * matters here (the estimator that computes the final bpm still uses double).
 * `mag`,`fre`,`fim` are caller scratch of length >= nfft/2+1 (mag) / nfft
 * (fre,fim); `xm` caller scratch >= n floats. */
static float pair_snr(const float *xr, int n, float low_hz, float high_hz,
                      float rate, int nfft, float *xm, float *mag,
                      float *fre, float *fim) {
    if (n < 16) return 0.0f;
    float mean = 0.0f;
    for (int k = 0; k < n; k++) mean += xr[k];
    mean /= n;
    float var = 0.0f;
    for (int k = 0; k < n; k++) { float d = xr[k] - mean; var += d * d; }
    if (sqrtf(var / n) < 1e-9f) return 0.0f;

    for (int k = 0; k < n; k++) xm[k] = xr[k] - mean;
    dsp_rfft_mag_f(xm, n, nfft, mag, fre, fim);

    int nb = nfft / 2 + 1;
    float df = rate / (float)nfft;
    float sum_mag = 0.0f, peak_in_band = 0.0f;
    for (int k = 0; k < nb; k++) {
        sum_mag += mag[k];
        float f = (float)k * df;
        if (f >= low_hz && f <= high_hz && mag[k] > peak_in_band) peak_in_band = mag[k];
    }
    float mean_mag = sum_mag / (float)nb + 1e-12f;
    if (peak_in_band <= 0.0f) return 0.0f;
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
    double *scratch = (double *)malloc((size_t)n * sizeof(double));  /* median (double) */
    float  *xr  = (float *)malloc((size_t)n * sizeof(float));        /* CSCR real part */
    float  *xm  = (float *)malloc((size_t)n * sizeof(float));        /* zero-meaned */
    float  *mag = (float *)malloc((size_t)(nfft / 2 + 1) * sizeof(float));
    float  *fre = (float *)malloc((size_t)nfft * sizeof(float));     /* FFT scratch */
    float  *fim = (float *)malloc((size_t)nfft * sizeof(float));
    scored_t *scored = (scored_t *)malloc(
        (size_t)DSP_PAIRS_MAX_CANDIDATES * sizeof(scored_t));
    if (!scratch || !xr || !xm || !mag || !fre || !fim || !scored) {
        free(scratch); free(xr); free(xm); free(mag); free(fre); free(fim); free(scored);
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
             * (a+bi)/(c+di) = ((ac+bd) + (bc-ad)i)/(c^2+d^2). Float32. */
            for (int r = 0; r < n; r++) {
                float a = H[(size_t)r * s * 2 + (size_t)i * 2 + 0];
                float b = H[(size_t)r * s * 2 + (size_t)i * 2 + 1];
                float c = H[(size_t)r * s * 2 + (size_t)j * 2 + 0];
                float d = H[(size_t)r * s * 2 + (size_t)j * 2 + 1];
                float den = c * c + d * d;
                if (sqrtf(den) < 1e-6f) { c = 1e-6f; d = 0.0f; den = 1e-12f; }
                xr[r] = (a * c + b * d) / den;   /* real part only */
            }

            float sc = pair_snr(xr, n, (float)low_hz, (float)high_hz, (float)rate,
                                nfft, xm, mag, fre, fim);
            if (sc > 0.0f) {
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

    free(scratch); free(xr); free(xm); free(mag); free(fre); free(fim);
    free(scored); free(col_med);
    return out;
}
