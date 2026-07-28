/* dsp_pairs.h — Stage 03: subcarrier-pair selection.
 *
 * Port of select_subcarrier_pairs() in
 * firmware/components/dsp_breathing/cscr.py.
 *
 * For each candidate (i,j) pair (i != j, generated i-outer/j-inner, capped at
 * MAX_CANDIDATES), form the CSCR ratio H[:,i]/H[:,j], score it by the
 * breathing-band peak-to-mean of its real-part magnitude spectrum, and return
 * the top `num_pairs` by score (descending, stable on ties = candidate order).
 *
 * NOTE on cost: the reference scores up to 3000 candidates, each with an FFT.
 * This host port uses a direct DFT for correctness/validation; it is NOT the
 * on-device implementation (far too slow for the ESP32). On-device this stage
 * will run ONCE at session start and cache the pairs, and/or use ESP-DSP's
 * FFT — tracked as a separate optimisation. Correctness first.
 *
 * Pure C99, math in double to match numpy.
 */
#ifndef DSP_PAIRS_H
#define DSP_PAIRS_H

#define DSP_PAIRS_MAX_CANDIDATES 3000

/* Input:  H        interleaved complex, n rows * s cols (uniform-resampled CSI).
 *         n, s     dimensions.
 *         num_pairs how many pairs to return (Python default 20).
 *         low_hz,high_hz  breathing band (0.1, 0.5).
 *         rate     sample rate (10.0).
 * Output: out_i, out_j  caller buffers >= num_pairs ints; filled with the
 *                       selected subcarrier index pairs, best score first.
 * Returns the number of pairs written (<= num_pairs; fewer if not enough
 * candidates scored > 0).
 */
int dsp_select_pairs(const float *H, int n, int s, int num_pairs,
                     double low_hz, double high_hz, double rate,
                     int *out_i, int *out_j);

#endif /* DSP_PAIRS_H */
