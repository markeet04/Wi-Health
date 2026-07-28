#!/usr/bin/env python3
"""Generate per-stage golden reference vectors for the ESP32 C DSP port.

Runs the validated Python preprocessing pipeline on one clean capture and
dumps the intermediate output of each stage to plain-text files. The C port
of each stage diffs its output against these to prove numerical equivalence
before anything is flashed to the board.

Stages dumped (preprocessing only — estimator/FFT come later):
    00_input_complex   raw complex CSI after load + null-drop, resampled input
    01_nulldrop        active-subcarrier complex matrix (post null-drop)
    02_resample        uniform-10Hz complex matrix (the C resampler's target)
    03_pairs           selected subcarrier index pairs
    04_cscr            CSCR complex matrix on the selected pairs
    05_waveform        real projection + normalize + Hampel + Savgol
    06_bandpass        Butterworth 0.1-0.5Hz zero-phase output (estimator input)

Text format (easy to parse in C):
    - complex matrix: first line "N S", then N rows of "re im re im ..." (S pairs)
    - real matrix:    first line "N S", then N rows of S floats
    - real vector:    first line "N",   then N lines each one float
    - pairs:          first line "P",    then P lines "i j"
All floats printed with %.9g so a float32 C port matches within tolerance.

Usage:
    python gen_golden.py [capture.csv] [--outdir ../../firmware/dsp_port/test_vectors]
                         [--max-packets 4000]
"""
from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', '..'))

from firmware.components.csi_capture.clean_health import (  # noqa: E402
    load_complex_session, drop_null_subcarriers_complex,
)
from firmware.components.dsp_breathing.breathing import (  # noqa: E402
    DEFAULTS, _resample_complex_uniform, _bandpass,
    bpm_from_fft, bpm_from_autocorrelation,
)
import numpy as _np  # noqa: E402
from firmware.components.dsp_breathing.cscr import (  # noqa: E402
    compute_cscr, select_subcarrier_pairs, cscr_to_respiratory_waveform,
)

DEFAULT_CSV = "data/live_20260724_122036_b_3ft_qasim.csv"


def _write_complex(path: Path, mat: np.ndarray) -> None:
    mat = np.atleast_2d(mat)
    n, s = mat.shape
    with path.open("w", encoding="utf-8") as f:
        f.write(f"{n} {s}\n")
        for row in mat:
            parts = []
            for z in row:
                parts.append(f"{z.real:.9g}")
                parts.append(f"{z.imag:.9g}")
            f.write(" ".join(parts) + "\n")


def _write_real_matrix(path: Path, mat: np.ndarray) -> None:
    mat = np.atleast_2d(mat)
    n, s = mat.shape
    with path.open("w", encoding="utf-8") as f:
        f.write(f"{n} {s}\n")
        for row in mat:
            f.write(" ".join(f"{v:.9g}" for v in row) + "\n")


def _write_real_vector(path: Path, vec: np.ndarray) -> None:
    vec = np.ravel(vec)
    with path.open("w", encoding="utf-8") as f:
        f.write(f"{vec.size}\n")
        for v in vec:
            f.write(f"{v:.9g}\n")


def _write_pairs(path: Path, pairs: list[tuple[int, int]]) -> None:
    with path.open("w", encoding="utf-8") as f:
        f.write(f"{len(pairs)}\n")
        for (i, j) in pairs:
            f.write(f"{i} {j}\n")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("csv", nargs="?", default=DEFAULT_CSV)
    ap.add_argument("--outdir", default="../../firmware/dsp_port/test_vectors")
    ap.add_argument("--max-packets", type=int, default=4000,
                    help="cap input packets so host C tests stay quick (0 = all)")
    args = ap.parse_args()

    csv_path = Path(args.csv).resolve()
    outdir = Path(args.outdir).resolve()
    outdir.mkdir(parents=True, exist_ok=True)

    cfg = DEFAULTS
    fs = float(cfg["target_sample_rate_hz"])
    band = (float(cfg["bandpass_low_hz"]), float(cfg["bandpass_high_hz"]))

    print(f"loading {csv_path.name} ...")
    H_raw, timestamps, meta = load_complex_session(csv_path)
    if args.max_packets and H_raw.shape[0] > args.max_packets:
        H_raw = H_raw[:args.max_packets]
        timestamps = timestamps[:args.max_packets]
    print(f"  packets={H_raw.shape[0]} subcarriers={H_raw.shape[1]}")

    # Stage 00: raw complex CSI (the C's entry point) + timestamps
    _write_complex(outdir / "00_input_complex.txt", H_raw)
    _write_real_vector(outdir / "00_input_timestamps.txt", timestamps)

    # Stage 01: null-subcarrier drop
    H_active, kept_idx = drop_null_subcarriers_complex(
        H_raw, threshold=float(cfg["null_subcarrier_threshold"]))
    _write_complex(outdir / "01_nulldrop.txt", H_active)
    _write_pairs(outdir / "01_kept_indices.txt",
                 [(int(k), 0) for k in kept_idx])
    print(f"  active subcarriers after null-drop: {H_active.shape[1]}")

    # Stage 02: uniform resample to 10 Hz
    grid, H_u = _resample_complex_uniform(timestamps, H_active, fs)
    _write_complex(outdir / "02_resample.txt", H_u)
    _write_real_vector(outdir / "02_resample_grid.txt", grid)
    print(f"  resampled to {H_u.shape[0]} samples at {fs} Hz")

    # Stage 03: subcarrier-pair selection
    pairs = select_subcarrier_pairs(
        H_u, num_pairs=int(cfg["num_pairs"]),
        breathing_band=band, sample_rate=fs)
    _write_pairs(outdir / "03_pairs.txt", pairs)
    print(f"  selected {len(pairs)} pairs")

    # Stage 04: CSCR on selected pairs
    cscr = compute_cscr(H_u, pairs)
    _write_complex(outdir / "04_cscr.txt", cscr)

    # Stage 05: real projection + normalize + Hampel + Savgol
    wave = cscr_to_respiratory_waveform(
        cscr,
        hampel_window=int(cfg["hampel_window_size"]),
        hampel_threshold=float(cfg["hampel_threshold"]),
        savgol_window=int(cfg["savgol_window"]),
        savgol_order=int(cfg["savgol_order"]))
    _write_real_vector(outdir / "05_waveform.txt", wave)

    # Stage 06: Butterworth bandpass (zero-phase) — estimator input
    wave_bp = _bandpass(wave, band[0], band[1], fs, order=int(cfg["butter_order"]))
    _write_real_vector(outdir / "06_bandpass.txt", wave_bp)

    # Stage 07: estimator (FFT + autocorrelation + gating). Dump the scalar
    # outputs so the C estimator can diff against them. Mirrors the exact
    # combine/gate logic in _estimate_from_complex.
    bpm_fft, conf_fft = bpm_from_fft(wave_bp, fs, band=band)
    bpm_ac, conf_ac = bpm_from_autocorrelation(wave_bp, fs, band=band)
    min_bpm = float(cfg["min_bpm"]); max_bpm = float(cfg["max_bpm"])
    valid_fft = _np.isfinite(bpm_fft) and min_bpm <= bpm_fft <= max_bpm
    valid_ac = _np.isfinite(bpm_ac) and min_bpm <= bpm_ac <= max_bpm
    if valid_fft and valid_ac:
        bpm_median = float(_np.median([bpm_fft, bpm_ac]))
        agreement = abs(bpm_fft - bpm_ac) <= float(cfg["agreement_threshold_bpm"])
        confidence = float(min(conf_fft, conf_ac))
    elif valid_fft:
        bpm_median, agreement, confidence = float(bpm_fft), False, float(conf_fft) * 0.5
    elif valid_ac:
        bpm_median, agreement, confidence = float(bpm_ac), False, float(conf_ac) * 0.5
    else:
        bpm_median, agreement, confidence = float("nan"), False, 0.0
    min_conf = float(cfg["min_confidence"])
    if not (valid_fft or valid_ac):
        status = "no_valid_breathing"
    elif not agreement:
        status = "disagreement"
    elif confidence < min_conf:
        status = "low_confidence"
    else:
        status = "ok"

    def _f(v):
        return "nan" if (isinstance(v, float) and _np.isnan(v)) else f"{v:.9g}"

    with (outdir / "07_estimator.txt").open("w", encoding="utf-8") as f:
        f.write("# key value\n")
        f.write(f"bpm_fft {_f(bpm_fft)}\n")
        f.write(f"conf_fft {_f(conf_fft)}\n")
        f.write(f"bpm_ac {_f(bpm_ac)}\n")
        f.write(f"conf_ac {_f(conf_ac)}\n")
        f.write(f"bpm_median {_f(bpm_median)}\n")
        f.write(f"confidence {_f(confidence)}\n")
        f.write(f"agreement {1 if agreement else 0}\n")
        f.write(f"status {status}\n")
    print(f"  estimator: bpm_fft={bpm_fft:.2f} bpm_ac={bpm_ac:.2f} "
          f"median={bpm_median:.2f} conf={confidence:.3f} status={status}")

    print(f"\ngolden vectors written to {outdir}")
    print("stages:", ", ".join(sorted(p.name for p in outdir.glob("*.txt"))))
    return 0


if __name__ == "__main__":
    sys.exit(main())
