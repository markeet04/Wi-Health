/* dsp_waveform.c — Stage 05 implementation. See dsp_waveform.h. */
#include "dsp_waveform.h"
#include "savgol_coeffs.h"

#include <math.h>
#include <stdlib.h>
#include <stddef.h>

static int cmp_double(const void *a, const void *b) {
    double da = *(const double *)a, db = *(const double *)b;
    return (da < db) ? -1 : (da > db) ? 1 : 0;
}

static double median_sorted_copy(double *buf, int m) {
    qsort(buf, (size_t)m, sizeof(double), cmp_double);
    if (m & 1) return buf[m / 2];
    return 0.5 * (buf[m / 2 - 1] + buf[m / 2]);
}

/* Hampel: centered rolling window, edges shrink (min_periods=1). For each i,
 * take the window [i-half, i+half] clamped to [0,n); median = med; MAD =
 * median(|w - median(w)|) with MAD floored to 1e-9; replace x[i] with med if
 * |x[i]-med| > threshold*MAD. Matches _hampel() in cscr.py. */
void dsp_hampel(const float *src, int n, int window, double threshold,
                float *dst) {
    if (n < window) {
        for (int i = 0; i < n; i++) dst[i] = src[i];
        return;
    }
    int half = window / 2;
    double *wbuf = (double *)malloc((size_t)window * sizeof(double));
    double *dbuf = (double *)malloc((size_t)window * sizeof(double));
    if (!wbuf || !dbuf) { free(wbuf); free(dbuf); return; }

    for (int i = 0; i < n; i++) {
        int lo = i - half; if (lo < 0) lo = 0;
        int hi = i + half; if (hi > n - 1) hi = n - 1;
        int m = hi - lo + 1;
        for (int k = 0; k < m; k++) wbuf[k] = (double)src[lo + k];
        /* median of window */
        for (int k = 0; k < m; k++) dbuf[k] = wbuf[k];   /* copy, wbuf sorted next */
        double med = median_sorted_copy(dbuf, m);
        /* MAD = median(|w - med|) */
        for (int k = 0; k < m; k++) dbuf[k] = fabs(wbuf[k] - med);
        double mad = median_sorted_copy(dbuf, m);
        if (mad <= 0.0) mad = 1e-9;
        double x = (double)src[i];
        if (fabs(x - med) > threshold * mad) {
            dst[i] = (float)med;
        } else {
            dst[i] = src[i];
        }
    }
    free(wbuf); free(dbuf);
}

/* Savitzky-Golay, scipy mode='interp': interior via SAVGOL_INTERIOR centered;
 * first SAVGOL_HALF outputs via SAVGOL_EDGE[pos] over samples [0,WIN); last
 * SAVGOL_HALF outputs via the reversed edge kernels over the last WIN samples.
 * If n < WIN, scipy would reduce the window; the pipeline guards win>=5 and
 * only applies savgol when combined.size is large, so we require n >= WIN. */
static void savgol(const float *src, int n, float *dst) {
    if (n < SAVGOL_WIN) {
        for (int i = 0; i < n; i++) dst[i] = src[i];
        return;
    }
    int half = SAVGOL_HALF;

    /* leading edge: output i (0..half-1) = sum_k EDGE[i][k] * src[k] */
    for (int i = 0; i < half; i++) {
        double acc = 0.0;
        for (int k = 0; k < SAVGOL_WIN; k++)
            acc += (double)SAVGOL_EDGE[i][k] * (double)src[k];
        dst[i] = (float)acc;
    }
    /* interior: output i (half..n-half-1) centered kernel */
    for (int i = half; i < n - half; i++) {
        double acc = 0.0;
        int base = i - half;
        for (int k = 0; k < SAVGOL_WIN; k++)
            acc += (double)SAVGOL_INTERIOR[k] * (double)src[base + k];
        dst[i] = (float)acc;
    }
    /* trailing edge: output i (n-half..n-1). Position from the end is
     * pe = n-1-i (0..half-1); scipy uses savgol_coeffs(win, order, pos=win-1-pe)
     * over the last WIN samples, which equals the reversed EDGE[pe] kernel
     * applied to the last WIN samples in reverse. Equivalent formulation:
     * dst[n-1-pe] = sum_k EDGE[pe][k] * src[n-1-k]. */
    for (int pe = 0; pe < half; pe++) {
        int i = n - 1 - pe;
        double acc = 0.0;
        for (int k = 0; k < SAVGOL_WIN; k++)
            acc += (double)SAVGOL_EDGE[pe][k] * (double)src[n - 1 - k];
        dst[i] = (float)acc;
    }
}

int dsp_waveform(const float *cscr, int n, int p, float *out, float *work) {
    if (n <= 0 || p <= 0) {
        for (int i = 0; i < n; i++) out[i] = 0.0f;
        return 0;
    }

    /* --- step 2: per-column normalize (real part), then average ---
     * numpy casts real to float32 and reduces in float32, so accumulate the
     * per-column mean/std in float to match. */
    float *combined = (float *)malloc((size_t)n * sizeof(float));
    if (!combined) return 0;
    for (int i = 0; i < n; i++) combined[i] = 0.0f;

    for (int c = 0; c < p; c++) {
        /* mean of column c real part (float32 accumulation) */
        float mean = 0.0f;
        for (int r = 0; r < n; r++)
            mean += cscr[((size_t)r * p + c) * 2 + 0];
        mean /= (float)n;
        float var = 0.0f;
        for (int r = 0; r < n; r++) {
            float d = cscr[((size_t)r * p + c) * 2 + 0] - mean;
            var += d * d;
        }
        var /= (float)n;              /* population variance (ddof=0) */
        float sd = sqrtf(var);
        if (sd < 1e-9f) sd = 1.0f;
        for (int r = 0; r < n; r++) {
            float v = (cscr[((size_t)r * p + c) * 2 + 0] - mean) / sd;
            combined[r] += v;
        }
    }
    for (int r = 0; r < n; r++) combined[r] /= (float)p;   /* mean across cols */

    /* --- step 3: Hampel --- */
    int own_work = 0;
    if (!work) { work = (float *)malloc((size_t)n * sizeof(float)); own_work = 1; }
    if (!work) { free(combined); return 0; }
    dsp_hampel(combined, n, 5, 3.0, work);   /* work = hampel(combined) */

    /* --- step 4: Savgol (window 21, order 3) into out ---
     * Python only applies savgol when win>=order+2 and win>=5; with win=21
     * that needs n>=21. Below that it returns the Hampel output unchanged. */
    if (n >= SAVGOL_WIN) {
        savgol(work, n, out);
    } else {
        for (int i = 0; i < n; i++) out[i] = work[i];
    }

    if (own_work) free(work);
    free(combined);
    return n;
}
