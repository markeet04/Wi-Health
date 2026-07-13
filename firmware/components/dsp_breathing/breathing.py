"""End-to-end breathing / respiration detection pipeline.

Given a raw wi-netra CSI capture CSV (subject stationary, breathing normally),
extract breaths-per-minute via two independent estimators (FFT and
autocorrelation) and flag agreement.

Pipeline
--------
    1. load_complex_session  (strip boot-bleed, parse complex CSI, timestamps)
    2. drop_null_subcarriers
    3. resample real+imag to a uniform grid at ~10 Hz
    4. select_subcarrier_pairs — pick top-N pairs by breathing-band SNR
    5. compute_cscr on selected pairs
    6. cscr_to_respiratory_waveform (real projection + avg + hampel + savgol)
    7. Butterworth bandpass 0.1-0.5 Hz
    8. bpm_from_fft, bpm_from_autocorrelation
    9. Report median + agreement flag.
"""
from __future__ import annotations

from pathlib import Path
from typing import Any

import numpy as np
from scipy.interpolate import interp1d
from scipy.signal import butter, sosfiltfilt

from ..csi_capture.clean_health import load_complex_session, drop_null_subcarriers_complex
from .cscr import (
    compute_cscr,
    select_subcarrier_pairs,
    cscr_to_respiratory_waveform,
)


DEFAULTS: dict[str, Any] = {
    "target_sample_rate_hz": 10.0,
    "hampel_window_size": 5,
    "hampel_threshold": 3.0,
    "null_subcarrier_threshold": 2.0,
    "num_pairs": 20,
    "bandpass_low_hz": 0.1,
    "bandpass_high_hz": 0.5,
    "butter_order": 4,
    "savgol_window": 21,
    "savgol_order": 3,
    "window_seconds": 30.0,
    "stride_seconds": 5.0,
    "min_bpm": 6.0,
    "max_bpm": 30.0,
    "agreement_threshold_bpm": 2.0,
}


def _resample_complex_uniform(
    timestamps: np.ndarray,
    H: np.ndarray,
    target_rate_hz: float,
) -> tuple[np.ndarray, np.ndarray]:
    """Linear-interpolate a complex CSI matrix onto a uniform grid.

    Real and imaginary parts are interpolated separately, then recombined.
    """
    if H.shape[0] < 2:
        return np.zeros((0,), dtype=np.float64), np.zeros((0, H.shape[1]), dtype=np.complex64)

    order = np.argsort(timestamps, kind="stable")
    t = timestamps[order]
    H = H[order]
    uniq = np.concatenate(([True], np.diff(t) > 0))
    t = t[uniq]
    H = H[uniq]

    dt = 1.0 / target_rate_hz
    start = float(np.ceil(t[0] / dt) * dt)
    stop = float(np.floor(t[-1] / dt) * dt)
    if stop < start:
        return np.zeros((0,), dtype=np.float64), np.zeros((0, H.shape[1]), dtype=np.complex64)
    n_out = int(round((stop - start) / dt)) + 1
    grid = start + dt * np.arange(n_out, dtype=np.float64)

    real_fn = interp1d(t, H.real, axis=0, kind="linear", assume_sorted=True, copy=False)
    imag_fn = interp1d(t, H.imag, axis=0, kind="linear", assume_sorted=True, copy=False)
    resampled = (real_fn(grid) + 1j * imag_fn(grid)).astype(np.complex64)
    return grid, resampled


def _bandpass(signal: np.ndarray, low_hz: float, high_hz: float,
              sample_rate: float, order: int = 4) -> np.ndarray:
    nyq = 0.5 * sample_rate
    lo = max(1e-6, low_hz / nyq)
    hi = min(0.999, high_hz / nyq)
    sos = butter(order, [lo, hi], btype="bandpass", output="sos")
    # sosfiltfilt requires signal length > padlen; guard tiny inputs.
    if signal.size < 3 * (2 * order + 1):
        return signal.astype(np.float32, copy=True)
    return sosfiltfilt(sos, signal).astype(np.float32)


def bpm_from_fft(
    signal: np.ndarray,
    sample_rate: float,
    band: tuple[float, float] = (0.1, 0.5),
) -> tuple[float, float]:
    """FFT peak in `band` -> (bpm, confidence).

    Confidence = peak magnitude / mean magnitude across the full spectrum.
    """
    x = signal.astype(np.float64) - float(np.mean(signal))
    n = x.size
    if n < 16 or np.std(x) < 1e-9:
        return float("nan"), 0.0
    # Zero-pad to at least 4x for finer frequency resolution.
    nfft = int(2 ** np.ceil(np.log2(max(n * 4, 128))))
    spec = np.abs(np.fft.rfft(x, n=nfft))
    freqs = np.fft.rfftfreq(nfft, d=1.0 / sample_rate)
    in_band = (freqs >= band[0]) & (freqs <= band[1])
    if not np.any(in_band):
        return float("nan"), 0.0
    band_spec = spec.copy()
    band_spec[~in_band] = 0.0
    peak_idx = int(np.argmax(band_spec))
    peak_freq = float(freqs[peak_idx])
    peak_mag = float(spec[peak_idx])
    mean_mag = float(np.mean(spec) + 1e-12)
    return peak_freq * 60.0, peak_mag / mean_mag


def bpm_from_autocorrelation(
    signal: np.ndarray,
    sample_rate: float,
    band: tuple[float, float] = (0.1, 0.5),
) -> tuple[float, float]:
    """First significant autocorrelation peak in the lag range for `band`.

    Confidence = peak_height / autocorr[0].
    """
    x = signal.astype(np.float64) - float(np.mean(signal))
    n = x.size
    if n < 16 or np.std(x) < 1e-9:
        return float("nan"), 0.0
    # Biased autocorrelation via FFT.
    nfft = int(2 ** np.ceil(np.log2(2 * n)))
    F = np.fft.rfft(x, n=nfft)
    ac = np.fft.irfft(F * np.conj(F), n=nfft)[:n]
    ac0 = float(ac[0])
    if ac0 <= 0:
        return float("nan"), 0.0

    # Lag search bounds: high_hz -> smallest lag, low_hz -> largest lag.
    lag_min = int(np.floor(sample_rate / band[1]))
    lag_max = int(np.ceil(sample_rate / band[0]))
    lag_min = max(1, lag_min)
    lag_max = min(n - 1, lag_max)
    if lag_max <= lag_min:
        return float("nan"), 0.0

    segment = ac[lag_min:lag_max + 1]
    # Find first local peak; fall back to global argmax if none exists.
    peak_off: int | None = None
    for i in range(1, segment.size - 1):
        if segment[i] > segment[i - 1] and segment[i] > segment[i + 1]:
            peak_off = i
            break
    if peak_off is None:
        peak_off = int(np.argmax(segment))
    lag = lag_min + peak_off
    freq = sample_rate / lag
    conf = float(segment[peak_off] / ac0)
    return freq * 60.0, conf


def extract_breathing_rate(
    csv_path: str | Path,
    config: dict | None = None,
) -> dict:
    """Full breathing detection pipeline; returns a diagnostic dict."""
    cfg = {**DEFAULTS, **(config or {})}
    fs = float(cfg["target_sample_rate_hz"])
    band = (float(cfg["bandpass_low_hz"]), float(cfg["bandpass_high_hz"]))

    H_raw, timestamps, load_meta = load_complex_session(csv_path)

    H_active, kept_idx = drop_null_subcarriers_complex(
        H_raw, threshold=float(cfg["null_subcarrier_threshold"])
    )
    if H_active.shape[1] < 4:
        raise ValueError(
            f"only {H_active.shape[1]} active subcarriers after null-drop; "
            "check gain / link"
        )

    grid, H_u = _resample_complex_uniform(timestamps, H_active, fs)
    if H_u.shape[0] < int(fs * 10):
        raise ValueError(
            f"resampled capture too short ({H_u.shape[0]} samples at {fs} Hz)"
        )

    pairs = select_subcarrier_pairs(
        H_u,
        num_pairs=int(cfg["num_pairs"]),
        breathing_band=band,
        sample_rate=fs,
    )
    if not pairs:
        raise ValueError("no viable subcarrier pairs — CSCR selection failed")

    cscr = compute_cscr(H_u, pairs)
    wave = cscr_to_respiratory_waveform(
        cscr,
        hampel_window=int(cfg["hampel_window_size"]),
        hampel_threshold=float(cfg["hampel_threshold"]),
        savgol_window=int(cfg["savgol_window"]),
        savgol_order=int(cfg["savgol_order"]),
    )
    wave_bp = _bandpass(wave, band[0], band[1], fs, order=int(cfg["butter_order"]))

    bpm_fft, conf_fft = bpm_from_fft(wave_bp, fs, band=band)
    bpm_ac, conf_ac = bpm_from_autocorrelation(wave_bp, fs, band=band)

    valid_fft = np.isfinite(bpm_fft) and cfg["min_bpm"] <= bpm_fft <= cfg["max_bpm"]
    valid_ac = np.isfinite(bpm_ac) and cfg["min_bpm"] <= bpm_ac <= cfg["max_bpm"]

    if valid_fft and valid_ac:
        bpm_median = float(np.median([bpm_fft, bpm_ac]))
        agreement = abs(bpm_fft - bpm_ac) <= float(cfg["agreement_threshold_bpm"])
        confidence = float(min(conf_fft, conf_ac))
    elif valid_fft:
        bpm_median, agreement, confidence = float(bpm_fft), False, float(conf_fft) * 0.5
    elif valid_ac:
        bpm_median, agreement, confidence = float(bpm_ac), False, float(conf_ac) * 0.5
    else:
        bpm_median, agreement, confidence = float("nan"), False, 0.0

    # Spectrum for plotting / reporting.
    x = wave_bp.astype(np.float64) - float(np.mean(wave_bp))
    nfft = int(2 ** np.ceil(np.log2(max(x.size * 4, 128))))
    spec = np.abs(np.fft.rfft(x, n=nfft))
    freqs = np.fft.rfftfreq(nfft, d=1.0 / fs)

    return {
        "bpm_fft": float(bpm_fft),
        "bpm_autocorr": float(bpm_ac),
        "bpm_median": float(bpm_median),
        "confidence": float(confidence),
        "confidence_fft": float(conf_fft),
        "confidence_autocorr": float(conf_ac),
        "agreement": bool(agreement),
        "respiratory_waveform": wave_bp,
        "waveform_unfiltered": wave,
        "spectrum": spec,
        "spectrum_freqs": freqs,
        "timestamps": grid,
        "selected_pairs": pairs,
        "kept_subcarriers": kept_idx.tolist(),
        "sample_rate_hz": fs,
        "band_hz": band,
        "load_meta": load_meta,
        "config": cfg,
    }
