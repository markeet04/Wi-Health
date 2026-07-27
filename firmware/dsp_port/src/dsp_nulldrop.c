/* dsp_nulldrop.c — Stage 01 implementation. See dsp_nulldrop.h. */
#include "dsp_nulldrop.h"

#include <math.h>
#include <stdlib.h>

/* qsort comparator for doubles (ascending). */
static int cmp_double(const void *a, const void *b) {
    double da = *(const double *)a, db = *(const double *)b;
    if (da < db) return -1;
    if (da > db) return 1;
    return 0;
}

/* Median of a double array, numpy semantics: sorts in place and for even n
 * averages the two central elements. Amplitude/median math is done in double
 * to match numpy (np.abs / np.median run in float64). */
static double median_double(double *v, int n) {
    qsort(v, (size_t)n, sizeof(double), cmp_double);
    if (n & 1) {
        return v[n / 2];
    }
    return 0.5 * (v[n / 2 - 1] + v[n / 2]);
}

float dsp_col_median_amp(const float *in, int n, int s, int col, float *scratch) {
    (void)scratch; /* host path allocates; on-device pass a persistent buffer */
    double *amp = (double *)malloc((size_t)n * sizeof(double));
    if (!amp) return 0.0f;
    for (int r = 0; r < n; r++) {
        double re = (double)in[(size_t)r * s * 2 + (size_t)col * 2 + 0];
        double im = (double)in[(size_t)r * s * 2 + (size_t)col * 2 + 1];
        amp[r] = sqrt(re * re + im * im);
    }
    double med = median_double(amp, n);
    free(amp);
    return (float)med;
}

int dsp_nulldrop(const float *in, int n, int s, float threshold,
                 float *out, int *kept_idx) {
    if (n <= 0 || s <= 0) return 0;

    /* Pass 1: decide which columns survive (median amplitude > threshold). */
    int kept = 0;
    for (int c = 0; c < s; c++) {
        double med = (double)dsp_col_median_amp(in, n, s, c, NULL);
        if (med > (double)threshold) {
            kept_idx[kept++] = c;
        }
    }
    if (kept == 0) return 0;

    /* Pass 2: pack the kept columns into `out`, row-major with width `kept`. */
    for (int r = 0; r < n; r++) {
        for (int w = 0; w < kept; w++) {
            int c = kept_idx[w];
            float re = in[(size_t)r * s * 2 + (size_t)c * 2 + 0];
            float im = in[(size_t)r * s * 2 + (size_t)c * 2 + 1];
            out[((size_t)r * kept + w) * 2 + 0] = re;
            out[((size_t)r * kept + w) * 2 + 1] = im;
        }
    }

    return kept;
}
