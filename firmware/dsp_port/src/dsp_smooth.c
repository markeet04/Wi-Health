/* dsp_smooth.c — rolling-median BPM smoother. See dsp_smooth.h. */
#include "dsp_smooth.h"

#include <math.h>
#include <stdlib.h>

void dsp_smooth_init(dsp_smoother_t *s, int size) {
    if (size < 1) size = 1;
    if (size > DSP_SMOOTH_MAX) size = DSP_SMOOTH_MAX;
    s->size = size;
    s->count = 0;
    s->head = 0;
}

void dsp_smooth_push(dsp_smoother_t *s, double bpm) {
    s->buf[s->head] = bpm;
    s->head = (s->head + 1) % s->size;
    if (s->count < s->size) s->count++;
}

static int cmp_double(const void *a, const void *b) {
    double da = *(const double *)a, db = *(const double *)b;
    return (da < db) ? -1 : (da > db) ? 1 : 0;
}

double dsp_smooth_value(const dsp_smoother_t *s) {
    if (s->count == 0) return NAN;
    double tmp[DSP_SMOOTH_MAX];
    for (int i = 0; i < s->count; i++) tmp[i] = s->buf[i];
    qsort(tmp, (size_t)s->count, sizeof(double), cmp_double);
    int m = s->count;
    /* numpy.median semantics: even count -> average of two central values */
    if (m & 1) return tmp[m / 2];
    return 0.5 * (tmp[m / 2 - 1] + tmp[m / 2]);
}

int dsp_smooth_count(const dsp_smoother_t *s) {
    return s->count;
}
