/* wihealth_cloud_map.c — see wihealth_cloud_map.h. Pure C99, host-testable. */
#include "wihealth_cloud_map.h"

#include <stdio.h>
#include <math.h>

const char *wihealth_status_str(unsigned char status) {
    switch (status) {
        case WH_STATUS_OK:                 return "ok";
        case WH_STATUS_NO_VALID_BREATHING: return "no_breathing";
        case WH_STATUS_LOW_CONFIDENCE:     return "low_signal";
        case WH_STATUS_DISAGREEMENT:       return "low_signal";
        default:                           return "low_signal"; /* fail safe */
    }
}

int wihealth_packet_valid(const wihealth_result_t *p, size_t len) {
    if (!p || len < sizeof(wihealth_result_t)) return 0;
    if (p->magic != WIHEALTH_RESULT_MAGIC) return 0;
    if (p->version != WIHEALTH_RESULT_VER) return 0;
    return 1;
}

static float clamp01(float v) {
    if (!(v == v)) return 0.0f;      /* NaN -> 0 */
    if (v < 0.0f) return 0.0f;
    if (v > 1.0f) return 1.0f;
    return v;
}

int wihealth_build_live_json(const wihealth_result_t *p, char *out, size_t cap) {
    if (!p || !out || cap == 0) return 0;

    const char *status = wihealth_status_str(p->status);

    /* Schema rule: bpm MUST be 0 whenever status != "ok". Also clamp bpm into
     * the schema's [0,60] range defensively. */
    float bpm = p->bpm;
    if (p->status != WH_STATUS_OK) bpm = 0.0f;
    if (!(bpm == bpm) || bpm < 0.0f) bpm = 0.0f;
    if (bpm > 60.0f) bpm = 60.0f;

    float confidence = clamp01(p->confidence);
    float signalQuality = clamp01(p->signal_quality);

    /* updatedAt uses the RTDB server-value placeholder so Firebase stamps the
     * server time: {".sv":"timestamp"}. */
    int n = snprintf(out, cap,
        "{\"bpm\":%.2f,\"confidence\":%.3f,\"signalQuality\":%.3f,"
        "\"status\":\"%s\",\"updatedAt\":{\".sv\":\"timestamp\"}}",
        (double)bpm, (double)confidence, (double)signalQuality, status);

    if (n < 0 || (size_t)n >= cap) return 0;   /* overflow / error */
    return n;
}
