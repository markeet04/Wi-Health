"""Cross-Subcarrier CSI Ratio (CSCR) — SA-WiSense 2025.

Rationale
---------
On a single-antenna ESP32, every packet's raw CSI is corrupted by common
CFO/SFO/PBD phase and gain offsets shared across all subcarriers within the
packet. Taking the ratio H[i] / H[j] between two subcarriers of the same
packet cancels that shared offset — the residual carries the multipath /
Doppler modulation induced by respiration (chest wall motion at 0.1-0.5 Hz).

Pipeline stages exposed here:
  - compute_cscr:              pairwise complex ratios
  - select_subcarrier_pairs:   pick the pairs with highest breathing-band SNR
  - cscr_to_respiratory_waveform: combine multiple CSCR streams into one
                                  smoothed real-valued waveform.
"""
from __future__ import annotations

import numpy as np
import pandas as pd
from scipy.signal import butter, sosfiltfilt, savgol_filter


def compute_cscr(
    complex_csi: np.ndarray,
    pair_indices: list[tuple[int, int]],
) -> np.ndarray:
    """CSCR = H[:, i] / H[:, j] for each (i, j) pair.

    Parameters
    ----------
    complex_csi : (N, S) complex array — packets x subcarriers
    pair_indices : list of (i, j) subcarrier index pairs

    Returns
    -------
    (N, num_pairs) complex64 array.
    """
    if complex_csi.ndim != 2:
        raise ValueError(f"complex_csi must be 2-D, got {complex_csi.shape}")
    N, S = complex_csi.shape
    if not pair_indices:
        return np.zeros((N, 0), dtype=np.complex64)

    out = np.zeros((N, len(pair_indices)), dtype=np.complex64)
    eps = np.complex64(1e-6 + 0j)
    for k, (i, j) in enumerate(pair_indices):
        if not (0 <= i < S and 0 <= j < S):
            raise IndexError(f"pair ({i},{j}) out of range for S={S}")
        denom = complex_csi[:, j]
        # Guard against zero denominators (null / dropped subcarriers).
        denom_safe = np.where(np.abs(denom) < 1e-6, eps, denom)
        out[:, k] = (complex_csi[:, i] / denom_safe).astype(np.complex64)
    return out


def _bandpass_sos(low_hz: float, high_hz: float, sample_rate: float, order: int = 4):
    nyq = 0.5 * sample_rate
    lo = max(1e-6, low_hz / nyq)
    hi = min(0.999, high_hz / nyq)
    if not (0 < lo < hi < 1):
        raise ValueError(f"invalid bandpass edges: {low_hz}-{high_hz} Hz at fs={sample_rate}")
    return butter(order, [lo, hi], btype="bandpass", output="sos")


def _pair_snr(
    ratio: np.ndarray,
    sample_rate: float,
    band: tuple[float, float],
) -> float:
    """SNR proxy for one CSCR stream: peak FFT magnitude in `band` / mean off-band."""
    x = ratio.real.astype(np.float64)
    x = x - np.mean(x)
    if x.size < 16 or np.std(x) < 1e-9:
        return 0.0
    n = x.size
    spec = np.abs(np.fft.rfft(x))
    freqs = np.fft.rfftfreq(n, d=1.0 / sample_rate)
    in_band = (freqs >= band[0]) & (freqs <= band[1])
    if not np.any(in_band):
        return 0.0
    peak = float(np.max(spec[in_band]))
    mean_mag = float(np.mean(spec) + 1e-12)
    return peak / mean_mag


def select_subcarrier_pairs(
    complex_csi: np.ndarray,
    num_pairs: int = 20,
    breathing_band: tuple[float, float] = (0.1, 0.5),
    sample_rate: float = 10.0,
    candidate_stride: int = 1,
    max_candidates: int = 3000,
) -> list[tuple[int, int]]:
    """Pick the `num_pairs` best subcarrier pairs for breathing detection.

    Approach: for each candidate pair, compute its CSCR, score it by peak-to-
    mean FFT magnitude within `breathing_band`, and return the top pairs.

    This is a variance-based simplification of SA-WiSense's genetic-algorithm
    subcarrier selection (GASS) — fast enough for real-time and empirically
    close enough on ESP32 CSI, where the differentiator is mostly which
    subcarrier pairs escape the guard/pilot dead zones.
    """
    if complex_csi.ndim != 2:
        raise ValueError(f"complex_csi must be 2-D, got {complex_csi.shape}")
    S = complex_csi.shape[1]
    if S < 4 or complex_csi.shape[0] < 16:
        return []

    idx = np.arange(0, S, candidate_stride)
    candidates: list[tuple[int, int]] = []
    for a in idx:
        for b in idx:
            if a == b:
                continue
            candidates.append((int(a), int(b)))
            if len(candidates) >= max_candidates:
                break
        if len(candidates) >= max_candidates:
            break

    scored: list[tuple[float, tuple[int, int]]] = []
    for (i, j) in candidates:
        denom = complex_csi[:, j]
        if np.median(np.abs(denom)) < 1e-3:
            continue
        r = complex_csi[:, i] / np.where(np.abs(denom) < 1e-6, 1e-6 + 0j, denom)
        s = _pair_snr(r, sample_rate, breathing_band)
        if s > 0:
            scored.append((s, (i, j)))

    scored.sort(key=lambda t: t[0], reverse=True)
    return [p for _, p in scored[:num_pairs]]


def _hampel(x: np.ndarray, window: int = 5, threshold: float = 3.0) -> np.ndarray:
    if x.size < window:
        return x
    col = pd.Series(x.astype(np.float64))
    roll = col.rolling(window, center=True, min_periods=1)
    med = roll.median()
    mad = roll.apply(lambda v: np.median(np.abs(v - np.median(v))), raw=True)
    mad_safe = mad.where(mad > 0, 1e-9)
    diff = (col - med).abs()
    out_mask = diff > threshold * mad_safe
    cleaned = col.where(~out_mask, med).to_numpy()
    return cleaned.astype(np.float32)


def cscr_to_respiratory_waveform(
    cscr_matrix: np.ndarray,
    hampel_window: int = 5,
    hampel_threshold: float = 3.0,
    savgol_window: int = 21,
    savgol_order: int = 3,
) -> np.ndarray:
    """Combine multiple complex CSCR streams into one respiratory waveform.

    Steps:
      1. Take real part per stream (projects complex ratio to R).
      2. Zero-mean and unit-variance each stream, then average across streams.
      3. Hampel outlier removal.
      4. Savitzky-Golay smoothing for waveform fidelity.
    """
    if cscr_matrix.ndim != 2 or cscr_matrix.shape[1] == 0:
        return np.zeros(cscr_matrix.shape[0] if cscr_matrix.ndim >= 1 else 0,
                        dtype=np.float32)

    real = cscr_matrix.real.astype(np.float32)
    mu = real.mean(axis=0, keepdims=True)
    sd = real.std(axis=0, keepdims=True)
    sd = np.where(sd < 1e-9, 1.0, sd)
    normed = (real - mu) / sd
    combined = normed.mean(axis=1)

    combined = _hampel(combined, window=hampel_window, threshold=hampel_threshold)

    win = min(savgol_window, combined.size if combined.size % 2 == 1 else combined.size - 1)
    if win >= savgol_order + 2 and win >= 5:
        if win % 2 == 0:
            win -= 1
        combined = savgol_filter(combined, window_length=win,
                                 polyorder=min(savgol_order, win - 1)).astype(np.float32)
    return combined.astype(np.float32)
