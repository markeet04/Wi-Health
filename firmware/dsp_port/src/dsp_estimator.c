/* dsp_estimator.c — Stage 07 implementation. See dsp_estimator.h. */
#include "dsp_estimator.h"
#include "dsp_fft.h"

#include <math.h>
#include <stdlib.h>
#include <stddef.h>

void dsp_est_defaults(dsp_est_cfg_t *cfg) {
    cfg->sample_rate = 10.0;
    cfg->low_hz = 0.1;
    cfg->high_hz = 0.5;
    cfg->min_bpm = 6.0;
    cfg->max_bpm = 30.0;
    cfg->agreement_bpm = 2.0;
    cfg->min_confidence = 0.3;
}

static int next_pow2(int v) {
    int p = 1;
    while (p < v) p <<= 1;
    return p;
}

/* bpm_from_fft: zero-mean, zero-pad to nfft=next_pow2(max(n*4,128)), rFFT,
 * peak within band, confidence = peak_mag / mean_mag(full spectrum). */
void dsp_bpm_fft(const float *x, int n, const dsp_est_cfg_t *cfg,
                 double *bpm, double *conf) {
    *bpm = NAN; *conf = 0.0;
    if (n < 16) return;

    double mean = 0.0;
    for (int i = 0; i < n; i++) mean += (double)x[i];
    mean /= n;
    double var = 0.0;
    for (int i = 0; i < n; i++) { double d = (double)x[i] - mean; var += d * d; }
    if (sqrt(var / n) < 1e-9) return;

    int want = n * 4; if (want < 128) want = 128;
    int nfft = next_pow2(want);

    double *xm = (double *)malloc((size_t)n * sizeof(double));
    double *mag = (double *)malloc((size_t)(nfft / 2 + 1) * sizeof(double));
    if (!xm || !mag) { free(xm); free(mag); return; }
    for (int i = 0; i < n; i++) xm[i] = (double)x[i] - mean;

    dsp_rfft_mag(xm, n, nfft, mag);

    int nb = nfft / 2 + 1;
    double df = cfg->sample_rate / (double)nfft;  /* rfftfreq spacing */
    int peak_idx = -1;
    double peak_mag = -1.0;
    double sum_mag = 0.0;
    for (int k = 0; k < nb; k++) {
        sum_mag += mag[k];
        double f = (double)k * df;
        if (f >= cfg->low_hz && f <= cfg->high_hz && mag[k] > peak_mag) {
            peak_mag = mag[k];
            peak_idx = k;
        }
    }
    if (peak_idx < 0) { free(xm); free(mag); return; }

    double peak_freq = (double)peak_idx * df;
    double mean_mag = sum_mag / (double)nb + 1e-12;
    *bpm = peak_freq * 60.0;
    *conf = mag[peak_idx] / mean_mag;
    free(xm); free(mag);
}

/* bpm_from_autocorrelation: biased autocorr via FFT, first significant local
 * peak in the lag range [fs/high, fs/low], confidence = peak/ac[0]. */
void dsp_bpm_autocorr(const float *x, int n, const dsp_est_cfg_t *cfg,
                      double *bpm, double *conf) {
    *bpm = NAN; *conf = 0.0;
    if (n < 16) return;

    double mean = 0.0;
    for (int i = 0; i < n; i++) mean += (double)x[i];
    mean /= n;
    double var = 0.0;
    for (int i = 0; i < n; i++) { double d = (double)x[i] - mean; var += d * d; }
    if (sqrt(var / n) < 1e-9) return;

    double *xm = (double *)malloc((size_t)n * sizeof(double));
    double *ac = (double *)malloc((size_t)n * sizeof(double));
    if (!xm || !ac) { free(xm); free(ac); return; }
    for (int i = 0; i < n; i++) xm[i] = (double)x[i] - mean;

    int nfft = next_pow2(2 * n);
    dsp_autocorr(xm, n, nfft, ac);

    double ac0 = ac[0];
    if (ac0 <= 0.0) { free(xm); free(ac); return; }

    int lag_min = (int)floor(cfg->sample_rate / cfg->high_hz);
    int lag_max = (int)ceil(cfg->sample_rate / cfg->low_hz);
    if (lag_min < 1) lag_min = 1;
    if (lag_max > n - 1) lag_max = n - 1;
    if (lag_max <= lag_min) { free(xm); free(ac); return; }

    /* segment = ac[lag_min .. lag_max]; first local peak, else global argmax */
    int seg_n = lag_max - lag_min + 1;
    int peak_off = -1;
    for (int i = 1; i < seg_n - 1; i++) {
        double a = ac[lag_min + i - 1], b = ac[lag_min + i], c = ac[lag_min + i + 1];
        if (b > a && b > c) { peak_off = i; break; }
    }
    if (peak_off < 0) {
        double best = ac[lag_min]; peak_off = 0;
        for (int i = 1; i < seg_n; i++) {
            if (ac[lag_min + i] > best) { best = ac[lag_min + i]; peak_off = i; }
        }
    }
    int lag = lag_min + peak_off;
    double freq = cfg->sample_rate / (double)lag;
    *bpm = freq * 60.0;
    *conf = ac[lag] / ac0;
    free(xm); free(ac);
}

static double median2(double a, double b) { return 0.5 * (a + b); }

void dsp_estimate(const float *x, int n, const dsp_est_cfg_t *cfg,
                  dsp_estimate_t *out) {
    dsp_bpm_fft(x, n, cfg, &out->bpm_fft, &out->conf_fft);
    dsp_bpm_autocorr(x, n, cfg, &out->bpm_ac, &out->conf_ac);

    int valid_fft = isfinite(out->bpm_fft) &&
                    out->bpm_fft >= cfg->min_bpm && out->bpm_fft <= cfg->max_bpm;
    int valid_ac = isfinite(out->bpm_ac) &&
                   out->bpm_ac >= cfg->min_bpm && out->bpm_ac <= cfg->max_bpm;

    if (valid_fft && valid_ac) {
        out->bpm_median = median2(out->bpm_fft, out->bpm_ac);
        out->agreement = fabs(out->bpm_fft - out->bpm_ac) <= cfg->agreement_bpm;
        out->confidence = (out->conf_fft < out->conf_ac) ? out->conf_fft : out->conf_ac;
    } else if (valid_fft) {
        out->bpm_median = out->bpm_fft; out->agreement = 0;
        out->confidence = out->conf_fft * 0.5;
    } else if (valid_ac) {
        out->bpm_median = out->bpm_ac; out->agreement = 0;
        out->confidence = out->conf_ac * 0.5;
    } else {
        out->bpm_median = NAN; out->agreement = 0; out->confidence = 0.0;
    }

    if (!(valid_fft || valid_ac)) {
        out->status = DSP_STATUS_NO_VALID_BREATHING;
    } else if (!out->agreement) {
        out->status = DSP_STATUS_DISAGREEMENT;
    } else if (out->confidence < cfg->min_confidence) {
        out->status = DSP_STATUS_LOW_CONFIDENCE;
    } else {
        out->status = DSP_STATUS_OK;
    }
}

const char *dsp_status_str(dsp_status_t s) {
    switch (s) {
        case DSP_STATUS_OK: return "ok";
        case DSP_STATUS_LOW_CONFIDENCE: return "low_confidence";
        case DSP_STATUS_DISAGREEMENT: return "disagreement";
        case DSP_STATUS_NO_VALID_BREATHING: return "no_valid_breathing";
        default: return "unknown";
    }
}
