/* anomaly_test.c — host test for Module 5 Tier-1 anomaly detection.
 *
 * No golden vector — this validates the rule/voting LOGIC directly against the
 * spec: normal -> silent; tachypnea/bradypnea require N-of-M temporal votes
 * (single blips suppressed); apnea is occupancy-gated (empty room never fires,
 * real breathing-then-stopping does); alerts de-dup (raise once per onset).
 */
#include "../src/dsp_anomaly.h"

#include <stdio.h>
#include <string.h>

static int fails = 0;
#define CHECK(c, m) do { if (!(c)) { printf("FAIL: %s\n", m); fails++; } } while (0)

static dsp_anom_type_t feed(dsp_anom_t *a, int ok, double bpm) {
    return dsp_anom_update(a, ok ? true : false, bpm).type;
}

int main(void) {
    dsp_anom_cfg_t cfg; dsp_anom_defaults(&cfg);  /* tachy25 brady8 apnea20s stride5 vote3/3 */

    /* normal 15 bpm never alerts */
    { dsp_anom_t a; dsp_anom_init(&a, &cfg); int any = 0;
      for (int i = 0; i < 10; i++) if (feed(&a, 1, 15.0) != DSP_ANOM_NONE) any = 1;
      CHECK(!any, "normal 15bpm never alerts"); }

    /* tachypnea needs 3 consecutive, then de-dups */
    { dsp_anom_t a; dsp_anom_init(&a, &cfg);
      CHECK(feed(&a, 1, 28.0) == DSP_ANOM_NONE, "tachy 1/3 no alert");
      CHECK(feed(&a, 1, 28.0) == DSP_ANOM_NONE, "tachy 2/3 no alert");
      CHECK(feed(&a, 1, 28.0) == DSP_ANOM_TACHYPNEA, "tachy 3/3 ALERT");
      CHECK(feed(&a, 1, 28.0) == DSP_ANOM_NONE, "tachy persists -> no repeat"); }

    /* single high blip suppressed by voting */
    { dsp_anom_t a; dsp_anom_init(&a, &cfg); int any = 0;
      for (int i = 0; i < 8; i++) { double v = (i == 3) ? 28.0 : 15.0;
        if (feed(&a, 1, v) != DSP_ANOM_NONE) any = 1; }
      CHECK(!any, "single blip suppressed"); }

    /* bradypnea 3/3 */
    { dsp_anom_t a; dsp_anom_init(&a, &cfg);
      feed(&a, 1, 6.0); feed(&a, 1, 6.0);
      CHECK(feed(&a, 1, 6.0) == DSP_ANOM_BRADYPNEA, "bradypnea 3/3 alert"); }

    /* empty room (never valid breathing) must NOT fire apnea */
    { dsp_anom_t a; dsp_anom_init(&a, &cfg); int any = 0;
      for (int i = 0; i < 20; i++) if (feed(&a, 0, 0.0) != DSP_ANOM_NONE) any = 1;
      CHECK(!any, "empty room never fires apnea"); }

    /* real apnea: occupied, then no breathing for >=20s (stride 5 -> 4th window) */
    { dsp_anom_t a; dsp_anom_init(&a, &cfg);
      feed(&a, 1, 15.0); feed(&a, 1, 15.0);
      CHECK(feed(&a, 0, 0.0) == DSP_ANOM_NONE, "apnea 5s no");
      CHECK(feed(&a, 0, 0.0) == DSP_ANOM_NONE, "apnea 10s no");
      CHECK(feed(&a, 0, 0.0) == DSP_ANOM_NONE, "apnea 15s no");
      CHECK(feed(&a, 0, 0.0) == DSP_ANOM_APNEA, "apnea 20s ALERT"); }

    /* type/severity strings */
    CHECK(strcmp(dsp_anom_type_str(DSP_ANOM_APNEA), "apnea") == 0, "type apnea");
    CHECK(strcmp(dsp_anom_severity_str(DSP_ANOM_APNEA), "urgent") == 0, "apnea urgent");
    CHECK(strcmp(dsp_anom_severity_str(DSP_ANOM_TACHYPNEA), "warning") == 0, "tachy warning");

    if (!fails) printf("PASS  anomaly: Tier-1 rules + temporal voting + apnea gating verified\n");
    else printf(">>> %d FAILURES\n", fails);
    return fails ? 1 : 0;
}
