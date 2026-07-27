/* nulldrop_test.c — host test for Stage 01 (null-subcarrier drop).
 *
 * Loads 00_input_complex.txt, runs dsp_nulldrop(), and diffs the result
 * against the Python golden 01_nulldrop.txt (shape + values). Also checks
 * kept indices against 01_kept_indices.txt.
 */
#include "../src/dsp_nulldrop.h"
#include "vec_io.h"

#include <stdio.h>
#include <stdlib.h>

#define THRESHOLD 2.0f
#define TOL 1e-4  /* int-valued CSI copied verbatim -> expect near-exact */

int main(int argc, char **argv) {
    const char *dir = (argc > 1) ? argv[1] : "test_vectors";
    char in_path[512], gold_path[512], idx_path[512];
    snprintf(in_path, sizeof(in_path), "%s/00_input_complex.txt", dir);
    snprintf(gold_path, sizeof(gold_path), "%s/01_nulldrop.txt", dir);
    snprintf(idx_path, sizeof(idx_path), "%s/01_kept_indices.txt", dir);

    cmatrix_t in = vec_load_complex(in_path);
    cmatrix_t gold = vec_load_complex(gold_path);
    pairs_t gold_idx = vec_load_pairs(idx_path); /* i = original index, j = 0 */

    float *out = (float *)malloc((size_t)in.n * in.s * 2 * sizeof(float));
    int *kept_idx = (int *)malloc((size_t)in.s * sizeof(int));
    if (!out || !kept_idx) { fprintf(stderr, "OOM\n"); return 1; }

    int kept = dsp_nulldrop(in.data, in.n, in.s, THRESHOLD, out, kept_idx);

    int ok = 1;

    /* 1. kept column count matches golden width */
    if (kept != gold.s) {
        printf("FAIL: kept=%d but golden width=%d\n", kept, gold.s);
        ok = 0;
    }

    /* 2. kept indices match */
    if (ok) {
        if (kept != gold_idx.p) {
            printf("FAIL: kept=%d but golden index count=%d\n", kept, gold_idx.p);
            ok = 0;
        } else {
            for (int k = 0; k < kept; k++) {
                if (kept_idx[k] != gold_idx.i[k]) {
                    printf("FAIL: kept_idx[%d]=%d but golden=%d\n",
                           k, kept_idx[k], gold_idx.i[k]);
                    ok = 0;
                    break;
                }
            }
        }
    }

    /* 3. packed values match */
    double worst = 0.0;
    if (ok) {
        size_t count = (size_t)in.n * kept * 2;
        worst = vec_max_abs_err_real(out, gold.data, count);
        if (worst > TOL) {
            printf("FAIL: max abs err %.6g > tol %.6g\n", worst, TOL);
            ok = 0;
        }
    }

    if (ok) {
        printf("PASS  nulldrop: %d/%d subcarriers kept, max abs err %.3g\n",
               kept, in.s, worst);
    }

    free(out);
    free(kept_idx);
    vec_free_complex(&in);
    vec_free_complex(&gold);
    vec_free_pairs(&gold_idx);
    return ok ? 0 : 1;
}
