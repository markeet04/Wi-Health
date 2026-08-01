/* dsp_motion.h — Stage 08: motion-artifact rejection gate.
 *
 * Port of window_motion_score() + MotionGate (v2) in
 * firmware/components/dsp_breathing/motion.py.
 *
 * Score: mean per-subcarrier amplitude variance / mean_amp^2 over one window
 * of complex CSI. The stateful gate flags a window as motion if either:
 *   - COLD: score > cold_baseline * cold_spike_ratio (baseline = median of the
 *     first cold_baseline_windows scores, locked and never updated), or
 *   - STEP: score > prev_score * step_ratio.
 * The first cold_baseline_windows windows are trusted by construction.
 *
 * Pure C99. Math in double to match numpy (np.var population, np.median).
 */
#ifndef DSP_MOTION_H
#define DSP_MOTION_H

#define DSP_MOTION_MAX_COLD 8   /* upper bound on cold_baseline_windows */

typedef struct {
    int    cold_baseline_windows;   /* 3 */
    double cold_spike_ratio;        /* 2.5 */
    double step_ratio;              /* 1.6 */

    /* state */
    double cold_samples[DSP_MOTION_MAX_COLD];
    int    cold_count;
    int    cold_locked;             /* 0 until baseline is set */
    double cold_baseline;
    double prev_score;
    int    have_prev;
} dsp_motion_gate_t;

/* Motion score for one window of complex CSI (n samples * s subcarriers,
 * interleaved re,im). */
double dsp_motion_score(const float *H_window, int n, int s);

/* Initialise a gate with the Python defaults (3, 2.5, 1.6). */
void dsp_motion_init(dsp_motion_gate_t *g);

/* Feed the next window; returns 1 if motion (drop the window), else 0.
 * *score and *baseline (optional, may be NULL) report the window score and the
 * reference baseline used, matching MotionGate.check()'s returns. */
int dsp_motion_check(dsp_motion_gate_t *g, const float *H_window, int n, int s,
                     double *score, double *baseline);

#endif /* DSP_MOTION_H */
