/* dsp_motion.c — Stage 08 implementation. See dsp_motion.h. */
#include "dsp_motion.h"

#include <math.h>
#include <stdlib.h>
#include <stddef.h>

double dsp_motion_score(const float *H_window, int n, int s) {
    if (n < 2 || s <= 0) return 0.0;

    /* amplitude |H| per element; per-subcarrier variance (population); mean
     * amplitude overall. score = mean(per_sub_var) / (mean_amp + 1e-9)^2. */
    double sum_amp = 0.0;
    double sum_var = 0.0;
    for (int c = 0; c < s; c++) {
        /* mean and variance of |H[:,c]| */
        double m = 0.0;
        for (int r = 0; r < n; r++) {
            double re = (double)H_window[(size_t)r * s * 2 + (size_t)c * 2 + 0];
            double im = (double)H_window[(size_t)r * s * 2 + (size_t)c * 2 + 1];
            double a = sqrt(re * re + im * im);
            m += a;
            sum_amp += a;
        }
        m /= n;
        double v = 0.0;
        for (int r = 0; r < n; r++) {
            double re = (double)H_window[(size_t)r * s * 2 + (size_t)c * 2 + 0];
            double im = (double)H_window[(size_t)r * s * 2 + (size_t)c * 2 + 1];
            double a = sqrt(re * re + im * im);
            double d = a - m;
            v += d * d;
        }
        v /= n;                 /* population variance (ddof=0) */
        sum_var += v;
    }
    double mean_var = sum_var / (double)s;
    double mean_amp = sum_amp / ((double)n * (double)s) + 1e-9;
    return mean_var / (mean_amp * mean_amp);
}

void dsp_motion_init(dsp_motion_gate_t *g) {
    g->cold_baseline_windows = 3;
    g->cold_spike_ratio = 2.5;
    g->step_ratio = 1.6;
    g->cold_count = 0;
    g->cold_locked = 0;
    g->cold_baseline = 0.0;
    g->prev_score = 0.0;
    g->have_prev = 0;
}

static int cmp_double(const void *a, const void *b) {
    double da = *(const double *)a, db = *(const double *)b;
    return (da < db) ? -1 : (da > db) ? 1 : 0;
}

static double median_of(const double *v, int m) {
    double *tmp = (double *)malloc((size_t)m * sizeof(double));
    if (!tmp) return 0.0;
    for (int i = 0; i < m; i++) tmp[i] = v[i];
    qsort(tmp, (size_t)m, sizeof(double), cmp_double);
    double med = (m & 1) ? tmp[m / 2] : 0.5 * (tmp[m / 2 - 1] + tmp[m / 2]);
    free(tmp);
    return med;
}

int dsp_motion_check(dsp_motion_gate_t *g, const float *H_window, int n, int s,
                     double *score_out, double *baseline_out) {
    double score = dsp_motion_score(H_window, n, s);

    if (!g->cold_locked) {
        if (g->cold_count < DSP_MOTION_MAX_COLD) {
            g->cold_samples[g->cold_count++] = score;
        }
        g->prev_score = score;
        g->have_prev = 1;
        if (g->cold_count >= g->cold_baseline_windows) {
            g->cold_baseline = median_of(g->cold_samples, g->cold_count);
            g->cold_locked = 1;
        }
        /* pre-lock: baseline reported is the running MEAN of cold samples */
        if (baseline_out) {
            double m = 0.0;
            for (int i = 0; i < g->cold_count; i++) m += g->cold_samples[i];
            *baseline_out = (g->cold_count > 0) ? m / g->cold_count : 0.0;
        }
        if (score_out) *score_out = score;
        return 0;   /* opening windows trusted by construction */
    }

    int cold_flag = (g->cold_baseline > 1e-12) &&
                    (score > g->cold_baseline * g->cold_spike_ratio);
    int step_flag = g->have_prev && (g->prev_score > 1e-12) &&
                    (score > g->prev_score * g->step_ratio);
    int is_motion = cold_flag || step_flag;

    g->prev_score = score;
    g->have_prev = 1;

    if (score_out) *score_out = score;
    if (baseline_out) *baseline_out = g->cold_baseline;
    return is_motion ? 1 : 0;
}
