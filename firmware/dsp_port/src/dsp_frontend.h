/* dsp_frontend.h — fused null-drop + resample straight from raw int16 CSI.
 *
 * On-device, holding the full raw window as a float matrix costs several MB
 * of PSRAM (two 3+ MB buffers). This fuses stages 01 (null-drop) and 02
 * (resample) into a single pass that reads the raw int16 samples directly and
 * writes ONLY the small resampled float matrix (~300 KB). Numerically it is
 * identical to running dsp_nulldrop then dsp_resample — same median-amplitude
 * keep test, same linear interpolation onto the same 10 Hz grid — so the
 * host golden tests still cover the math; this just changes the data source
 * and avoids the intermediate float copies.
 *
 * Raw input layout (matches the CSI ring): for packet r,
 *   re[r*s_raw + c], im[r*s_raw + c]  are int16 gain-compensated I/Q,
 *   ts[r] is that packet's timestamp in seconds (double, monotonic).
 *
 * Pure C99, no ESP-IDF deps.
 */
#ifndef DSP_FRONTEND_H
#define DSP_FRONTEND_H

#include <stdint.h>

/* Input:  re, im   n*s_raw int16 arrays (row-major, packet-major).
 *         ts        n packet timestamps (seconds, non-decreasing).
 *         n, s_raw  raw dimensions.
 *         threshold null-drop median-amplitude keep threshold (2.0).
 *         rate      resample target Hz (10.0).
 * Output: Huni      caller buffer >= n_out_max * s_raw * 2 floats; filled with
 *                   the resampled complex matrix over the KEPT subcarriers
 *                   (n_out rows * kept cols, interleaved re,im).
 *         kept_idx  caller buffer >= s_raw ints; original indices of kept cols.
 *         s_kept    receives the kept-subcarrier count.
 *         n_out_max capacity of Huni in rows.
 *         scratch_med  caller buffer >= n doubles (median work), reused per col.
 * Returns n_out (resampled rows), 0 if insufficient data, -1 on overflow.
 */
int dsp_frontend(const int16_t *re, const int16_t *im, const double *ts,
                 int n, int s_raw, float threshold, double rate,
                 float *Huni, int *kept_idx, int *s_kept,
                 int n_out_max, double *scratch_med);

#endif /* DSP_FRONTEND_H */
