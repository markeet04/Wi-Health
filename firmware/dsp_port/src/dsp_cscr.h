/* dsp_cscr.h — Stage 04: Cross-Subcarrier CSI Ratio.
 *
 * Port of compute_cscr() in firmware/components/dsp_breathing/cscr.py.
 *
 * For each selected (i,j) subcarrier pair, CSCR = H[:,i] / H[:,j] per packet.
 * The denominator is guarded: if |H[:,j]| < 1e-6 it is replaced by 1e-6+0j
 * (matching the Python eps guard) to avoid divide-by-zero on null carriers.
 *
 * Pure C99. Math in double (matches numpy complex64 division closely; output
 * stored as float32 interleaved complex).
 */
#ifndef DSP_CSCR_H
#define DSP_CSCR_H

/* Input:  H        interleaved complex, n rows * s cols (resampled CSI).
 *         n, s     dimensions.
 *         pair_i,pair_j  p subcarrier index pairs (from stage 03).
 *         p        number of pairs.
 * Output: out      caller buffer >= n * p * 2 floats; filled row-major with
 *                  the CSCR complex matrix (n rows * p pair-columns).
 */
void dsp_cscr(const float *H, int n, int s,
              const int *pair_i, const int *pair_j, int p,
              float *out);

#endif /* DSP_CSCR_H */
