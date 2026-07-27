/* dsp_nulldrop.h — Stage 01: drop null/dead subcarriers.
 *
 * Port of drop_null_subcarriers_complex() in
 * firmware/components/csi_capture/clean_health.py.
 *
 * For each subcarrier column, compute the median amplitude sqrt(re^2+im^2)
 * across all packets; keep the column iff median > threshold (default 2.0).
 * Pure C99, no ESP-IDF deps.
 */
#ifndef DSP_NULLDROP_H
#define DSP_NULLDROP_H

#include <stddef.h>

/* Input:  in       interleaved complex, n rows * s cols, (re,im) pairs.
 *         n, s     dimensions.
 *         threshold median-amplitude keep threshold (Python default 2.0).
 * Output: out      caller-allocated buffer of at least n * s * 2 floats;
 *                  filled with the kept columns (n rows * kept cols).
 *         kept_idx caller-allocated int buffer of at least s; filled with the
 *                  original indices of kept columns.
 * Returns the number of kept columns (0..s).
 */
int dsp_nulldrop(const float *in, int n, int s, float threshold,
                 float *out, int *kept_idx);

/* Median amplitude of one subcarrier column (exposed for unit testing).
 * `scratch` must hold at least n floats. Matches numpy.median semantics
 * (even n -> average of the two central order statistics). */
float dsp_col_median_amp(const float *in, int n, int s, int col, float *scratch);

#endif /* DSP_NULLDROP_H */
