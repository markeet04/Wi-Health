/* wihealth_result.h — the ESP-NOW result packet contract between the RX
 * (capture + DSP) board and the uploader board (Firebase write).
 *
 * SINGLE SOURCE OF TRUTH for the on-air byte layout. Both firmwares include
 * this so they can never disagree on the format. Chip-agnostic (plain C, POD,
 * packed, little-endian fields) so the uploader can be an ESP32-S3, a plain
 * ESP32, a C3, etc.
 *
 * Flow:
 *   TX (S3) --CSI--> RX (S3): capture+DSP --ESP-NOW(this packet)-->
 *     uploader: WiFi STA --> Firebase /devices/$deviceId/live
 *
 * Field -> Firebase mapping (done on the uploader, per device-live-schema.json):
 *   bpm           -> live.bpm           (already 0 when no valid reading)
 *   confidence    -> live.confidence    (clamp to 0..1)
 *   signalQuality -> live.signalQuality (0..1, spectral SNR proxy from DSP)
 *   status        -> live.status        (map dsp_status_t -> schema enum, below)
 *   (uploader adds updatedAt server timestamp)
 *
 * status mapping (dsp_status_t -> DeviceLive.status):
 *   0 DSP_STATUS_OK                -> "ok"
 *   1 DSP_STATUS_LOW_CONFIDENCE    -> "low_signal"
 *   2 DSP_STATUS_DISAGREEMENT      -> "low_signal"
 *   3 DSP_STATUS_NO_VALID_BREATHING-> "no_breathing"
 */
#ifndef WIHEALTH_RESULT_H
#define WIHEALTH_RESULT_H

#include <stdint.h>

#define WIHEALTH_RESULT_MAGIC 0x57484C54u   /* "WHLT" */
#define WIHEALTH_RESULT_VER   3              /* v3 adds alert_type/alert_votes */

/* alert_type values (mirror dsp_anom_type_t): the Module 5 Tier-1 flag raised
 * ON-DEVICE this window (0 = none). The uploader forwards a non-zero alert to
 * Firebase /alerts/$deviceId. Detection stays on the device (offline-safe);
 * the cloud only delivers/displays it. */
#define WIHEALTH_ALERT_NONE      0
#define WIHEALTH_ALERT_APNEA     1
#define WIHEALTH_ALERT_TACHYPNEA 2
#define WIHEALTH_ALERT_BRADYPNEA 3

typedef struct __attribute__((packed)) {
    uint32_t magic;         /* WIHEALTH_RESULT_MAGIC — receiver filters on this */
    uint8_t  version;       /* WIHEALTH_RESULT_VER */
    uint8_t  status;        /* dsp_status_t: 0=ok,1=low_conf,2=disagree,3=no_breath */
    uint8_t  alert_type;    /* WIHEALTH_ALERT_* raised this window (0 = none) */
    uint8_t  alert_votes;   /* temporal-voting tally for the alert (e.g. 3) */
    float    bpm;           /* smoothed bpm (0 when no valid reading) */
    float    confidence;    /* window confidence (~0..1) */
    float    signal_quality;/* 0..1 spectral SNR proxy */
    uint32_t seq;           /* monotonic window index */
} wihealth_result_t;        /* 24 bytes; ESP-NOW payload limit is 250 */

#endif /* WIHEALTH_RESULT_H */
