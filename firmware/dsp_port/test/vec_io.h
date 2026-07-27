/* vec_io.h — load the golden test vectors written by gen_golden.py.
 *
 * Host-only helper (uses stdio/malloc). Not compiled into firmware.
 * Formats (see gen_golden.py):
 *   complex matrix: "N S\n" then N rows of "re im re im ..." (S complex)
 *   real matrix:    "N S\n" then N rows of S floats
 *   real vector:    "N\n"   then N lines, one float each
 *   pairs:          "P\n"   then P lines "i j"
 */
#ifndef DSP_PORT_VEC_IO_H
#define DSP_PORT_VEC_IO_H

#include <stddef.h>

/* Interleaved complex matrix: data has n*s*2 floats, row-major, (re,im) pairs. */
typedef struct {
    int n;        /* rows (packets)      */
    int s;        /* cols (subcarriers)  */
    float *data;  /* n*s*2 interleaved re,im */
} cmatrix_t;

typedef struct {
    int n;
    int s;
    float *data;  /* n*s row-major */
} rmatrix_t;

typedef struct {
    int n;
    float *data;
} rvector_t;

typedef struct {
    int n;
    double *data;
} dvector_t;

typedef struct {
    int p;
    int *i;       /* p indices */
    int *j;       /* p indices */
} pairs_t;

/* All loaders exit(1) with a message on failure. Caller frees .data / .i/.j. */
cmatrix_t vec_load_complex(const char *path);
rmatrix_t vec_load_real_matrix(const char *path);
rvector_t vec_load_real_vector(const char *path);
dvector_t vec_load_double_vector(const char *path);
pairs_t   vec_load_pairs(const char *path);

void vec_free_complex(cmatrix_t *m);
void vec_free_real_matrix(rmatrix_t *m);
void vec_free_real_vector(rvector_t *v);
void vec_free_double_vector(dvector_t *v);
void vec_free_pairs(pairs_t *p);

/* Compare helpers: return max abs error; print a summary line. */
double vec_max_abs_err_real(const float *a, const float *b, size_t n);
double vec_max_abs_err_complex(const float *a, const float *b, size_t n_complex);

#endif /* DSP_PORT_VEC_IO_H */
