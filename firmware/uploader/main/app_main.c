/*
 * uploader — plain ESP32 (ESP32-D0WD-V3). Receives breathing results from the
 * RX/S3 over ESP-NOW and writes them to Firebase RTDB. RX itself can't (it is
 * promiscuous on the CSI channel, not associated to an AP).
 *
 * Flow (mirrors the proven backend/scripts/test-device-token.mjs path):
 *   ESP-NOW recv (wihealth_result_t v3)
 *     -> WiFi STA join
 *     -> signInWithCustomToken(device custom token)   [HTTPS, Identity Toolkit]
 *     -> PUT  /devices/$id/live.json?auth=<idToken>    [live bpm/status/...]
 *     -> POST /alerts/$id.json?auth=<idToken>          [if Module 5 alert set]
 *
 * The result->JSON mapping + schema enforcement lives in the shared, host-
 * tested wihealth_cloud_map. This file is the WiFi/TLS/HTTP wrapper around it.
 *
 * Secrets (WiFi creds, device id, device custom token, web api key, db url)
 * live in config.h — gitignored, copied from config.example.h.
 */
#include <stdio.h>
#include <string.h>

#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "freertos/event_groups.h"
#include "freertos/queue.h"

#include "nvs_flash.h"
#include "esp_event.h"
#include "esp_log.h"
#include "esp_wifi.h"
#include "esp_netif.h"
#include "esp_now.h"
#include "esp_http_client.h"
#include "esp_crt_bundle.h"
#include "esp_timer.h"
#include "cJSON.h"

#include "wihealth_result.h"
#include "wihealth_cloud_map.h"
#include "config.h"

static const char *TAG = "uploader";

/* ---- WiFi connect ---- */
#define WIFI_CONNECTED_BIT BIT0
static EventGroupHandle_t s_wifi_events;

/* queue of received result packets (from the ESP-NOW callback -> worker task) */
static QueueHandle_t s_pkt_q;

/* cached Firebase ID token (refreshed periodically) */
static char s_id_token[2048];
static int64_t s_id_token_deadline_us = 0;   /* re-auth after this */

/* ================= WiFi ================= */
static void wifi_event_handler(void *arg, esp_event_base_t base, int32_t id, void *data)
{
    if (base == WIFI_EVENT && id == WIFI_EVENT_STA_START) {
        esp_wifi_connect();
    } else if (base == WIFI_EVENT && id == WIFI_EVENT_STA_DISCONNECTED) {
        ESP_LOGW(TAG, "wifi disconnected, retrying...");
        esp_wifi_connect();
        xEventGroupClearBits(s_wifi_events, WIFI_CONNECTED_BIT);
    } else if (base == IP_EVENT && id == IP_EVENT_STA_GOT_IP) {
        ESP_LOGI(TAG, "wifi connected, got IP");
        xEventGroupSetBits(s_wifi_events, WIFI_CONNECTED_BIT);
    }
}

static void wifi_init_sta(void)
{
    s_wifi_events = xEventGroupCreate();
    ESP_ERROR_CHECK(esp_netif_init());
    ESP_ERROR_CHECK(esp_event_loop_create_default());
    esp_netif_create_default_wifi_sta();

    wifi_init_config_t cfg = WIFI_INIT_CONFIG_DEFAULT();
    ESP_ERROR_CHECK(esp_wifi_init(&cfg));

    ESP_ERROR_CHECK(esp_event_handler_instance_register(
        WIFI_EVENT, ESP_EVENT_ANY_ID, &wifi_event_handler, NULL, NULL));
    ESP_ERROR_CHECK(esp_event_handler_instance_register(
        IP_EVENT, IP_EVENT_STA_GOT_IP, &wifi_event_handler, NULL, NULL));

    wifi_config_t wc = {0};
    strncpy((char *)wc.sta.ssid, CFG_WIFI_SSID, sizeof(wc.sta.ssid) - 1);
    strncpy((char *)wc.sta.password, CFG_WIFI_PASS, sizeof(wc.sta.password) - 1);
    ESP_ERROR_CHECK(esp_wifi_set_mode(WIFI_MODE_STA));
    ESP_ERROR_CHECK(esp_wifi_set_config(WIFI_IF_STA, &wc));
    ESP_ERROR_CHECK(esp_wifi_start());
    /* ESP-NOW receive also works while joined as STA; the router should ideally
     * be on the CSI channel (6) so the uploader hears RX without channel-hop
     * loss — see the coexistence note in the findings. */
}

/* ================= ESP-NOW receive ================= */
static void espnow_recv_cb(const esp_now_recv_info_t *info, const uint8_t *data, int len)
{
    (void)info;
    if (len < (int)sizeof(wihealth_result_t)) return;
    const wihealth_result_t *p = (const wihealth_result_t *)data;
    if (!wihealth_packet_valid(p, (size_t)len)) return;
    /* hand off to the worker task; drop if the queue is full (next one comes in ~5s) */
    wihealth_result_t copy = *p;
    xQueueSend(s_pkt_q, &copy, 0);
}

static void espnow_init(void)
{
    ESP_ERROR_CHECK(esp_now_init());
    ESP_ERROR_CHECK(esp_now_register_recv_cb(espnow_recv_cb));
    /* add the broadcast address as a peer so we can receive broadcast frames */
    esp_now_peer_info_t peer = {0};
    memset(peer.peer_addr, 0xff, 6);
    peer.channel = 0;              /* 0 = current channel */
    peer.ifidx = WIFI_IF_STA;
    peer.encrypt = false;
    esp_now_add_peer(&peer);
}

/* ================= Firebase HTTPS ================= */

/* small response accumulator for esp_http_client */
typedef struct { char *buf; int len; int cap; } resp_t;
static esp_err_t http_ev(esp_http_client_event_t *e)
{
    if (e->event_id == HTTP_EVENT_ON_DATA && e->user_data) {
        resp_t *r = (resp_t *)e->user_data;
        int n = e->data_len;
        if (r->len + n < r->cap) { memcpy(r->buf + r->len, e->data, n); r->len += n; r->buf[r->len] = 0; }
    }
    return ESP_OK;
}

/* signInWithCustomToken -> fill s_id_token. Returns true on success. */
static bool firebase_auth(void)
{
    char url[256];
    snprintf(url, sizeof(url),
        "https://identitytoolkit.googleapis.com/v1/accounts:signInWithCustomToken?key=%s",
        CFG_WEB_API_KEY);

    char body[1200];
    snprintf(body, sizeof(body),
        "{\"token\":\"%s\",\"returnSecureToken\":true}", CFG_DEVICE_TOKEN);

    static char rbuf[3072];
    resp_t r = { rbuf, 0, sizeof(rbuf) };
    esp_http_client_config_t cfg = {
        .url = url, .method = HTTP_METHOD_POST,
        .event_handler = http_ev, .user_data = &r,
        .crt_bundle_attach = esp_crt_bundle_attach,
        .timeout_ms = 15000,
        .buffer_size = 3072,       /* response holds the ~2KB idToken */
        .buffer_size_tx = 2048,    /* request body holds the custom token */
    };
    esp_http_client_handle_t c = esp_http_client_init(&cfg);
    esp_http_client_set_header(c, "Content-Type", "application/json");
    esp_http_client_set_post_field(c, body, strlen(body));
    esp_err_t err = esp_http_client_perform(c);
    int status = esp_http_client_get_status_code(c);
    esp_http_client_cleanup(c);
    if (err != ESP_OK || status != 200) {
        ESP_LOGE(TAG, "auth failed err=%s status=%d", esp_err_to_name(err), status);
        return false;
    }

    cJSON *root = cJSON_Parse(rbuf);
    if (!root) return false;
    cJSON *idt = cJSON_GetObjectItem(root, "idToken");
    cJSON *exp = cJSON_GetObjectItem(root, "expiresIn");
    bool ok = cJSON_IsString(idt);
    if (ok) {
        strncpy(s_id_token, idt->valuestring, sizeof(s_id_token) - 1);
        int secs = (cJSON_IsString(exp)) ? atoi(exp->valuestring) : 3600;
        /* refresh 5 min before expiry */
        s_id_token_deadline_us = esp_timer_get_time() + (int64_t)(secs - 300) * 1000000LL;
        ESP_LOGI(TAG, "authenticated, id token valid ~%ds", secs);
    }
    cJSON_Delete(root);
    return ok;
}

/* PUT/POST json to an RTDB path (path like "devices/<id>/live" or "alerts/<id>").
 * The URL embeds the ~2 KB ID token in ?auth=, so the buffer is large and
 * static (too big for the stack). Not reentrant — only the single uploader
 * task calls this. */
static char s_url[3072];
static bool rtdb_write(const char *path, const char *json, esp_http_client_method_t method)
{
    char *url = s_url;
    snprintf(s_url, sizeof(s_url), "%s/%s.json?auth=%s", CFG_DB_URL, path, s_id_token);
    esp_http_client_config_t cfg = {
        .url = url, .method = method,
        .crt_bundle_attach = esp_crt_bundle_attach,
        .timeout_ms = 15000,
        /* the URL embeds the ~2 KB ID token in ?auth=, so the default 512-byte
         * tx buffer overflows ("HTTP_CLIENT: Out of buffer"). Size the tx
         * buffer for the long URL + headers. */
        .buffer_size = 2048,
        .buffer_size_tx = 4096,
    };
    esp_http_client_handle_t c = esp_http_client_init(&cfg);
    esp_http_client_set_header(c, "Content-Type", "application/json");
    esp_http_client_set_post_field(c, json, strlen(json));
    esp_err_t err = esp_http_client_perform(c);
    int status = esp_http_client_get_status_code(c);
    esp_http_client_cleanup(c);
    if (err != ESP_OK || status < 200 || status >= 300) {
        ESP_LOGE(TAG, "rtdb %s failed err=%s status=%d", path, esp_err_to_name(err), status);
        return false;
    }
    return true;
}

/* ================= worker ================= */
static void uploader_task(void *arg)
{
    (void)arg;
    /* wait for wifi */
    xEventGroupWaitBits(s_wifi_events, WIFI_CONNECTED_BIT, pdFALSE, pdTRUE, portMAX_DELAY);
    if (!firebase_auth()) ESP_LOGE(TAG, "initial auth failed; will retry on first packet");

    wihealth_result_t p;
    char json[512];
    char path[128];
    while (1) {
        if (xQueueReceive(s_pkt_q, &p, portMAX_DELAY) != pdTRUE) continue;

        /* (re)authenticate if the token is missing or near expiry */
        if (s_id_token[0] == 0 || esp_timer_get_time() > s_id_token_deadline_us) {
            if (!firebase_auth()) { vTaskDelay(pdMS_TO_TICKS(2000)); continue; }
        }

        /* live write */
        int n = wihealth_build_live_json(&p, json, sizeof(json));
        if (n > 0) {
            snprintf(path, sizeof(path), "devices/%s/live", CFG_DEVICE_ID);
            if (rtdb_write(path, json, HTTP_METHOD_PUT)) {
                ESP_LOGI(TAG, "live seq=%u bpm=%.1f status=%d uploaded",
                         (unsigned)p.seq, p.bpm, p.status);
            }
        }

        /* health write — mark the device online (the app treats a device as
         * live only when health.online==true). PATCH so we only touch these
         * fields. */
        int hn = wihealth_build_health_json(json, sizeof(json));
        if (hn > 0) {
            snprintf(path, sizeof(path), "devices/%s/health", CFG_DEVICE_ID);
            rtdb_write(path, json, HTTP_METHOD_PATCH);
        }

        /* alert write (Module 5), if any */
        int an = wihealth_build_alert_json(&p, json, sizeof(json));
        if (an > 0) {
            snprintf(path, sizeof(path), "alerts/%s", CFG_DEVICE_ID);
            if (rtdb_write(path, json, HTTP_METHOD_POST)) {
                ESP_LOGW(TAG, "ALERT type=%u votes=%u pushed to /alerts",
                         (unsigned)p.alert_type, (unsigned)p.alert_votes);
            }
        }
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

    printf("\n===== wi-health uploader (ESP32) =====\n");
    printf("device: %s\n", CFG_DEVICE_ID);

    s_pkt_q = xQueueCreate(8, sizeof(wihealth_result_t));

    wifi_init_sta();
    espnow_init();

    xTaskCreate(uploader_task, "uploader", 8192, NULL, 5, NULL);
}
