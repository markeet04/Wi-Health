/* bandpass_test.c — host test for Stage 06 (zero-phase Butterworth bandpass).
 *
 * Input : 05_waveform.txt (respiratory waveform).
 * Output: filtered signal diffed against Python golden 06_bandpass.txt.
 *
 * sosfiltfilt is the trickiest stage (padding + forward/backward IIR); we
 * hold it to a tight tolerance to confirm the edge/state handling matches.
 */
#include "../src/dsp_bandpass.h"
#include "vec_io.h"

#include <math.h>
#include <stdio.h>
#include <stdlib.h>

#define TOL 1e-3

int main(int argc, char **argv) {
    const char *dir = (argc > 1) ? argv[1] : "test_vectors";
    char in_path[512], gold_path[512];
    snprintf(in_path, sizeof(in_path), "%s/05_waveform.txt", dir);
    snprintf(gold_path, sizeof(gold_path), "%s/06_bandpass.txt", dir);

    rvector_t in = vec_load_real_vector(in_path);
    rvector_t gold = vec_load_real_vector(gold_path);

    int ok = 1;
    if (gold.n != in.n) {
        printf("FAIL: golden length %d != n %d\n", gold.n, in.n);
        ok = 0;
    }

    float *out = (float *)malloc((size_t)in.n * sizeof(float));
    if (!out) { fprintf(stderr, "OOM\n"); return 1; }

    dsp_bandpass(in.data, in.n, out, NULL);

    double worst = 0.0;
    if (ok) {
        worst = vec_max_abs_err_real(out, gold.data, (size_t)in.n);
        if (worst > TOL || isnan(worst)) {
            printf("FAIL: max abs err %.6g > tol %.6g\n", worst, TOL);
            ok = 0;
        }
    }

    if (ok) {
        printf("PASS  bandpass: length %d, max abs err %.3g\n", in.n, worst);
    }

    free(out);
    vec_free_real_vector(&in);
    vec_free_real_vector(&gold);
    return ok ? 0 : 1;
}
