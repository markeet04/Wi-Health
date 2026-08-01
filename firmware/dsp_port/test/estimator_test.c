/* estimator_test.c — host test for Stage 07 (FFT + autocorrelation + gate).
 *
 * Input : 06_bandpass.txt (respiratory waveform).
 * Output: scalar estimate diffed against Python golden 07_estimator.txt.
 *
 * bpm values are frequency-bin quantised so should match closely; confidences
 * involve full-spectrum means so allow a small relative tolerance. status and
 * agreement must match exactly.
 */
#include "../src/dsp_estimator.h"
#include "vec_io.h"

#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define BPM_TOL 0.05     /* bpm bins are ~0.3 apart; 0.05 is tight */
#define CONF_TOL 1e-2    /* confidence: allow small abs error */

/* read one "key value" line's value by key from 07_estimator.txt */
static int read_gold(const char *path, const char *key, char *val, int vlen) {
    FILE *f = fopen(path, "r");
    if (!f) { fprintf(stderr, "cannot open %s\n", path); exit(1); }
    char line[256];
    int found = 0;
    while (fgets(line, sizeof(line), f)) {
        if (line[0] == '#') continue;
        char k[64], v[128];
        if (sscanf(line, "%63s %127s", k, v) == 2 && strcmp(k, key) == 0) {
            strncpy(val, v, vlen - 1); val[vlen - 1] = '\0';
            found = 1; break;
        }
    }
    fclose(f);
    return found;
}

int main(int argc, char **argv) {
    const char *dir = (argc > 1) ? argv[1] : "test_vectors";
    char in_path[512], gold_path[512];
    snprintf(in_path, sizeof(in_path), "%s/06_bandpass.txt", dir);
    snprintf(gold_path, sizeof(gold_path), "%s/07_estimator.txt", dir);

    rvector_t in = vec_load_real_vector(in_path);

    dsp_est_cfg_t cfg; dsp_est_defaults(&cfg);
    dsp_estimate_t e;
    dsp_estimate(in.data, in.n, &cfg, &e);

    char gv[128];
    int ok = 1;

    /* helper macros */
    #define CHECK_SCALAR(key, got, tol) do { \
        if (!read_gold(gold_path, key, gv, sizeof(gv))) { \
            printf("FAIL: golden missing %s\n", key); ok = 0; \
        } else { \
            double gd = atof(gv); \
            if (fabs((double)(got) - gd) > (tol)) { \
                printf("FAIL: %s C=%.6g golden=%.6g (tol %.3g)\n", \
                       key, (double)(got), gd, (double)(tol)); ok = 0; \
            } \
        } \
    } while (0)

    CHECK_SCALAR("bpm_fft", e.bpm_fft, BPM_TOL);
    CHECK_SCALAR("conf_fft", e.conf_fft, 0.05);   /* full-spectrum mean */
    CHECK_SCALAR("bpm_ac", e.bpm_ac, BPM_TOL);
    CHECK_SCALAR("conf_ac", e.conf_ac, CONF_TOL);
    CHECK_SCALAR("bpm_median", e.bpm_median, BPM_TOL);
    CHECK_SCALAR("confidence", e.confidence, CONF_TOL);

    /* agreement (0/1) */
    if (read_gold(gold_path, "agreement", gv, sizeof(gv))) {
        int ga = atoi(gv);
        if (ga != e.agreement) {
            printf("FAIL: agreement C=%d golden=%d\n", e.agreement, ga); ok = 0;
        }
    }
    /* status string */
    if (read_gold(gold_path, "status", gv, sizeof(gv))) {
        if (strcmp(gv, dsp_status_str(e.status)) != 0) {
            printf("FAIL: status C=%s golden=%s\n", dsp_status_str(e.status), gv);
            ok = 0;
        }
    }

    if (ok) {
        printf("PASS  estimator: bpm=%.2f conf=%.3f status=%s "
               "(fft=%.2f ac=%.2f)\n",
               e.bpm_median, e.confidence, dsp_status_str(e.status),
               e.bpm_fft, e.bpm_ac);
    }

    vec_free_real_vector(&in);
    return ok ? 0 : 1;
}
