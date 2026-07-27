/* vec_io.c — implementation of the golden-vector loaders (host only). */
#include "vec_io.h"

#include <math.h>
#include <stdio.h>
#include <stdlib.h>

static FILE *open_or_die(const char *path) {
    FILE *f = fopen(path, "r");
    if (!f) {
        fprintf(stderr, "vec_io: cannot open %s\n", path);
        exit(1);
    }
    return f;
}

cmatrix_t vec_load_complex(const char *path) {
    FILE *f = open_or_die(path);
    cmatrix_t m = {0, 0, NULL};
    if (fscanf(f, "%d %d", &m.n, &m.s) != 2) {
        fprintf(stderr, "vec_io: bad header in %s\n", path);
        exit(1);
    }
    size_t count = (size_t)m.n * m.s * 2;
    m.data = (float *)malloc(count * sizeof(float));
    if (!m.data) { fprintf(stderr, "vec_io: OOM\n"); exit(1); }
    for (size_t k = 0; k < count; k++) {
        if (fscanf(f, "%f", &m.data[k]) != 1) {
            fprintf(stderr, "vec_io: short read in %s at %zu/%zu\n", path, k, count);
            exit(1);
        }
    }
    fclose(f);
    return m;
}

rmatrix_t vec_load_real_matrix(const char *path) {
    FILE *f = open_or_die(path);
    rmatrix_t m = {0, 0, NULL};
    if (fscanf(f, "%d %d", &m.n, &m.s) != 2) {
        fprintf(stderr, "vec_io: bad header in %s\n", path);
        exit(1);
    }
    size_t count = (size_t)m.n * m.s;
    m.data = (float *)malloc(count * sizeof(float));
    if (!m.data) { fprintf(stderr, "vec_io: OOM\n"); exit(1); }
    for (size_t k = 0; k < count; k++) {
        if (fscanf(f, "%f", &m.data[k]) != 1) {
            fprintf(stderr, "vec_io: short read in %s\n", path);
            exit(1);
        }
    }
    fclose(f);
    return m;
}

rvector_t vec_load_real_vector(const char *path) {
    FILE *f = open_or_die(path);
    rvector_t v = {0, NULL};
    if (fscanf(f, "%d", &v.n) != 1) {
        fprintf(stderr, "vec_io: bad header in %s\n", path);
        exit(1);
    }
    v.data = (float *)malloc((size_t)v.n * sizeof(float));
    if (!v.data) { fprintf(stderr, "vec_io: OOM\n"); exit(1); }
    for (int k = 0; k < v.n; k++) {
        if (fscanf(f, "%f", &v.data[k]) != 1) {
            fprintf(stderr, "vec_io: short read in %s\n", path);
            exit(1);
        }
    }
    fclose(f);
    return v;
}

dvector_t vec_load_double_vector(const char *path) {
    FILE *f = open_or_die(path);
    dvector_t v = {0, NULL};
    if (fscanf(f, "%d", &v.n) != 1) {
        fprintf(stderr, "vec_io: bad header in %s\n", path);
        exit(1);
    }
    v.data = (double *)malloc((size_t)v.n * sizeof(double));
    if (!v.data) { fprintf(stderr, "vec_io: OOM\n"); exit(1); }
    for (int k = 0; k < v.n; k++) {
        if (fscanf(f, "%lf", &v.data[k]) != 1) {
            fprintf(stderr, "vec_io: short read in %s\n", path);
            exit(1);
        }
    }
    fclose(f);
    return v;
}

pairs_t vec_load_pairs(const char *path) {
    FILE *f = open_or_die(path);
    pairs_t p = {0, NULL, NULL};
    if (fscanf(f, "%d", &p.p) != 1) {
        fprintf(stderr, "vec_io: bad header in %s\n", path);
        exit(1);
    }
    p.i = (int *)malloc((size_t)p.p * sizeof(int));
    p.j = (int *)malloc((size_t)p.p * sizeof(int));
    if (!p.i || !p.j) { fprintf(stderr, "vec_io: OOM\n"); exit(1); }
    for (int k = 0; k < p.p; k++) {
        if (fscanf(f, "%d %d", &p.i[k], &p.j[k]) != 2) {
            fprintf(stderr, "vec_io: short read in %s\n", path);
            exit(1);
        }
    }
    fclose(f);
    return p;
}

void vec_free_complex(cmatrix_t *m) { free(m->data); m->data = NULL; }
void vec_free_real_matrix(rmatrix_t *m) { free(m->data); m->data = NULL; }
void vec_free_real_vector(rvector_t *v) { free(v->data); v->data = NULL; }
void vec_free_double_vector(dvector_t *v) { free(v->data); v->data = NULL; }
void vec_free_pairs(pairs_t *p) { free(p->i); free(p->j); p->i = p->j = NULL; }

double vec_max_abs_err_real(const float *a, const float *b, size_t n) {
    double worst = 0.0;
    for (size_t k = 0; k < n; k++) {
        double e = fabs((double)a[k] - (double)b[k]);
        if (e > worst) worst = e;
    }
    return worst;
}

double vec_max_abs_err_complex(const float *a, const float *b, size_t n_complex) {
    return vec_max_abs_err_real(a, b, n_complex * 2);
}
