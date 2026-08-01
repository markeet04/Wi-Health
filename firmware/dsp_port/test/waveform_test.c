/* waveform_test.c — host test for Stage 05 (CSCR -> respiratory waveform).
 *
 * Input : 04_cscr.txt (CSCR complex matrix).
 * Output: waveform diffed against Python golden 05_waveform.txt.
 *
 * Combines float32 normalize/average + Hampel + Savgol. Small nonzero error
 * expected (float rounding, median tie handling); kept tight.
 */
#include "../src/dsp_waveform.h"
#include "vec_io.h"

#include <math.h>
#include <stdio.h>
#include <stdlib.h>

#define TOL 1e-3

int main(int argc, char **argv) {
    const char *dir = (argc > 1) ? argv[1] : "test_vectors";
    char in_path[512], gold_path[512];
    snprintf(in_path, sizeof(in_path), "%s/04_cscr.txt", dir);
    snprintf(gold_path, sizeof(gold_path), "%s/05_waveform.txt", dir);

    cmatrix_t in = vec_load_complex(in_path);   /* n x p complex CSCR */
    rvector_t gold = vec_load_real_vector(gold_path);

    int ok = 1;
    if (gold.n != in.n) {
        printf("FAIL: golden length %d != n %d\n", gold.n, in.n);
        ok = 0;
    }

    float *out = (float *)malloc((size_t)in.n * sizeof(float));
    if (!out) { fprintf(stderr, "OOM\n"); return 1; }

    dsp_waveform(in.data, in.n, in.s, out, NULL);

    double worst = 0.0;
    if (ok) {
        worst = vec_max_abs_err_real(out, gold.data, (size_t)in.n);
        if (worst > TOL || isnan(worst)) {
            printf("FAIL: max abs err %.6g > tol %.6g\n", worst, TOL);
            ok = 0;
        }
    }

    if (ok) {
        printf("PASS  waveform: length %d, max abs err %.3g\n", in.n, worst);
    }

    free(out);
    vec_free_complex(&in);
    vec_free_real_vector(&gold);
    return ok ? 0 : 1;
}
