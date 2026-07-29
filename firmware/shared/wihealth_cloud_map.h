/* wihealth_cloud_map.h — map a received result packet to the Firebase
 * /devices/$id/live schema. Pure logic, no ESP-IDF / no networking, so it is
 * host-testable and shared by the uploader firmware. The uploader only has to
 * add WiFi/TLS + the RTDB PUT around this.
 *
 * Enforces the device-live-schema.json contract:
 *   - status: dsp_status_t -> "ok" | "low_signal" | "no_breathing"
 *   - bpm MUST be 0 whenever status != "ok" (device refuses to guess)
 *   - confidence, signalQuality clamped to 0..1
 *   - updatedAt is the RTDB server-timestamp placeholder (added as a raw JSON
 *     object, NOT a number, so the field is {".sv":"timestamp"})
 */
#ifndef WIHEALTH_CLOUD_MAP_H
#define WIHEALTH_CLOUD_MAP_H

#include "wihealth_result.h"
#include <stddef.h>

/* dsp_status_t values (kept in sync with firmware/dsp_port/src/dsp_estimator.h)
 * so this header is standalone for the uploader. */
enum {
    WH_STATUS_OK = 0,
    WH_STATUS_LOW_CONFIDENCE = 1,
    WH_STATUS_DISAGREEMENT = 2,
    WH_STATUS_NO_VALID_BREATHING = 3,
};

/* Map a dsp status byte to the schema's status string. Unknown -> "low_signal"
 * (fail safe: treat unrecognised as untrusted, not "ok"). */
const char *wihealth_status_str(unsigned char status);

/* Validate a received packet: correct magic + a known version. Returns 1 if
 * the packet is a well-formed result frame we can map, else 0. */
int wihealth_packet_valid(const wihealth_result_t *p, size_t len);

/* Build the JSON body for a PUT to /devices/$id/live.json, enforcing the
 * schema rules (bpm=0 unless ok, clamps). Writes up to `cap` bytes into `out`
 * (NUL-terminated). Returns the number of chars written (excluding NUL), or 0
 * on error/overflow. */
int wihealth_build_live_json(const wihealth_result_t *p, char *out, size_t cap);

#endif /* WIHEALTH_CLOUD_MAP_H */
