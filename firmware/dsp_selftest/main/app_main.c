/*
 * dsp_selftest — on-device proof that the ported C DSP runs correctly on the
 * ESP32-S3 (xtensa) and matches the host/Python golden.
 *
 * Two tests:
 *   1. estimator-only: embedded stage-06 bandpass waveform -> dsp_estimate.
 *   2. per-window chain: embedded stage-02 resample window + PRE-SELECTED
 *      pairs -> CSCR -> waveform -> bandpass -> estimator. This is the real
 *      per-window pipeline. Stage 03 (pair selection) is deliberately NOT run
 *      on-device: it scores 3000 candidate DFTs and would take minutes per
 *      window. In the real system it runs ONCE at session start and the pairs
 *      are cached; here we embed the golden pairs to stand in for that.
 *
 * Big buffers are heap-allocated (the resample window is flash const; the
 * CSCR / working buffers are ~70 KB and must not go on the stack).
 */
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <math.h>

#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "esp_log.h"
#include "esp_timer.h"
#include "esp_heap_caps.h"

#include "dsp_cscr.h"
#include "dsp_waveform.h"
#include "dsp_bandpass.h"
#include "dsp_estimator.h"
#include "test_data.h"

static const char *TAG = "dsp_selftest";

#define BPM_TOL  0.05
#define CONF_TOL 0.01

static void heap_report(const char *when)
{
    printf("[heap %s] free=%u largest=%u\n", when,
           (unsigned)heap_caps_get_free_size(MALLOC_CAP_8BIT),
           (unsigned)heap_caps_get_largest_free_block(MALLOC_CAP_8BIT));
}

static int check_estimate(const dsp_estimate_t *e)
{
    int ok = 1;
    if (fabs(e->bpm_median - (double)TD_EXP_BPM_MEDIAN) > BPM_TOL) ok = 0;
    if (fabs(e->confidence - (double)TD_EXP_CONFIDENCE) > CONF_TOL) ok = 0;
    if (strcmp(dsp_status_str(e->status), TD_EXP_STATUS) != 0) ok = 0;
    return ok;
}

static void print_estimate(const dsp_estimate_t *e)
{
    printf("  bpm_fft=%.4f (g %.4f)  bpm_ac=%.4f (g %.4f)\n",
           e->bpm_fft, (double)TD_EXP_BPM_FFT, e->bpm_ac, (double)TD_EXP_BPM_AC);
    printf("  bpm_median=%.4f (g %.4f)  conf=%.4f (g %.4f)  status=%s (g %s)\n",
           e->bpm_median, (double)TD_EXP_BPM_MEDIAN, e->confidence,
           (double)TD_EXP_CONFIDENCE, dsp_status_str(e->status), TD_EXP_STATUS);
}

/* Test 1: estimator only, on the embedded bandpass waveform. */
static int test_estimator(void)
{
    printf("\n--- test 1: estimator (bandpass -> bpm) ---\n");
    dsp_est_cfg_t cfg; dsp_est_defaults(&cfg);
    dsp_estimate_t e;
    int64_t t0 = esp_timer_get_time();
    dsp_estimate(TD_BANDPASS, TD_BANDPASS_N, &cfg, &e);
    int64_t t1 = esp_timer_get_time();
    print_estimate(&e);
    printf("  time: %lld us\n", (long long)(t1 - t0));
    int ok = check_estimate(&e);
    printf("  -> %s\n", ok ? "PASS" : "FAIL");
    return ok;
}

/* Test 2: full per-window chain from the resample window + cached pairs. */
static int test_chain(void)
{
    printf("\n--- test 2: per-window chain (CSCR->waveform->bandpass->bpm) ---\n");
    const int n = TD_RESAMPLE_N;
    const int s = TD_RESAMPLE_S;
    const int p = TD_PAIRS_P;

    /* heap buffers (CSCR ~70KB, waveform/bandpass small) */
    float *cscr = (float *)malloc((size_t)n * p * 2 * sizeof(float));
    float *wave = (float *)malloc((size_t)n * sizeof(float));
    float *bp   = (float *)malloc((size_t)n * sizeof(float));
    if (!cscr || !wave || !bp) {
        printf("  FAIL: OOM (cscr=%p wave=%p bp=%p)\n",
               (void *)cscr, (void *)wave, (void *)bp);
        free(cscr); free(wave); free(bp);
        return 0;
    }

    int64_t t0 = esp_timer_get_time();
    /* stage 04: CSCR on the cached pairs */
    dsp_cscr(TD_RESAMPLE, n, s, TD_PAIRS_I, TD_PAIRS_J, p, cscr);
    /* stage 05: waveform */
    dsp_waveform(cscr, n, p, wave, NULL);
    /* stage 06: bandpass */
    dsp_bandpass(wave, n, bp, NULL);
    /* stage 07: estimator */
    dsp_est_cfg_t cfg; dsp_est_defaults(&cfg);
    dsp_estimate_t e;
    dsp_estimate(bp, n, &cfg, &e);
    int64_t t1 = esp_timer_get_time();

    print_estimate(&e);
    printf("  time (stages 04-07): %lld us\n", (long long)(t1 - t0));
    int ok = check_estimate(&e);
    printf("  -> %s\n", ok ? "PASS" : "FAIL");

    free(cscr); free(wave); free(bp);
    return ok;
}

void app_main(void)
{
    vTaskDelay(pdMS_TO_TICKS(1500));   /* let USB-Serial-JTAG settle */

    printf("\n===== dsp_selftest: full DSP chain on-device =====\n");
    heap_report("start");
    printf("resample window: %dx%d complex (flash), pairs: %d\n",
           TD_RESAMPLE_N, TD_RESAMPLE_S, TD_PAIRS_P);

    int ok1 = test_estimator();
    int ok2 = test_chain();
    heap_report("end");

    int all = ok1 && ok2;
    printf("\n===== %s =====\n",
           all ? "ALL PASS (on-device matches golden)"
               : "SOME FAILED (on-device differs from golden)");
    if (all) ESP_LOGI(TAG, "full DSP chain verified on ESP32-S3");
    else     ESP_LOGE(TAG, "DSP chain DIVERGED on-device");

    while (1) vTaskDelay(pdMS_TO_TICKS(5000));
}
