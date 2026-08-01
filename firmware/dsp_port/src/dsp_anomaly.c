/* dsp_anomaly.c — Module 5 Tier-1 implementation. See dsp_anomaly.h. */
#include "dsp_anomaly.h"

#include <string.h>

void dsp_anom_defaults(dsp_anom_cfg_t *cfg) {
    cfg->tachypnea_bpm = 25.0;
    cfg->bradypnea_bpm = 8.0;
    cfg->apnea_trigger_s = 20.0;
    cfg->stride_s = 5.0;
    cfg->vote_window = 3;
    cfg->vote_needed = 3;
}

void dsp_anom_init(dsp_anom_t *a, const dsp_anom_cfg_t *cfg) {
    memset(a, 0, sizeof(*a));
    a->cfg = *cfg;
    if (a->cfg.vote_window < 1) a->cfg.vote_window = 1;
    if (a->cfg.vote_window > DSP_ANOM_VOTE_MAX) a->cfg.vote_window = DSP_ANOM_VOTE_MAX;
    if (a->cfg.vote_needed < 1) a->cfg.vote_needed = 1;
    if (a->cfg.vote_needed > a->cfg.vote_window) a->cfg.vote_needed = a->cfg.vote_window;
    a->last_raised = DSP_ANOM_NONE;
}

/* count set votes across the active history (up to vote_window entries) */
static int count_votes(const unsigned char *hist, int count) {
    int v = 0;
    for (int i = 0; i < count; i++) v += hist[i] ? 1 : 0;
    return v;
}

dsp_anom_alert_t dsp_anom_update(dsp_anom_t *a, bool status_ok, double bpm) {
    dsp_anom_alert_t out;
    memset(&out, 0, sizeof(out));
    out.type = DSP_ANOM_NONE;

    const dsp_anom_cfg_t *c = &a->cfg;

    /* --- apnea tracking (time-based, occupancy-gated) --- */
    if (status_ok) {
        a->had_valid_breathing = true;
        a->no_breath_seconds = 0.0;
    } else {
        /* only accumulate "no breathing" time once the room is known occupied,
         * so an empty room (never any valid breathing) can't trigger apnea */
        if (a->had_valid_breathing) {
            a->no_breath_seconds += c->stride_s;
        }
    }

    /* --- rate condition votes (only meaningful when we have a trusted bpm) --- */
    unsigned char tachy = 0, brady = 0;
    if (status_ok) {
        tachy = (bpm > c->tachypnea_bpm) ? 1 : 0;
        brady = (bpm < c->bradypnea_bpm) ? 1 : 0;
    }
    a->tachy_hist[a->hist_head] = tachy;
    a->brady_hist[a->hist_head] = brady;
    a->hist_head = (a->hist_head + 1) % c->vote_window;
    if (a->hist_count < c->vote_window) a->hist_count++;

    int tachy_votes = count_votes(a->tachy_hist, a->hist_count);
    int brady_votes = count_votes(a->brady_hist, a->hist_count);

    /* --- decide, apnea first (most severe) --- */
    dsp_anom_type_t current = DSP_ANOM_NONE;
    if (a->had_valid_breathing && a->no_breath_seconds >= c->apnea_trigger_s) {
        current = DSP_ANOM_APNEA;
    } else if (tachy_votes >= c->vote_needed) {
        current = DSP_ANOM_TACHYPNEA;
    } else if (brady_votes >= c->vote_needed) {
        current = DSP_ANOM_BRADYPNEA;
    }

    /* de-dup: raise only on a transition into a condition (or a change of
     * condition), not every window while it persists. */
    if (current != DSP_ANOM_NONE && current != a->last_raised) {
        out.type = current;
        out.window = c->vote_window;
        if (current == DSP_ANOM_APNEA) {
            out.votes = c->vote_window;              /* apnea is time-based; report full */
            out.bpm = 0.0;
            out.apnea_seconds = a->no_breath_seconds;
        } else if (current == DSP_ANOM_TACHYPNEA) {
            out.votes = tachy_votes;
            out.bpm = bpm;
        } else {
            out.votes = brady_votes;
            out.bpm = bpm;
        }
    }
    a->last_raised = current;   /* track state so we don't repeat */

    return out;
}

const char *dsp_anom_type_str(dsp_anom_type_t t) {
    switch (t) {
        case DSP_ANOM_APNEA:     return "apnea";
        case DSP_ANOM_TACHYPNEA: return "tachypnea";
        case DSP_ANOM_BRADYPNEA: return "bradypnea";
        default:                 return "none";
    }
}

const char *dsp_anom_severity_str(dsp_anom_type_t t) {
    switch (t) {
        case DSP_ANOM_APNEA:     return "urgent";   /* suspected apnea = urgent */
        case DSP_ANOM_TACHYPNEA: return "warning";
        case DSP_ANOM_BRADYPNEA: return "warning";
        default:                 return "info";
    }
}
