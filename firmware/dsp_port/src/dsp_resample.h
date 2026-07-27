/* dsp_resample.h — Stage 02: linear resample of complex CSI onto a uniform grid.
 *
 * Port of _resample_complex_uniform() in
 * firmware/components/dsp_breathing/breathing.py.
 *
 * Given per-packet timestamps (seconds) and a complex CSI matrix, produce a
 * uniformly-sampled complex matrix at target_rate_hz by linear interpolation
 * of the real and imaginary parts separately.
 *
 * Matches the Python edge behaviour exactly:
 *   - assumes timestamps are non-decreasing (host-recv order); duplicates
 *     (dt == 0) are collapsed keeping the FIRST occurrence, same as
 *     numpy's concatenate(([True], diff(t) > 0)) mask.
 *   - grid start = ceil(t0/dt)*dt, stop = floor(tN/dt)*dt, dt = 1/rate.
 *   - n_out = round((stop-start)/dt) + 1.
 *
 * Pure C99, no ESP-IDF deps. Interpolation math is done in double to match
 * numpy/scipy float64 internals, output stored as float32.
 */
#ifndef DSP_RESAMPLE_H
#define DSP_RESAMPLE_H

#include <stddef.h>

/* Input:  ts    n timestamps (seconds), non-decreasing. DOUBLE precision:
 *               interpolation fraction near large t (tens of seconds) needs
 *               more than float32's ~1e-6 relative precision to match scipy.
 *               On-device the natural source is the ESP32 local_timestamp
 *               microsecond counter, converted to seconds in double.
 *         in    interleaved complex, n rows * s cols, (re,im) pairs.
 *         n, s  dimensions.
 *         rate  target sample rate (Hz), e.g. 10.0.
 * Output: out       caller buffer >= n_out_max * s * 2 floats (uniform matrix).
 *         out_grid  caller buffer >= n_out_max floats (grid timestamps), or NULL.
 *         n_out_max capacity of out/out_grid in rows; if the computed n_out
 *                   exceeds it, the function returns -1 (buffer too small).
 * Returns n_out (rows written), 0 if not enough data, or -1 on overflow.
 *
 * A safe upper bound for n_out_max is ceil((ts[n-1]-ts[0]) * rate) + 2.
 */
int dsp_resample(const double *ts, const float *in, int n, int s, double rate,
                 float *out, float *out_grid, int n_out_max);

#endif /* DSP_RESAMPLE_H */
