/* dsp_frontend.c — fused null-drop + resample. See dsp_frontend.h.
 *
 * Equivalent to dsp_nulldrop() followed by dsp_resample(), but reading raw
 * int16 samples and emitting only the resampled matrix. The median-amplitude
 * keep test and the linear-interpolation grid are identical to those stages.
 */
#include "dsp_frontend.h"

#include <math.h>
#include <stdlib.h>
#include <stddef.h>

static int cmp_double(const void *a, const void *b) {
    double da = *(const double *)a, db = *(const double *)b;
    return (da < db) ? -1 : (da > db) ? 1 : 0;
}

static double median_double(double *v, int n) {
    qsort(v, (size_t)n, sizeof(double), cmp_double);
    if (n & 1) return v[n / 2];
    return 0.5 * (v[n / 2 - 1] + v[n / 2]);
}

int dsp_frontend(const int16_t *re, const int16_t *im, const double *ts,
                 int n, int s_raw, float threshold, double rate,
                 float *Huni, int *kept_idx, int *s_kept,
                 int n_out_max, double *scratch_med) {
    *s_kept = 0;
    if (n < 2 || s_raw <= 0) return 0;

    /* --- null-drop: keep subcarriers with median |H| > threshold --- */
    int kept = 0;
    for (int c = 0; c < s_raw; c++) {
        for (int r = 0; r < n; r++) {
            double a = (double)re[(size_t)r * s_raw + c];
            double b = (double)im[(size_t)r * s_raw + c];
            scratch_med[r] = sqrt(a * a + b * b);
        }
        double med = median_double(scratch_med, n);
        if (med > (double)threshold) {
            kept_idx[kept++] = c;
        }
    }
    if (kept < 1) return 0;
    *s_kept = kept;

    /* --- resample: dedup timestamps (keep first of equal run), build the
     * uniform grid, and linear-interpolate each kept subcarrier. This mirrors
     * _resample_complex_uniform exactly. We two-pointer over the deduped
     * source indices. --- */
    /* build deduped index list */
    int *idx = (int *)malloc((size_t)n * sizeof(int));
    if (!idx) return -1;
    int m = 0;
    idx[m++] = 0;
    for (int k = 1; k < n; k++) {
        if (ts[k] > ts[idx[m - 1]]) idx[m++] = k;
    }
    if (m < 2) { free(idx); return 0; }

    double dt = 1.0 / rate;
    double t0 = ts[idx[0]];
    double tN = ts[idx[m - 1]];
    double start = ceil(t0 / dt) * dt;
    double stop = floor(tN / dt) * dt;
    if (stop < start) { free(idx); return 0; }
    int n_out = (int)lround((stop - start) / dt) + 1;
    if (n_out <= 0) { free(idx); return 0; }
    if (n_out > n_out_max) { free(idx); return -1; }

    int p = 0;
    for (int g = 0; g < n_out; g++) {
        double gt = start + dt * (double)g;
        while (p + 1 < m - 1 && ts[idx[p + 1]] < gt) p++;
        int ia = idx[p], ib = idx[p + 1];
        double ta = ts[ia], tb = ts[ib];
        double frac = (tb > ta) ? (gt - ta) / (tb - ta) : 0.0;
        for (int w = 0; w < kept; w++) {
            int c = kept_idx[w];
            double ra = (double)re[(size_t)ia * s_raw + c];
            double ia_ = (double)im[(size_t)ia * s_raw + c];
            double rb = (double)re[(size_t)ib * s_raw + c];
            double ib_ = (double)im[(size_t)ib * s_raw + c];
            double rr = ra + frac * (rb - ra);
            double ri = ia_ + frac * (ib_ - ia_);
            Huni[((size_t)g * kept + w) * 2 + 0] = (float)rr;
            Huni[((size_t)g * kept + w) * 2 + 1] = (float)ri;
        }
    }

    free(idx);
    return n_out;
}
