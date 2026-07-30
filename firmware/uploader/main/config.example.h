/* config.example.h — copy to config.h and fill in. config.h is GITIGNORED
 * (contains the WiFi password + the device custom token = secrets). Never
 * commit config.h.
 *
 * Get CFG_DEVICE_TOKEN by calling the backend endpoint:
 *   POST /admin/devices/<deviceId>/token   (admin auth)
 * or from backend/scripts/test-device-token.mjs (it mints one). It is a long
 * custom token string; the uploader exchanges it for an ID token at runtime.
 */
#ifndef UPLOADER_CONFIG_H
#define UPLOADER_CONFIG_H

/* --- WiFi (2.4 GHz; ideally on channel 6 to match the CSI/ESP-NOW channel) --- */
#define CFG_WIFI_SSID    "your-ssid"
#define CFG_WIFI_PASS    "your-password"

/* --- Firebase --- */
#define CFG_DEVICE_ID    "test-device-1"      /* == the uid the token was minted for */
#define CFG_WEB_API_KEY  "your-firebase-web-api-key"
#define CFG_DB_URL       "https://wi-health-faa5d-default-rtdb.asia-southeast1.firebasedatabase.app"

/* The device custom token (uid=CFG_DEVICE_ID, claim device=true). LONG string. */
#define CFG_DEVICE_TOKEN "paste-the-custom-token-here"

#endif /* UPLOADER_CONFIG_H */
