/* dsp_cscr.c — Stage 04 implementation. See dsp_cscr.h. */
#include "dsp_cscr.h"

#include <math.h>
#include <stddef.h>

void dsp_cscr(const float *H, int n, int s,
              const int *pair_i, const int *pair_j, int p,
              float *out) {
    for (int r = 0; r < n; r++) {
        for (int k = 0; k < p; k++) {
            int i = pair_i[k];
            int j = pair_j[k];

            double a = (double)H[(size_t)r * s * 2 + (size_t)i * 2 + 0];
            double b = (double)H[(size_t)r * s * 2 + (size_t)i * 2 + 1];
            double c = (double)H[(size_t)r * s * 2 + (size_t)j * 2 + 0];
            double d = (double)H[(size_t)r * s * 2 + (size_t)j * 2 + 1];

            /* eps guard: if |denom| < 1e-6, replace denom with 1e-6 + 0j
             * (Python: np.where(np.abs(denom) < 1e-6, 1e-6+0j, denom)). */
            double denom_abs = sqrt(c * c + d * d);
            if (denom_abs < 1e-6) {
                c = 1e-6;
                d = 0.0;
            }

            /* complex division (a+bi)/(c+di) */
            double den = c * c + d * d;
            double re = (a * c + b * d) / den;
            double im = (b * c - a * d) / den;

            out[((size_t)r * p + k) * 2 + 0] = (float)re;
            out[((size_t)r * p + k) * 2 + 1] = (float)im;
        }
    }
}
