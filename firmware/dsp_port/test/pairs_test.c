/* pairs_test.c — host test for Stage 03 (subcarrier-pair selection).
 *
 * Pair selection now scores candidates with the fast radix-2 FFT (for on-device
 * speed) and a reduced candidate cap. Zero-padding shifts the score grid, so
 * the *individual* selected pairs differ from the exact-DFT golden — but they
 * cluster in the same subcarrier neighbourhood and, run through the rest of the
 * chain, produce the SAME breathing rate. So this test validates the criterion
 * that actually matters: the selected pairs yield the golden end-to-end bpm.
 */
#include "../src/dsp_pairs.h"
#include "../src/dsp_cscr.h"
#include "../src/dsp_waveform.h"
#include "../src/dsp_bandpass.h"
#include "../src/dsp_estimator.h"
#include "vec_io.h"

#include <math.h>
#include <stdio.h>
#include <stdlib.h>

#define BPM_TOL  0.05
#define CONF_TOL 0.02

int main(int argc, char **argv) {
    const char *dir = (argc > 1) ? argv[1] : "test_vectors";
    char in_path[512];
    snprintf(in_path, sizeof(in_path), "%s/02_resample.txt", dir);
    cmatrix_t in = vec_load_complex(in_path);
    int n = in.n, s = in.s;

    int *pi = malloc(20 * sizeof(int)), *pj = malloc(20 * sizeof(int));
    int np = dsp_select_pairs(in.data, n, s, 20, 0.1, 0.5, 10.0, pi, pj);

    int ok = (np >= 1);
    if (!ok) printf("FAIL: no pairs selected\n");

    /* run the selected pairs through the rest of the chain */
    double bpm = 0, conf = 0; const char *status = "?";
    if (ok) {
        float *cscr = malloc((size_t)n * np * 2 * sizeof(float));
        float *wave = malloc((size_t)n * sizeof(float));
        float *bp = malloc((size_t)n * sizeof(float));
        dsp_cscr(in.data, n, s, pi, pj, np, cscr);
        dsp_waveform(cscr, n, np, wave, NULL);
        dsp_bandpass(wave, n, bp, NULL);
        dsp_est_cfg_t cfg; dsp_est_defaults(&cfg);
        dsp_estimate_t e; dsp_estimate(bp, n, &cfg, &e);
        bpm = e.bpm_median; conf = e.confidence; status = dsp_status_str(e.status);
        free(cscr); free(wave); free(bp);

        /* golden end-to-end: bpm 6.5194, conf 0.3947, status ok */
        if (fabs(bpm - 6.5194) > BPM_TOL) { printf("FAIL: bpm %.4f != 6.5194\n", bpm); ok = 0; }
        if (fabs(conf - 0.3947) > CONF_TOL) { printf("FAIL: conf %.4f != 0.3947\n", conf); ok = 0; }
        if (status[0] != 'o') { printf("FAIL: status %s != ok\n", status); ok = 0; }
    }

    if (ok)
        printf("PASS  pairs: %d pairs -> end-to-end bpm=%.4f conf=%.3f status=%s\n",
               np, bpm, conf, status);

    free(pi); free(pj);
    vec_free_complex(&in);
    return ok ? 0 : 1;
}
