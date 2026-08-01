/* cscr_test.c — host test for Stage 04 (Cross-Subcarrier CSI Ratio).
 *
 * Input : 02_resample.txt (uniform complex CSI) + 03_pairs.txt (selected pairs).
 * Output: CSCR matrix diffed against Python golden 04_cscr.txt.
 *
 * Complex division of ~O(1) ratios; float32 vs numpy complex64 -> small
 * nonzero error expected, kept tight.
 */
#include "../src/dsp_cscr.h"
#include "vec_io.h"

#include <math.h>
#include <stdio.h>
#include <stdlib.h>

#define TOL 1e-3

int main(int argc, char **argv) {
    const char *dir = (argc > 1) ? argv[1] : "test_vectors";
    char in_path[512], pairs_path[512], gold_path[512];
    snprintf(in_path, sizeof(in_path), "%s/02_resample.txt", dir);
    snprintf(pairs_path, sizeof(pairs_path), "%s/03_pairs.txt", dir);
    snprintf(gold_path, sizeof(gold_path), "%s/04_cscr.txt", dir);

    cmatrix_t in = vec_load_complex(in_path);
    pairs_t pairs = vec_load_pairs(pairs_path);
    cmatrix_t gold = vec_load_complex(gold_path);

    int ok = 1;
    if (gold.n != in.n || gold.s != pairs.p) {
        printf("FAIL: golden shape %dx%d != expected %dx%d\n",
               gold.n, gold.s, in.n, pairs.p);
        ok = 0;
    }

    float *out = (float *)malloc((size_t)in.n * pairs.p * 2 * sizeof(float));
    if (!out) { fprintf(stderr, "OOM\n"); return 1; }

    dsp_cscr(in.data, in.n, in.s, pairs.i, pairs.j, pairs.p, out);

    double worst = 0.0;
    if (ok) {
        size_t count = (size_t)in.n * pairs.p * 2;
        worst = vec_max_abs_err_real(out, gold.data, count);
        if (worst > TOL || isnan(worst)) {
            printf("FAIL: max abs err %.6g > tol %.6g\n", worst, TOL);
            ok = 0;
        }
    }

    if (ok) {
        printf("PASS  cscr: %d x %d CSCR matrix, max abs err %.3g\n",
               in.n, pairs.p, worst);
    }

    free(out);
    vec_free_complex(&in);
    vec_free_pairs(&pairs);
    vec_free_complex(&gold);
    return ok ? 0 : 1;
}
