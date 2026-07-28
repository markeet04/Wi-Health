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

#endif /* DSP_FFT_H */
