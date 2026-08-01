/* dsp_smooth.h — rolling-median BPM smoother.
 *
 * Port of RollingBpmBuffer in firmware/components/dsp_breathing/breathing.py.
 *
 * Keeps the last `size` VALID (status=ok) window bpm estimates and reports
 * their median, so a single noisy window is outvoted by its neighbours
 * instead of standing alone as "the" reading. Only valid windows are pushed;
 * invalid ones (low_confidence/disagreement/no_valid_breathing) never pollute
 * the smoothed value. This is what turns the jumpy per-window raw bpm into a
 * stable, trustworthy reading (see the Python `smoothed=` column).
 *
 * Pure C99.
 */
#ifndef DSP_SMOOTH_H
#define DSP_SMOOTH_H

#define DSP_SMOOTH_MAX 16   /* upper bound on buffer size */

typedef struct {
    int    size;                    /* window size (Python default 6) */
    double buf[DSP_SMOOTH_MAX];     /* ring of last `size` valid bpm */
    int    count;                   /* number currently held (<= size) */
    int    head;                    /* next write position (ring) */
} dsp_smoother_t;

/* Initialise with the given window size (clamped to [1, DSP_SMOOTH_MAX]). */
void dsp_smooth_init(dsp_smoother_t *s, int size);

/* Push a valid window's bpm. Call ONLY for status=ok windows. */
void dsp_smooth_push(dsp_smoother_t *s, double bpm);

/* Current rolling median of held values; NAN if none held yet. */
double dsp_smooth_value(const dsp_smoother_t *s);

/* How many valid windows are currently held. */
int dsp_smooth_count(const dsp_smoother_t *s);

#endif /* DSP_SMOOTH_H */
