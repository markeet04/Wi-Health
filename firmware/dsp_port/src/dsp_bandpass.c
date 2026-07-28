/* dsp_bandpass.c — Stage 06 implementation. See dsp_bandpass.h.
 *
 * Replicates scipy.signal.sosfiltfilt(sos, x):
 *   1. odd-reflection pad by padlen at each end.
 *   2. forward sosfilt, initial state zi * x_padded[0].
 *   3. reverse, forward sosfilt again, initial state zi * y[0].
 *   4. reverse back, trim the padding.
 * sosfilt for one biquad section (b0,b1,b2, a0=1,a1,a2) uses the transposed
 * direct-form II difference equations, carrying state (z0,z1) per section.
 */
#include "dsp_bandpass.h"
#include "butter_coeffs.h"

#include <stdlib.h>
#include <stddef.h>

/* One forward sosfilt pass over `y` (length m) in place, cascading all
 * sections. `zi_scale` is multiplied into each section's zi and seeded as the
 * initial state (scipy: zi * y[0]). */
static void sosfilt_forward(double *y, int m) {
    /* initial states per section, scaled by the first input sample */
    double z0[BUTTER_NSECTIONS], z1[BUTTER_NSECTIONS];
    double x0 = y[0];
    for (int s = 0; s < BUTTER_NSECTIONS; s++) {
        z0[s] = (double)BUTTER_ZI[s][0] * x0;
        z1[s] = (double)BUTTER_ZI[s][1] * x0;
    }
    for (int i = 0; i < m; i++) {
        double x = y[i];
        for (int s = 0; s < BUTTER_NSECTIONS; s++) {
            double b0 = (double)BUTTER_SOS[s][0];
            double b1 = (double)BUTTER_SOS[s][1];
            double b2 = (double)BUTTER_SOS[s][2];
            /* a0 = SOS[s][3] == 1 */
            double a1 = (double)BUTTER_SOS[s][4];
            double a2 = (double)BUTTER_SOS[s][5];
            /* transposed direct-form II:
             *   yout = b0*x + z0
             *   z0   = b1*x - a1*yout + z1
             *   z1   = b2*x - a2*yout            */
            double yout = b0 * x + z0[s];
            z0[s] = b1 * x - a1 * yout + z1[s];
            z1[s] = b2 * x - a2 * yout;
            x = yout;  /* cascade into next section */
        }
        y[i] = x;
    }
}

static void reverse_inplace(double *y, int m) {
    for (int i = 0, j = m - 1; i < j; i++, j--) {
        double t = y[i]; y[i] = y[j]; y[j] = t;
    }
}

int dsp_bandpass(const float *x, int n, float *out, double *work) {
    /* Python guard: too short -> return input unchanged. */
    if (n < 3 * (2 * 4 + 1)) {
        for (int i = 0; i < n; i++) out[i] = x[i];
        return n;
    }

    int pad = BUTTER_PADLEN;
    int m = n + 2 * pad;

    int own = 0;
    if (!work) { work = (double *)malloc((size_t)m * sizeof(double)); own = 1; }
    if (!work) return 0;
    double *y = work;

    /* --- odd-reflection padding (scipy default 'odd' for sosfiltfilt) ---
     * left  : 2*x[0]   - x[pad], x[pad-1], ..., x[1]
     * middle: x[0..n-1]
     * right : 2*x[n-1] - x[n-2], x[n-3], ..., x[n-1-pad]
     */
    double x0 = (double)x[0];
    double xN = (double)x[n - 1];
    for (int k = 0; k < pad; k++) {
        y[k] = 2.0 * x0 - (double)x[pad - k];
    }
    for (int i = 0; i < n; i++) {
        y[pad + i] = (double)x[i];
    }
    for (int k = 0; k < pad; k++) {
        y[pad + n + k] = 2.0 * xN - (double)x[n - 2 - k];
    }

    /* --- forward, reverse, forward, reverse --- */
    sosfilt_forward(y, m);
    reverse_inplace(y, m);
    sosfilt_forward(y, m);
    reverse_inplace(y, m);

    /* trim padding */
    for (int i = 0; i < n; i++) out[i] = (float)y[pad + i];

    if (own) free(work);
    return n;
}
