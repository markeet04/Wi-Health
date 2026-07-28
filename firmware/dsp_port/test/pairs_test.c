/* pairs_test.c — host test for Stage 03 (subcarrier-pair selection).
 *
 * Input : 02_resample.txt (uniform complex CSI).
 * Output: selected (i,j) pairs diffed against Python golden 03_pairs.txt.
 *
 * The output is a ranked SET of integer pairs, so this must match exactly
 * (same pairs, same order). The reference score gaps near the cutoff are
 * wide, so a correct DFT reproduces the ranking despite float differences.
 */
#include "../src/dsp_pairs.h"
#include "vec_io.h"

#include <stdio.h>
#include <stdlib.h>

#define NUM_PAIRS 20
#define LOW_HZ 0.1
#define HIGH_HZ 0.5
#define RATE 10.0

int main(int argc, char **argv) {
    const char *dir = (argc > 1) ? argv[1] : "test_vectors";
    char in_path[512], gold_path[512];
    snprintf(in_path, sizeof(in_path), "%s/02_resample.txt", dir);
    snprintf(gold_path, sizeof(gold_path), "%s/03_pairs.txt", dir);

    cmatrix_t in = vec_load_complex(in_path);
    pairs_t gold = vec_load_pairs(gold_path);

    int *oi = (int *)malloc(NUM_PAIRS * sizeof(int));
    int *oj = (int *)malloc(NUM_PAIRS * sizeof(int));
    if (!oi || !oj) { fprintf(stderr, "OOM\n"); return 1; }

    int got = dsp_select_pairs(in.data, in.n, in.s, NUM_PAIRS,
                               LOW_HZ, HIGH_HZ, RATE, oi, oj);

    int ok = 1;
    if (got != gold.p) {
        printf("FAIL: selected %d pairs but golden has %d\n", got, gold.p);
        ok = 0;
    }

    int mismatches = 0;
    if (ok) {
        for (int k = 0; k < got; k++) {
            if (oi[k] != gold.i[k] || oj[k] != gold.j[k]) {
                if (mismatches < 8) {
                    printf("  rank %2d: C=(%d,%d) golden=(%d,%d)\n",
                           k, oi[k], oj[k], gold.i[k], gold.j[k]);
                }
                mismatches++;
            }
        }
        if (mismatches > 0) {
            printf("FAIL: %d/%d pairs differ from golden\n", mismatches, got);
            ok = 0;
        }
    }

    if (ok) {
        printf("PASS  pairs: %d/%d selected pairs match golden exactly\n",
               got, gold.p);
    }

    free(oi);
    free(oj);
    vec_free_complex(&in);
    vec_free_pairs(&gold);
    return ok ? 0 : 1;
}
