/* dsp_estimator.h — Stage 07: FFT + autocorrelation dual estimator + gate.
 *
 * Port of bpm_from_fft(), bpm_from_autocorrelation(), and the combine/gate
 * logic in _estimate_from_complex() (firmware/components/dsp_breathing/
 * breathing.py).
 *
 * Takes the preprocessed respiratory waveform (stage 06 output) and produces
 * breaths-per-minute plus a confidence and a trust status.
 */
#ifndef DSP_ESTIMATOR_H
#define DSP_ESTIMATOR_H

typedef enum {
    DSP_STATUS_OK = 0,
    DSP_STATUS_LOW_CONFIDENCE,
    DSP_STATUS_DISAGREEMENT,
    DSP_STATUS_NO_VALID_BREATHING,
} dsp_status_t;

typedef struct {
    double bpm_fft;
    double conf_fft;
    double bpm_ac;
    double conf_ac;
    double bpm_median;
    double confidence;
    int agreement;          /* 0/1 */
    dsp_status_t status;
} dsp_estimate_t;

/* Config knobs (Python DEFAULTS). */
typedef struct {
    double sample_rate;         /* 10.0 */
    double low_hz, high_hz;     /* 0.1, 0.5 */
    double min_bpm, max_bpm;    /* 6.0, 30.0 */
    double agreement_bpm;       /* 2.0 */
    double min_confidence;      /* 0.3 */
} dsp_est_cfg_t;

/* Fill `cfg` with the Python DEFAULTS. */
void dsp_est_defaults(dsp_est_cfg_t *cfg);

/* Individual estimators (exposed for testing). Return bpm via *bpm and
 * confidence via *conf; bpm is NAN when no valid estimate. */
void dsp_bpm_fft(const float *x, int n, const dsp_est_cfg_t *cfg,
                 double *bpm, double *conf);
void dsp_bpm_autocorr(const float *x, int n, const dsp_est_cfg_t *cfg,
                      double *bpm, double *conf);

/* Full estimator: waveform -> estimate + gate. */
void dsp_estimate(const float *x, int n, const dsp_est_cfg_t *cfg,
                  dsp_estimate_t *out);

const char *dsp_status_str(dsp_status_t s);

#endif /* DSP_ESTIMATOR_H */
