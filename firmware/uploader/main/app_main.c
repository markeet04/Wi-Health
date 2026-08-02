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

#include "freertos/semphr.h"
#include "lwip/sockets.h"

#include "nvs_flash.h"
#include "nvs.h"
#include "esp_event.h"
#include "esp_log.h"
#include "esp_wifi.h"
#include "esp_netif.h"
#include "esp_now.h"
#include "esp_http_client.h"
#include "esp_http_server.h"
#include "esp_crt_bundle.h"
#include "esp_timer.h"
#include "esp_mac.h"
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

/* long-lived Firebase refresh token. Obtained once (first boot, from the
 * custom-token exchange), persisted in NVS, and thereafter used to mint fresh
 * ID tokens indefinitely so the device never needs the (1h-expiry) custom
 * token again — no re-flashing required for long-running deployments. */
static char s_refresh_token[512];

#define NVS_NS         "wihealth"
#define NVS_KEY_REFRESH "refresh_tok"

/* Load the saved refresh token into s_refresh_token. Returns true if one was
 * present. */
static bool load_refresh_token(void)
{
    nvs_handle_t h;
    if (nvs_open(NVS_NS, NVS_READONLY, &h) != ESP_OK) return false;
    size_t len = sizeof(s_refresh_token);
    esp_err_t err = nvs_get_str(h, NVS_KEY_REFRESH, s_refresh_token, &len);
    nvs_close(h);
    return err == ESP_OK && s_refresh_token[0] != 0;
}

/* Persist a refresh token to NVS so it survives reboots. */
static void save_refresh_token(const char *token)
{
    strncpy(s_refresh_token, token, sizeof(s_refresh_token) - 1);
    s_refresh_token[sizeof(s_refresh_token) - 1] = 0;
    nvs_handle_t h;
    if (nvs_open(NVS_NS, NVS_READWRITE, &h) != ESP_OK) return;
    nvs_set_str(h, NVS_KEY_REFRESH, s_refresh_token);
    nvs_commit(h);
    nvs_close(h);
}

/* ================= WiFi ================= */
/* If saved/seed credentials can't connect after this many attempts, they're
 * probably wrong (password changed, network gone) — clear them and reboot into
 * the captive portal so the user can re-enter WiFi. 0 = never fall back (used
 * during the portal's own connect, where a different recovery path applies). */
static volatile int s_connect_attempts = 0;
static volatile int s_max_connect_attempts = 0;   /* 0 until we're joining saved creds */

static void clear_wifi_creds(void);   /* fwd */

static void wifi_event_handler(void *arg, esp_event_base_t base, int32_t id, void *data)
{
    if (base == WIFI_EVENT && id == WIFI_EVENT_STA_START) {
        esp_wifi_connect();
    } else if (base == WIFI_EVENT && id == WIFI_EVENT_STA_DISCONNECTED) {
        if (s_max_connect_attempts > 0 &&
            ++s_connect_attempts >= s_max_connect_attempts) {
            /* Saved credentials aren't working — wipe them and restart so the
             * next boot opens the setup portal for fresh WiFi. */
            ESP_LOGE(TAG, "wifi: saved credentials failed %d times — clearing and "
                          "rebooting into setup mode", s_connect_attempts);
            clear_wifi_creds();
            esp_restart();
        }
        ESP_LOGW(TAG, "wifi disconnected, retrying... (%d/%d)",
                 s_connect_attempts, s_max_connect_attempts);
        esp_wifi_connect();
        xEventGroupClearBits(s_wifi_events, WIFI_CONNECTED_BIT);
    } else if (base == IP_EVENT && id == IP_EVENT_STA_GOT_IP) {
        ESP_LOGI(TAG, "wifi connected, got IP");
        s_connect_attempts = 0;
        xEventGroupSetBits(s_wifi_events, WIFI_CONNECTED_BIT);
    }
}

/* ================= WiFi credential storage (NVS) ================= */
#define NVS_KEY_SSID "wifi_ssid"
#define NVS_KEY_PASS "wifi_pass"

/* Load saved WiFi creds from NVS. Returns true if an SSID was present. */
static bool load_wifi_creds(char *ssid, size_t ssid_len, char *pass, size_t pass_len)
{
    nvs_handle_t h;
    if (nvs_open(NVS_NS, NVS_READONLY, &h) != ESP_OK) return false;
    ssid[0] = 0; pass[0] = 0;
    size_t sl = ssid_len, pl = pass_len;
    esp_err_t e1 = nvs_get_str(h, NVS_KEY_SSID, ssid, &sl);
    nvs_get_str(h, NVS_KEY_PASS, pass, &pl);   /* password may be empty (open AP) */
    nvs_close(h);
    return e1 == ESP_OK && ssid[0] != 0;
}

static void save_wifi_creds(const char *ssid, const char *pass)
{
    nvs_handle_t h;
    if (nvs_open(NVS_NS, NVS_READWRITE, &h) != ESP_OK) return;
    nvs_set_str(h, NVS_KEY_SSID, ssid);
    nvs_set_str(h, NVS_KEY_PASS, pass ? pass : "");
    nvs_commit(h);
    nvs_close(h);
}

/* Erase saved WiFi creds so the next boot re-opens the setup portal. */
static void clear_wifi_creds(void)
{
    nvs_handle_t h;
    if (nvs_open(NVS_NS, NVS_READWRITE, &h) != ESP_OK) return;
    nvs_erase_key(h, NVS_KEY_SSID);
    nvs_erase_key(h, NVS_KEY_PASS);
    nvs_commit(h);
    nvs_close(h);
}

/* Join a given SSID/password as STA. */
static void wifi_join(const char *ssid, const char *pass)
{
    wifi_config_t wc = {0};
    strncpy((char *)wc.sta.ssid, ssid, sizeof(wc.sta.ssid) - 1);
    strncpy((char *)wc.sta.password, pass ? pass : "", sizeof(wc.sta.password) - 1);
    ESP_ERROR_CHECK(esp_wifi_set_mode(WIFI_MODE_STA));
    ESP_ERROR_CHECK(esp_wifi_set_config(WIFI_IF_STA, &wc));
    ESP_ERROR_CHECK(esp_wifi_start());
}

/* ================= Captive-portal setup ================= */
/* Set when the user submits WiFi via the portal — unblocks wifi_init_sta. */
static EventGroupHandle_t s_portal_events;
#define PORTAL_DONE_BIT BIT0
static char s_portal_ssid[33];
static char s_portal_pass[65];

/* URL-decode form field in place (handles %XX and '+'). */
static void url_decode(char *s)
{
    char *o = s;
    for (char *p = s; *p; ++p) {
        if (*p == '+') { *o++ = ' '; }
        else if (*p == '%' && p[1] && p[2]) {
            int hi = (p[1] <= '9') ? p[1]-'0' : (p[1]|0x20)-'a'+10;
            int lo = (p[2] <= '9') ? p[2]-'0' : (p[2]|0x20)-'a'+10;
            *o++ = (char)((hi << 4) | lo);
            p += 2;
        } else { *o++ = *p; }
    }
    *o = 0;
}

/* Build the setup page: a form listing scanned nearby networks + a password. */
static esp_err_t portal_root_handler(httpd_req_t *req)
{
    /* scan for nearby APs to populate the dropdown */
    uint16_t n = 0;
    wifi_scan_config_t scan = { .show_hidden = false };
    esp_wifi_scan_start(&scan, true);
    esp_wifi_scan_get_ap_num(&n);
    if (n > 20) n = 20;
    wifi_ap_record_t *aps = calloc(n ? n : 1, sizeof(wifi_ap_record_t));
    uint16_t got = n;
    if (aps) esp_wifi_scan_get_ap_records(&got, aps);

    static char page[4096];
    int off = snprintf(page, sizeof(page),
        "<!doctype html><html><head><meta name=viewport content='width=device-width,initial-scale=1'>"
        "<title>Wi-Health Setup</title><style>"
        "body{font-family:sans-serif;background:#0f1a17;color:#e6f0ea;margin:0;padding:24px}"
        ".c{max-width:420px;margin:auto}h1{font-size:20px}label{display:block;margin:14px 0 6px;font-size:13px;color:#9fb0a4}"
        "select,input{width:100%%;padding:11px;border-radius:10px;border:1px solid #2b3a33;background:#1b2420;color:#e6f0ea;font-size:15px;box-sizing:border-box}"
        "button{width:100%%;margin-top:20px;padding:13px;border:0;border-radius:10px;background:#4f7d63;color:#fff;font-size:16px;font-weight:600}"
        "</style></head><body><div class=c><h1>Connect Wi-Health to WiFi</h1>"
        "<form method=POST action=/save><label>WiFi network</label><select name=ssid>");
    for (uint16_t i = 0; i < got && off < (int)sizeof(page) - 200; ++i) {
        off += snprintf(page + off, sizeof(page) - off,
            "<option value=\"%s\">%s</option>", (char *)aps[i].ssid, (char *)aps[i].ssid);
    }
    snprintf(page + off, sizeof(page) - off,
        "</select><label>Password</label><input name=pass type=password placeholder='WiFi password'>"
        "<button type=submit>Connect</button></form>"
        "<p style='color:#9fb0a4;font-size:12px;margin-top:18px'>The device will join this network and start monitoring.</p>"
        "</div></body></html>");
    free(aps);

    httpd_resp_set_type(req, "text/html");
    httpd_resp_sendstr(req, page);
    return ESP_OK;
}

/* Handle the submitted form: stash creds, confirm, and signal completion. */
static esp_err_t portal_save_handler(httpd_req_t *req)
{
    char buf[256];
    int len = httpd_req_recv(req, buf, sizeof(buf) - 1);
    if (len <= 0) { httpd_resp_send_500(req); return ESP_FAIL; }
    buf[len] = 0;

    /* parse "ssid=...&pass=..." */
    char ssid[33] = {0}, pass[65] = {0};
    char *ps = strstr(buf, "ssid=");
    char *pp = strstr(buf, "pass=");
    if (ps) {
        ps += 5; char *end = strchr(ps, '&'); if (end) *end = 0;
        strncpy(ssid, ps, sizeof(ssid) - 1); url_decode(ssid);
    }
    if (pp) {
        pp += 5; char *end = strchr(pp, '&'); if (end) *end = 0;
        strncpy(pass, pp, sizeof(pass) - 1); url_decode(pass);
    }
    if (ssid[0] == 0) { httpd_resp_send_500(req); return ESP_FAIL; }

    strncpy(s_portal_ssid, ssid, sizeof(s_portal_ssid) - 1);
    strncpy(s_portal_pass, pass, sizeof(s_portal_pass) - 1);

    httpd_resp_set_type(req, "text/html");
    httpd_resp_sendstr(req,
        "<!doctype html><html><head><meta name=viewport content='width=device-width,initial-scale=1'>"
        "<style>body{font-family:sans-serif;background:#0f1a17;color:#e6f0ea;text-align:center;padding:60px 24px}</style></head>"
        "<body><h2>Connecting…</h2><p>Wi-Health is joining your WiFi. You can close this page.</p></body></html>");

    /* signal the main flow to stop the portal and join */
    xEventGroupSetBits(s_portal_events, PORTAL_DONE_BIT);
    return ESP_OK;
}

/* Captive-portal redirect: answer 404s with a redirect to the setup page so the
 * phone's "sign in to WiFi" popup appears automatically. */
static esp_err_t portal_redirect_handler(httpd_req_t *req, httpd_err_code_t err)
{
    (void)err;
    httpd_resp_set_status(req, "302 Found");
    httpd_resp_set_hdr(req, "Location", "http://192.168.4.1/");
    httpd_resp_send(req, NULL, 0);
    return ESP_OK;
}

/* Minimal DNS server: answer every query with the SoftAP IP (192.168.4.1) so
 * any domain the phone probes resolves to us — this triggers the captive-portal
 * popup on both Android and iOS. */
static void dns_hijack_task(void *arg)
{
    (void)arg;
    int sock = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
    if (sock < 0) { vTaskDelete(NULL); return; }
    struct sockaddr_in sa = { .sin_family = AF_INET, .sin_port = htons(53), .sin_addr.s_addr = htonl(INADDR_ANY) };
    if (bind(sock, (struct sockaddr *)&sa, sizeof(sa)) < 0) { close(sock); vTaskDelete(NULL); return; }

    uint8_t pkt[512];
    while (1) {
        struct sockaddr_in from; socklen_t fl = sizeof(from);
        int r = recvfrom(sock, pkt, sizeof(pkt), 0, (struct sockaddr *)&from, &fl);
        if (r < 12) continue;
        /* build a response: copy query, set QR=1, one answer -> 192.168.4.1 */
        pkt[2] |= 0x80;          /* QR */
        pkt[3] |= 0x00;
        pkt[6] = 0; pkt[7] = 1;  /* ANCOUNT = 1 */
        int qlen = r;            /* question ends at r (single question typical) */
        if (qlen + 16 > (int)sizeof(pkt)) continue;
        uint8_t *a = pkt + qlen;
        *a++ = 0xC0; *a++ = 0x0C;                 /* name ptr to question */
        *a++ = 0x00; *a++ = 0x01;                 /* type A */
        *a++ = 0x00; *a++ = 0x01;                 /* class IN */
        *a++ = 0x00; *a++ = 0x00; *a++ = 0x00; *a++ = 0x3C; /* TTL 60 */
        *a++ = 0x00; *a++ = 0x04;                 /* RDLENGTH 4 */
        *a++ = 192; *a++ = 168; *a++ = 4; *a++ = 1;
        sendto(sock, pkt, qlen + 16, 0, (struct sockaddr *)&from, fl);
    }
}

/* Bring up the SoftAP + captive portal and block until the user submits WiFi. */
static void run_captive_portal(void)
{
    ESP_LOGI(TAG, "wifi setup: starting hotspot 'Wi-Health-Setup' — connect to it to configure WiFi");
    s_portal_events = xEventGroupCreate();

    /* SoftAP + STA (STA needed so we can scan for the user's networks). */
    wifi_config_t ap = {0};
    strncpy((char *)ap.ap.ssid, "Wi-Health-Setup", sizeof(ap.ap.ssid) - 1);
    ap.ap.ssid_len = strlen("Wi-Health-Setup");
    ap.ap.channel = 1;
    ap.ap.max_connection = 4;
    ap.ap.authmode = WIFI_AUTH_OPEN;
    ESP_ERROR_CHECK(esp_wifi_set_mode(WIFI_MODE_APSTA));
    ESP_ERROR_CHECK(esp_wifi_set_config(WIFI_IF_AP, &ap));
    ESP_ERROR_CHECK(esp_wifi_start());

    /* DNS hijack -> captive-portal popup. */
    xTaskCreate(dns_hijack_task, "dns_hijack", 3072, NULL, 4, NULL);

    /* HTTP server with the form + a catch-all redirect. */
    httpd_handle_t server = NULL;
    httpd_config_t hc = HTTPD_DEFAULT_CONFIG();
    hc.max_uri_handlers = 4;
    hc.lru_purge_enable = true;
    ESP_ERROR_CHECK(httpd_start(&server, &hc));
    httpd_uri_t root = { .uri = "/", .method = HTTP_GET, .handler = portal_root_handler };
    httpd_uri_t save = { .uri = "/save", .method = HTTP_POST, .handler = portal_save_handler };
    httpd_register_uri_handler(server, &root);
    httpd_register_uri_handler(server, &save);
    httpd_register_err_handler(server, HTTPD_404_NOT_FOUND, portal_redirect_handler);

    /* Wait for the user to submit. */
    xEventGroupWaitBits(s_portal_events, PORTAL_DONE_BIT, pdTRUE, pdTRUE, portMAX_DELAY);

    /* Give the "Connecting…" page a moment to flush, then tear down the portal. */
    vTaskDelay(pdMS_TO_TICKS(800));
    httpd_stop(server);
    esp_wifi_stop();

    /* Persist + join the chosen network. */
    save_wifi_creds(s_portal_ssid, s_portal_pass);
    ESP_LOGI(TAG, "wifi setup: saved '%s', joining...", s_portal_ssid);
    wifi_join(s_portal_ssid, s_portal_pass);
}

/*
 * WiFi bring-up with NVS-first credentials + captive-portal onboarding:
 *   1. NVS has creds (set before, via portal or seed) -> join directly.
 *   2. else config.h has a non-empty SSID (dev seed)  -> join + save to NVS.
 *   3. else -> run the captive portal ('Wi-Health-Setup'); the user picks their
 *      WiFi on an auto-popup page, we save it and join. No app, no reflash.
 */
static void wifi_init_sta(void)
{
    s_wifi_events = xEventGroupCreate();
    ESP_ERROR_CHECK(esp_netif_init());
    ESP_ERROR_CHECK(esp_event_loop_create_default());
    esp_netif_create_default_wifi_sta();
    esp_netif_create_default_wifi_ap();   /* for the setup hotspot */

    wifi_init_config_t cfg = WIFI_INIT_CONFIG_DEFAULT();
    ESP_ERROR_CHECK(esp_wifi_init(&cfg));

    ESP_ERROR_CHECK(esp_event_handler_instance_register(
        WIFI_EVENT, ESP_EVENT_ANY_ID, &wifi_event_handler, NULL, NULL));
    ESP_ERROR_CHECK(esp_event_handler_instance_register(
        IP_EVENT, IP_EVENT_STA_GOT_IP, &wifi_event_handler, NULL, NULL));

    char ssid[33], pass[65];
    if (load_wifi_creds(ssid, sizeof(ssid), pass, sizeof(pass))) {
        ESP_LOGI(TAG, "wifi: using saved credentials for '%s'", ssid);
        /* If these NVS creds keep failing, fall back to the setup portal. Only
         * armed for NVS creds — a bad config.h seed would loop, so it isn't. */
        s_max_connect_attempts = 15;   /* ~15 * ~2.4s ≈ 35 s before giving up */
        wifi_join(ssid, pass);
        return;
    }
    if (CFG_WIFI_SSID[0] != 0) {
        ESP_LOGI(TAG, "wifi: using config.h seed credentials");
        save_wifi_creds(CFG_WIFI_SSID, CFG_WIFI_PASS);   /* so it sticks in NVS */
        wifi_join(CFG_WIFI_SSID, CFG_WIFI_PASS);
        return;
    }
    /* No creds anywhere — onboard the user via the captive portal (blocks). */
    run_captive_portal();
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
    /* add the broadcast address as a peer so we can receive AND send broadcast
     * frames (send is used for the channel-announce beacon below). */
    esp_now_peer_info_t peer = {0};
    memset(peer.peer_addr, 0xff, 6);
    peer.channel = 0;              /* 0 = current channel */
    peer.ifidx = WIFI_IF_STA;
    peer.encrypt = false;
    esp_now_add_peer(&peer);
}

/* Channel-announce beacon. Once joined to the router, the uploader's radio sits
 * on the router's channel; broadcast that channel so the TX + RX retune to it.
 * Sent repeatedly (they may boot/hear later) but cheaply. This is what makes
 * the rig work on ANY home WiFi, not just channel 6. */
static void channel_beacon_task(void *arg)
{
    (void)arg;
    static const uint8_t BCAST[6] = {0xff, 0xff, 0xff, 0xff, 0xff, 0xff};
    while (1) {
        /* only meaningful once associated (radio parked on router's channel) */
        if (xEventGroupGetBits(s_wifi_events) & WIFI_CONNECTED_BIT) {
            uint8_t primary = 0;
            wifi_second_chan_t second;
            if (esp_wifi_get_channel(&primary, &second) == ESP_OK && primary >= 1) {
                wihealth_ctrl_t ctrl = {
                    .magic = WIHEALTH_CTRL_MAGIC,
                    .version = WIHEALTH_CTRL_VER,
                    .channel = primary,
                };
                esp_now_send(BCAST, (const uint8_t *)&ctrl, sizeof(ctrl));
            }
        }
        vTaskDelay(pdMS_TO_TICKS(2000));
    }
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

/* Exchange the long-lived refresh token for a fresh ID token via the Secure
 * Token service. This is the steady-state path once first-boot provisioning has
 * stored a refresh token — it works indefinitely and never touches the (1h)
 * custom token. Returns true on success; false lets the caller fall back to the
 * custom-token exchange (e.g. if the refresh token was revoked). */
static bool firebase_refresh(void)
{
    if (s_refresh_token[0] == 0) return false;

    char url[256];
    snprintf(url, sizeof(url),
        "https://securetoken.googleapis.com/v1/token?key=%s", CFG_WEB_API_KEY);

    /* form-encoded body: grant_type=refresh_token&refresh_token=<token> */
    static char body[768];
    snprintf(body, sizeof(body),
        "grant_type=refresh_token&refresh_token=%s", s_refresh_token);

    static char rbuf[3072];
    resp_t r = { rbuf, 0, sizeof(rbuf) };
    esp_http_client_config_t cfg = {
        .url = url, .method = HTTP_METHOD_POST,
        .event_handler = http_ev, .user_data = &r,
        .crt_bundle_attach = esp_crt_bundle_attach,
        .timeout_ms = 15000,
        .buffer_size = 3072,
        .buffer_size_tx = 1024,
    };
    esp_http_client_handle_t c = esp_http_client_init(&cfg);
    esp_http_client_set_header(c, "Content-Type", "application/x-www-form-urlencoded");
    esp_http_client_set_post_field(c, body, strlen(body));
    esp_err_t err = esp_http_client_perform(c);
    int status = esp_http_client_get_status_code(c);
    esp_http_client_cleanup(c);
    if (err != ESP_OK || status != 200) {
        ESP_LOGW(TAG, "token refresh failed err=%s status=%d (will try custom token)",
                 esp_err_to_name(err), status);
        return false;
    }

    /* Secure Token returns snake_case: id_token, expires_in, refresh_token. */
    cJSON *root = cJSON_Parse(rbuf);
    if (!root) return false;
    cJSON *idt = cJSON_GetObjectItem(root, "id_token");
    cJSON *exp = cJSON_GetObjectItem(root, "expires_in");
    cJSON *rft = cJSON_GetObjectItem(root, "refresh_token");
    bool ok = cJSON_IsString(idt);
    if (ok) {
        strncpy(s_id_token, idt->valuestring, sizeof(s_id_token) - 1);
        int secs = (cJSON_IsString(exp)) ? atoi(exp->valuestring) : 3600;
        s_id_token_deadline_us = esp_timer_get_time() + (int64_t)(secs - 300) * 1000000LL;
        /* Secure Token may hand back a rotated refresh token — persist it. */
        if (cJSON_IsString(rft) && strcmp(rft->valuestring, s_refresh_token) != 0) {
            save_refresh_token(rft->valuestring);
        }
        ESP_LOGI(TAG, "token refreshed, id token valid ~%ds", secs);
    }
    cJSON_Delete(root);
    return ok;
}

/* signInWithCustomToken -> fill s_id_token AND persist the refresh token for
 * subsequent boots. Returns true on success. */
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
    cJSON *rft = cJSON_GetObjectItem(root, "refreshToken");
    bool ok = cJSON_IsString(idt);
    if (ok) {
        strncpy(s_id_token, idt->valuestring, sizeof(s_id_token) - 1);
        int secs = (cJSON_IsString(exp)) ? atoi(exp->valuestring) : 3600;
        /* refresh 5 min before expiry */
        s_id_token_deadline_us = esp_timer_get_time() + (int64_t)(secs - 300) * 1000000LL;
        /* Persist the refresh token so future boots/refreshes never need the
         * custom token again (it expires ~1h after minting). */
        if (cJSON_IsString(rft)) {
            save_refresh_token(rft->valuestring);
            ESP_LOGI(TAG, "authenticated + refresh token stored, id token valid ~%ds", secs);
        } else {
            ESP_LOGW(TAG, "authenticated but no refresh token in response");
        }
    }
    cJSON_Delete(root);
    return ok;
}

/* Ensure we hold a valid ID token. Strategy: prefer the stored refresh token
 * (steady state, works forever); only fall back to the custom token on true
 * first boot or if refresh fails. Returns true if s_id_token is usable. */
static bool firebase_ensure_token(void)
{
    if (firebase_refresh()) return true;   /* no-op + false if no refresh token yet */
    return firebase_auth();                /* first boot, or refresh token rejected */
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

    const bool had_refresh = (s_refresh_token[0] != 0);
    if (!firebase_ensure_token()) {
        if (!had_refresh) {
            /* True first boot and the custom token didn't work — almost always
             * because it expired (~1h after minting). Make this loud so it's
             * obvious a re-mint + reflash is needed, not a mystery. */
            ESP_LOGE(TAG, "======================================================");
            ESP_LOGE(TAG, "FIRST-BOOT AUTH FAILED. The device custom token in");
            ESP_LOGE(TAG, "config.h is likely expired (custom tokens last ~1h");
            ESP_LOGE(TAG, "after minting). Re-mint the token and reflash once;");
            ESP_LOGE(TAG, "after a successful first boot a refresh token is");
            ESP_LOGE(TAG, "stored and the device runs indefinitely.");
            ESP_LOGE(TAG, "======================================================");
        } else {
            ESP_LOGE(TAG, "initial token refresh failed; will retry on first packet");
        }
    }

    wihealth_result_t p;
    char json[512];
    char path[128];
    while (1) {
        if (xQueueReceive(s_pkt_q, &p, portMAX_DELAY) != pdTRUE) continue;

        /* (re)authenticate if the token is missing or near expiry. Uses the
         * refresh token in steady state, so this keeps working past the custom
         * token's 1h lifetime. */
        if (s_id_token[0] == 0 || esp_timer_get_time() > s_id_token_deadline_us) {
            if (!firebase_ensure_token()) { vTaskDelay(pdMS_TO_TICKS(2000)); continue; }
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

    /* Load a previously-stored refresh token, if any. Present => this device has
     * booted successfully before and can renew ID tokens without the custom
     * token. Absent => first boot, we'll exchange the custom token once. */
    if (load_refresh_token()) {
        printf("auth: using stored refresh token (custom token not needed)\n");
    } else {
        printf("auth: first boot — will exchange the custom token once\n");
    }

    s_pkt_q = xQueueCreate(8, sizeof(wihealth_result_t));

    wifi_init_sta();
    espnow_init();

    xTaskCreate(uploader_task, "uploader", 8192, NULL, 5, NULL);
    xTaskCreate(channel_beacon_task, "chan_beacon", 3072, NULL, 4, NULL);
}
