/* dsp_fft.h — radix-2 complex FFT (host port; ESP-DSP replaces this on-device).
 *
 * Both estimators (bpm_from_fft, bpm_from_autocorrelation) zero-pad to a
 * power-of-two length, so a radix-2 FFT suffices — unlike stage 03's awkward
 * 440-point DFT. Math in double to match numpy.
 *
 * Provides:
 *   dsp_fft_forward   in-place radix-2 DIT FFT of a complex array (len power of 2).
 *   dsp_rfft_mag      |rFFT| of a real, zero-padded signal -> nfft/2+1 magnitudes.
 *   dsp_autocorr      biased autocorrelation via FFT (matches numpy irfft path).
 */
#ifndef DSP_FFT_H
#define DSP_FFT_H

/* In-place forward FFT. re/im are length `n` (power of 2). sign=-1 forward. */
void dsp_fft(double *re, double *im, int n, int sign);

/* Magnitude spectrum of a real signal `x` (length m) zero-padded to nfft
 * (power of 2). Writes nfft/2+1 magnitudes to `mag`. The signal is NOT
 * mean-subtracted here — caller does that (matches the Python which subtracts
 * mean before rfft). */
void dsp_rfft_mag(const double *x, int m, int nfft, double *mag);

/* Biased autocorrelation of real `x` (length n) via FFT, matching:
 *     nfft = next_pow2(2n); F = rfft(x, nfft); ac = irfft(F*conj(F))[:n]
 * Writes n autocorrelation lags to `ac`. Caller mean-subtracts x first.
 * `nfft` must be a power of two >= 2n. */
void dsp_autocorr(const double *x, int n, int nfft, double *ac);

/* ---- single-precision variants (float32) ----
 * The ESP32-S3 has a HARDWARE float32 FPU but only SOFTWARE double, so float
 * is ~10-40x faster on-device. These are used ONLY by pair selection, where
 * we need the ranking of candidate scores, not full double precision. The
 * estimator keeps the double versions above (final bpm accuracy matters).
 *
 * dsp_fft_f: in-place radix-2 FFT on float re/im (n power of two, sign=-1 fwd).
 * dsp_rfft_mag_f: |rFFT| of a real float signal zero-padded to nfft. `re`,`im`
 *   are caller scratch of length nfft; `mag` receives nfft/2+1 magnitudes.
 *   Passing scratch in avoids malloc per candidate. */
void dsp_fft_f(float *re, float *im, int n, int sign);
void dsp_rfft_mag_f(const float *x, int m, int nfft, float *mag,
                    float *re, float *im);

#endif /* DSP_FFT_H */
