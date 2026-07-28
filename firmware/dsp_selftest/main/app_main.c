/*
 * dsp_selftest — on-device proof that the ported C DSP runs correctly on the
 * ESP32-S3 and matches the host/Python golden.
 *
 * Runs the embedded stage-06 bandpass waveform (test_data.h) through the C
 * estimator (dsp_estimate) on the actual xtensa hardware, prints the result
 * over the USB-Serial-JTAG console, and compares bpm/confidence/status against
 * the Python golden. This confirms the port survives on-device float behaviour
 * before it is wired into live CSI capture.
 *
 * Expand later: feed a resampled window through stages 03-08 too.
 */
#include <stdio.h>
#include <string.h>
#include <math.h>

#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "esp_log.h"
#include "esp_timer.h"
#include "esp_heap_caps.h"

#include "dsp_estimator.h"
#include "test_data.h"

static const char *TAG = "dsp_selftest";

#define BPM_TOL  0.05
#define CONF_TOL 0.01

void app_main(void)
{
    /* let the USB-Serial-JTAG console settle so the first lines aren't lost */
    vTaskDelay(pdMS_TO_TICKS(1500));

    printf("\n===== dsp_selftest: estimator on-device =====\n");
    printf("free heap: %u bytes, largest block: %u bytes\n",
           (unsigned)heap_caps_get_free_size(MALLOC_CAP_8BIT),
           (unsigned)heap_caps_get_largest_free_block(MALLOC_CAP_8BIT));
    printf("input: bandpass waveform, N=%d\n", TD_BANDPASS_N);

    dsp_est_cfg_t cfg;
    dsp_est_defaults(&cfg);

    dsp_estimate_t e;
    int64_t t0 = esp_timer_get_time();
    dsp_estimate(TD_BANDPASS, TD_BANDPASS_N, &cfg, &e);
    int64_t t1 = esp_timer_get_time();

    printf("\n--- result ---\n");
    printf("bpm_fft    = %.4f  (golden %.4f)\n", e.bpm_fft, (double)TD_EXP_BPM_FFT);
    printf("bpm_ac     = %.4f  (golden %.4f)\n", e.bpm_ac, (double)TD_EXP_BPM_AC);
    printf("bpm_median = %.4f  (golden %.4f)\n", e.bpm_median, (double)TD_EXP_BPM_MEDIAN);
    printf("confidence = %.4f  (golden %.4f)\n", e.confidence, (double)TD_EXP_CONFIDENCE);
    printf("status     = %s  (golden %s)\n", dsp_status_str(e.status), TD_EXP_STATUS);
    printf("compute time: %lld us\n", (long long)(t1 - t0));

    int ok = 1;
    if (fabs(e.bpm_median - (double)TD_EXP_BPM_MEDIAN) > BPM_TOL) ok = 0;
    if (fabs(e.confidence - (double)TD_EXP_CONFIDENCE) > CONF_TOL) ok = 0;
    if (strcmp(dsp_status_str(e.status), TD_EXP_STATUS) != 0) ok = 0;

    printf("\n===== %s =====\n", ok ? "PASS (on-device matches golden)"
                                    : "FAIL (on-device differs from golden)");
    if (ok) {
        ESP_LOGI(TAG, "on-device DSP estimator verified against golden");
    } else {
        ESP_LOGE(TAG, "on-device DSP estimator DIVERGED from golden");
    }

    /* idle */
    while (1) {
        vTaskDelay(pdMS_TO_TICKS(5000));
    }
}
