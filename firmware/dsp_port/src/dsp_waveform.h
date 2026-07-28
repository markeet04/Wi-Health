/* dsp_waveform.h — Stage 05: CSCR matrix -> single respiratory waveform.
 *
 * Port of cscr_to_respiratory_waveform() in
 * firmware/components/dsp_breathing/cscr.py.
 *
 * Steps (see the Python docstring):
 *   1. real part per CSCR stream.
 *   2. per-column zero-mean / unit-variance (population std; std<1e-9 -> 1),
 *      then average across the p columns -> one length-n signal.
 *   3. Hampel outlier removal (window 5, threshold 3.0), centered, edges
 *      shrink the window (pandas min_periods=1 semantics).
 *   4. Savitzky-Golay smoothing (window 21, order 3), scipy mode='interp'
 *      via the exact coefficients in savgol_coeffs.h.
 *
 * Pure C99. Math in double where the reference uses float64; final output f32.
 */
#ifndef DSP_WAVEFORM_H
#define DSP_WAVEFORM_H

/* Input:  cscr   interleaved complex, n rows * p cols (from stage 04).
 *         n, p   dimensions.
 * Output: out    caller buffer >= n floats; the respiratory waveform.
 *         work   caller scratch >= n floats (used internally), or NULL to
 *                have the function allocate/free its own.
 * Returns n on success, 0 if p == 0 or n == 0.
 */
int dsp_waveform(const float *cscr, int n, int p, float *out, float *work);

/* Hampel filter, exposed for unit testing. In-place-safe: src != dst.
 * window odd (e.g. 5), threshold e.g. 3.0. */
void dsp_hampel(const float *src, int n, int window, double threshold,
                float *dst);

#endif /* DSP_WAVEFORM_H */
