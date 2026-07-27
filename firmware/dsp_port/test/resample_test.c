/* resample_test.c — host test for Stage 02 (uniform resample to 10 Hz).
 *
 * Input : 01_nulldrop.txt (active complex matrix) + 00_input_timestamps.txt.
 * Output: diffed against Python golden 02_resample.txt.
 *
 * This is the first floating-point stage, so we expect a small nonzero error
 * (float32 interpolation vs scipy float64), not bit-exact. Tolerance is set
 * accordingly but tight.
 */
#include "../src/dsp_resample.h"
#include "vec_io.h"

#include <math.h>
#include <stdio.h>
#include <stdlib.h>

#define RATE 10.0
#define TOL 1e-2  /* CSI magnitudes are ~10s; 1e-2 abs err is ~0.1% — tight */

int main(int argc, char **argv) {
    const char *dir = (argc > 1) ? argv[1] : "test_vectors";
    char in_path[512], ts_path[512], gold_path[512];
    snprintf(in_path, sizeof(in_path), "%s/01_nulldrop.txt", dir);
    snprintf(ts_path, sizeof(ts_path), "%s/00_input_timestamps.txt", dir);
    snprintf(gold_path, sizeof(gold_path), "%s/02_resample.txt", dir);

    cmatrix_t in = vec_load_complex(in_path);
    dvector_t ts = vec_load_double_vector(ts_path);
    cmatrix_t gold = vec_load_complex(gold_path);

    if (ts.n != in.n) {
        printf("FAIL: timestamp count %d != matrix rows %d\n", ts.n, in.n);
        return 1;
    }

    /* generous capacity: (span * rate) + a few */
    int cap = gold.n + 8;
    float *out = (float *)malloc((size_t)cap * in.s * 2 * sizeof(float));
    float *grid = (float *)malloc((size_t)cap * sizeof(float));
    if (!out || !grid) { fprintf(stderr, "OOM\n"); return 1; }

    int n_out = dsp_resample(ts.data, in.data, in.n, in.s, RATE, out, grid, cap);

    int ok = 1;
    if (n_out < 0) {
        printf("FAIL: resample overflow (cap=%d)\n", cap);
        ok = 0;
    } else if (n_out != gold.n) {
        printf("FAIL: n_out=%d but golden rows=%d\n", n_out, gold.n);
        ok = 0;
    }

    double worst = 0.0;
    if (ok) {
        size_t count = (size_t)n_out * in.s * 2;
        worst = vec_max_abs_err_real(out, gold.data, count);
        if (worst > TOL || isnan(worst)) {
            printf("FAIL: max abs err %.6g > tol %.6g\n", worst, TOL);
            ok = 0;
        }
    }

    if (ok) {
        printf("PASS  resample: %d -> %d samples @ %.0f Hz, %d cols, max abs err %.3g\n",
               in.n, n_out, RATE, in.s, worst);
    }

    free(out);
    free(grid);
    vec_free_complex(&in);
    vec_free_double_vector(&ts);
    vec_free_complex(&gold);
    return ok ? 0 : 1;
}
