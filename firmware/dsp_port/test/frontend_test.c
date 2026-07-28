/* frontend_test.c — host test for the fused null-drop+resample front end.
 *
 * Input : 00_input_complex.txt (raw int16 CSI) + 00_input_timestamps.txt.
 * Output: resampled matrix diffed against Python golden 02_resample.txt, AND
 *         kept indices vs 01_kept_indices.txt. Proves dsp_frontend is
 *         numerically identical to dsp_nulldrop + dsp_resample.
 */
#include "../src/dsp_frontend.h"
#include "vec_io.h"

#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

#define THRESHOLD 2.0f
#define RATE 10.0
#define TOL 1e-3

int main(int argc, char **argv) {
    const char *dir = (argc > 1) ? argv[1] : "test_vectors";
    char in_path[512], ts_path[512], gold_path[512], idx_path[512];
    snprintf(in_path, sizeof(in_path), "%s/00_input_complex.txt", dir);
    snprintf(ts_path, sizeof(ts_path), "%s/00_input_timestamps.txt", dir);
    snprintf(gold_path, sizeof(gold_path), "%s/02_resample.txt", dir);
    snprintf(idx_path, sizeof(idx_path), "%s/01_kept_indices.txt", dir);

    cmatrix_t in = vec_load_complex(in_path);      /* n x s_raw complex (int-valued) */
    dvector_t ts = vec_load_double_vector(ts_path);
    cmatrix_t gold = vec_load_complex(gold_path);
    pairs_t gidx = vec_load_pairs(idx_path);

    int n = in.n, s = in.s;
    /* split interleaved float complex into int16 re/im arrays */
    int16_t *re = malloc((size_t)n * s * sizeof(int16_t));
    int16_t *im = malloc((size_t)n * s * sizeof(int16_t));
    for (int r = 0; r < n; r++)
        for (int c = 0; c < s; c++) {
            re[(size_t)r * s + c] = (int16_t)lround(in.data[((size_t)r * s + c) * 2 + 0]);
            im[(size_t)r * s + c] = (int16_t)lround(in.data[((size_t)r * s + c) * 2 + 1]);
        }

    int cap = gold.n + 8;
    float *Huni = malloc((size_t)cap * s * 2 * sizeof(float));
    int *kept = malloc((size_t)s * sizeof(int));
    double *scratch = malloc((size_t)n * sizeof(double));
    int s_kept = 0;

    int n_out = dsp_frontend(re, im, ts.data, n, s, THRESHOLD, RATE,
                             Huni, kept, &s_kept, cap, scratch);

    int ok = 1;
    if (n_out != gold.n) { printf("FAIL: n_out=%d golden rows=%d\n", n_out, gold.n); ok = 0; }
    if (ok && s_kept != gold.s) { printf("FAIL: s_kept=%d golden cols=%d\n", s_kept, gold.s); ok = 0; }
    if (ok && s_kept != gidx.p) { printf("FAIL: kept count %d vs golden idx %d\n", s_kept, gidx.p); ok = 0; }
    if (ok) for (int k = 0; k < s_kept; k++) if (kept[k] != gidx.i[k]) {
        printf("FAIL: kept_idx[%d]=%d golden=%d\n", k, kept[k], gidx.i[k]); ok = 0; break;
    }
    double worst = 0.0;
    if (ok) {
        worst = vec_max_abs_err_real(Huni, gold.data, (size_t)n_out * s_kept * 2);
        if (worst > TOL || isnan(worst)) { printf("FAIL: max abs err %.6g > %.3g\n", worst, TOL); ok = 0; }
    }

    if (ok) printf("PASS  frontend: %d->%d samp, %d/%d subc kept, max abs err %.3g\n",
                   n, n_out, s_kept, s, worst);

    free(re); free(im); free(Huni); free(kept); free(scratch);
    vec_free_complex(&in); vec_free_double_vector(&ts);
    vec_free_complex(&gold); vec_free_pairs(&gidx);
    return ok ? 0 : 1;
}
