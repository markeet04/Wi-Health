/*
 * wi-netra Step 0 — TRANSMITTER (tx_csi_send)
 *
 * Adapted from esp-csi/examples/get-started/csi_send (Apache-2.0, Espressif).
 * Sends broadcast ESP-NOW frames at HT MCS0_LGI (~6.5 Mbps in HT20) so the
 * receiver gets a valid CSI preamble. No router / no AP: this is the
 * dedicated-TX + promiscuous-RX topology (Option 3).
 *
 * Project-specific knobs are at the top of the file. Both TX and RX MUST
 * use the SAME WIFI_CHANNEL.
 */
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <unistd.h>

#include "nvs_flash.h"
#include "esp_mac.h"
#include "esp_log.h"
#include "esp_wifi.h"
#include "esp_netif.h"
#include "esp_now.h"
#include "esp_timer.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"

#include "wihealth_result.h"   /* channel-announce control packet contract */

/* ============ wi-netra project knobs ============ */
#define WIFI_CHANNEL            6     /* MUST match rx_csi_recv */
#define SEND_FREQUENCY_HZ       100   /* packets per second */
/* ================================================ */

/* The original example uses CONFIG_LESS_INTERFERENCE_CHANNEL — keep the same
 * symbol name so the rest of the upstream code is unchanged. */
#define CONFIG_LESS_INTERFERENCE_CHANNEL   WIFI_CHANNEL
#define CONFIG_SEND_FREQUENCY              SEND_FREQUENCY_HZ

/* HT20 everywhere: TX phymode + bandwidth must agree with RX. */
#if CONFIG_IDF_TARGET_ESP32C5 || CONFIG_IDF_TARGET_ESP32C61 || (CONFIG_IDF_TARGET_ESP32C6 && ESP_IDF_VERSION >= ESP_IDF_VERSION_VAL(5, 4, 0))
#define CONFIG_WIFI_BAND_MODE               WIFI_BAND_MODE_2G_ONLY
#define CONFIG_WIFI_2G_BANDWIDTHS           WIFI_BW_HT20
#define CONFIG_WIFI_5G_BANDWIDTHS           WIFI_BW_HT20
#define CONFIG_WIFI_2G_PROTOCOL             WIFI_PROTOCOL_11N
#define CONFIG_WIFI_5G_PROTOCOL             WIFI_PROTOCOL_11N
#else
#define CONFIG_WIFI_BANDWIDTH               WIFI_BW_HT20
#endif

#define CONFIG_ESP_NOW_PHYMODE              WIFI_PHY_MODE_HT20
#define CONFIG_ESP_NOW_RATE                 WIFI_PHY_RATE_MCS0_LGI  /* HT, OFDM — carries CSI */

#if ESP_IDF_VERSION >= ESP_IDF_VERSION_VAL(6, 0, 0)
#define ESP_IF_WIFI_STA ESP_MAC_WIFI_STA
#endif

/* Same fixed sender MAC as the upstream example — the RX filters on it. */
static const uint8_t CONFIG_CSI_SEND_MAC[] = {0x1a, 0x00, 0x00, 0x00, 0x00, 0x00};
static const char *TAG = "tx_csi_send";

static void wifi_init(void)
{
    ESP_ERROR_CHECK(esp_event_loop_create_default());
    ESP_ERROR_CHECK(esp_netif_init());
    wifi_init_config_t cfg = WIFI_INIT_CONFIG_DEFAULT();
    ESP_ERROR_CHECK(esp_wifi_init(&cfg));

    ESP_ERROR_CHECK(esp_wifi_set_mode(WIFI_MODE_STA));
    ESP_ERROR_CHECK(esp_wifi_set_storage(WIFI_STORAGE_RAM));

#if CONFIG_IDF_TARGET_ESP32C5
    ESP_ERROR_CHECK(esp_wifi_start());
    esp_wifi_set_band_mode(CONFIG_WIFI_BAND_MODE);
    wifi_protocols_t protocols = { .ghz_2g = CONFIG_WIFI_2G_PROTOCOL, .ghz_5g = CONFIG_WIFI_5G_PROTOCOL };
    ESP_ERROR_CHECK(esp_wifi_set_protocols(ESP_IF_WIFI_STA, &protocols));
    wifi_bandwidths_t bandwidth = { .ghz_2g = CONFIG_WIFI_2G_BANDWIDTHS, .ghz_5g = CONFIG_WIFI_5G_BANDWIDTHS };
    ESP_ERROR_CHECK(esp_wifi_set_bandwidths(ESP_IF_WIFI_STA, &bandwidth));

    /* --- TX power check & maximize --- */
    int8_t power;
    esp_wifi_get_max_tx_power(&power);
    ESP_LOGI(TAG, "TX power before: %d (%.1f dBm)", power, power * 0.25);
    esp_wifi_set_max_tx_power(84);
    esp_wifi_get_max_tx_power(&power);
    ESP_LOGI(TAG, "TX power after:  %d (%.1f dBm)", power, power * 0.25);

#elif (CONFIG_IDF_TARGET_ESP32C6 && ESP_IDF_VERSION >= ESP_IDF_VERSION_VAL(5, 4, 0)) || CONFIG_IDF_TARGET_ESP32C61
    ESP_ERROR_CHECK(esp_wifi_start());
    esp_wifi_set_band_mode(CONFIG_WIFI_BAND_MODE);
    wifi_protocols_t protocols = { .ghz_2g = CONFIG_WIFI_2G_PROTOCOL };
    ESP_ERROR_CHECK(esp_wifi_set_protocols(ESP_IF_WIFI_STA, &protocols));
    wifi_bandwidths_t bandwidth = { .ghz_2g = CONFIG_WIFI_2G_BANDWIDTHS };
    ESP_ERROR_CHECK(esp_wifi_set_bandwidths(ESP_IF_WIFI_STA, &bandwidth));

    /* --- TX power check & maximize --- */
    int8_t power;
    esp_wifi_get_max_tx_power(&power);
    ESP_LOGI(TAG, "TX power before: %d (%.1f dBm)", power, power * 0.25);
    esp_wifi_set_max_tx_power(84);
    esp_wifi_get_max_tx_power(&power);
    ESP_LOGI(TAG, "TX power after:  %d (%.1f dBm)", power, power * 0.25);

#else
    ESP_ERROR_CHECK(esp_wifi_set_bandwidth(ESP_IF_WIFI_STA, CONFIG_WIFI_BANDWIDTH));
    ESP_ERROR_CHECK(esp_wifi_start());

    /* --- TX power check & maximize --- */
    int8_t power;
    esp_wifi_get_max_tx_power(&power);
    ESP_LOGI(TAG, "TX power before: %d (%.1f dBm)", power, power * 0.25);
    esp_wifi_set_max_tx_power(84);
    esp_wifi_get_max_tx_power(&power);
    ESP_LOGI(TAG, "TX power after:  %d (%.1f dBm)", power, power * 0.25);

#endif

    ESP_ERROR_CHECK(esp_wifi_set_ps(WIFI_PS_NONE));
    /* HT20 → primary channel only, no secondary. */
    ESP_ERROR_CHECK(esp_wifi_set_channel(CONFIG_LESS_INTERFERENCE_CHANNEL, WIFI_SECOND_CHAN_NONE));
    ESP_ERROR_CHECK(esp_wifi_set_mac(WIFI_IF_STA, CONFIG_CSI_SEND_MAC));
}

/* ===== Channel auto-discovery (TX side) =====
 * The TX starts on the compiled default channel and sweeps 1..13 listening for
 * the channel-announce beacon (from the uploader on the router channel, and/or
 * the RX re-broadcasting after it locks). On hearing it, the TX locks to that
 * channel so it and the RX end up matched for CSI. FALLBACK-FIRST: if no beacon
 * arrives within the timeout, the TX settles on the compiled default (original
 * single-channel behaviour). */
static volatile uint8_t s_active_channel = CONFIG_LESS_INTERFERENCE_CHANNEL;
static volatile bool    s_channel_locked = false;

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

/* Last time we heard a channel-announce beacon (for stall/self-heal). */
static volatile int64_t s_last_beacon_us = 0;

/* Listen for the channel-announce beacon and lock onto it. */
static void espnow_recv_cb(const esp_now_recv_info_t *info, const uint8_t *data, int len)
{
    (void)info;
    if (len < (int)sizeof(wihealth_ctrl_t)) return;
    const wihealth_ctrl_t *c = (const wihealth_ctrl_t *)data;
    if (c->magic != WIHEALTH_CTRL_MAGIC || c->version != WIHEALTH_CTRL_VER) return;
    if (c->channel < 1 || c->channel > CHAN_MAX) return;
    s_last_beacon_us = esp_timer_get_time();
    if (!s_channel_locked || c->channel != s_active_channel) {
        set_channel(c->channel);
        s_channel_locked = true;
        ESP_LOGW(TAG, "channel auto-discovery: locked to channel %u", (unsigned)c->channel);
    }
}

/* Sweep channels until a beacon locks us, or the timeout elapses (then default). */
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
        set_channel(CONFIG_LESS_INTERFERENCE_CHANNEL);
        ESP_LOGW(TAG, "channel auto-discovery: no beacon, using default channel %d",
                 CONFIG_LESS_INTERFERENCE_CHANNEL);
    }
    vTaskDelete(NULL);
}

/* Self-heal: the RX re-broadcasts the channel whenever it (re)locks, so the TX
 * hearing beacons means it's still on the right channel. If the AP roams and the
 * RX moves, the TX stops hearing beacons — after a timeout it re-scans to
 * re-find the (moved) channel. Plain polling task; unrelated to the IDF WDT. */
#define BEACON_STALL_TIMEOUT_MS  20000
static void channel_watchdog_task(void *arg)
{
    (void)arg;
    while (1) {
        vTaskDelay(pdMS_TO_TICKS(1000));
        if (!s_channel_locked) continue;
        if (s_last_beacon_us == 0) continue;   /* haven't heard one yet */
        if ((esp_timer_get_time() - s_last_beacon_us) > (int64_t)BEACON_STALL_TIMEOUT_MS * 1000) {
            ESP_LOGW(TAG, "channel auto-discovery: no beacon for a while — re-scanning");
            s_channel_locked = false;
            xTaskCreate(channel_scan_task, "chan_scan", 3072, NULL, 6, NULL);
            /* Reset the beacon clock so we give the fresh scan its full window
             * before considering another re-scan (the scan task self-deletes;
             * if it re-locks, espnow_recv_cb updates s_last_beacon_us). */
            s_last_beacon_us = esp_timer_get_time();
        }
    }
}

static void wifi_esp_now_init(esp_now_peer_info_t peer)
{
    ESP_ERROR_CHECK(esp_now_init());
    ESP_ERROR_CHECK(esp_now_set_pmk((uint8_t *)"pmk1234567890123"));
    ESP_ERROR_CHECK(esp_now_add_peer(&peer));
    ESP_ERROR_CHECK(esp_now_register_recv_cb(espnow_recv_cb));
#if CONFIG_IDF_TARGET_ESP32S3
    /* ESP32-S3: esp_now_set_peer_rate_config() is declared but its internal
     * per-peer rate-control path is not implemented in the S3 Wi-Fi driver,
     * so calling it triggers a LoadProhibited crash. Use the (deprecated but
     * functional) global ESP-NOW rate API instead — HT MCS0_LGI still carries
     * the HT preamble that the RX needs for CSI. */
    ESP_ERROR_CHECK(esp_wifi_config_espnow_rate(WIFI_IF_STA, CONFIG_ESP_NOW_RATE));
#else
    esp_now_rate_config_t rate_config = {
        .phymode = CONFIG_ESP_NOW_PHYMODE,
        .rate    = CONFIG_ESP_NOW_RATE,
        .ersu    = false,
        .dcm     = false,
    };
    ESP_ERROR_CHECK(esp_now_set_peer_rate_config(peer.peer_addr, &rate_config));
#endif
}

void app_main(void)
{
    esp_err_t ret = nvs_flash_init();
    if (ret == ESP_ERR_NVS_NO_FREE_PAGES || ret == ESP_ERR_NVS_NEW_VERSION_FOUND) {
        ESP_ERROR_CHECK(nvs_flash_erase());
        ret = nvs_flash_init();
    }
    ESP_ERROR_CHECK(ret);

    wifi_init();

    /* Broadcast peer — no router involved. channel=0 means "use the current
     * radio channel", so ESP-NOW sends follow the radio if it retunes for
     * channel auto-discovery (otherwise sends would stay pinned to the default
     * channel after a retune). */
    esp_now_peer_info_t peer = {
        .channel   = 0,
        .ifidx     = WIFI_IF_STA,
        .encrypt   = false,
        .peer_addr = {0xff, 0xff, 0xff, 0xff, 0xff, 0xff},
    };
    wifi_esp_now_init(peer);

    /* Channel auto-discovery: sweep for the beacon and lock the CSI channel to
     * match the RX. Sends keep going during the sweep (harmless); once locked,
     * TX + RX are on the same channel. */
    xTaskCreate(channel_scan_task, "chan_scan", 3072, NULL, 6, NULL);
    /* Re-scan if the AP roams and beacons stop arriving (self-heal). */
    xTaskCreate(channel_watchdog_task, "chan_wd", 3072, NULL, 4, NULL);

    ESP_LOGI(TAG, "================ CSI SEND ================");
    ESP_LOGI(TAG, "channel: %d, rate: %d pkt/s, bw: HT20, mac: " MACSTR,
             CONFIG_LESS_INTERFERENCE_CHANNEL, CONFIG_SEND_FREQUENCY,
             MAC2STR(CONFIG_CSI_SEND_MAC));

    const uint32_t period_us = 1000000U / CONFIG_SEND_FREQUENCY;
    for (uint32_t count = 0; ; ++count) {
        esp_err_t r = esp_now_send(peer.peer_addr, (const uint8_t *)&count, sizeof(count));
        if (r != ESP_OK) {
            ESP_LOGW(TAG, "free_heap: %ld <%s> ESP-NOW send error",
                     esp_get_free_heap_size(), esp_err_to_name(r));
        }
        usleep(period_us);
    }
}