/*
 * dsp_live — live on-device breathing monitor (ESP32-S3).
 *
 * Captures CSI from the paired tx_csi_send board (reusing the validated
 * rx_csi_recv WiFi/CSI setup), buffers a sliding 30 s window into a PSRAM
 * ring buffer, and every 5 s runs the ported C DSP chain to print a live
 * breathing rate over the USB-Serial-JTAG console.
 *
 * Pipeline per window (matches the host-validated dsp_port chain):
 *   raw CSI ring -> null-drop -> resample(10 Hz, us timestamps) ->
 *   [pairs selected ONCE, cached] -> CSCR -> waveform -> bandpass ->
 *   motion gate -> FFT+autocorr estimator + gate -> bpm/conf/status.
 *
 * Two contexts:
 *   - CSI RX callback (WiFi task): parse + gain-compensate + push one sample
 *     (complex[S] + timestamp) into the ring. Fast, non-blocking.
 *   - DSP task: snapshots the ring and runs the chain (~0.4 s). Runs on the
 *     APP cpu so it never stalls packet reception on the PRO cpu.
 *
 * No Firebase yet (Module 4). Output is serial only.
 */
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <math.h>

#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "freertos/semphr.h"

#include "nvs_flash.h"
#include "esp_mac.h"
#include "rom/ets_sys.h"
#include "esp_log.h"
#include "esp_wifi.h"
#include "esp_netif.h"
#include "esp_now.h"
#include "esp_timer.h"
#include "esp_heap_caps.h"
#include "esp_csi_gain_ctrl.h"

#include "dsp_frontend.h"
#include "dsp_pairs.h"
#include "dsp_cscr.h"
#include "dsp_waveform.h"
#include "dsp_bandpass.h"
#include "dsp_motion.h"
#include "dsp_estimator.h"
#include "dsp_smooth.h"
#include "dsp_anomaly.h"

/* ================= config (mirror rx_csi_recv) ================= */
#define WIFI_CHANNEL 6
#define CONFIG_LESS_INTERFERENCE_CHANNEL WIFI_CHANNEL
#define CONFIG_WIFI_BANDWIDTH            WIFI_BW_HT20
#define CONFIG_ESP_NOW_PHYMODE           WIFI_PHY_MODE_HT20
#define CONFIG_ESP_NOW_RATE              WIFI_PHY_RATE_MCS0_LGI
#define CONFIG_FORCE_GAIN                0
#define CONFIG_GAIN_CONTROL              1

static const uint8_t CONFIG_CSI_SEND_MAC[] = {0x1a, 0x00, 0x00, 0x00, 0x00, 0x00};
static const char *TAG = "dsp_live";

/* ================= Module 4: result broadcast to the uploader =============
 * After each window, RX broadcasts the derived breathing result over ESP-NOW.
 * A separate "uploader" board (STA-joined to a router) receives this and writes
 * it to Firebase /devices/$id/live — RX itself can't do that (it is locked in
 * promiscuous mode on the CSI channel, not associated to an AP). The packet
 * layout is the shared firmware/shared/wihealth_result.h contract so RX and
 * the uploader can never disagree on the bytes. */
#include "wihealth_result.h"

/* broadcast address — the uploader listens as a broadcast peer on the same
 * channel; we don't need to know its MAC in advance. */
static const uint8_t BROADCAST_MAC[6] = {0xff, 0xff, 0xff, 0xff, 0xff, 0xff};

/* ================= DSP window params ================= */
#define FS_HZ            10.0     /* resample target rate */
#define WINDOW_SEC       30.0
#define STRIDE_SEC       5.0
#define PAIR_RESELECT_WINDOWS 6   /* re-select pairs every N windows (~30 s) */
/* raw CSI arrives ~90-100 pkt/s; hold >30 s with a little headroom */
#define RING_SECONDS     33
#define RING_PKT_PER_SEC 100
#define RING_CAP         (RING_SECONDS * RING_PKT_PER_SEC)   /* 3300 packets */
#define WINDOW_PKTS      (int)(WINDOW_SEC * RING_PKT_PER_SEC) /* 3000 */
#define MAX_SUBC         128     /* S3 HT20 CSI: info->len/2 complex subcarriers */

/* one captured packet: S complex subcarriers + a microsecond timestamp */
typedef struct {
    uint32_t ts_us;           /* rx_ctrl->timestamp (local, microseconds) */
    int16_t  re[MAX_SUBC];    /* gain-compensated I */
    int16_t  im[MAX_SUBC];    /* gain-compensated Q */
    int16_t  s;               /* number of complex subcarriers this packet */
} csi_sample_t;

/* ring buffer in PSRAM */
static csi_sample_t *s_ring = NULL;
static volatile int  s_head = 0;      /* next write index */
static volatile int  s_count = 0;     /* total pushed (monotonic) */
static SemaphoreHandle_t s_ring_mtx;

/* cached subcarrier pairs (selected once) */
static int s_pair_i[64];
static int s_pair_j[64];
static int s_pair_count = 0;
static int s_active_s = 0;    /* subcarrier count locked with the pairs */

static dsp_motion_gate_t s_gate;

/* ================= WiFi / CSI init (verbatim from rx_csi_recv) ============ */
static void wifi_init(void)
{
    ESP_ERROR_CHECK(esp_event_loop_create_default());
    ESP_ERROR_CHECK(esp_netif_init());
    wifi_init_config_t cfg = WIFI_INIT_CONFIG_DEFAULT();
    ESP_ERROR_CHECK(esp_wifi_init(&cfg));
    ESP_ERROR_CHECK(esp_wifi_set_mode(WIFI_MODE_STA));
    ESP_ERROR_CHECK(esp_wifi_set_storage(WIFI_STORAGE_RAM));
    ESP_ERROR_CHECK(esp_wifi_set_bandwidth(WIFI_IF_STA, CONFIG_WIFI_BANDWIDTH));
    ESP_ERROR_CHECK(esp_wifi_start());
    ESP_ERROR_CHECK(esp_wifi_set_ps(WIFI_PS_NONE));
    ESP_ERROR_CHECK(esp_wifi_set_channel(CONFIG_LESS_INTERFERENCE_CHANNEL, WIFI_SECOND_CHAN_NONE));
    ESP_ERROR_CHECK(esp_wifi_set_mac(WIFI_IF_STA, CONFIG_CSI_SEND_MAC));
}

/* ===== Channel auto-discovery (RX side) =====
 * The uploader is associated to the user's router and can only send ESP-NOW on
 * that (unknown) channel. The RX is free (promiscuous, not associated), so IT
 * does the finding: it sweeps channels 1..13 listening for the uploader's
 * channel-announce beacon. On hearing it, the RX LOCKS to that channel and
 * re-broadcasts the beacon so the TX (sweeping the same way) converges too.
 *
 * FALLBACK-FIRST: sweeping only runs until a beacon is found OR a bounded
 * timeout elapses. If no uploader is present, the RX settles back on the
 * compiled default channel and behaves exactly as before (TX+RX both default). */
static volatile uint8_t s_active_channel = CONFIG_LESS_INTERFERENCE_CHANNEL;
static volatile bool    s_channel_locked = false;
static volatile bool    s_channel_settled = false;  /* scan finished (locked or default) */

/* How long to sweep for the uploader before giving up and using the default. */
#define CHAN_SCAN_TIMEOUT_MS  60000
#define CHAN_SCAN_DWELL_MS      600
#define CHAN_MAX                 13

static void set_channel(uint8_t ch)
{
    if (ch < 1 || ch > CHAN_MAX) return;
    if (esp_wifi_set_channel(ch, WIFI_SECOND_CHAN_NONE) == ESP_OK) {
        s_active_channel = ch;
    }
}

/* Lock onto the announced channel (called from the ESP-NOW recv cb). */
static void lock_channel(uint8_t ch)
{
    if (ch < 1 || ch > CHAN_MAX) return;
    if (!s_channel_locked || ch != s_active_channel) {
        set_channel(ch);
        s_channel_locked = true;
        ESP_LOGW(TAG, "channel auto-discovery: locked to channel %u", (unsigned)ch);
    }
}

/* Re-broadcast the locked channel so the TX converges to us. */
static void rebroadcast_channel(uint8_t ch)
{
    static const uint8_t BCAST[6] = {0xff, 0xff, 0xff, 0xff, 0xff, 0xff};
    wihealth_ctrl_t ctrl = {
        .magic = WIHEALTH_CTRL_MAGIC,
        .version = WIHEALTH_CTRL_VER,
        .channel = ch,
    };
    esp_now_send(BCAST, (const uint8_t *)&ctrl, sizeof(ctrl));
}

/* ESP-NOW receive: the RX only cares about the channel-announce beacon. */
static void espnow_recv_cb(const esp_now_recv_info_t *info, const uint8_t *data, int len)
{
    (void)info;
    if (len < (int)sizeof(wihealth_ctrl_t)) return;
    const wihealth_ctrl_t *c = (const wihealth_ctrl_t *)data;
    if (c->magic != WIHEALTH_CTRL_MAGIC || c->version != WIHEALTH_CTRL_VER) return;
    lock_channel(c->channel);
}

/* Sweep channels until a beacon locks us, or the timeout elapses (then settle on
 * the compiled default). Runs once at startup; exits as soon as we're locked so
 * CSI capture proceeds undisturbed on the found channel. */
static void channel_scan_task(void *arg)
{
    (void)arg;
    int64_t start = esp_timer_get_time();
    uint8_t ch = 1;
    while (!s_channel_locked &&
           (esp_timer_get_time() - start) < (int64_t)CHAN_SCAN_TIMEOUT_MS * 1000) {
        set_channel(ch);
        vTaskDelay(pdMS_TO_TICKS(CHAN_SCAN_DWELL_MS));
        ch = (ch % CHAN_MAX) + 1;
    }
    if (!s_channel_locked) {
        /* No uploader found — behave like the original single-channel rig. */
        set_channel(CONFIG_LESS_INTERFERENCE_CHANNEL);
        ESP_LOGW(TAG, "channel auto-discovery: no beacon, using default channel %d",
                 CONFIG_LESS_INTERFERENCE_CHANNEL);
    }
    /* Let CSI buffering/DSP proceed now that the channel is fixed. */
    s_channel_settled = true;
    if (s_channel_locked) {
        /* Help the TX converge: re-announce the locked channel for a few seconds. */
        for (int i = 0; i < 20; ++i) {
            rebroadcast_channel(s_active_channel);
            vTaskDelay(pdMS_TO_TICKS(500));
        }
    }
    vTaskDelete(NULL);
}

/* Self-heal: if the AP channel roams (phone hotspots do this), the TX and RX can
 * end up on different channels and CSI stops flowing. This monitor watches the
 * CSI packet counter; if we're locked but no packets have arrived for a while,
 * it unlocks and re-launches the scan so both boards re-find the (moved) channel
 * — no physical reset needed. Plain FreeRTOS polling task (yields every second);
 * unrelated to the IDF task-WDT, which stays disabled. */
#define CSI_STALL_TIMEOUT_MS  15000
static void channel_watchdog_task(void *arg)
{
    (void)arg;
    int last_count = 0;
    int64_t last_progress = esp_timer_get_time();
    int tick = 0;
    while (1) {
        vTaskDelay(pdMS_TO_TICKS(1000));

        /* While locked, periodically re-announce our channel so a TX that
         * drifted (AP roam) has a beacon to re-sync to. Cheap, every ~4s. */
        if (s_channel_locked && (++tick % 4) == 0) {
            rebroadcast_channel(s_active_channel);
        }

        /* Only meaningful once we've locked to a discovered channel and the
         * scan has settled (not during initial sweep / default fallback). */
        if (!s_channel_locked || !s_channel_settled) {
            last_count = s_count;
            last_progress = esp_timer_get_time();
            continue;
        }

        if (s_count != last_count) {
            last_count = s_count;
            last_progress = esp_timer_get_time();
            continue;
        }

        if ((esp_timer_get_time() - last_progress) > (int64_t)CSI_STALL_TIMEOUT_MS * 1000) {
            ESP_LOGW(TAG, "channel auto-discovery: CSI stalled — re-scanning (AP channel may have moved)");
            s_channel_locked = false;
            s_channel_settled = false;   /* DSP keeps running; scan gates only initial start */
            xTaskCreatePinnedToCore(channel_scan_task, "chan_scan", 3072, NULL, 6, NULL, 0);
            /* Wait for the re-scan to settle before monitoring again. */
            while (!s_channel_settled) vTaskDelay(pdMS_TO_TICKS(200));
            last_count = s_count;
            last_progress = esp_timer_get_time();
        }
    }
}

static void wifi_esp_now_init(esp_now_peer_info_t peer)
{
    ESP_ERROR_CHECK(esp_now_init());
    ESP_ERROR_CHECK(esp_now_set_pmk((uint8_t *)"pmk1234567890123"));
    ESP_ERROR_CHECK(esp_now_add_peer(&peer));
    /* Listen for the uploader's channel-announce beacon (auto-discovery). */
    ESP_ERROR_CHECK(esp_now_register_recv_cb(espnow_recv_cb));
    /* S3: per-peer rate cfg faults; use the global API. */
    ESP_ERROR_CHECK(esp_wifi_config_espnow_rate(WIFI_IF_STA, CONFIG_ESP_NOW_RATE));
}

/* Broadcast one breathing result over ESP-NOW to the uploader board. Non-fatal
 * on error (the monitor keeps working even if no uploader is listening). */
static void send_result(uint32_t seq, float bpm, float confidence,
                        float signal_quality, uint8_t status,
                        uint8_t alert_type, uint8_t alert_votes)
{
    wihealth_result_t pkt = {
        .magic = WIHEALTH_RESULT_MAGIC,
        .version = WIHEALTH_RESULT_VER,
        .status = status,
        .alert_type = alert_type,
        .alert_votes = alert_votes,
        .bpm = bpm,
        .confidence = confidence,
        .signal_quality = signal_quality,
        .seq = seq,
    };
    esp_err_t err = esp_now_send(BROADCAST_MAC, (const uint8_t *)&pkt, sizeof(pkt));
    if (err != ESP_OK) {
        ESP_LOGD(TAG, "esp_now_send result failed: %s", esp_err_to_name(err));
    }
}

/* ================= CSI callback: parse + push to ring ================= */
static void wifi_csi_rx_cb(void *ctx, wifi_csi_info_t *info)
{
    if (!info || !info->buf) return;
    if (memcmp(info->mac, CONFIG_CSI_SEND_MAC, 6)) return;   /* our TX only */

    const wifi_pkt_rx_ctrl_t *rx_ctrl = &info->rx_ctrl;

    /* gain compensation, same baseline logic as rx_csi_recv */
    float compensate_gain = 1.0f;
    static int cb_count = 0;
#if CONFIG_GAIN_CONTROL
    static uint8_t agc_gain = 0; static int8_t fft_gain = 0;
    static uint8_t agc_base = 0; static int8_t fft_base = 0;
    esp_csi_gain_ctrl_get_rx_gain(rx_ctrl, &agc_gain, &fft_gain);
    if (cb_count < 100) {
        esp_csi_gain_ctrl_record_rx_gain(agc_gain, fft_gain);
    } else if (cb_count == 100) {
        esp_csi_gain_ctrl_get_rx_gain_baseline(&agc_base, &fft_base);
    }
    esp_csi_gain_ctrl_get_gain_compensation(&compensate_gain, agc_gain, fft_gain);
#endif
    cb_count++;

    /* raw buf is interleaved I/Q int8; len bytes -> len/2 complex subcarriers */
    int s = info->len / 2;
    if (s > MAX_SUBC) s = MAX_SUBC;
    if (s < 4) return;

    /* build the sample outside the lock, then commit under it */
    static csi_sample_t tmp;   /* callback is single-threaded (WiFi task) */
    tmp.ts_us = rx_ctrl->timestamp;
    tmp.s = s;
    for (int k = 0; k < s; k++) {
        int8_t i8 = (int8_t)info->buf[2 * k + 0];
        int8_t q8 = (int8_t)info->buf[2 * k + 1];
        tmp.re[k] = (int16_t)(compensate_gain * i8);
        tmp.im[k] = (int16_t)(compensate_gain * q8);
    }

    if (xSemaphoreTake(s_ring_mtx, 0) == pdTRUE) {   /* never block the WiFi task */
        memcpy(&s_ring[s_head], &tmp, sizeof(csi_sample_t));
        s_head = (s_head + 1) % RING_CAP;
        s_count++;
        xSemaphoreGive(s_ring_mtx);
    }
    /* if the lock was held (DSP snapshotting), we drop this packet — rare and
     * harmless: the resampler tolerates jitter/gaps. */
}

static void wifi_csi_init(void)
{
    ESP_ERROR_CHECK(esp_wifi_set_promiscuous(true));
    wifi_csi_config_t csi_config = {
        .lltf_en           = true,
        .htltf_en          = true,
        .stbc_htltf2_en    = true,
        .ltf_merge_en      = true,
        .channel_filter_en = true,
        .manu_scale        = false,
        .shift             = false,
    };
    ESP_ERROR_CHECK(esp_wifi_set_csi_config(&csi_config));
    ESP_ERROR_CHECK(esp_wifi_set_csi_rx_cb(wifi_csi_rx_cb, NULL));
    ESP_ERROR_CHECK(esp_wifi_set_csi(true));
}

/* ================= DSP task ================= */

/* Snapshot the most recent packets covering ~WINDOW_SEC into raw int16 re/im
 * arrays + timestamps (seconds). Returns packet count (oldest-first); s_out is
 * the common subcarrier width. The int16 copy is ~4x smaller than a float
 * copy and feeds dsp_frontend directly (fused null-drop + resample), so no
 * multi-MB float window buffer is needed. */
static int snapshot_window(int16_t *re, int16_t *im, double *ts, int cap, int *s_out)
{
    /* hold the lock only to read head/count (not during the copy) */
    xSemaphoreTake(s_ring_mtx, portMAX_DELAY);
    int total = s_count;
    int head = s_head;
    xSemaphoreGive(s_ring_mtx);

    int have = (total < RING_CAP) ? total : RING_CAP;
    int take = (have < WINDOW_PKTS) ? have : WINDOW_PKTS;
    if (take > cap) take = cap;
    if (take < 1) { *s_out = 0; return 0; }

    int start = (head - take + RING_CAP) % RING_CAP;
    uint32_t t0_us = s_ring[start].ts_us;
    int s_common = s_ring[start].s;

    int n = 0;
    for (int k = 0; k < take; k++) {
        int idx = (start + k) % RING_CAP;
        csi_sample_t *smp = &s_ring[idx];
        int s = smp->s;
        if (s > s_common) s = s_common;
        uint32_t dt = smp->ts_us - t0_us;   /* uint32 subtraction handles wrap */
        ts[k] = (double)dt / 1e6;
        for (int c = 0; c < s_common; c++) {
            re[(size_t)k * s_common + c] = (c < s) ? smp->re[c] : 0;
            im[(size_t)k * s_common + c] = (c < s) ? smp->im[c] : 0;
        }
        n++;
    }
    *s_out = s_common;
    return n;
}

static void dsp_task(void *arg)
{
    (void)arg;
    dsp_motion_init(&s_gate);

    /* Wait until channel auto-discovery has settled so we buffer on the correct
     * channel. Then flush any packets the ring caught while sweeping (they may
     * be from other channels / stale). */
    while (!s_channel_settled) {
        vTaskDelay(pdMS_TO_TICKS(100));
    }
    if (xSemaphoreTake(s_ring_mtx, portMAX_DELAY) == pdTRUE) {
        s_head = 0;
        xSemaphoreGive(s_ring_mtx);
    }

    /* Buffers in PSRAM. The raw window is now int16 (not float) — ~4x smaller
     * — and feeds dsp_frontend directly, which emits only the small resampled
     * float matrix Huni. No multi-MB float window buffers. */
    const int cap_pkts = WINDOW_PKTS;
    int16_t *raw_re = heap_caps_malloc((size_t)cap_pkts * MAX_SUBC * sizeof(int16_t), MALLOC_CAP_SPIRAM);
    int16_t *raw_im = heap_caps_malloc((size_t)cap_pkts * MAX_SUBC * sizeof(int16_t), MALLOC_CAP_SPIRAM);
    double  *ts     = heap_caps_malloc((size_t)cap_pkts * sizeof(double), MALLOC_CAP_SPIRAM);
    double  *medbuf = heap_caps_malloc((size_t)cap_pkts * sizeof(double), MALLOC_CAP_SPIRAM);
    int     *kept   = heap_caps_malloc((size_t)MAX_SUBC * sizeof(int), MALLOC_CAP_SPIRAM);
    /* Resampled length = span_seconds * FS + 1. The snapshot takes up to
     * WINDOW_PKTS packets; at the *slowest* plausible rate (~70 pps) that spans
     * more than WINDOW_SEC, so size the grid for the worst case with headroom
     * (WINDOW_PKTS packets could be ~WINDOW_PKTS/70 s). */
    int uni_cap = (int)((double)WINDOW_PKTS / 70.0 * FS_HZ) + 16;
    float *Huni = heap_caps_malloc((size_t)uni_cap * MAX_SUBC * 2 * sizeof(float), MALLOC_CAP_SPIRAM);
    float *cscr = heap_caps_malloc((size_t)uni_cap * 64 * 2 * sizeof(float), MALLOC_CAP_SPIRAM);
    float *wave = heap_caps_malloc((size_t)uni_cap * sizeof(float), MALLOC_CAP_SPIRAM);
    float *bp   = heap_caps_malloc((size_t)uni_cap * sizeof(float), MALLOC_CAP_SPIRAM);

    if (!raw_re || !raw_im || !ts || !medbuf || !kept || !Huni || !cscr || !wave || !bp) {
        ESP_LOGE(TAG, "PSRAM alloc failed — cannot run DSP");
        vTaskDelete(NULL);
        return;
    }
    ESP_LOGI(TAG, "DSP buffers in PSRAM: raw int16 window %.1f MB + scratch",
             2.0 * cap_pkts * MAX_SUBC * sizeof(int16_t) / 1024.0 / 1024.0);

    dsp_est_cfg_t ecfg; dsp_est_defaults(&ecfg);
    dsp_smoother_t smoother; dsp_smooth_init(&smoother, 6);
    dsp_anom_cfg_t acfg; dsp_anom_defaults(&acfg);
    acfg.stride_s = STRIDE_SEC;
    dsp_anom_t anom; dsp_anom_init(&anom, &acfg);
    double s_last_ok_conf = 0.0, s_last_ok_sq = 0.0;  /* conf/SQ of latest trusted window */
    int s_last_ok_window = -1;   /* window_idx of the most recent valid (ok) window */
    int valid_windows = 0;
    int window_idx = 0;

    /* Staleness guard: the smoothed reading is only reported as a live rate if a
     * valid window landed within this many seconds. Smoothing rides out
     * per-window noise, but a health monitor must NOT show a stale rate that
     * looks current — if the signal degrades (a run of disagreement/low-conf
     * windows, which do NOT trip the apnea reset), blank the rate after this.
     * ~30 s = one window length; long enough to not flicker on a single bad
     * window, short enough that a real loss of signal surfaces promptly. */
    const double STALE_AFTER_S = 30.0;

    while (1) {
        /* wait until we have at least one full window of data */
        if (s_count < cap_pkts) {
            printf("buffering... %d / %d packets\n", s_count, cap_pkts);
            vTaskDelay(pdMS_TO_TICKS(2000));
            continue;
        }

        int64_t t_start = esp_timer_get_time();

        int s_raw = 0;
        int n = snapshot_window(raw_re, raw_im, ts, cap_pkts, &s_raw);
        if (n < 32 || s_raw < 4) { vTaskDelay(pdMS_TO_TICKS((int)(STRIDE_SEC*1000))); continue; }

        /* stages 01+02 fused: null-drop + resample straight from int16 -> Huni */
        int s_act = 0;
        int m = dsp_frontend(raw_re, raw_im, ts, n, s_raw, 2.0f, FS_HZ,
                             Huni, kept, &s_act, uni_cap, medbuf);
        if (m < 16 || s_act < 4) {
            printf("window %d: front-end produced too little (m=%d s=%d) — skip\n",
                   window_idx, m, s_act);
            window_idx++;
            vTaskDelay(pdMS_TO_TICKS((int)(STRIDE_SEC*1000)));
            continue;
        }

        /* motion gate on the resampled window (complex) */
        double mscore = 0, mbase = 0;
        int is_motion = dsp_motion_check(&s_gate, Huni, m, s_act, &mscore, &mbase);

        /* stage 03: (re)select subcarrier pairs. Now that scoring is float32
         * (fast on the S3 FPU), we re-select periodically so the pairs stay
         * matched to the live signal — selecting once from the opening window
         * (which may be during settling/movement) gave poor pairs and few
         * trusted windows. Re-select on the first window and every
         * PAIR_RESELECT_WINDOWS thereafter. */
        if (s_pair_count == 0 || (window_idx % PAIR_RESELECT_WINDOWS) == 0) {
            int64_t tp = esp_timer_get_time();
            int np = dsp_select_pairs(Huni, m, s_act, 20, 0.1, 0.5, FS_HZ,
                                      s_pair_i, s_pair_j);
            if (np >= 1) { s_pair_count = np; s_active_s = s_act; }
            printf("  [pairs re-selected: %d in %lld ms]\n", s_pair_count,
                   (long long)((esp_timer_get_time() - tp) / 1000));
        }
        if (s_pair_count < 1) { window_idx++; vTaskDelay(pdMS_TO_TICKS((int)(STRIDE_SEC*1000))); continue; }

        if (is_motion) {
            printf("window %d: MOTION DETECTED (score %.4f vs base %.4f) — skipped\n",
                   window_idx, mscore, mbase);
            window_idx++;
            vTaskDelay(pdMS_TO_TICKS((int)(STRIDE_SEC*1000)));
            continue;
        }

        /* stages 04-07: CSCR -> waveform -> bandpass -> estimator */
        dsp_cscr(Huni, m, s_act, s_pair_i, s_pair_j, s_pair_count, cscr);
        dsp_waveform(cscr, m, s_pair_count, wave, NULL);
        dsp_bandpass(wave, m, bp, NULL);
        dsp_estimate_t e;
        dsp_estimate(bp, m, &ecfg, &e);

        int64_t t_ms = (esp_timer_get_time() - t_start) / 1000;

        /* Only valid (status=ok) windows feed the rolling-median smoother, so a
         * single noisy window is outvoted instead of standing alone. The
         * SMOOTHED value is the trustworthy reading (like the Python
         * `smoothed=` column); the raw per-window bpm is shown for context. */
        double smoothed = NAN;
        int smooth_n = 0;
        if (e.status == DSP_STATUS_OK) {
            valid_windows++;
            dsp_smooth_push(&smoother, e.bpm_median);
            /* remember the confidence/signalQuality of the latest TRUSTED window,
             * so a smoothed-OK report carries a coherent (trusted) confidence
             * rather than the current possibly-noisy window's low value. */
            s_last_ok_conf = e.confidence;
            s_last_ok_sq   = e.signal_quality;
            s_last_ok_window = window_idx;
        }
        smoothed = dsp_smooth_value(&smoother);
        smooth_n = dsp_smooth_count(&smoother);

        if (smooth_n > 0) {
            printf("window %d [%d pkts -> %d samp]  bpm=%.1f  conf=%+.2f  status=%-14s "
                   "SMOOTHED=%.1f (n=%d)  %lldms\n",
                   window_idx, n, m, e.bpm_median, e.confidence,
                   dsp_status_str(e.status), smoothed, smooth_n, (long long)t_ms);
        } else {
            printf("window %d [%d pkts -> %d samp]  bpm=%.1f  conf=%+.2f  status=%-14s "
                   "SMOOTHED=-- (settling)  %lldms\n",
                   window_idx, n, m, e.bpm_median, e.confidence,
                   dsp_status_str(e.status), (long long)t_ms);
        }

        /* Module 5 Tier-1: feed the window to the anomaly detector (rate rules
         * + temporal voting, apnea occupancy-gated) ON-DEVICE. Detection stays
         * here (offline-safe); the alert is forwarded to the cloud in the
         * result packet for the app to display. */
        uint8_t alert_type = WIHEALTH_ALERT_NONE, alert_votes = 0;
        {
            int ok = (e.status == DSP_STATUS_OK);
            double abpm = (smooth_n > 0 && !isnan(smoothed)) ? smoothed : 0.0;
            dsp_anom_alert_t al = dsp_anom_update(&anom, ok ? true : false, abpm);
            if (al.type != DSP_ANOM_NONE) {
                alert_type = (uint8_t)al.type;      /* dsp_anom_type_t == WIHEALTH_ALERT_* */
                alert_votes = (uint8_t)al.votes;
                if (al.type == DSP_ANOM_APNEA) {
                    printf("  ** ALERT: APNEA (%s) — no valid breathing for %.0fs **\n",
                           dsp_anom_severity_str(al.type), al.apnea_seconds);
                    /* breathing genuinely stopped — drop the smoothed history so
                     * we report no-breathing, not a stale rate. */
                    dsp_smooth_init(&smoother, 6);
                    smoothed = NAN;
                    smooth_n = 0;
                } else {
                    printf("  ** ALERT: %s (%s) — bpm %.1f, votes %d/%d **\n",
                           dsp_anom_type_str(al.type), dsp_anom_severity_str(al.type),
                           al.bpm, al.votes, al.window);
                }
            }
        }

        /* Module 4: broadcast the result (+ any alert) to the uploader board.
         * Report the SMOOTHED reading, not the current raw window: the rolling
         * median of recent VALID windows is the trustworthy live rate, and it
         * rides out individual noisy windows (the whole point of the smoother).
         * So the status we report reflects the SMOOTHER, not this one window:
         *   - smoother has valid windows -> status OK, bpm = smoothed
         *   - smoother empty            -> no_valid_breathing, bpm = 0
         * (the smoother is cleared above when apnea fires, so a genuine stop
         * correctly falls back to no_valid_breathing.) */
        {
            /* staleness: how long since the last valid (ok) window? */
            double since_ok_s = (s_last_ok_window < 0)
                ? 1e9
                : (double)(window_idx - s_last_ok_window) * STRIDE_SEC;
            int fresh = (smooth_n > 0) && !isnan(smoothed) && (since_ok_s <= STALE_AFTER_S);

            uint8_t out_status;
            float out_bpm, out_conf, out_sq;
            if (fresh) {
                out_bpm = (float)smoothed;
                out_status = DSP_STATUS_OK;
                out_conf = (float)s_last_ok_conf;  /* coherent with the OK reading */
                out_sq   = (float)s_last_ok_sq;
            } else {
                /* either no valid window ever, or the smoothed reading has gone
                 * stale (>STALE_AFTER_S with no fresh valid window). Withhold the
                 * rate rather than show a stale number that looks current. */
                out_bpm = 0.0f;
                out_status = DSP_STATUS_NO_VALID_BREATHING;
                out_conf = (float)e.confidence;    /* current window's (low) values */
                out_sq   = (float)e.signal_quality;
            }
            send_result((uint32_t)window_idx, out_bpm, out_conf, out_sq,
                        out_status, alert_type, alert_votes);
        }

        window_idx++;
        vTaskDelay(pdMS_TO_TICKS((int)(STRIDE_SEC * 1000)));
    }
}

/* ================= app_main ================= */
void app_main(void)
{
    esp_err_t ret = nvs_flash_init();
    if (ret == ESP_ERR_NVS_NO_FREE_PAGES || ret == ESP_ERR_NVS_NEW_VERSION_FOUND) {
        ESP_ERROR_CHECK(nvs_flash_erase());
        ret = nvs_flash_init();
    }
    ESP_ERROR_CHECK(ret);

    /* ring buffer in PSRAM */
    s_ring = heap_caps_malloc((size_t)RING_CAP * sizeof(csi_sample_t), MALLOC_CAP_SPIRAM);
    if (!s_ring) {
        ESP_LOGE(TAG, "failed to allocate CSI ring in PSRAM (%u bytes)",
                 (unsigned)((size_t)RING_CAP * sizeof(csi_sample_t)));
        return;
    }
    s_ring_mtx = xSemaphoreCreateMutex();

    printf("\n===== dsp_live: on-device breathing monitor =====\n");
    printf("ring: %d packets (%.0f KB PSRAM), window %.0fs, stride %.0fs\n",
           RING_CAP, (double)RING_CAP * sizeof(csi_sample_t) / 1024.0,
           WINDOW_SEC, STRIDE_SEC);
    printf("waiting for CSI from TX %02x:%02x:%02x:%02x:%02x:%02x ...\n",
           CONFIG_CSI_SEND_MAC[0], CONFIG_CSI_SEND_MAC[1], CONFIG_CSI_SEND_MAC[2],
           CONFIG_CSI_SEND_MAC[3], CONFIG_CSI_SEND_MAC[4], CONFIG_CSI_SEND_MAC[5]);

    wifi_init();
    esp_now_peer_info_t peer = {
        /* channel=0 => send on the current radio channel, so result packets
         * still reach the uploader after channel auto-discovery retunes us. */
        .channel   = 0,
        .ifidx     = WIFI_IF_STA,
        .encrypt   = false,
        .peer_addr = {0xff, 0xff, 0xff, 0xff, 0xff, 0xff},
    };
    wifi_esp_now_init(peer);
    wifi_csi_init();

    /* Channel auto-discovery: sweep for the uploader's beacon before we start
     * trusting CSI. Settles on the found channel, or the default if no uploader.
     * The DSP task waits for s_channel_settled so buffering starts on the right
     * channel instead of collecting cross-channel garbage while sweeping. */
    xTaskCreatePinnedToCore(channel_scan_task, "chan_scan", 3072, NULL, 6, NULL, 0);

    /* Self-heal channel drift (roaming AP) by re-scanning when CSI stalls. */
    xTaskCreatePinnedToCore(channel_watchdog_task, "chan_wd", 3072, NULL, 4, NULL, 0);

    /* DSP on the APP cpu (core 1) so the WiFi/CSI callback on core 0 is never
     * stalled by the ~0.4 s per-window compute. */
    xTaskCreatePinnedToCore(dsp_task, "dsp", 8192, NULL, 5, NULL, 1);
}
