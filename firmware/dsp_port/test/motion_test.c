/* motion_test.c — host test for Stage 08 (motion gate).
 *
 * Input : 02_resample.txt, sliced into 30s/5s windows (win=300, stride=50).
 * Output: per-window (score, is_motion, baseline) diffed against golden
 *         08_motion.txt. Also checks the standalone 08_motion_score0.txt.
 *
 * Note: the reference capture is stationary, so this validates the
 * no-false-positive path + the cold-baseline running-mean/median state
 * machine. A positive-motion capture would exercise the flag paths.
 */
#include "../src/dsp_motion.h"
#include "vec_io.h"

#include <math.h>
#include <stdio.h>
#include <stdlib.h>

#define WIN 300
#define STRIDE 50
#define SCORE_TOL 1e-5

int main(int argc, char **argv) {
    const char *dir = (argc > 1) ? argv[1] : "test_vectors";
    char in_path[512], gold_path[512], s0_path[512];
    snprintf(in_path, sizeof(in_path), "%s/02_resample.txt", dir);
    snprintf(gold_path, sizeof(gold_path), "%s/08_motion.txt", dir);
    snprintf(s0_path, sizeof(s0_path), "%s/08_motion_score0.txt", dir);

    cmatrix_t in = vec_load_complex(in_path);   /* n x s complex */

    int ok = 1;

    /* --- standalone score0 check --- */
    {
        FILE *f = fopen(s0_path, "r");
        if (f) {
            double g0; if (fscanf(f, "%lf", &g0) == 1) {
                double c0 = dsp_motion_score(in.data, WIN, in.s);
                if (fabs(c0 - g0) > SCORE_TOL) {
                    printf("FAIL: score0 C=%.9g golden=%.9g\n", c0, g0); ok = 0;
                }
            }
            fclose(f);
        }
    }

    /* --- windowed gate replay --- */
    FILE *gf = fopen(gold_path, "r");
    if (!gf) { fprintf(stderr, "cannot open %s\n", gold_path); return 1; }
    char line[256];

    dsp_motion_gate_t g; dsp_motion_init(&g);
    int start = 0, widx = 0, nrows = 0;

    while (fgets(line, sizeof(line), gf)) {
        if (line[0] == '#') continue;
        int gidx, gmotion; double gscore, gbase;
        if (sscanf(line, "%d %lf %d %lf", &gidx, &gscore, &gmotion, &gbase) != 4)
            continue;
        nrows++;

        if (start + WIN > in.n) {
            printf("FAIL: golden has window %d but input exhausted\n", gidx);
            ok = 0; break;
        }
        const float *win = in.data + (size_t)start * in.s * 2;
        double score = 0.0, base = 0.0;
        int motion = dsp_motion_check(&g, win, WIN, in.s, &score, &base);

        if (gidx != widx) { printf("FAIL: index %d != %d\n", widx, gidx); ok = 0; }
        if (fabs(score - gscore) > SCORE_TOL) {
            printf("FAIL: win %d score C=%.9g golden=%.9g\n", widx, score, gscore);
            ok = 0;
        }
        if (motion != gmotion) {
            printf("FAIL: win %d is_motion C=%d golden=%d\n", widx, motion, gmotion);
            ok = 0;
        }
        if (fabs(base - gbase) > SCORE_TOL) {
            printf("FAIL: win %d baseline C=%.9g golden=%.9g\n", widx, base, gbase);
            ok = 0;
        }
        start += STRIDE;
        widx++;
    }
    fclose(gf);

    if (ok) {
        printf("PASS  motion: %d windows, scores + gate decisions match golden\n",
               nrows);
    }

    vec_free_complex(&in);
    return ok ? 0 : 1;
}
