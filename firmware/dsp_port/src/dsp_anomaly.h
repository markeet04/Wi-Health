/* dsp_anomaly.h — Module 5 Tier-1: deterministic respiratory anomaly flags.
 *
 * CORE, on-device. Consumes the per-window DSP result (bpm + status) and
 * raises alerts for:
 *   - apnea      : no valid breathing for >= apnea_trigger_seconds, while the
 *                  room still looks occupied (uses status to avoid firing on an
 *                  empty room — an empty room reads no_valid_breathing too, so
 *                  apnea requires a RECENT history of valid breathing first).
 *   - tachypnea  : smoothed bpm above tachypnea_bpm.
 *   - bradypnea  : smoothed bpm below bradypnea_bpm.
 *
 * Temporal voting: a condition must hold across `vote_needed` of the last
 * `vote_window` windows before an alert is raised, suppressing spurious
 * single-window flags. Each raised alert reports its vote tally (e.g. "3/3").
 *
 * Deterministic, explainable, no training data. Pure C99, no ESP-IDF deps —
 * host-testable and runs on-device beside the DSP.
 */
#ifndef DSP_ANOMALY_H
#define DSP_ANOMALY_H

#include <stdbool.h>

#define DSP_ANOM_VOTE_MAX 8   /* upper bound on the voting window */

typedef enum {
    DSP_ANOM_NONE = 0,
    DSP_ANOM_APNEA,
    DSP_ANOM_TACHYPNEA,
    DSP_ANOM_BRADYPNEA,
} dsp_anom_type_t;

typedef struct {
    double tachypnea_bpm;        /* upper bound, e.g. 25 */
    double bradypnea_bpm;        /* lower bound, e.g. 8  */
    double apnea_trigger_s;      /* no valid breathing this long -> apnea, e.g. 20 */
    double stride_s;             /* seconds between windows (for apnea timing) */
    int    vote_window;          /* M: recent windows considered (<= DSP_ANOM_VOTE_MAX) */
    int    vote_needed;          /* N: votes required to raise (N-of-M) */
} dsp_anom_cfg_t;

/* One emitted alert. type==DSP_ANOM_NONE means "nothing raised this window". */
typedef struct {
    dsp_anom_type_t type;
    int   votes;                 /* how many of the last window matched */
    int   window;                /* vote_window (denominator) */
    double bpm;                  /* the bpm that triggered it (0 for apnea) */
    double apnea_seconds;        /* how long no valid breathing (apnea only) */
} dsp_anom_alert_t;

typedef struct {
    dsp_anom_cfg_t cfg;
    /* rolling vote history per condition (1 = condition met that window) */
    unsigned char tachy_hist[DSP_ANOM_VOTE_MAX];
    unsigned char brady_hist[DSP_ANOM_VOTE_MAX];
    int   hist_count;            /* how many windows seen (<= vote_window) */
    int   hist_head;             /* ring position */
    /* apnea tracking */
    double no_breath_seconds;    /* consecutive seconds with no valid breathing */
    bool   had_valid_breathing;  /* seen at least one valid window (room occupied) */
    /* de-dup: don't re-raise the same alert type every window while it persists */
    dsp_anom_type_t last_raised;
} dsp_anom_t;

/* Fill cfg with sensible defaults (tachypnea 25, bradypnea 8, apnea 20 s,
 * stride 5 s, vote 3-of-3). */
void dsp_anom_defaults(dsp_anom_cfg_t *cfg);

void dsp_anom_init(dsp_anom_t *a, const dsp_anom_cfg_t *cfg);

/* Feed one window. `status_ok` = the DSP window was status==ok (trusted bpm);
 * `bpm` is the smoothed/trusted bpm (ignored when !status_ok). Returns an
 * alert (type NONE if none raised this window). An alert of a given type is
 * raised once when it first crosses the vote threshold and not repeated until
 * the condition clears and recurs. */
dsp_anom_alert_t dsp_anom_update(dsp_anom_t *a, bool status_ok, double bpm);

const char *dsp_anom_type_str(dsp_anom_type_t t);   /* "apnea"/"tachypnea"/... */
const char *dsp_anom_severity_str(dsp_anom_type_t t); /* "urgent"/"warning" */

#endif /* DSP_ANOMALY_H */
