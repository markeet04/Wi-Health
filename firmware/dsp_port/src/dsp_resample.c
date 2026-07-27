/* dsp_resample.c — Stage 02 implementation. See dsp_resample.h. */
#include "dsp_resample.h"

#include <math.h>
#include <stdlib.h>

int dsp_resample(const double *ts, const float *in, int n, int s, double rate,
                 float *out, float *out_grid, int n_out_max) {
    if (n < 2 || s <= 0) return 0;

    /* --- dedup timestamps, keeping the FIRST of each equal run ---
     * numpy mask: keep[0]=true, keep[k]= (t[k] - t[k-1] > 0).
     * We build a compact list of source-row indices `idx[0..m)` with strictly
     * increasing timestamps. (Input is assumed already sorted, as in Python
     * where argsort is stable and the data arrives in host-recv order.) */
    int *idx = (int *)malloc((size_t)n * sizeof(int));
    if (!idx) return -1;
    int m = 0;
    idx[m++] = 0;
    for (int k = 1; k < n; k++) {
        if ((double)ts[k] > (double)ts[idx[m - 1]]) {
            idx[m++] = k;
        }
    }
    if (m < 2) { free(idx); return 0; }

    double dt = 1.0 / rate;
    double t0 = (double)ts[idx[0]];
    double tN = (double)ts[idx[m - 1]];
    double start = ceil(t0 / dt) * dt;
    double stop = floor(tN / dt) * dt;
    if (stop < start) { free(idx); return 0; }
    int n_out = (int)lround((stop - start) / dt) + 1;
    if (n_out <= 0) { free(idx); return 0; }
    if (n_out > n_out_max) { free(idx); return -1; }

    /* --- linear interpolation, two-pointer over the deduped source ---
     * For each uniform grid point g, find the source interval [t_a, t_b]
     * with t_a <= g <= t_b and interpolate re/im linearly. Both the source
     * timestamps (idx order) and the grid are monotonic, so we advance a
     * single cursor `p` (index into idx[]) rather than searching each time. */
    int p = 0;
    for (int g = 0; g < n_out; g++) {
        double gt = start + dt * (double)g;

        /* advance p so that ts[idx[p]] <= gt <= ts[idx[p+1]] (clamp at ends) */
        while (p + 1 < m - 1 && (double)ts[idx[p + 1]] < gt) {
            p++;
        }
        int ia = idx[p];
        int ib = idx[p + 1];
        double ta = (double)ts[ia];
        double tb = (double)ts[ib];
        double frac = (tb > ta) ? (gt - ta) / (tb - ta) : 0.0;
        /* scipy interp1d does not extrapolate; our grid is within [t0,tN] by
         * construction (ceil/floor), so gt always lies in some interval. */

        for (int c = 0; c < s; c++) {
            double re_a = (double)in[(size_t)ia * s * 2 + (size_t)c * 2 + 0];
            double im_a = (double)in[(size_t)ia * s * 2 + (size_t)c * 2 + 1];
            double re_b = (double)in[(size_t)ib * s * 2 + (size_t)c * 2 + 0];
            double im_b = (double)in[(size_t)ib * s * 2 + (size_t)c * 2 + 1];
            double re = re_a + frac * (re_b - re_a);
            double im = im_a + frac * (im_b - im_a);
            out[((size_t)g * s + c) * 2 + 0] = (float)re;
            out[((size_t)g * s + c) * 2 + 1] = (float)im;
        }
        if (out_grid) out_grid[g] = (float)gt;
    }

    free(idx);
    return n_out;
}
