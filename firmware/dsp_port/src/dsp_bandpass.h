/* dsp_bandpass.h — Stage 06: zero-phase Butterworth bandpass (0.1-0.5 Hz).
 *
 * Port of _bandpass() in firmware/components/dsp_breathing/breathing.py,
 * which calls scipy.signal.sosfiltfilt on an order-4 SOS bandpass.
 *
 * sosfiltfilt = forward-backward (zero-phase) IIR filtering with odd
 * reflection padding of length padlen at each end, and per-section steady-
 * state initial conditions scaled by the first sample. Coefficients and zi
 * are the exact scipy values in butter_coeffs.h.
 *
 * Python guards tiny inputs: if signal.size < 3*(2*order+1) it returns the
 * input unchanged (float32). We mirror that.
 *
 * Pure C99, math in double (scipy filters in float64), output float32.
 */
#ifndef DSP_BANDPASS_H
#define DSP_BANDPASS_H

/* Input:  x    n real samples (the respiratory waveform from stage 05).
 *         n    length.
 * Output: out  caller buffer >= n floats; the zero-phase filtered signal.
 *         work caller scratch >= (n + 2*BUTTER_PADLEN) doubles, or NULL to
 *              have the function allocate/free internally.
 * Returns n on success, 0 on allocation failure.
 */
int dsp_bandpass(const float *x, int n, float *out, double *work);

#endif /* DSP_BANDPASS_H */
